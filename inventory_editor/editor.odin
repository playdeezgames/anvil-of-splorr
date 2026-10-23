package inventory_editor

import cm "../common"
import "core:fmt"
import "core:mem"

// The inventory editor edits one inventory of a world, in place: the entries a character, a feature
// or a map cell holds. It is only ever hosted by the world editor, which owns the file. An entry is a
// stack of one item type: how many, and the values of the type's numeric properties that differ from
// its defaults. A stack of one is a unique item; the type's max stack says how big a stack may get.
// An inventory that runs empty is gone (the model removes it), so this editor never leaves one behind.
//
// Red always means "back". Modes:
//   List:  up/down choose an entry (the last row adds one); left/right change its count by 1, green
//          opens its properties (or adds an item on the last row), yellow types the count, blue
//          deletes the entry (green confirms; anything else cancels), red leaves.
//   Props: up/down choose a property of the entry's type; left/right change the entry's value by 1,
//          green types it, yellow puts back the type's default, red returns to the list.
//   Types: the item types of the world; green puts one item of the chosen type in (it joins a stack
//          that matches, if there is one), red cancels.
//   Text:  the keypad, for numbers.
// The mouse works everywhere: click a row to select it (again to open it) and use the buttons.
Mode :: enum {
	List,
	Props,
	Types,
	Text,
}

Text_Target :: enum {
	Count,
	Value,
}

Editor :: struct {
	world:          ^cm.World,
	owner:          cm.Inventory_Owner,
	sel:            int, // List: the selected row (entries, then the NEW row)
	scroll:         int,
	prop_sel:       int, // Props: the selected property
	prop_scroll:    int,
	type_sel:       int, // Types: the highlighted item type
	type_scroll:    int,
	mode:           Mode,
	back:           Mode, // where the keypad returns to
	text_target:    Text_Target,
	dirty:          bool, // the inventory changed since editor_begin
	exit_requested: bool,
	confirm_delete: bool,
	note:           string,
	entry:          cm.Text_Entry,
	labels:         ^cm.Input_Map,
}

NOTE_FULL :: "THE INVENTORY IS FULL"
NOTE_NO_TYPES :: "NO ITEM TYPES YET"
NOTE_NO_PROPS :: "THIS TYPE HAS NO PROPERTIES"
NOTE_NOT_NUMBER :: "TYPE A WHOLE NUMBER"
NOTE_VALUE_RANGE :: "TOO BIG FOR 32 BITS"

// Starts the editor on the inventory the owner holds (it may have none yet: the NEW row makes it).
editor_begin :: proc(e: ^Editor, world: ^cm.World, owner: cm.Inventory_Owner) {
	labels := e.labels
	mem.zero_item(e)
	e.labels = labels
	e.world = world
	e.owner = owner
}

editor_set_labels :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.labels = m
}

entry_count :: proc(e: ^Editor) -> int {
	return cm.world_owner_entry_count(e.world, e.owner)
}

// The selected entry, or nil on the NEW row (or when the owner is gone).
current_entry :: proc(e: ^Editor) -> ^cm.Entry {
	return cm.world_owner_entry(e.world, e.owner, e.sel)
}

// The index into the world's item types of an entry's type.
entry_type :: proc(e: ^Editor, en: ^cm.Entry) -> int {
	return cm.world_find_item_type(e.world, cm.name_str(&en.type))
}

// How many rows the List has: the entries and a NEW row while there is room.
list_rows :: proc(e: ^Editor) -> int {
	n := entry_count(e)
	return n < cm.INVENTORY_MAX_ENTRIES ? n + 1 : n
}

// How many properties the selected entry's type has.
prop_rows :: proc(e: ^Editor) -> int {
	en := current_entry(e)
	if en == nil {
		return 0
	}
	ti := entry_type(e, en)
	return ti >= 0 ? e.world.item_types[ti].props.count : 0
}

@(private = "file")
scroll_to :: proc(scroll, row, total: int) -> int {
	s := scroll
	if row < s {
		s = row
	} else if row >= s + LIST_ROWS {
		s = row - LIST_ROWS + 1
	}
	return clamp(s, 0, max(total - LIST_ROWS, 0))
}

fix_selection :: proc(e: ^Editor) {
	e.sel = clamp(e.sel, 0, max(list_rows(e) - 1, 0))
	e.scroll = scroll_to(e.scroll, e.sel, list_rows(e))
	e.prop_sel = clamp(e.prop_sel, 0, max(prop_rows(e) - 1, 0))
	e.prop_scroll = scroll_to(e.prop_scroll, e.prop_sel, prop_rows(e))
	e.type_sel = clamp(e.type_sel, 0, max(e.world.item_type_count - 1, 0))
	e.type_scroll = scroll_to(e.type_scroll, e.type_sel, e.world.item_type_count)
}

// --- Count and values ---

@(private = "file")
set_count :: proc(e: ^Editor, en: ^cm.Entry, n: int) -> bool {
	ti := entry_type(e, en)
	if ti < 0 || n < 1 || n > e.world.item_types[ti].max_stack {
		return false
	}
	if en.count != n {
		en.count = n
		e.dirty = true
	}
	return true
}

@(private = "file")
step_count :: proc(e: ^Editor, delta: int) {
	if en := current_entry(e); en != nil {
		ti := entry_type(e, en)
		if ti >= 0 {
			set_count(e, en, clamp(en.count + delta, 1, e.world.item_types[ti].max_stack))
		}
	}
}

@(private = "file")
prop_value :: proc(e: ^Editor, en: ^cm.Entry, p: int) -> i32 {
	return cm.world_entry_value(e.world, en, p)
}

@(private = "file")
set_prop :: proc(e: ^Editor, value: i32) {
	if en := current_entry(e); en != nil && prop_value(e, en, e.prop_sel) != value {
		if cm.world_entry_set_value(e.world, en, e.prop_sel, value) {
			e.dirty = true
		}
	}
}

@(private = "file")
step_prop :: proc(e: ^Editor, delta: int) {
	if en := current_entry(e); en != nil && prop_rows(e) > 0 {
		v := clamp(i64(prop_value(e, en, e.prop_sel)) + i64(delta), i64(min(i32)), i64(max(i32)))
		set_prop(e, i32(v))
	}
}

// Yellow in Props mode: the type's default again.
@(private = "file")
reset_prop :: proc(e: ^Editor) {
	en := current_entry(e)
	ti := en == nil ? -1 : entry_type(e, en)
	if ti >= 0 && e.prop_sel < e.world.item_types[ti].props.count {
		set_prop(e, e.world.item_types[ti].props.values[e.prop_sel])
	}
}

// A whole number typed as text: digits with an optional leading minus.
@(private = "file")
parse_whole :: proc(text: string) -> (n: i64, ok: bool) {
	if len(text) == 0 || len(text) > 12 {
		return 0, false
	}
	start := text[0] == '-' ? 1 : 0
	if start == len(text) {
		return 0, false
	}
	for i in start ..< len(text) {
		if text[i] < '0' || text[i] > '9' {
			return 0, false
		}
		n = n * 10 + i64(text[i] - '0')
	}
	return start == 1 ? -n : n, true
}

@(private = "file")
begin_text :: proc(e: ^Editor, target: Text_Target, prompt, initial: string, max_len: int) {
	cm.text_entry_begin(&e.entry, prompt, initial, max_len)
	e.text_target = target
	e.back = e.mode
	e.mode = .Text
}

@(private = "file")
begin_count :: proc(e: ^Editor) {
	if en := current_entry(e); en != nil {
		begin_text(e, .Count, "HOW MANY", fmt.tprintf("%d", en.count), 10)
	}
}

@(private = "file")
begin_value :: proc(e: ^Editor) {
	if en := current_entry(e); en != nil && prop_rows(e) > 0 {
		begin_text(e, .Value, "VALUE", fmt.tprintf("%d", prop_value(e, en, e.prop_sel)), 11)
	}
}

@(private = "file")
handle_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = e.back
	case .Done:
		n, ok := parse_whole(cm.text_entry_text(&e.entry))
		en := current_entry(e)
		switch e.text_target {
		case .Count:
			ti := en == nil ? -1 : entry_type(e, en)
			switch {
			case !ok:
				cm.text_entry_resume(&e.entry, NOTE_NOT_NUMBER)
			case ti < 0 || n < 1 || n > i64(e.world.item_types[ti].max_stack):
				cm.text_entry_resume(&e.entry, fmt.tprintf("1 TO %d", ti >= 0 ? e.world.item_types[ti].max_stack : 1))
			case:
				set_count(e, en, int(n))
				e.mode = e.back
			}
		case .Value:
			switch {
			case !ok:
				cm.text_entry_resume(&e.entry, NOTE_NOT_NUMBER)
			case n < i64(min(i32)) || n > i64(max(i32)):
				cm.text_entry_resume(&e.entry, NOTE_VALUE_RANGE)
			case:
				set_prop(e, i32(n))
				e.mode = e.back
			}
		}
	}
}

// --- Adding and deleting ---

@(private = "file")
begin_types :: proc(e: ^Editor) {
	if e.world.item_type_count == 0 {
		e.note = NOTE_NO_TYPES
		return
	}
	e.mode = .Types
	fix_selection(e)
}

// Puts one item of the chosen type in (it joins a matching stack), and selects where it went.
@(private = "file")
use_type :: proc(e: ^Editor) {
	if e.type_sel < 0 || e.type_sel >= e.world.item_type_count {
		return
	}
	_, result := cm.world_owner_add(e.world, e.owner, e.type_sel, 1)
	if result != .Added {
		e.note = NOTE_FULL
		e.mode = .List
		return
	}
	e.dirty = true
	name := cm.name_str(&e.world.item_types[e.type_sel].name)
	for n in 0 ..< entry_count(e) {
		if en := cm.world_owner_entry(e.world, e.owner, n); cm.name_str(&en.type) == name {
			e.sel = n
			break
		}
	}
	e.mode = .List
	fix_selection(e)
}

// Blue arms the deletion of the selected entry (all of its items); the next green carries it out.
@(private = "file")
arm_delete :: proc(e: ^Editor) {
	if current_entry(e) != nil {
		e.confirm_delete = true
	}
}

@(private = "file")
delete_entry :: proc(e: ^Editor) {
	if en := current_entry(e); en != nil {
		cm.world_owner_remove(e.world, e.owner, e.sel, en.count)
		e.dirty = true
		fix_selection(e)
	}
}

// Green in List mode: an entry's properties, or a new item on the last row.
@(private = "file")
open_row :: proc(e: ^Editor) {
	if current_entry(e) == nil {
		begin_types(e)
		return
	}
	if prop_rows(e) == 0 {
		e.note = NOTE_NO_PROPS
		return
	}
	e.mode = .Props
	e.prop_sel, e.prop_scroll = 0, 0
}

// --- Events ---

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	if e.mode == .Text {
		handle_text(e, ev)
		return
	}
	// Only a command or a left press confirms or cancels a deletion, and clears the note.
	#partial switch v in ev {
	case cm.Mouse_Move:
		return
	case cm.Mouse_Wheel:
		wheel(e, v.dy)
		return
	case cm.Mouse_Button_Event:
		if v.button != .Left || !v.down {
			return
		}
	}
	armed := e.confirm_delete
	e.confirm_delete = false
	e.note = ""
	switch v in ev {
	case cm.Command:
		if armed && v.action == .Green && e.mode == .List {
			delete_entry(e)
			return
		}
		editor_apply_action(e, v.action)
	case cm.Mouse_Move, cm.Mouse_Wheel:
	case cm.Mouse_Button_Event:
		click(e, v.x, v.y, armed)
	}
	fix_selection(e)
}

@(private = "file")
wheel :: proc(e: ^Editor, dy: int) {
	switch e.mode {
	case .List:
		e.scroll = clamp(e.scroll - dy, 0, max(list_rows(e) - LIST_ROWS, 0))
	case .Props:
		e.prop_scroll = clamp(e.prop_scroll - dy, 0, max(prop_rows(e) - LIST_ROWS, 0))
	case .Types:
		e.type_scroll = clamp(e.type_scroll - dy, 0, max(e.world.item_type_count - LIST_ROWS, 0))
	case .Text:
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	switch e.mode {
	case .List:
		#partial switch a {
		case .Up:
			e.sel = max(e.sel - 1, 0)
		case .Down:
			e.sel = min(e.sel + 1, list_rows(e) - 1)
		case .Left:
			step_count(e, -1)
		case .Right:
			step_count(e, 1)
		case .Green:
			open_row(e)
		case .Yellow:
			begin_count(e)
		case .Blue:
			arm_delete(e)
		case .Red:
			e.exit_requested = true
		}
	case .Props:
		#partial switch a {
		case .Up:
			e.prop_sel = max(e.prop_sel - 1, 0)
		case .Down:
			e.prop_sel = min(e.prop_sel + 1, prop_rows(e) - 1)
		case .Left:
			step_prop(e, -1)
		case .Right:
			step_prop(e, 1)
		case .Green:
			begin_value(e)
		case .Yellow:
			reset_prop(e)
		case .Red:
			e.mode = .List
		}
	case .Types:
		#partial switch a {
		case .Up:
			e.type_sel = max(e.type_sel - 1, 0)
		case .Down:
			e.type_sel = min(e.type_sel + 1, e.world.item_type_count - 1)
		case .Green:
			use_type(e)
		case .Red:
			e.mode = .List
		}
	case .Text:
	}
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int, armed: bool) {
	if row, ok := list_row_at(x, y); ok {
		switch e.mode {
		case .List:
			if i := e.scroll + row; i < list_rows(e) {
				if i == e.sel {
					open_row(e) // again: open it
				} else {
					e.sel = i
				}
			}
		case .Props:
			if i := e.prop_scroll + row; i < prop_rows(e) {
				if i == e.prop_sel {
					begin_value(e)
				} else {
					e.prop_sel = i
				}
			}
		case .Types:
			if i := e.type_scroll + row; i < e.world.item_type_count {
				if i == e.type_sel {
					use_type(e)
				} else {
					e.type_sel = i
				}
			}
		case .Text:
		}
		return
	}
	switch e.mode {
	case .List:
		switch {
		case rect_contains(MINUS, x, y):
			step_count(e, -1)
		case rect_contains(PLUS, x, y):
			step_count(e, 1)
		case rect_contains(COUNT_BUTTON, x, y):
			begin_count(e)
		case rect_contains(PROPS_BUTTON, x, y):
			if current_entry(e) != nil {
				open_row(e)
			}
		case rect_contains(NEW_BUTTON, x, y):
			begin_types(e)
		case rect_contains(DELETE_BUTTON, x, y):
			if armed {
				delete_entry(e) // a second click confirms
			} else {
				arm_delete(e)
			}
		case rect_contains(BACK_BUTTON, x, y):
			e.exit_requested = true
		}
	case .Props:
		switch {
		case rect_contains(MINUS, x, y):
			step_prop(e, -1)
		case rect_contains(PLUS, x, y):
			step_prop(e, 1)
		case rect_contains(COUNT_BUTTON, x, y):
			begin_value(e)
		case rect_contains(PROPS_BUTTON, x, y):
			reset_prop(e)
		case rect_contains(BACK_BUTTON, x, y):
			e.mode = .List
		}
	case .Types:
		switch {
		case rect_contains(NEW_BUTTON, x, y):
			use_type(e)
		case rect_contains(BACK_BUTTON, x, y):
			e.mode = .List
		}
	case .Text:
	}
}
