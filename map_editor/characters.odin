package map_editor

import cm "../common"
import "core:fmt"

// The Characters layer of the map editor. Characters live in the world's table and stand in map
// cells by uuid (see common/world_characters.odin); this layer puts them on the map and edits them.
//
//   Draw:  d-pad moves the cursor; green on a cell with a character makes it the current one, on an
//          empty cell puts the current character there (moving it from wherever it stood); yellow
//          opens Setup; blue steps the current character on by 16; red leaves.
//   Setup: up/down choose a row (Character, Type, Player, Rename, New, Unplace, Delete, Zoom, Layer);
//          left/right change the Character, Type, Player and Zoom rows; green runs the action rows;
//          red returns to Draw.
// The mouse: click a cell as green does, right click picks the character under the pointer, the
// picker chooses the current character, and every row has - and + buttons or a button of its own.

Layer :: enum {
	Terrain,
	Characters,
}

NOTE_NO_CHARACTERS :: "NO CHARACTERS YET: USE NEW"
NOTE_NEED_TYPE :: "ADD A CHARACTER TYPE FIRST"
NOTE_CELL_TAKEN :: "THAT CELL IS TAKEN"
NOTE_NOT_PLACED :: "NOT ON ANY MAP"
NOTE_CHAR_FULL :: "THE WORLD HAS 1024 CHARACTERS"
NOTE_NAME_EMPTY :: "A NAME CANNOT BE EMPTY"
NOTE_NAME_BAD :: "UNUSABLE CHARACTER IN NAME"

// The Setup rows offered in each layer (the others are skipped by up/down).
row_offered :: proc(layer: Layer, row: Setup_Row) -> bool {
	switch row {
	case .Terrain, .Columns, .Rows, .Set, .Flip_Horizontal, .Flip_Vertical, .Rotate_Left, .Rotate_Right, .Rotate_180, .Frame, .Fill, .Flood_Fill, .Replace, .Clear:
		return layer == .Terrain
	case .Character, .Char_Type, .Char_Player, .Char_Rename, .Char_New, .Char_Unplace, .Char_Delete:
		return layer == .Characters
	case .Zoom, .Layer, .Tags:
		return true
	}
	return true
}

next_row :: proc(e: ^Editor, delta: int) -> Setup_Row {
	row := e.row
	for _ in 0 ..< len(Setup_Row) {
		row = Setup_Row((int(row) + delta + len(Setup_Row)) % len(Setup_Row))
		if row_offered(e.layer, row) {
			return row
		}
	}
	return e.row
}

// --- The current character ---

char_count :: proc(e: ^Editor) -> int {
	return e.world.character_count
}

has_characters :: proc(e: ^Editor) -> bool {
	return char_count(e) > 0
}

// The current character (only valid while the world has one).
current_character :: proc(e: ^Editor) -> ^cm.Character {
	return &e.world.characters[clamp(e.cur_char, 0, char_count(e) - 1)]
}

character_name :: proc(e: ^Editor, index: int) -> string {
	return cm.name_str(&e.world.characters[index].name)
}

// The sprite a character draws, through its type (nil when the type has none).
character_sprite :: proc(w: ^cm.World, c: ^cm.Character) -> ^cm.Sprite {
	ti := cm.world_find_char_type(w, cm.name_str(&c.type))
	return ti >= 0 ? cm.world_char_type_sprite(w, &w.char_types[ti]) : nil
}

// Makes character `index` current; the cursor goes to it if it stands on this map.
@(private = "file")
select_character :: proc(e: ^Editor, index: int) {
	if !has_characters(e) {
		return
	}
	e.cur_char = ((index % char_count(e)) + char_count(e)) % char_count(e)
	if mi, x, y, ok := cm.world_character_location(e.world, current_character(e).uuid); ok && mi == e.index {
		e.cx, e.cy = x, y
	}
}

step_character :: proc(e: ^Editor, delta: int) {
	if !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		return
	}
	select_character(e, e.cur_char + delta)
}

// Green on a cell: pick up the character standing there, or put the current character there.
@(private = "file")
char_green :: proc(e: ^Editor) {
	m := current_map(e)
	if occupant := cm.world_character_at(e.world, e.index, e.cx, e.cy); occupant >= 0 {
		if occupant != clamp(e.cur_char, 0, char_count(e) - 1) {
			e.cur_char = occupant
		}
		return
	}
	if !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		return
	}
	_ = m
	switch cm.world_place_character(e.world, e.index, e.cx, e.cy, current_character(e).uuid) {
	case .Placed:
		e.dirty = true
	case .Taken:
		e.note = NOTE_CELL_TAKEN
	case .Outside, .Unknown:
	}
}

@(private = "file")
step_char_type :: proc(e: ^Editor, delta: int) {
	if !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		return
	}
	n := e.world.char_type_count
	if n == 0 {
		e.note = NOTE_NEED_TYPE
		return
	}
	cur := max(cm.world_find_char_type(e.world, cm.name_str(&current_character(e).type)), 0)
	next := ((cur + delta) % n + n) % n
	if next != cur {
		cm.world_set_character_type(e.world, clamp(e.cur_char, 0, char_count(e) - 1), next)
		e.dirty = true
	}
}

@(private = "file")
toggle_player :: proc(e: ^Editor) {
	if !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		return
	}
	if e.world.player == current_character(e).uuid {
		cm.world_set_player(e.world, cm.UUID_NONE)
	} else {
		cm.world_set_player(e.world, current_character(e).uuid)
	}
	e.dirty = true
}

@(private = "file")
unplace :: proc(e: ^Editor) {
	if !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		return
	}
	if cm.world_unplace_character(e.world, current_character(e).uuid) {
		e.dirty = true
	} else {
		e.note = NOTE_NOT_PLACED
	}
}

@(private = "file")
begin_rename :: proc(e: ^Editor) {
	if !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		return
	}
	cm.text_entry_begin(&e.entry, "RENAME CHARACTER", character_name(e, e.cur_char), cm.NAME_MAX)
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
}

// A new character of the current character's type (or the first type), put at the cursor if that
// cell is free, then named.
@(private = "file")
new_character :: proc(e: ^Editor) {
	if e.world.char_type_count == 0 {
		e.note = NOTE_NEED_TYPE
		return
	}
	type_index := 0
	if has_characters(e) {
		type_index = max(cm.world_find_char_type(e.world, cm.name_str(&current_character(e).type)), 0)
	}
	n := cm.world_add_character(e.world, type_index)
	if n < 0 {
		e.note = NOTE_CHAR_FULL
		return
	}
	e.cur_char = n
	cm.world_place_character(e.world, e.index, e.cx, e.cy, e.world.characters[n].uuid) // refused if taken: it stays off the map
	e.dirty = true
	begin_rename(e)
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_character :: proc(e: ^Editor) {
	if !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.world_delete_character(e.world, e.cur_char)
	e.cur_char = clamp(e.cur_char, 0, max(char_count(e) - 1, 0))
	e.dirty = true
}

// The layer switch: terrain painting or characters. Abandons any rectangle in progress.
toggle_layer :: proc(e: ^Editor) {
	cancel_shape(e)
	e.layer = e.layer == .Terrain ? .Characters : .Terrain
	e.confirm_delete = false
	e.row = e.layer == .Terrain ? .Terrain : .Character
}

char_handle_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = e.back
	case .Done:
		switch cm.world_rename_character(e.world, e.cur_char, cm.text_entry_text(&e.entry)) {
		case .None:
			e.dirty = true
			e.mode = e.back
		case .Empty:
			cm.text_entry_resume(&e.entry, NOTE_NAME_EMPTY)
		case .Too_Long, .Bad_Character, .In_Use:
			cm.text_entry_resume(&e.entry, NOTE_NAME_BAD)
		}
	}
}

@(private = "file")
run_row :: proc(e: ^Editor, row: Setup_Row) {
	#partial switch row {
	case .Char_Player:
		toggle_player(e)
	case .Char_Rename:
		begin_rename(e)
	case .Char_New:
		new_character(e)
	case .Char_Unplace:
		unplace(e)
	case .Char_Delete:
		delete_character(e)
	case .Layer:
		toggle_layer(e)
	case .Tags:
		begin_tags(e)
	}
}

@(private = "file")
change_row :: proc(e: ^Editor, row: Setup_Row, delta: int) {
	#partial switch row {
	case .Character:
		step_character(e, delta)
	case .Char_Type:
		step_char_type(e, delta)
	case .Char_Player:
		toggle_player(e)
	case .Zoom:
		step_zoom(e, delta)
	case .Tags:
		begin_tags(e)
	}
}

// Commands in the Characters layer (Draw and Setup modes). Returns false for anything else.
char_action :: proc(e: ^Editor, a: cm.Action) -> bool {
	if !(e.mode == .Setup && e.row == .Char_Delete && a == .Green) {
		e.confirm_delete = false
	}
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
			char_green(e)
		case .Yellow:
			e.mode = .Setup
		case .Blue:
			step_character(e, CHAR_PAGE)
		case .Red:
			e.exit_requested = true
		}
		return true
	case .Setup:
		#partial switch a {
		case .Up:
			e.row = next_row(e, -1)
		case .Down:
			e.row = next_row(e, 1)
		case .Left:
			change_row(e, e.row, -1)
		case .Right:
			change_row(e, e.row, 1)
		case .Green:
			run_row(e, e.row)
		case .Blue:
			step_character(e, CHAR_PAGE)
		case .Red:
			e.mode = .Draw
		}
		return true
	case .Rect, .Text, .Tags:
	}
	return false
}

// --- The picker ---

CHAR_PAGE :: PICKER_PAGE

// The character shown in a picker slot under a position, if there is one.
char_picker_at :: proc(e: ^Editor, x, y: int) -> (index: int, ok: bool) {
	slot, hit := picker_slot_at(x, y)
	if !hit || !has_characters(e) {
		return 0, false
	}
	i := clamp(e.cur_char, 0, char_count(e) - 1) / CHAR_PAGE * CHAR_PAGE + slot
	return i, i < char_count(e)
}

// --- The mouse ---

// Right click: take the character under the pointer (a map cell or a picker thumbnail) as current.
char_pick :: proc(e: ^Editor, x, y: int) {
	if cx, cy, ok := cell_at(e, x, y); ok {
		e.cx, e.cy = cx, cy
		if occupant := cm.world_character_at(e.world, e.index, cx, cy); occupant >= 0 {
			e.cur_char = occupant
			e.mode, e.row = .Setup, .Character
		}
	} else if i, ok := char_picker_at(e, x, y); ok {
		select_character(e, i)
		e.mode, e.row = .Setup, .Character
	}
}

// A left click in the Characters layer. Everything is handled here.
char_click :: proc(e: ^Editor, x, y: int) {
	if cx, cy, ok := cell_at(e, x, y); ok {
		e.cx, e.cy = cx, cy
		e.mode = .Draw
		char_green(e)
		return
	}
	if click_bars(e, x, y) {
		return
	}
	if i, ok := char_picker_at(e, x, y); ok {
		select_character(e, i)
		e.mode, e.row = .Setup, .Character
		return
	}
	setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
		e.mode, e.row = .Setup, row
		change_row(e, row, delta)
	}
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		run_row(e, row)
	}
	if !rect_contains(CHAR_DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	switch {
	case rect_contains(TERRAIN_MINUS, x, y):
		setting(e, .Character, -1)
	case rect_contains(TERRAIN_PLUS, x, y):
		setting(e, .Character, 1)
	case rect_contains(COLUMNS_MINUS, x, y):
		setting(e, .Char_Type, -1)
	case rect_contains(COLUMNS_PLUS, x, y):
		setting(e, .Char_Type, 1)
	case rect_contains(ROWS_MINUS, x, y), rect_contains(ROWS_PLUS, x, y):
		setting(e, .Char_Player, 1)
	case rect_contains(ZOOM_MINUS, x, y):
		setting(e, .Zoom, -1)
	case rect_contains(ZOOM_PLUS, x, y):
		setting(e, .Zoom, 1)
	case rect_contains(CHAR_NEW_BUTTON, x, y):
		action(e, .Char_New)
	case rect_contains(CHAR_UNPLACE_BUTTON, x, y):
		action(e, .Char_Unplace)
	case rect_contains(CHAR_DELETE_BUTTON, x, y):
		action(e, .Char_Delete) // a second click confirms
	case rect_contains(CHAR_PLAYER_BUTTON, x, y):
		action(e, .Char_Player)
	case rect_contains(CHAR_RENAME_BUTTON, x, y):
		action(e, .Char_Rename)
	case rect_contains(TAGS_BUTTON, x, y):
		action(e, .Tags)
	case rect_contains(LAYER_BUTTON, x, y):
		toggle_layer(e)
	case rect_contains(BACK_BUTTON, x, y):
		e.exit_requested = true
	}
}

// Where the current character stands, for the readout: "AT 3,4", "ON <map> 3,4" or "OFF MAP".
char_place_text :: proc(e: ^Editor, index: int) -> string {
	if mi, x, y, ok := cm.world_character_location(e.world, e.world.characters[index].uuid); ok {
		if mi == e.index {
			return fmt.tprintf("AT %d,%d", x, y)
		}
		return fmt.tprintf("ON %s", cm.name_str(&e.world.maps[mi].name))
	}
	return "OFF MAP"
}

// --- Tags ---

// What the tags of the thing being tagged are: in the Characters layer the current character's own
// settings over its type's tags, in the Terrain layer the cursor cell's own settings over its terrain's.
tag_view :: proc(e: ^Editor) -> cm.Tag_View {
	if e.layer == .Characters {
		c := current_character(e)
		inherited: cm.Tag_Mask
		if ti := cm.world_find_char_type(e.world, cm.name_str(&c.type)); ti >= 0 {
			inherited = e.world.char_types[ti].tags
		}
		return cm.Tag_View{set = c.tags_set, cleared = c.tags_cleared, inherited = inherited, instance = true}
	}
	m := current_map(e)
	inherited: cm.Tag_Mask
	if set := current_set(e); set != nil {
		inherited = set.terrains[clamp(int(cm.map_get(m, e.cx, e.cy)), 0, set.count - 1)].tags
	}
	ct := m.cell_tags[e.cy][e.cx]
	return cm.Tag_View{set = ct.set, cleared = ct.cleared, inherited = inherited, instance = true}
}

begin_tags :: proc(e: ^Editor) {
	if e.layer == .Characters && !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		return
	}
	e.back = e.mode
	e.mode = .Tags
	cm.tag_list_fix(&e.tags, e.world.tag_count)
}

// Green on a tag: inherit -> set -> cleared -> inherit, for the cell or the character.
@(private = "file")
cycle_tag :: proc(e: ^Editor, tag: int) {
	ok := false
	if e.layer == .Characters {
		ok = cm.world_cycle_character_tag(e.world, clamp(e.cur_char, 0, char_count(e) - 1), tag)
	} else {
		ok = cm.world_cycle_cell_tag(e.world, e.index, e.cx, e.cy, tag)
	}
	if ok {
		e.dirty = true
	}
}

// Tags mode: up and down choose a tag, green cycles it, red goes back; the mouse clicks a row (which
// also cycles it) and the wheel scrolls.
handle_tags :: proc(e: ^Editor, ev: cm.Input_Event) {
	n := e.world.tag_count
	#partial switch v in ev {
	case cm.Command:
		#partial switch v.action {
		case .Up:
			cm.tag_list_move(&e.tags, n, -1)
		case .Down:
			cm.tag_list_move(&e.tags, n, 1)
		case .Green:
			cycle_tag(e, e.tags.sel)
		case .Red:
			e.mode = e.back
		}
	case cm.Mouse_Button_Event:
		if v.button == .Left && v.down {
			if tag, ok := cm.tag_list_at(&e.tags, n, v.x, v.y); ok {
				e.tags.sel = tag
				cycle_tag(e, tag)
			} else if rect_contains(BACK_BUTTON, v.x, v.y) {
				e.mode = e.back
			}
		}
	case cm.Mouse_Wheel:
		cm.tag_list_scroll(&e.tags, n, v.dy)
	}
}
