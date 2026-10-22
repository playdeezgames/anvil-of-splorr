package map_editor

import cm "../common"
import "core:fmt"

// The Features layer of the map editor, a sibling of the Characters layer. Features live in the
// world's table and stand in map cells by uuid (see common/world_features.odin); a cell holds at most
// one, never together with a character. This layer puts them on the map and edits them.
//
//   Draw:  d-pad moves the cursor; green on a cell with a feature makes it the current one, on an empty
//          cell puts the current feature there (moving it from wherever it stood; refused where a
//          character stands); yellow opens Setup; blue steps the current feature on by 16; red leaves.
//   Setup: up/down choose a row (Feature, Type, Rename, New, Unplace, Delete, Zoom, Layer, Tags);
//          left/right change the Feature, Type and Zoom rows; green runs the action rows; red returns
//          to Draw.
// The mouse: click a cell as green does, right click picks the feature under the pointer, the picker
// chooses the current feature, and every row has - and + buttons or a button of its own.

NOTE_NO_FEATURES :: "NO FEATURES YET: USE NEW"
NOTE_NEED_FEATURE_TYPE :: "ADD A FEATURE TYPE FIRST"
NOTE_CELL_CHARACTER :: "A CHARACTER STANDS THERE"
NOTE_FEATURE_FULL :: "THE WORLD HAS 2048 FEATURES"

// --- The current feature ---

feat_count :: proc(e: ^Editor) -> int {
	return e.world.feature_count
}

has_features :: proc(e: ^Editor) -> bool {
	return feat_count(e) > 0
}

// The index of the current feature, kept inside the table.
cur_feature_index :: proc(e: ^Editor) -> int {
	return clamp(e.cur_feat, 0, max(feat_count(e) - 1, 0))
}

// The current feature (only valid while the world has one).
current_feature :: proc(e: ^Editor) -> ^cm.Feature {
	return &e.world.features[cur_feature_index(e)]
}

feature_name :: proc(e: ^Editor, index: int) -> string {
	return cm.name_str(&e.world.features[index].name)
}

// Makes feature `index` current; the cursor goes to it if it stands on this map.
@(private = "file")
select_feature :: proc(e: ^Editor, index: int) {
	if !has_features(e) {
		return
	}
	e.cur_feat = ((index % feat_count(e)) + feat_count(e)) % feat_count(e)
	if mi, x, y, ok := cm.world_feature_location(e.world, current_feature(e).uuid); ok && mi == e.index {
		e.cx, e.cy = x, y
	}
}

step_feature :: proc(e: ^Editor, delta: int) {
	if !has_features(e) {
		e.note = NOTE_NO_FEATURES
		return
	}
	select_feature(e, e.cur_feat + delta)
}

// Green on a cell: pick up the feature standing there, or put the current feature there.
@(private = "file")
feat_green :: proc(e: ^Editor) {
	if occupant := cm.world_feature_at(e.world, e.index, e.cx, e.cy); occupant >= 0 {
		e.cur_feat = occupant
		return
	}
	if !has_features(e) {
		e.note = NOTE_NO_FEATURES
		return
	}
	switch cm.world_place_feature(e.world, e.index, e.cx, e.cy, current_feature(e).uuid) {
	case .Placed:
		e.dirty = true
	case .Character_There:
		e.note = NOTE_CELL_CHARACTER
	case .Taken:
		e.note = NOTE_CELL_TAKEN
	case .Outside, .Unknown, .Feature_There:
	}
}

@(private = "file")
step_feat_type :: proc(e: ^Editor, delta: int) {
	if !has_features(e) {
		e.note = NOTE_NO_FEATURES
		return
	}
	n := e.world.feature_type_count
	if n == 0 {
		e.note = NOTE_NEED_FEATURE_TYPE
		return
	}
	cur := max(cm.world_find_feature_type(e.world, cm.name_str(&current_feature(e).type)), 0)
	next := ((cur + delta) % n + n) % n
	if next != cur {
		cm.world_set_feature_type(e.world, cur_feature_index(e), next)
		e.dirty = true
	}
}

@(private = "file")
unplace_feature :: proc(e: ^Editor) {
	if !has_features(e) {
		e.note = NOTE_NO_FEATURES
		return
	}
	if cm.world_unplace_feature(e.world, current_feature(e).uuid) {
		e.dirty = true
	} else {
		e.note = NOTE_NOT_PLACED
	}
}

@(private = "file")
begin_rename_feature :: proc(e: ^Editor) {
	if !has_features(e) {
		e.note = NOTE_NO_FEATURES
		return
	}
	cm.text_entry_begin(&e.entry, "RENAME FEATURE", feature_name(e, cur_feature_index(e)), cm.NAME_MAX)
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
}

// A new feature of the current feature's type (or the first type), put at the cursor if that cell is
// free, then named.
@(private = "file")
new_feature :: proc(e: ^Editor) {
	if e.world.feature_type_count == 0 {
		e.note = NOTE_NEED_FEATURE_TYPE
		return
	}
	type_index := 0
	if has_features(e) {
		type_index = max(cm.world_find_feature_type(e.world, cm.name_str(&current_feature(e).type)), 0)
	}
	n := cm.world_add_feature(e.world, type_index)
	if n < 0 {
		e.note = NOTE_FEATURE_FULL
		return
	}
	e.cur_feat = n
	cm.world_place_feature(e.world, e.index, e.cx, e.cy, e.world.features[n].uuid) // refused if taken: it stays off the map
	e.dirty = true
	begin_rename_feature(e)
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_feature :: proc(e: ^Editor) {
	if !has_features(e) {
		e.note = NOTE_NO_FEATURES
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.world_delete_feature(e.world, cur_feature_index(e))
	e.cur_feat = clamp(e.cur_feat, 0, max(feat_count(e) - 1, 0))
	e.dirty = true
}

@(private = "file")
run_feat_row :: proc(e: ^Editor, row: Setup_Row) {
	#partial switch row {
	case .Feat_Rename:
		begin_rename_feature(e)
	case .Feat_New:
		new_feature(e)
	case .Feat_Unplace:
		unplace_feature(e)
	case .Feat_Delete:
		delete_feature(e)
	case .Layer:
		toggle_layer(e)
	case .Tags:
		begin_tags(e)
	}
}

@(private = "file")
change_feat_row :: proc(e: ^Editor, row: Setup_Row, delta: int) {
	#partial switch row {
	case .Feature:
		step_feature(e, delta)
	case .Feat_Type:
		step_feat_type(e, delta)
	case .Zoom:
		step_zoom(e, delta)
	case .Tags:
		begin_tags(e)
	}
}

// Commands in the Features layer (Draw and Setup modes). Returns false for anything else.
feat_action :: proc(e: ^Editor, a: cm.Action) -> bool {
	if !(e.mode == .Setup && e.row == .Feat_Delete && a == .Green) {
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
			feat_green(e)
		case .Yellow:
			e.mode = .Setup
		case .Blue:
			step_feature(e, FEAT_PAGE)
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
			change_feat_row(e, e.row, -1)
		case .Right:
			change_feat_row(e, e.row, 1)
		case .Green:
			run_feat_row(e, e.row)
		case .Blue:
			step_feature(e, FEAT_PAGE)
		case .Red:
			e.mode = .Draw
		}
		return true
	case .Rect, .Text, .Tags:
	}
	return false
}

// --- The picker ---

FEAT_PAGE :: PICKER_PAGE

// The feature shown in a picker slot under a position, if there is one.
feat_picker_at :: proc(e: ^Editor, x, y: int) -> (index: int, ok: bool) {
	slot, hit := picker_slot_at(x, y)
	if !hit || !has_features(e) {
		return 0, false
	}
	i := cur_feature_index(e) / FEAT_PAGE * FEAT_PAGE + slot
	return i, i < feat_count(e)
}

// --- The mouse ---

// Right click: take the feature under the pointer (a map cell or a picker thumbnail) as current.
feat_pick :: proc(e: ^Editor, x, y: int) {
	if cx, cy, ok := cell_at(e, x, y); ok {
		e.cx, e.cy = cx, cy
		if occupant := cm.world_feature_at(e.world, e.index, cx, cy); occupant >= 0 {
			e.cur_feat = occupant
			e.mode, e.row = .Setup, .Feature
		}
	} else if i, ok := feat_picker_at(e, x, y); ok {
		select_feature(e, i)
		e.mode, e.row = .Setup, .Feature
	}
}

// A left click in the Features layer. Everything is handled here.
feat_click :: proc(e: ^Editor, x, y: int) {
	if cx, cy, ok := cell_at(e, x, y); ok {
		e.cx, e.cy = cx, cy
		e.mode = .Draw
		feat_green(e)
		return
	}
	if click_bars(e, x, y) {
		return
	}
	if i, ok := feat_picker_at(e, x, y); ok {
		select_feature(e, i)
		e.mode, e.row = .Setup, .Feature
		return
	}
	setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
		e.mode, e.row = .Setup, row
		change_feat_row(e, row, delta)
	}
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		run_feat_row(e, row)
	}
	if !rect_contains(FEAT_DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	switch {
	case rect_contains(TERRAIN_MINUS, x, y):
		setting(e, .Feature, -1)
	case rect_contains(TERRAIN_PLUS, x, y):
		setting(e, .Feature, 1)
	case rect_contains(COLUMNS_MINUS, x, y):
		setting(e, .Feat_Type, -1)
	case rect_contains(COLUMNS_PLUS, x, y):
		setting(e, .Feat_Type, 1)
	case rect_contains(ZOOM_MINUS, x, y):
		setting(e, .Zoom, -1)
	case rect_contains(ZOOM_PLUS, x, y):
		setting(e, .Zoom, 1)
	case rect_contains(FEAT_NEW_BUTTON, x, y):
		action(e, .Feat_New)
	case rect_contains(FEAT_UNPLACE_BUTTON, x, y):
		action(e, .Feat_Unplace)
	case rect_contains(FEAT_DELETE_BUTTON, x, y):
		action(e, .Feat_Delete) // a second click confirms
	case rect_contains(FEAT_RENAME_BUTTON, x, y):
		action(e, .Feat_Rename)
	case rect_contains(TAGS_BUTTON, x, y):
		action(e, .Tags)
	case rect_contains(LAYER_BUTTON, x, y):
		toggle_layer(e)
	case rect_contains(BACK_BUTTON, x, y):
		e.exit_requested = true
	}
}

// Where the feature stands, for the readout: "AT 3,4", "ON <map>" or "OFF MAP".
feat_place_text :: proc(e: ^Editor, index: int) -> string {
	if mi, x, y, ok := cm.world_feature_location(e.world, e.world.features[index].uuid); ok {
		if mi == e.index {
			return fmt.tprintf("AT %d,%d", x, y)
		}
		return fmt.tprintf("ON %s", cm.name_str(&e.world.maps[mi].name))
	}
	return "OFF MAP"
}
