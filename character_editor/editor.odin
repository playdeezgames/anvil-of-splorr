package character_editor

import cm "../common"
import "core:fmt"
import "core:mem"

// The character editor edits the characters of a world (the table every map cell and the player
// refer to by uuid), in place, and is only ever hosted by the world editor, which owns the file.
// A character has a name (a label), a character type, a uuid it never changes, and maybe a place on
// a map and the role of the player. Characters can also be edited from the map editor.
//
// Red always means "back". Modes:
//   List:  up/down choose a character; green renames it (the keypad); yellow opens Actions; red leaves.
//   Setup: (Actions) up/down choose a row; left/right change the type; green runs the action rows:
//          Rename, New, Duplicate, Delete (twice), Player (this character is the player, or not),
//          Unplace (take it off its map); red returns to the list.
//   Text:  the keypad, for names.
// The mouse works everywhere: click a character to select it, again to rename it; the type has
// - and + buttons and every action a button.
Mode :: enum {
	List,
	Setup,
	Text,
	Tags, // the world's tags: inherit, set or clear on this character
	Props, // its values of its type's numeric properties
}

Setup_Row :: enum {
	Rename,
	New,
	Duplicate,
	Delete,
	Type,
	Player,
	Unplace,
	Tags,
	Items,
	Props,
}

Editor :: struct {
	world:          ^cm.World,
	sel:            int, // the selected character (0 while there are none)
	scroll:         int, // the first visible list row
	mode:           Mode,
	back:           Mode, // where the keypad returns to
	row:            Setup_Row,
	dirty:          bool, // the characters changed since editor_begin
	exit_requested: bool,
	items_requested: bool, // the host should open the selected character's inventory
	confirm_delete: bool,
	tags:           cm.Tag_List, // Tags mode: the selected tag
	prop_sel:       int, // Props mode: the selected property
	text_value:     bool, // the keypad is typing a property value (not a name)
	props_back:     Mode, // where Props mode returns to
	note:           string,
	entry:          cm.Text_Entry,
	labels:         ^cm.Input_Map,
}

NOTE_NO_CHARACTERS :: "NO CHARACTERS YET: USE NEW"
NOTE_NEED_TYPE :: "ADD A CHARACTER TYPE FIRST"
NOTE_FULL :: "THE WORLD HAS 1024 CHARACTERS"
NOTE_NOT_PLACED :: "NOT ON ANY MAP"
NOTE_NO_PROPS :: "ITS TYPE HAS NO PROPERTIES"
NOTE_NOT_NUMBER :: "TYPE A WHOLE NUMBER"
NOTE_VALUE_RANGE :: "TOO BIG FOR 32 BITS"
NOTE_NAME_EMPTY :: "A NAME CANNOT BE EMPTY"
NOTE_NAME_BAD :: "UNUSABLE CHARACTER IN NAME"

// Starts the editor in List mode.
editor_begin :: proc(e: ^Editor, world: ^cm.World) {
	labels := e.labels
	mem.zero_item(e)
	e.labels = labels
	e.world = world
}

editor_set_labels :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.labels = m
}

count :: proc(e: ^Editor) -> int {
	return e.world.character_count
}

has_characters :: proc(e: ^Editor) -> bool {
	return count(e) > 0
}

// The selected character (only valid while there is one).
current :: proc(e: ^Editor) -> ^cm.Character {
	return &e.world.characters[e.sel]
}

character_name :: proc(e: ^Editor, index: int) -> string {
	return cm.name_str(&e.world.characters[index].name)
}

is_player :: proc(e: ^Editor, index: int) -> bool {
	return e.world.player == e.world.characters[index].uuid
}

fix_selection :: proc(e: ^Editor) {
	n := count(e)
	e.sel = clamp(e.sel, 0, max(n - 1, 0))
	if e.sel < e.scroll {
		e.scroll = e.sel
	} else if e.sel >= e.scroll + LIST_ROWS {
		e.scroll = e.sel - LIST_ROWS + 1
	}
	e.scroll = clamp(e.scroll, 0, max(n - LIST_ROWS, 0))
}

@(private = "file")
select :: proc(e: ^Editor, index: int) {
	e.sel = index
	fix_selection(e)
}

@(private = "file")
need_character :: proc(e: ^Editor) -> bool {
	if !has_characters(e) {
		e.note = NOTE_NO_CHARACTERS
		return false
	}
	return true
}

// Where the selected character stands, for the readout: "MAP name AT x,y" or "".
location_text :: proc(e: ^Editor, index: int) -> string {
	if mi, x, y, ok := cm.world_character_location(e.world, e.world.characters[index].uuid); ok {
		return fmt.tprintf("%s AT %d,%d", cm.name_str(&e.world.maps[mi].name), x, y)
	}
	return ""
}

// --- Tags ---

// What the selected character's tags are: its own settings over its type's tags.
tag_view :: proc(e: ^Editor) -> cm.Tag_View {
	c := current(e)
	inherited: cm.Tag_Mask
	if ti := cm.world_find_char_type(e.world, cm.name_str(&c.type)); ti >= 0 {
		inherited = e.world.char_types[ti].tags
	}
	return cm.Tag_View{set = c.tags_set, cleared = c.tags_cleared, inherited = inherited, instance = true}
}

@(private = "file")
begin_tags :: proc(e: ^Editor) {
	if !need_character(e) {
		return
	}
	e.back = e.mode
	e.mode = .Tags
	cm.tag_list_fix(&e.tags, e.world.tag_count)
}

// Green on a tag: inherit -> set -> cleared -> inherit.
@(private = "file")
cycle_tag :: proc(e: ^Editor, tag: int) {
	if cm.world_cycle_character_tag(e.world, e.sel, tag) {
		e.dirty = true
	}
}

// Tags mode: up and down choose a tag, green cycles it, red goes back; the mouse clicks a row (which
// also cycles it) and the wheel scrolls.
@(private = "file")
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

// --- Actions ---

@(private = "file")
begin_rename :: proc(e: ^Editor) {
	if !need_character(e) {
		return
	}
	e.text_value = false
	cm.text_entry_begin(&e.entry, "RENAME CHARACTER", character_name(e, e.sel), cm.NAME_MAX)
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
}

// A new character gets the selected character's type (or the first type) and asks for its name.
@(private = "file")
new_character :: proc(e: ^Editor) {
	if e.world.char_type_count == 0 {
		e.note = NOTE_NEED_TYPE
		return
	}
	type_index := 0
	if has_characters(e) {
		type_index = max(cm.world_find_char_type(e.world, cm.name_str(&current(e).type)), 0)
	}
	if n := cm.world_add_character(e.world, type_index); n >= 0 {
		select(e, n)
		e.dirty = true
		begin_rename(e)
	} else {
		e.note = NOTE_FULL
	}
}

@(private = "file")
duplicate_character :: proc(e: ^Editor) {
	if !need_character(e) {
		return
	}
	if n := cm.world_duplicate_character(e.world, e.sel); n >= 0 {
		select(e, n)
		e.dirty = true
		begin_rename(e)
	} else {
		e.note = NOTE_FULL
	}
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_character :: proc(e: ^Editor) {
	if !need_character(e) {
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.world_delete_character(e.world, e.sel)
	fix_selection(e)
	e.dirty = true
}

@(private = "file")
step_type :: proc(e: ^Editor, delta: int) {
	if !need_character(e) {
		return
	}
	n := e.world.char_type_count
	if n == 0 {
		e.note = NOTE_NEED_TYPE
		return
	}
	cur := max(cm.world_find_char_type(e.world, cm.name_str(&current(e).type)), 0)
	next := ((cur + delta) % n + n) % n
	if next != cur {
		cm.world_set_character_type(e.world, e.sel, next)
		e.dirty = true
	}
}

@(private = "file")
toggle_player :: proc(e: ^Editor) {
	if !need_character(e) {
		return
	}
	if is_player(e, e.sel) {
		cm.world_set_player(e.world, cm.UUID_NONE)
	} else {
		cm.world_set_player(e.world, current(e).uuid)
	}
	e.dirty = true
}

@(private = "file")
unplace_character :: proc(e: ^Editor) {
	if !need_character(e) {
		return
	}
	if cm.world_unplace_character(e.world, current(e).uuid) {
		e.dirty = true
	} else {
		e.note = NOTE_NOT_PLACED
	}
}

@(private = "file")
handle_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	if e.text_value {
		handle_value_text(e, ev)
		return
	}
	handle_name_text(e, ev)
}

@(private = "file")
handle_name_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = e.back
	case .Done:
		name := cm.text_entry_text(&e.entry)
		switch cm.world_rename_character(e.world, e.sel, name) {
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

// --- Properties ---

// The properties of the selected character's type, or nil.
type_props :: proc(e: ^Editor) -> ^cm.Prop_Set {
	if !has_characters(e) {
		return nil
	}
	ti := cm.world_find_char_type(e.world, cm.name_str(&current(e).type))
	return ti >= 0 ? &e.world.char_types[ti].props : nil
}

props_count :: proc(e: ^Editor) -> int {
	if ps := type_props(e); ps != nil {
		return ps.count
	}
	return 0
}

@(private = "file")
begin_props :: proc(e: ^Editor) {
	if !need_character(e) {
		return
	}
	if props_count(e) == 0 {
		e.note = NOTE_NO_PROPS
		return
	}
	e.props_back = e.mode
	e.mode = .Props
	e.prop_sel = clamp(e.prop_sel, 0, props_count(e) - 1)
}

// The selected property's value for the selected character.
prop_value :: proc(e: ^Editor, p: int) -> i32 {
	return cm.world_character_value(e.world, e.sel, p)
}

@(private = "file")
set_prop :: proc(e: ^Editor, value: i32) {
	if prop_value(e, e.prop_sel) != value && cm.world_character_set_value(e.world, e.sel, e.prop_sel, value) {
		e.dirty = true
	}
}

@(private = "file")
step_prop :: proc(e: ^Editor, delta: int) {
	v := clamp(i64(prop_value(e, e.prop_sel)) + i64(delta), i64(min(i32)), i64(max(i32)))
	set_prop(e, i32(v))
}

// Yellow: the type's default again.
@(private = "file")
reset_prop :: proc(e: ^Editor) {
	if ps := type_props(e); ps != nil && e.prop_sel < ps.count {
		set_prop(e, ps.values[e.prop_sel])
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
begin_value :: proc(e: ^Editor) {
	e.text_value = true
	cm.text_entry_begin(&e.entry, "VALUE", fmt.tprintf("%d", prop_value(e, e.prop_sel)), 11)
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
}

@(private = "file")
handle_value_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = e.back
	case .Done:
		n, ok := parse_whole(cm.text_entry_text(&e.entry))
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

// Props mode: up and down choose a property, left and right change this character's value by 1, green types
// it, yellow puts back the type's default, red goes back. The mouse clicks a row (again to type its
// value) or a button.
@(private = "file")
handle_props :: proc(e: ^Editor, ev: cm.Input_Event) {
	n := props_count(e)
	#partial switch v in ev {
	case cm.Command:
		e.note = ""
		#partial switch v.action {
		case .Up:
			e.prop_sel = max(e.prop_sel - 1, 0)
		case .Down:
			e.prop_sel = min(e.prop_sel + 1, n - 1)
		case .Left:
			step_prop(e, -1)
		case .Right:
			step_prop(e, 1)
		case .Green:
			begin_value(e)
		case .Yellow:
			reset_prop(e)
		case .Red:
			e.mode = e.props_back
		}
	case cm.Mouse_Button_Event:
		if v.button != .Left || !v.down {
			return
		}
		e.note = ""
		if row := prop_row_at(v.x, v.y); row >= 0 && row < n {
			if row == e.prop_sel {
				begin_value(e) // again: type the value
			} else {
				e.prop_sel = row
			}
			return
		}
		switch {
		case rect_contains(PROP_VALUE_BUTTON, v.x, v.y):
			begin_value(e)
		case rect_contains(PROP_DEFAULT_BUTTON, v.x, v.y):
			reset_prop(e)
		case rect_contains(PROP_MINUS, v.x, v.y):
			step_prop(e, -1)
		case rect_contains(PROP_PLUS, v.x, v.y):
			step_prop(e, 1)
		case rect_contains(BACK_BUTTON, v.x, v.y):
			e.mode = e.props_back
		}
	}
}

@(private = "file")
run_row :: proc(e: ^Editor, row: Setup_Row) {
	switch row {
	case .Rename:
		begin_rename(e)
	case .New:
		new_character(e)
	case .Duplicate:
		duplicate_character(e)
	case .Delete:
		delete_character(e)
	case .Player:
		toggle_player(e)
	case .Unplace:
		unplace_character(e)
	case .Tags:
		begin_tags(e)
	case .Props:
		begin_props(e)
	case .Items:
		if need_character(e) {
			e.items_requested = true
		}
	case .Type:
		// A value, not an action: left/right change it.
	}
}

// --- Events ---

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	if e.mode == .Text {
		handle_text(e, ev)
		return
	}
	if e.mode == .Tags {
		handle_tags(e, ev)
		return
	}
	if e.mode == .Props {
		handle_props(e, ev)
		return
	}
	#partial switch v in ev {
	case cm.Command:
		e.note = ""
	case cm.Mouse_Button_Event:
		if v.down {
			e.note = ""
		}
	}
	switch v in ev {
	case cm.Command:
		editor_apply_action(e, v.action)
	case cm.Mouse_Move:
	case cm.Mouse_Button_Event:
		if v.button == .Left && v.down {
			click(e, v.x, v.y)
		}
	case cm.Mouse_Wheel:
		e.scroll = clamp(e.scroll - v.dy, 0, max(count(e) - LIST_ROWS, 0))
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	if !(e.mode == .Setup && e.row == .Delete && a == .Green) {
		e.confirm_delete = false
	}
	switch e.mode {
	case .List:
		#partial switch a {
		case .Up:
			if has_characters(e) {
				select(e, max(e.sel - 1, 0))
			}
		case .Down:
			if has_characters(e) {
				select(e, min(e.sel + 1, count(e) - 1))
			}
		case .Green:
			begin_rename(e)
		case .Yellow:
			e.mode = .Setup
		case .Red:
			e.exit_requested = true
		}
	case .Setup:
		#partial switch a {
		case .Up:
			e.row = Setup_Row((int(e.row) + len(Setup_Row) - 1) % len(Setup_Row))
		case .Down:
			e.row = Setup_Row((int(e.row) + 1) % len(Setup_Row))
		case .Left:
			if e.row == .Type {
				step_type(e, -1)
			}
		case .Right:
			if e.row == .Type {
				step_type(e, 1)
			}
		case .Green:
			run_row(e, e.row)
		case .Red:
			e.mode = .List
		}
	case .Text, .Tags, .Props:
	}
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	if row, ok := list_row_at(x, y); ok {
		index := e.scroll + row
		if index < count(e) {
			if index == e.sel && e.mode == .List {
				begin_rename(e) // clicking the selected character again renames it
			} else {
				select(e, index)
				e.mode = .List
			}
		}
		return
	}
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		run_row(e, row)
	}
	switch {
	case rect_contains(TYPE_MINUS, x, y):
		e.mode, e.row = .Setup, .Type
		step_type(e, -1)
	case rect_contains(TYPE_PLUS, x, y):
		e.mode, e.row = .Setup, .Type
		step_type(e, 1)
	case rect_contains(RENAME_BUTTON, x, y):
		action(e, .Rename)
	case rect_contains(NEW_BUTTON, x, y):
		action(e, .New)
	case rect_contains(DUPLICATE_BUTTON, x, y):
		action(e, .Duplicate)
	case rect_contains(DELETE_BUTTON, x, y):
		action(e, .Delete) // a second click confirms
	case rect_contains(PLAYER_BUTTON, x, y):
		action(e, .Player)
	case rect_contains(UNPLACE_BUTTON, x, y):
		action(e, .Unplace)
	case rect_contains(PROPS_BUTTON, x, y):
		action(e, .Props)
	case rect_contains(ITEMS_BUTTON, x, y):
		action(e, .Items)
	case rect_contains(TAGS_BUTTON, x, y):
		action(e, .Tags)
	case rect_contains(BACK_BUTTON, x, y):
		e.exit_requested = true
	}
}
