package map_editor

import cm "../common"
import "core:fmt"

// The map editor paints a map of the world with the terrains of the map's terrain set. It is
// patterned on the image editor (terrains instead of colours) and is only ever hosted by the world
// editor, which owns the file: it edits the map in the world in place.
//
// Red always means "back". Modes:
//   Draw:  d-pad moves the cursor; green paints the cell under it with the current terrain; yellow
//          opens Setup; blue steps the current terrain on by 16; red leaves.
//   Setup: up/down choose a row, left/right change it (terrain, columns, rows, terrain set); green
//          runs the action rows: Flip horizontal / vertical, Rotate left / right (square maps only) /
//          180, Frame / Fill (draw a rectangle), Flood fill (the connected region under the cursor
//          becomes the current terrain), Replace (every cell of the terrain under the cursor becomes
//          the current terrain) and Clear (the whole map becomes the current terrain); red returns
//          to Draw.
//   Rect:  placing a rectangle: the cursor is its second corner. Green draws it, red cancels.
// The mouse works in all modes (click/drag paints, right click picks up the terrain under the
// pointer, the picker chooses a terrain, - and + buttons, tool buttons) and switches mode itself.
// FRAME and FILL arm a drag tool; FLOOD and REPLACE arm a click tool (red or the button again
// disarms; CLEAR acts at once).
Mode :: enum {
	Draw,
	Setup,
	Rect,
}

Setup_Row :: enum {
	Terrain,
	Columns,
	Rows,
	Set,
	Flip_Horizontal,
	Flip_Vertical,
	Rotate_Left,
	Rotate_Right,
	Rotate_180,
	Frame,
	Fill,
	Flood_Fill,
	Replace,
	Clear,
}

Point_Tool :: enum {
	None,
	Flood_Fill,
	Replace,
}

Editor :: struct {
	world:          ^cm.World, // the hosting world; the map being edited is world.maps[index]
	index:          int,
	cx, cy:         int, // cursor, always inside the map
	mode:           Mode,
	row:            Setup_Row,
	terrain:        int, // the current terrain: an index in the map's terrain set
	dirty:          bool, // the map (or its size or set) changed since editor_begin
	exit_requested: bool,
	paint:          Maybe(int), // mouse drag in progress: the terrain being painted
	shape:          cm.Shape, // the rectangle being placed (Rect mode) or armed with the mouse
	ax, ay:         int, // the rectangle's first corner
	rect_drag:      bool,
	point_tool:     Point_Tool,
	note:           string, // a one-line message about the last action; cleared by the next input
	mx, my:         int, // the last mouse position
	labels:         ^cm.Input_Map,
}

NOTE_SAME_FILL :: "SAME TERRAIN: NOTHING TO FILL"
NOTE_SAME_REPLACE :: "SAME TERRAIN: NOTHING TO REPLACE"
NOTE_SAME_CLEAR :: "ALREADY ALL THAT TERRAIN"
NOTE_NO_TURN :: "ONLY A SQUARE MAP CAN TURN"
NOTE_ONE_SET :: "THERE IS NO OTHER TERRAIN SET"

// Starts editing map `index` of the world in Draw mode, with the set's default terrain current.
editor_begin :: proc(e: ^Editor, world: ^cm.World, index: int) {
	labels := e.labels
	e^ = {}
	e.labels = labels
	e.world = world
	e.index = index
	if set := current_set(e); set != nil {
		e.terrain = set.default
	}
}

editor_set_labels :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.labels = m
}

current_map :: proc(e: ^Editor) -> ^cm.World_Map {
	return &e.world.maps[e.index]
}

// The map's terrain set (nil only if the world is inconsistent).
current_set :: proc(e: ^Editor) -> ^cm.Terrain_Set {
	return cm.world_map_set(e.world, e.index)
}

terrain_count :: proc(e: ^Editor) -> int {
	if set := current_set(e); set != nil {
		return set.count
	}
	return 1
}

terrain_name :: proc(e: ^Editor, index: int) -> string {
	if set := current_set(e); set != nil && index >= 0 && index < set.count {
		return cm.name_str(&set.terrains[index].name)
	}
	return ""
}

@(private = "file")
clamp_cursor :: proc(e: ^Editor) {
	m := current_map(e)
	e.cx = clamp(e.cx, 0, m.width - 1)
	e.cy = clamp(e.cy, 0, m.height - 1)
}

@(private = "file")
paint_cell :: proc(e: ^Editor, x, y, terrain: int) {
	if cm.map_set(current_map(e), x, y, terrain) {
		e.dirty = true
	}
}

@(private = "file")
step_terrain :: proc(e: ^Editor, delta: int) {
	n := terrain_count(e)
	e.terrain = ((e.terrain + delta) % n + n) % n
}

@(private = "file")
set_size :: proc(e: ^Editor, columns, rows: int) {
	if cm.world_map_set_size(e.world, e.index, columns, rows) {
		e.dirty = true
		clamp_cursor(e)
	}
}

// Moves the map to the next (delta 1) or previous terrain set, keeping its cells' terrains by name.
// Refused, with a note, when the other set lacks one of them.
@(private = "file")
change_set :: proc(e: ^Editor, delta: int) {
	w := e.world
	if w.set_count < 2 {
		e.note = NOTE_ONE_SET
		return
	}
	current := cm.world_find_set(w, cm.name_str(&current_map(e).set))
	next := ((current + delta) % w.set_count + w.set_count) % w.set_count
	keep := terrain_name(e, e.terrain)
	ok, missing, cells := cm.world_map_change_set(w, e.index, next)
	if !ok {
		shown := missing
		if len(shown) > 12 {
			shown = shown[:12]
		}
		e.note = fmt.tprintf("%s LACKS %s (%d CELLS)", cm.name_str(&w.sets[next].name)[:min(12, len(cm.name_str(&w.sets[next].name)))], shown, cells)
		return
	}
	e.dirty = true
	// Keep the current terrain if the new set has one by that name, else its default.
	set := current_set(e)
	if i := cm.set_find_terrain(set, keep); i >= 0 {
		e.terrain = i
	} else {
		e.terrain = set.default
	}
}

// Whole-map transforms and tools. The map counts as changed only if a cell changed.
@(private = "file")
transform :: proc(e: ^Editor, row: Setup_Row) {
	m := current_map(e)
	changed := false
	#partial switch row {
	case .Flip_Horizontal:
		changed = cm.map_flip_horizontal(m)
	case .Flip_Vertical:
		changed = cm.map_flip_vertical(m)
	case .Rotate_Left, .Rotate_Right:
		if m.width != m.height {
			e.note = NOTE_NO_TURN
			return
		}
		changed = row == .Rotate_Left ? cm.map_rotate_left(m) : cm.map_rotate_right(m)
	case .Rotate_180:
		changed = cm.map_rotate_180(m)
	case .Flood_Fill:
		changed = cm.map_flood_fill(m, e.cx, e.cy, e.terrain)
		if !changed {
			e.note = NOTE_SAME_FILL
		}
	case .Replace:
		changed = cm.map_replace(m, int(cm.map_get(m, e.cx, e.cy)), e.terrain)
		if !changed {
			e.note = NOTE_SAME_REPLACE
		}
	case .Clear:
		changed = cm.map_clear(m, e.terrain)
		if !changed {
			e.note = NOTE_SAME_CLEAR
		}
	}
	if changed {
		e.dirty = true
	}
}

@(private = "file")
begin_shape :: proc(e: ^Editor, shape: cm.Shape) {
	e.shape = shape
	e.ax, e.ay = e.cx, e.cy
	e.mode = .Rect
}

@(private = "file")
commit_shape :: proc(e: ^Editor) {
	if cm.map_draw_shape(current_map(e), e.shape, e.ax, e.ay, e.cx, e.cy, e.terrain) {
		e.dirty = true
	}
	cancel_shape(e)
}

@(private = "file")
cancel_shape :: proc(e: ^Editor) {
	e.shape = .None
	e.point_tool = .None
	e.rect_drag = false
	if e.mode == .Rect {
		e.mode = .Draw
	}
}

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	// Any command or button press clears the message; moving the mouse or letting go does not.
	#partial switch v in ev {
	case cm.Command:
		e.note = ""
	case cm.Mouse_Button_Event:
		if v.down {
			e.note = ""
		}
	}
	m := current_map(e)
	switch v in ev {
	case cm.Command:
		editor_apply_action(e, v.action)
	case cm.Mouse_Move:
		e.mx, e.my = v.x, v.y
		if e.rect_drag {
			if x, y, ok := cell_at(m.width, m.height, v.x, v.y); ok {
				e.cx, e.cy = x, y
			}
		} else if terrain, painting := e.paint.?; painting {
			if x, y, ok := cell_at(m.width, m.height, v.x, v.y); ok {
				e.cx, e.cy = x, y
				paint_cell(e, x, y, terrain)
			}
		}
	case cm.Mouse_Button_Event:
		switch v.button {
		case .Left:
			e.mx, e.my = v.x, v.y
			if v.down {
				click(e, v.x, v.y)
			} else {
				e.paint = nil
				if e.rect_drag { 	// letting go places the second corner
					commit_shape(e)
				}
			}
		case .Right:
			if v.down {
				pick(e, v.x, v.y)
			}
		case .Middle:
		}
	case cm.Mouse_Wheel:
		if in_picker(e.mx, e.my) {
			step_terrain(e, -v.dy * PICKER_PAGE)
		}
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	m := current_map(e)
	switch e.mode {
	case .Draw:
		#partial switch a {
		case .Up:
			e.cy = max(e.cy - 1, 0)
		case .Down:
			e.cy = min(e.cy + 1, m.height - 1)
		case .Left:
			e.cx = max(e.cx - 1, 0)
		case .Right:
			e.cx = min(e.cx + 1, m.width - 1)
		case .Green:
			paint_cell(e, e.cx, e.cy, e.terrain)
		case .Yellow:
			e.mode = .Setup
		case .Blue:
			step_terrain(e, PICKER_PAGE)
		case .Red:
			if e.shape != .None || e.point_tool != .None {
				cancel_shape(e) // red first disarms a mouse-armed tool
			} else {
				e.exit_requested = true
			}
		}
	case .Rect:
		#partial switch a {
		case .Up:
			e.cy = max(e.cy - 1, 0)
		case .Down:
			e.cy = min(e.cy + 1, m.height - 1)
		case .Left:
			e.cx = max(e.cx - 1, 0)
		case .Right:
			e.cx = min(e.cx + 1, m.width - 1)
		case .Green:
			commit_shape(e)
		case .Red:
			cancel_shape(e)
		}
	case .Setup:
		#partial switch a {
		case .Up:
			e.row = Setup_Row((int(e.row) + len(Setup_Row) - 1) % len(Setup_Row))
		case .Down:
			e.row = Setup_Row((int(e.row) + 1) % len(Setup_Row))
		case .Left:
			change_setting(e, -1)
		case .Right:
			change_setting(e, 1)
		case .Green:
			#partial switch e.row {
			case .Flip_Horizontal, .Flip_Vertical, .Rotate_Left, .Rotate_Right, .Rotate_180:
				transform(e, e.row)
			case .Flood_Fill:
				before := e.dirty
				e.dirty = false
				transform(e, e.row)
				if e.dirty { 	// one fill, then back to drawing (when nothing changed the note says why)
					e.mode = .Draw
				}
				e.dirty ||= before
			case .Replace, .Clear:
				transform(e, e.row)
			case .Frame:
				begin_shape(e, .Frame)
			case .Fill:
				begin_shape(e, .Fill)
			}
		case .Blue:
			step_terrain(e, PICKER_PAGE)
		case .Red:
			e.mode = .Draw
		}
	}
}

@(private = "file")
change_setting :: proc(e: ^Editor, delta: int) {
	m := current_map(e)
	#partial switch e.row {
	case .Terrain:
		step_terrain(e, delta)
	case .Columns:
		set_size(e, m.width + delta, m.height)
	case .Rows:
		set_size(e, m.width, m.height + delta)
	case .Set:
		change_set(e, delta)
	}
}

// Right click: take the terrain under the pointer (a map cell or a picker thumbnail) as the current
// terrain. While a rectangle is being placed the mode is left alone.
@(private = "file")
pick :: proc(e: ^Editor, x, y: int) {
	m := current_map(e)
	if cx, cy, ok := cell_at(m.width, m.height, x, y); ok {
		if e.shape == .None {
			e.cx, e.cy = cx, cy
		}
		e.terrain = int(cm.map_get(m, cx, cy))
	} else if i, ok := picker_terrain_at(e, x, y); ok {
		e.terrain = i
	} else {
		return
	}
	if e.shape == .None {
		e.mode, e.row = .Setup, .Terrain
	}
}

// The terrain shown in the picker slot under a position, if there is one.
picker_terrain_at :: proc(e: ^Editor, x, y: int) -> (terrain: int, ok: bool) {
	slot, hit := picker_slot_at(x, y)
	if !hit {
		return 0, false
	}
	i := e.terrain / PICKER_PAGE * PICKER_PAGE + slot
	return i, i < terrain_count(e)
}

@(private = "file")
in_picker :: proc(x, y: int) -> bool {
	_, ok := picker_slot_at(x, y)
	return ok
}

@(private = "file")
toggle_tool :: proc(e: ^Editor, shape: cm.Shape) {
	armed := e.shape == shape && !e.rect_drag
	cancel_shape(e)
	if !armed {
		e.shape = shape
		e.mode = .Draw
	}
}

@(private = "file")
toggle_point_tool :: proc(e: ^Editor, tool: Point_Tool) {
	armed := e.point_tool == tool
	cancel_shape(e)
	if !armed {
		e.point_tool = tool
		e.mode = .Draw
	}
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	m := current_map(e)
	if cx, cy, ok := cell_at(m.width, m.height, x, y); ok {
		e.cx, e.cy = cx, cy
		switch {
		case e.point_tool != .None: // a click tool armed with a button: run it from this cell
			row: Setup_Row = e.point_tool == .Flood_Fill ? .Flood_Fill : .Replace
			e.point_tool = .None
			e.mode = .Draw
			transform(e, row)
		case e.mode == .Rect: // a rectangle started from the keyboard: this click is its second corner
			commit_shape(e)
		case e.shape != .None: // a tool armed with a button: start dragging out a rectangle
			e.ax, e.ay = cx, cy
			e.rect_drag = true
			e.mode = .Rect
		case:
			e.mode = .Draw
			paint_cell(e, cx, cy, e.terrain)
			e.paint = e.terrain // dragging paints the same terrain
		}
		return
	}
	// Choosing a terrain or a tool keeps a rectangle in progress; every other button abandons it.
	_, on_picker := picker_terrain_at(e, x, y)
	is_tool_button := rect_contains(FRAME_BUTTON, x, y) || rect_contains(FILL_BUTTON, x, y) || rect_contains(FLOOD_BUTTON, x, y) || rect_contains(REPLACE_BUTTON, x, y)
	if !on_picker && !is_tool_button {
		cancel_shape(e)
	}
	setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
		e.mode, e.row = .Setup, row
		change_setting(e, delta)
	}
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		transform(e, row)
	}
	switch {
	case rect_contains(TERRAIN_MINUS, x, y):
		setting(e, .Terrain, -1)
	case rect_contains(TERRAIN_PLUS, x, y):
		setting(e, .Terrain, 1)
	case rect_contains(COLUMNS_MINUS, x, y):
		setting(e, .Columns, -1)
	case rect_contains(COLUMNS_PLUS, x, y):
		setting(e, .Columns, 1)
	case rect_contains(ROWS_MINUS, x, y):
		setting(e, .Rows, -1)
	case rect_contains(ROWS_PLUS, x, y):
		setting(e, .Rows, 1)
	case rect_contains(SET_MINUS, x, y):
		setting(e, .Set, -1)
	case rect_contains(SET_PLUS, x, y):
		setting(e, .Set, 1)
	case on_picker:
		i, _ := picker_terrain_at(e, x, y)
		e.terrain = i
		if e.shape == .None {
			e.mode, e.row = .Setup, .Terrain
		}
	case rect_contains(FLIP_H_BUTTON, x, y):
		action(e, .Flip_Horizontal)
	case rect_contains(FLIP_V_BUTTON, x, y):
		action(e, .Flip_Vertical)
	case rect_contains(ROT_L_BUTTON, x, y):
		action(e, .Rotate_Left)
	case rect_contains(ROT_R_BUTTON, x, y):
		action(e, .Rotate_Right)
	case rect_contains(ROT_180_BUTTON, x, y):
		action(e, .Rotate_180)
	case rect_contains(FRAME_BUTTON, x, y):
		toggle_tool(e, .Frame)
	case rect_contains(FILL_BUTTON, x, y):
		toggle_tool(e, .Fill)
	case rect_contains(FLOOD_BUTTON, x, y):
		toggle_point_tool(e, .Flood_Fill)
	case rect_contains(REPLACE_BUTTON, x, y):
		toggle_point_tool(e, .Replace)
	case rect_contains(CLEAR_BUTTON, x, y):
		action(e, .Clear)
	case rect_contains(BACK_BUTTON, x, y):
		e.exit_requested = true
	}
}
