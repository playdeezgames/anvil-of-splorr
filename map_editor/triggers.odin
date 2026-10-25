package map_editor

import cm "../common"
import "core:fmt"

// The Triggers layer of the map editor, the fifth layer. Triggers live in the world's table (see
// common/world_triggers.odin); a trigger sits in a cell, on a feature, or nowhere, and any number may
// share a cell. This layer puts them in cells and edits them; putting one on a feature is the trigger
// editor's ATTACH.
//
//   Draw:  d-pad moves the cursor; green puts the current trigger in the cell under the cursor (taking
//          it from wherever it was); yellow opens Setup; blue steps the current trigger on by 16; red leaves.
//   Setup: up/down choose a row (Trigger, Type, Here, Rename, New, Unplace, Delete, Zoom, Layer);
//          left/right change the Trigger, Type, Here (the next trigger in this cell becomes the current
//          one) and Zoom rows; green runs the action rows; red returns to Draw.
// The mouse: click a cell as green does, right click picks a trigger of that cell (the next one in the
// cell each time), the picker chooses the current trigger, and every row has - and + buttons or a
// button of its own.

NOTE_NO_TRIGGERS :: "NO TRIGGERS YET: USE NEW"
NOTE_NEED_TRIGGER_TYPE :: "ADD A TRIGGER TYPE FIRST"
NOTE_NOT_HERE :: "NO TRIGGER IN THIS CELL"
NOTE_TRIGGER_FULL :: "THE WORLD HAS 2048 TRIGGERS"

TRIG_PAGE :: PICKER_PAGE

// --- The current trigger ---

trig_count :: proc(e: ^Editor) -> int {
	return e.world.trigger_count
}

has_triggers :: proc(e: ^Editor) -> bool {
	return trig_count(e) > 0
}

// The index of the current trigger, kept inside the table.
cur_trigger_index :: proc(e: ^Editor) -> int {
	return clamp(e.cur_trig, 0, max(trig_count(e) - 1, 0))
}

// The current trigger (only valid while the world has one).
current_trigger :: proc(e: ^Editor) -> ^cm.Trigger {
	return &e.world.triggers[cur_trigger_index(e)]
}

trigger_name :: proc(e: ^Editor, index: int) -> string {
	return cm.name_str(&e.world.triggers[index].name)
}

// Makes trigger `index` current; the cursor goes to it if it sits in a cell of this map.
@(private = "file")
select_trigger :: proc(e: ^Editor, index: int) {
	if !has_triggers(e) {
		return
	}
	e.cur_trig = ((index % trig_count(e)) + trig_count(e)) % trig_count(e)
	if mi, x, y, ok := cm.world_trigger_cell(e.world, e.cur_trig); ok && mi == e.index {
		e.cx, e.cy = x, y
	}
}

step_trigger :: proc(e: ^Editor, delta: int) {
	if !has_triggers(e) {
		e.note = NOTE_NO_TRIGGERS
		return
	}
	select_trigger(e, e.cur_trig + delta)
}

// The triggers in the cell under the cursor, in table order (temp allocator).
cell_triggers :: proc(e: ^Editor) -> []int {
	return cm.world_triggers_in_cell(e.world, e.index, e.cx, e.cy)
}

// Makes the next (delta 1) or previous trigger of the cell under the cursor the current one; the one
// after the current trigger if it is in the cell, else the first (or last).
step_here :: proc(e: ^Editor, delta: int) {
	list := cell_triggers(e)
	if len(list) == 0 {
		e.note = NOTE_NOT_HERE
		return
	}
	pos := -1
	for ti, i in list {
		if ti == cur_trigger_index(e) {
			pos = i
		}
	}
	next: int
	switch {
	case pos < 0:
		next = delta > 0 ? 0 : len(list) - 1
	case:
		next = ((pos + delta) % len(list) + len(list)) % len(list)
	}
	e.cur_trig = list[next]
}

// Green on a cell: put the current trigger there.
@(private = "file")
trig_green :: proc(e: ^Editor) {
	if !has_triggers(e) {
		e.note = NOTE_NO_TRIGGERS
		return
	}
	t := current_trigger(e)
	if mi, x, y, ok := cm.world_trigger_cell(e.world, cur_trigger_index(e)); ok && mi == e.index && x == e.cx && y == e.cy {
		return // already there
	}
	if cm.world_place_trigger(e.world, t.uuid, e.index, e.cx, e.cy) == .Placed {
		e.dirty = true
	}
}

@(private = "file")
step_trig_type :: proc(e: ^Editor, delta: int) {
	if !has_triggers(e) {
		e.note = NOTE_NO_TRIGGERS
		return
	}
	n := e.world.trigger_type_count
	if n == 0 {
		e.note = NOTE_NEED_TRIGGER_TYPE
		return
	}
	cur := max(cm.world_find_trigger_type(e.world, cm.name_str(&current_trigger(e).type)), 0)
	next := ((cur + delta) % n + n) % n
	if next != cur {
		cm.world_set_trigger_type(e.world, cur_trigger_index(e), next)
		e.dirty = true
	}
}

@(private = "file")
unplace_trigger :: proc(e: ^Editor) {
	if !has_triggers(e) {
		e.note = NOTE_NO_TRIGGERS
		return
	}
	if cm.world_unplace_trigger(e.world, current_trigger(e).uuid) {
		e.dirty = true
	} else {
		e.note = NOTE_NOT_PLACED
	}
}

@(private = "file")
begin_rename_trigger :: proc(e: ^Editor) {
	if !has_triggers(e) {
		e.note = NOTE_NO_TRIGGERS
		return
	}
	cm.text_entry_begin(&e.entry, "RENAME TRIGGER", trigger_name(e, cur_trigger_index(e)), cm.NAME_MAX)
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
}

// A new trigger of the current trigger's type (or the first type), put at the cursor, then named.
@(private = "file")
new_trigger :: proc(e: ^Editor) {
	if e.world.trigger_type_count == 0 {
		e.note = NOTE_NEED_TRIGGER_TYPE
		return
	}
	type_index := 0
	if has_triggers(e) {
		type_index = max(cm.world_find_trigger_type(e.world, cm.name_str(&current_trigger(e).type)), 0)
	}
	n := cm.world_add_trigger(e.world, type_index)
	if n < 0 {
		e.note = NOTE_TRIGGER_FULL
		return
	}
	e.cur_trig = n
	cm.world_place_trigger(e.world, e.world.triggers[n].uuid, e.index, e.cx, e.cy)
	e.dirty = true
	begin_rename_trigger(e)
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_trigger :: proc(e: ^Editor) {
	if !has_triggers(e) {
		e.note = NOTE_NO_TRIGGERS
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.world_delete_trigger(e.world, cur_trigger_index(e))
	e.cur_trig = clamp(e.cur_trig, 0, max(trig_count(e) - 1, 0))
	e.dirty = true
}

@(private = "file")
run_trig_row :: proc(e: ^Editor, row: Setup_Row) {
	#partial switch row {
	case .Trig_Rename:
		begin_rename_trigger(e)
	case .Trig_New:
		new_trigger(e)
	case .Trig_Unplace:
		unplace_trigger(e)
	case .Trig_Delete:
		delete_trigger(e)
	case .Layer:
		toggle_layer(e)
	}
}

@(private = "file")
change_trig_row :: proc(e: ^Editor, row: Setup_Row, delta: int) {
	#partial switch row {
	case .Trigger:
		step_trigger(e, delta)
	case .Trig_Type:
		step_trig_type(e, delta)
	case .Trig_Here:
		step_here(e, delta)
	case .Zoom:
		step_zoom(e, delta)
	}
}

// Commands in the Triggers layer (Draw and Setup modes). Returns false for anything else.
trig_action :: proc(e: ^Editor, a: cm.Action) -> bool {
	if !(e.mode == .Setup && e.row == .Trig_Delete && a == .Green) {
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
			trig_green(e)
		case .Yellow:
			e.mode = .Setup
		case .Blue:
			step_trigger(e, TRIG_PAGE)
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
			change_trig_row(e, e.row, -1)
		case .Right:
			change_trig_row(e, e.row, 1)
		case .Green:
			run_trig_row(e, e.row)
		case .Blue:
			step_trigger(e, TRIG_PAGE)
		case .Red:
			e.mode = .Draw
		}
		return true
	case .Rect, .Text, .Tags:
	}
	return false
}

// --- The picker ---

// The trigger shown in a picker slot under a position, if there is one.
trig_picker_at :: proc(e: ^Editor, x, y: int) -> (index: int, ok: bool) {
	slot, hit := picker_slot_at(x, y)
	if !hit || !has_triggers(e) {
		return 0, false
	}
	i := cur_trigger_index(e) / TRIG_PAGE * TRIG_PAGE + slot
	return i, i < trig_count(e)
}

// --- The mouse ---

// Right click: take a trigger as current: of the cell under the pointer (the next one each time), or
// the picker thumbnail under it.
trig_pick :: proc(e: ^Editor, x, y: int) {
	if cx, cy, ok := cell_at(e, x, y); ok {
		e.cx, e.cy = cx, cy
		if len(cell_triggers(e)) > 0 {
			step_here(e, 1)
			e.mode, e.row = .Setup, .Trigger
		}
	} else if i, ok := trig_picker_at(e, x, y); ok {
		select_trigger(e, i)
		e.mode, e.row = .Setup, .Trigger
	}
}

// A left click in the Triggers layer. Everything is handled here.
trig_click :: proc(e: ^Editor, x, y: int) {
	if cx, cy, ok := cell_at(e, x, y); ok {
		e.cx, e.cy = cx, cy
		e.mode = .Draw
		trig_green(e)
		return
	}
	if click_bars(e, x, y) {
		return
	}
	if i, ok := trig_picker_at(e, x, y); ok {
		select_trigger(e, i)
		e.mode, e.row = .Setup, .Trigger
		return
	}
	setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
		e.mode, e.row = .Setup, row
		change_trig_row(e, row, delta)
	}
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		run_trig_row(e, row)
	}
	if !rect_contains(TRIG_DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	switch {
	case rect_contains(TERRAIN_MINUS, x, y):
		setting(e, .Trigger, -1)
	case rect_contains(TERRAIN_PLUS, x, y):
		setting(e, .Trigger, 1)
	case rect_contains(COLUMNS_MINUS, x, y):
		setting(e, .Trig_Type, -1)
	case rect_contains(COLUMNS_PLUS, x, y):
		setting(e, .Trig_Type, 1)
	case rect_contains(ROWS_MINUS, x, y):
		setting(e, .Trig_Here, -1)
	case rect_contains(ROWS_PLUS, x, y):
		setting(e, .Trig_Here, 1)
	case rect_contains(ZOOM_MINUS, x, y):
		setting(e, .Zoom, -1)
	case rect_contains(ZOOM_PLUS, x, y):
		setting(e, .Zoom, 1)
	case rect_contains(TRIG_NEW_BUTTON, x, y):
		action(e, .Trig_New)
	case rect_contains(TRIG_UNPLACE_BUTTON, x, y):
		action(e, .Trig_Unplace)
	case rect_contains(TRIG_DELETE_BUTTON, x, y):
		action(e, .Trig_Delete) // a second click confirms
	case rect_contains(TRIG_RENAME_BUTTON, x, y):
		action(e, .Trig_Rename)
	case rect_contains(LAYER_BUTTON, x, y):
		toggle_layer(e)
	case rect_contains(BACK_BUTTON, x, y):
		e.exit_requested = true
	}
}

// Where trigger `index` is, for the readout: "AT 3,4", "ON <map>", "ON <feature>" or "NO PLACE".
trig_place_text :: proc(e: ^Editor, index: int) -> string {
	t := &e.world.triggers[index]
	switch t.place {
	case .None:
	case .Cell:
		if cm.name_str(&t.map_name) == cm.name_str(&current_map(e).name) {
			return fmt.tprintf("AT %d,%d", t.x, t.y)
		}
		name := cm.name_str(&t.map_name)
		return fmt.tprintf("ON %s", name[:min(len(name), 16)])
	case .Feature:
		if fi := cm.world_find_feature(e.world, t.feature); fi >= 0 {
			name := cm.name_str(&e.world.features[fi].name)
			return fmt.tprintf("ON %s", name[:min(len(name), 16)])
		}
	}
	return "NO PLACE"
}
