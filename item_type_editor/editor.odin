package item_type_editor

import cm "../common"
import "core:fmt"
import "core:mem"

// The item type editor edits the item types of a world, in place, and is only ever hosted
// by the world editor, which owns the file. A type has a name and a sprite (one of the world's sprite
// sets and a sprite in it) that every item of the type draws. Types show over a checkerboard,
// or over a terrain of the world chosen as a background (only for looking; not saved).
//
// Red always means "back". Modes:
//   Pick:   d-pad moves over the types; green chooses the sprite (Sprite mode, or Setup first if the
//           type has no sprite set yet); yellow opens Setup; red leaves.
//   Setup:  up/down choose a row; left/right change the value rows (sprite set, sprite, background
//           set, background terrain) and green runs the action rows: Rename (the keypad), New,
//           Duplicate, Delete (green twice; refused while entries have the type), Choose sprite;
//           red returns to Pick.
//   Sprite: a grid of the sprites of the type's sprite set; d-pad moves, green chooses, red cancels.
//   Text:   the keypad, for names.
// The mouse works everywhere: click a thumbnail to select, again to choose its sprite; every row has
// - and + buttons or a button of its own.
Mode :: enum {
	Pick,
	Setup,
	Sprite,
	Text,
	Tags, // the world's tags, set or cleared on this item type
	Props, // the type's numeric properties
}

// What the keypad is typing.
Text_Target :: enum {
	Name, // this type's name
	Stack, // this type's max stack
	Prop_Value, // the default value of the selected property
	Prop_Name, // the name of the selected property
}

Setup_Row :: enum {
	Rename,
	New,
	Duplicate,
	Delete,
	Set,
	Sprite,
	Stack,
	Choose,
	Tags,
	Props,
	Bg_Set,
	Bg_Terrain,
}

Editor :: struct {
	world:          ^cm.World,
	sel:            int, // the selected type (0 while there are none)
	scroll:         int, // the first visible grid row
	mode:           Mode,
	row:            Setup_Row,
	back:           Mode, // where Sprite / Text return to
	bg_set:         int, // the terrain set whose terrain is the backdrop, or NO_BG for the checkerboard
	bg_terrain:     int, // the backdrop terrain in that set
	dirty:          bool, // the types changed since editor_begin
	exit_requested: bool,
	confirm_delete: bool,
	tags:           cm.Tag_List, // Tags mode: the selected tag
	text_target:    Text_Target,
	prop_sel:       int, // Props mode: the selected row (the property list, then a NEW row)
	confirm_prop:   bool, // the next green deletes the selected property
	props_back:     Mode, // where Props mode returns to (the keypad has its own `back`)
	note:           string,
	pick_sel:       int, // Sprite mode: the highlighted sprite
	pick_scroll:    int,
	entry:          cm.Text_Entry,
	labels:         ^cm.Input_Map,
}

NO_BG :: -1

NOTE_NO_TYPES :: "NO TYPES YET: USE NEW"
NOTE_FULL :: "THE WORLD HAS 128 TYPES"
NOTE_NO_SET :: "CHOOSE A SPRITE SET FIRST"
NOTE_NO_SPRITES :: "NO SPRITE SET HAS SPRITES YET"
NOTE_NO_BG_SET :: "CHOOSE A BACKGROUND SET FIRST"
NOTE_PROPS_FULL :: "A TYPE HAS 16 PROPERTIES AT MOST"
NOTE_NOT_NUMBER :: "TYPE A WHOLE NUMBER"
NOTE_STACK_RANGE :: "1 TO 1000000000"
NOTE_VALUE_RANGE :: "TOO BIG FOR 32 BITS"
NOTE_NAME_EMPTY :: "A NAME CANNOT BE EMPTY"
NOTE_NAME_USED :: "NAME ALREADY IN USE"
NOTE_NAME_BAD :: "UNUSABLE CHARACTER IN NAME"

// Starts the editor in Pick mode, with the checkerboard backdrop.
editor_begin :: proc(e: ^Editor, world: ^cm.World) {
	labels := e.labels
	mem.zero_item(e)
	e.labels = labels
	e.world = world
	e.bg_set = NO_BG
}

editor_set_labels :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.labels = m
}

type_count :: proc(e: ^Editor) -> int {
	return e.world.item_type_count
}

has_types :: proc(e: ^Editor) -> bool {
	return type_count(e) > 0
}

// The selected type (only valid while there is one).
current_type :: proc(e: ^Editor) -> ^cm.Item_Type {
	return &e.world.item_types[e.sel]
}

type_name :: proc(e: ^Editor, index: int) -> string {
	return cm.name_str(&e.world.item_types[index].name)
}

fix_selection :: proc(e: ^Editor) {
	count := type_count(e)
	e.sel = clamp(e.sel, 0, max(count - 1, 0))
	e.scroll = scroll_to(e.scroll, e.sel / GRID_COLS, grid_total_rows(count))
}

@(private = "file")
scroll_to :: proc(scroll, row, total_rows: int) -> int {
	s := scroll
	if row < s {
		s = row
	} else if row >= s + GRID_ROWS {
		s = row - GRID_ROWS + 1
	}
	return clamp(s, 0, max(total_rows - GRID_ROWS, 0))
}

@(private = "file")
select :: proc(e: ^Editor, index: int) {
	e.sel = index
	fix_selection(e)
}

@(private = "file")
need_type :: proc(e: ^Editor) -> bool {
	if !has_types(e) {
		e.note = NOTE_NO_TYPES
		return false
	}
	return true
}

// --- Tags ---

// What the selected type's tags are, for the tag list and the readouts.
tag_view :: proc(e: ^Editor) -> cm.Tag_View {
	return cm.Tag_View{set = current_type(e).tags}
}

@(private = "file")
begin_tags :: proc(e: ^Editor) {
	if !need_type(e) {
		return
	}
	e.back = e.mode
	e.mode = .Tags
	cm.tag_list_fix(&e.tags, e.world.tag_count)
}

// Green on a tag: every item of this type has it, or none does (unless its own setting says so).
@(private = "file")
toggle_tag :: proc(e: ^Editor, tag: int) {
	if cm.world_toggle_item_type_tag(e.world, e.sel, tag) {
		e.dirty = true
	}
}

// Tags mode: up and down choose a tag, green sets or clears it, red goes back; the mouse clicks a
// row (which also toggles it) and the wheel scrolls.
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
			toggle_tag(e, e.tags.sel)
		case .Red:
			e.mode = e.back
		}
	case cm.Mouse_Button_Event:
		if v.button == .Left && v.down {
			if tag, ok := cm.tag_list_at(&e.tags, n, v.x, v.y); ok {
				e.tags.sel = tag
				toggle_tag(e, tag)
			} else if rect_contains(BACK_BUTTON, v.x, v.y) {
				e.mode = e.back
			}
		}
	case cm.Mouse_Wheel:
		cm.tag_list_scroll(&e.tags, n, v.dy)
	}
}

// --- The backdrop ---

// The terrain shown behind sprites, or nil for the checkerboard.
backdrop :: proc(e: ^Editor) -> ^cm.Terrain {
	if e.bg_set < 0 || e.bg_set >= e.world.set_count {
		return nil
	}
	set := &e.world.sets[e.bg_set]
	if e.bg_terrain < 0 || e.bg_terrain >= set.count {
		return nil
	}
	return &set.terrains[e.bg_terrain]
}

@(private = "file")
step_bg_set :: proc(e: ^Editor, delta: int) {
	n := e.world.set_count + 1 // none + the sets
	cur := ((e.bg_set + 1 + delta) % n + n) % n
	e.bg_set = cur - 1
	e.bg_terrain = e.bg_set >= 0 ? e.world.sets[e.bg_set].default : 0
}

@(private = "file")
step_bg_terrain :: proc(e: ^Editor, delta: int) {
	if e.bg_set < 0 || e.bg_set >= e.world.set_count {
		e.note = NOTE_NO_BG_SET
		return
	}
	n := e.world.sets[e.bg_set].count
	e.bg_terrain = ((e.bg_terrain + delta) % n + n) % n
}

// --- Sprite set and sprite ---

// The sprite sets a type can use: those with at least one sprite. Index -1 (not set) comes first.
@(private = "file")
usable_sets :: proc(e: ^Editor) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	append(&out, -1)
	for i in 0 ..< e.world.sprite_set_count {
		if e.world.sprite_sets[i].count > 0 {
			append(&out, i)
		}
	}
	return out[:]
}

@(private = "file")
point_at :: proc(e: ^Editor, ct: ^cm.Item_Type, set, sprite: int) {
	if set < 0 {
		ct.sprite_set, ct.sprite = {}, {}
		return
	}
	ct.sprite_set = e.world.sprite_sets[set].name
	ct.sprite = e.world.sprite_sets[set].sprites[sprite].name
}

@(private = "file")
step_set :: proc(e: ^Editor, delta: int) {
	if !need_type(e) {
		return
	}
	ct := current_type(e)
	options := usable_sets(e)
	if len(options) == 1 {
		e.note = NOTE_NO_SPRITES
		return
	}
	cur := cm.world_find_sprite_set(e.world, cm.name_str(&ct.sprite_set))
	pos := 0
	for o, i in options {
		if o == cur {
			pos = i
		}
	}
	next := options[((pos + delta) % len(options) + len(options)) % len(options)]
	if next != cur {
		point_at(e, ct, next, 0)
		e.dirty = true
	}
}

@(private = "file")
step_sprite :: proc(e: ^Editor, delta: int) {
	if !need_type(e) {
		return
	}
	ct := current_type(e)
	si := cm.world_find_sprite_set(e.world, cm.name_str(&ct.sprite_set))
	if si < 0 {
		e.note = NOTE_NO_SET
		return
	}
	set := &e.world.sprite_sets[si]
	cur := max(cm.sprite_set_find(set, cm.name_str(&ct.sprite)), 0)
	next := ((cur + delta) % set.count + set.count) % set.count
	if next != cur {
		point_at(e, ct, si, next)
		e.dirty = true
	}
}

// How many sprites the sprite grid has: those of the selected type's set.
@(private = "file")
sprite_count :: proc(e: ^Editor) -> int {
	if !has_types(e) {
		return 0
	}
	si := cm.world_find_sprite_set(e.world, cm.name_str(&current_type(e).sprite_set))
	return si >= 0 ? e.world.sprite_sets[si].count : 0
}

// Opens the grid of the sprites of the type's set to choose from.
@(private = "file")
begin_sprite :: proc(e: ^Editor) {
	if !need_type(e) {
		return
	}
	ct := current_type(e)
	si := cm.world_find_sprite_set(e.world, cm.name_str(&ct.sprite_set))
	if si < 0 {
		e.note = NOTE_NO_SET
		return
	}
	e.pick_sel = max(cm.sprite_set_find(&e.world.sprite_sets[si], cm.name_str(&ct.sprite)), 0)
	e.pick_scroll = scroll_to(0, e.pick_sel / GRID_COLS, grid_total_rows(e.world.sprite_sets[si].count))
	e.back = e.mode
	e.mode = .Sprite
}

@(private = "file")
choose_sprite :: proc(e: ^Editor, index: int) {
	ct := current_type(e)
	si := cm.world_find_sprite_set(e.world, cm.name_str(&ct.sprite_set))
	if si >= 0 && index >= 0 && index < e.world.sprite_sets[si].count {
		if cm.name_str(&ct.sprite) != cm.name_str(&e.world.sprite_sets[si].sprites[index].name) {
			point_at(e, ct, si, index)
			e.dirty = true
		}
	}
	e.mode = e.back
}

// --- Naming, new, duplicate, delete ---

// Opens the keypad for `target`; leaving it returns to where it was opened.
@(private = "file")
begin_text :: proc(e: ^Editor, target: Text_Target, prompt, initial: string, max_len: int) {
	cm.text_entry_begin(&e.entry, prompt, initial, max_len)
	e.text_target = target
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
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
begin_stack :: proc(e: ^Editor) {
	if !need_type(e) {
		return
	}
	begin_text(e, .Stack, "MAX STACK", fmt.tprintf("%d", current_type(e).max_stack), 10)
}

// Sets the max stack; false (with a note) when entries hold more than the new size.
@(private = "file")
set_stack :: proc(e: ^Editor, n: int) -> bool {
	if n == current_type(e).max_stack {
		return true
	}
	if too_big := cm.world_set_item_type_max_stack(e.world, e.sel, n); too_big > 0 {
		e.note = fmt.tprintf("%d ENTRIES HOLD MORE", too_big)
		return false
	}
	e.dirty = true
	return true
}

@(private = "file")
step_stack :: proc(e: ^Editor, delta: int) {
	if !need_type(e) {
		return
	}
	set_stack(e, clamp(current_type(e).max_stack + delta, 1, cm.ITEM_MAX_STACK))
}

@(private = "file")
begin_rename :: proc(e: ^Editor) {
	if !need_type(e) {
		return
	}
	begin_text(e, .Name, "RENAME TYPE", type_name(e, e.sel), cm.NAME_MAX)
}

@(private = "file")
new_type :: proc(e: ^Editor) {
	if n := cm.world_add_item_type(e.world); n >= 0 {
		select(e, n)
		e.dirty = true
		begin_rename(e) // name it right away
	} else {
		e.note = NOTE_FULL
	}
}

@(private = "file")
duplicate_type :: proc(e: ^Editor) {
	if !need_type(e) {
		return
	}
	if n := cm.world_duplicate_item_type(e.world, e.sel); n >= 0 {
		select(e, n)
		e.dirty = true
		begin_rename(e)
	} else {
		e.note = NOTE_FULL
	}
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_type :: proc(e: ^Editor) {
	if !need_type(e) {
		e.confirm_delete = false
		return
	}
	if uses := cm.world_item_type_uses(e.world, type_name(e, e.sel)); uses > 0 {
		e.confirm_delete = false
		e.note = fmt.tprintf("USED BY %d ENTRY%s", uses, uses == 1 ? "" : "S")
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.world_delete_item_type(e.world, e.sel)
	fix_selection(e)
	e.dirty = true
}

@(private = "file")
handle_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = e.back
	case .Done:
		text := cm.text_entry_text(&e.entry)
		switch e.text_target {
		case .Name:
			finish_name(e, text)
		case .Stack:
			n, ok := parse_whole(text)
			switch {
			case !ok:
				cm.text_entry_resume(&e.entry, NOTE_NOT_NUMBER)
			case n < 1 || n > cm.ITEM_MAX_STACK:
				cm.text_entry_resume(&e.entry, NOTE_STACK_RANGE)
			case set_stack(e, int(n)):
				e.mode = e.back
			case:
				cm.text_entry_resume(&e.entry, e.note)
			}
		case .Prop_Value:
			n, ok := parse_whole(text)
			switch {
			case !ok:
				cm.text_entry_resume(&e.entry, NOTE_NOT_NUMBER)
			case n < i64(min(i32)) || n > i64(max(i32)):
				cm.text_entry_resume(&e.entry, NOTE_VALUE_RANGE)
			case:
				set_prop_value(e, i32(n))
				e.mode = e.back
			}
		case .Prop_Name:
			ps := &current_type(e).props
			switch cm.prop_set_rename(ps, e.prop_sel, text) {
			case .None:
				e.dirty = true
				e.mode = e.back
			case .Empty:
				cm.text_entry_resume(&e.entry, NOTE_NAME_EMPTY)
			case .In_Use:
				cm.text_entry_resume(&e.entry, NOTE_NAME_USED)
			case .Too_Long, .Bad_Character:
				cm.text_entry_resume(&e.entry, NOTE_NAME_BAD)
			}
		}
	}
}

@(private = "file")
finish_name :: proc(e: ^Editor, name: string) {
	switch cm.world_check_item_type_name(e.world, e.sel, name) {
	case .None:
		if name != type_name(e, e.sel) {
			cm.world_rename_item_type(e.world, e.sel, name) // its entries follow
			e.dirty = true
		}
		e.mode = e.back
	case .Empty:
		cm.text_entry_resume(&e.entry, NOTE_NAME_EMPTY)
	case .In_Use:
		cm.text_entry_resume(&e.entry, NOTE_NAME_USED)
	case .Too_Long, .Bad_Character:
		cm.text_entry_resume(&e.entry, NOTE_NAME_BAD)
	}
}

// --- Properties ---

// How many rows the Props list has: the properties, and a NEW row while there is room.
props_rows :: proc(e: ^Editor) -> int {
	n := current_type(e).props.count
	return n < cm.PROP_MAX ? n + 1 : n
}

@(private = "file")
on_property :: proc(e: ^Editor) -> bool {
	return has_types(e) && e.prop_sel >= 0 && e.prop_sel < current_type(e).props.count
}

@(private = "file")
begin_props :: proc(e: ^Editor) {
	if !need_type(e) {
		return
	}
	e.props_back = e.mode
	e.mode = .Props
	e.confirm_prop = false
	e.prop_sel = clamp(e.prop_sel, 0, props_rows(e) - 1)
}

@(private = "file")
set_prop_value :: proc(e: ^Editor, value: i32) {
	if on_property(e) && current_type(e).props.values[e.prop_sel] != value {
		current_type(e).props.values[e.prop_sel] = value
		e.dirty = true
	}
}

@(private = "file")
step_prop_value :: proc(e: ^Editor, delta: int) {
	if on_property(e) {
		v := clamp(i64(current_type(e).props.values[e.prop_sel]) + i64(delta), i64(min(i32)), i64(max(i32)))
		set_prop_value(e, i32(v))
	}
}

// Green on the NEW row: adds a property and asks for its name.
@(private = "file")
new_prop :: proc(e: ^Editor) {
	if cm.world_item_type_add_prop(e.world, e.sel) >= 0 {
		e.prop_sel = current_type(e).props.count - 1
		e.dirty = true
		begin_text(e, .Prop_Name, "NAME PROPERTY", cm.name_str(&current_type(e).props.names[e.prop_sel]), cm.NAME_MAX)
	} else {
		e.note = NOTE_PROPS_FULL
	}
}

@(private = "file")
delete_prop :: proc(e: ^Editor) {
	if on_property(e) {
		cm.world_item_type_delete_prop(e.world, e.sel, e.prop_sel)
		e.dirty = true
		e.prop_sel = clamp(e.prop_sel, 0, props_rows(e) - 1)
	}
}

// Green on a row: edit a property's default, or add a new property.
@(private = "file")
props_green :: proc(e: ^Editor) {
	if on_property(e) {
		begin_text(e, .Prop_Value, "DEFAULT VALUE", fmt.tprintf("%d", current_type(e).props.values[e.prop_sel]), 11)
	} else {
		new_prop(e)
	}
}

@(private = "file")
props_rename :: proc(e: ^Editor) {
	if on_property(e) {
		begin_text(e, .Prop_Name, "RENAME PROPERTY", cm.name_str(&current_type(e).props.names[e.prop_sel]), cm.NAME_MAX)
	}
}

// Blue arms the deletion of the selected property; the next green carries it out and anything else cancels.
@(private = "file")
props_delete :: proc(e: ^Editor) {
	if on_property(e) {
		e.confirm_prop = true
	}
}

// Props mode: up and down choose a row, left and right change the value by 1, green types the value
// (or adds a property on the NEW row), yellow renames, blue deletes (green confirms), red goes back.
// The mouse clicks a row (again to type its value) or a button.
@(private = "file")
handle_props :: proc(e: ^Editor, ev: cm.Input_Event) {
	#partial switch v in ev { 	// only a command or a left press can confirm or cancel a deletion
	case cm.Mouse_Move, cm.Mouse_Wheel:
		return
	case cm.Mouse_Button_Event:
		if v.button != .Left || !v.down {
			return
		}
	}
	armed := e.confirm_prop
	e.confirm_prop = false
	#partial switch v in ev {
	case cm.Command:
		e.note = ""
		if armed && v.action == .Green {
			delete_prop(e)
			return
		}
		rows := props_rows(e)
		#partial switch v.action {
		case .Up:
			e.prop_sel = max(e.prop_sel - 1, 0)
		case .Down:
			e.prop_sel = min(e.prop_sel + 1, rows - 1)
		case .Left:
			step_prop_value(e, -1)
		case .Right:
			step_prop_value(e, 1)
		case .Green:
			props_green(e)
		case .Yellow:
			props_rename(e)
		case .Blue:
			props_delete(e)
		case .Red:
			e.mode = e.props_back
		}
	case cm.Mouse_Button_Event:
		if v.button != .Left || !v.down {
			return
		}
		e.note = ""
		if row := prop_row_at(v.x, v.y); row >= 0 && row < props_rows(e) {
			if row == e.prop_sel || row >= current_type(e).props.count {
				e.prop_sel = row
				props_green(e) // again: type the value; the NEW row adds
			} else {
				e.prop_sel = row
			}
			return
		}
		switch {
		case rect_contains(PROP_VALUE_BUTTON, v.x, v.y):
			props_green(e)
		case rect_contains(PROP_NAME_BUTTON, v.x, v.y):
			props_rename(e)
		case rect_contains(PROP_DELETE_BUTTON, v.x, v.y):
			if armed {
				delete_prop(e) // a second click confirms
			} else {
				props_delete(e)
			}
		case rect_contains(PROP_NEW_BUTTON, v.x, v.y):
			new_prop(e)
		case rect_contains(PROP_MINUS, v.x, v.y):
			step_prop_value(e, -1)
		case rect_contains(PROP_PLUS, v.x, v.y):
			step_prop_value(e, 1)
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
		new_type(e)
	case .Duplicate:
		duplicate_type(e)
	case .Delete:
		delete_type(e)
	case .Choose:
		begin_sprite(e)
	case .Tags:
		begin_tags(e)
	case .Props:
		begin_props(e)
	case .Stack:
		begin_stack(e) // a value, but typing it beats pressing + a million times
	case .Set, .Sprite, .Bg_Set, .Bg_Terrain:
		// Values, not actions: left/right change them.
	}
}

@(private = "file")
change_setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
	#partial switch row {
	case .Set:
		step_set(e, delta)
	case .Sprite:
		step_sprite(e, delta)
	case .Stack:
		step_stack(e, delta)
	case .Bg_Set:
		step_bg_set(e, delta)
	case .Bg_Terrain:
		step_bg_terrain(e, delta)
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
		if e.mode == .Sprite {
			e.pick_scroll = clamp(e.pick_scroll - v.dy, 0, max(grid_total_rows(sprite_count(e)) - GRID_ROWS, 0))
		} else {
			e.scroll = clamp(e.scroll - v.dy, 0, max(grid_total_rows(type_count(e)) - GRID_ROWS, 0))
		}
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	if !(e.mode == .Setup && e.row == .Delete && a == .Green) {
		e.confirm_delete = false
	}
	count := type_count(e)
	switch e.mode {
	case .Pick:
		#partial switch a {
		case .Up:
			if has_types(e) && e.sel - GRID_COLS >= 0 {
				select(e, e.sel - GRID_COLS)
			}
		case .Down:
			if has_types(e) && e.sel + GRID_COLS < count {
				select(e, e.sel + GRID_COLS)
			}
		case .Left:
			if e.sel > 0 {
				select(e, e.sel - 1)
			}
		case .Right:
			if e.sel + 1 < count {
				select(e, e.sel + 1)
			}
		case .Green:
			choose_picture(e)
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
			change_setting(e, e.row, -1)
		case .Right:
			change_setting(e, e.row, 1)
		case .Green:
			run_row(e, e.row)
		case .Red:
			e.mode = .Pick
		}
	case .Sprite:
		n := sprite_count(e)
		#partial switch a {
		case .Up:
			if e.pick_sel - GRID_COLS >= 0 {
				e.pick_sel -= GRID_COLS
			}
		case .Down:
			if e.pick_sel + GRID_COLS < n {
				e.pick_sel += GRID_COLS
			}
		case .Left:
			e.pick_sel = max(e.pick_sel - 1, 0)
		case .Right:
			e.pick_sel = min(e.pick_sel + 1, n - 1)
		case .Green:
			choose_sprite(e, e.pick_sel)
		case .Red:
			e.mode = e.back
		}
		e.pick_scroll = scroll_to(e.pick_scroll, e.pick_sel / GRID_COLS, grid_total_rows(n))
	case .Text, .Tags, .Props:
	}
}

// Green on a type in Pick mode: its sprite. A type without a sprite set goes to Setup on the Set
// row first.
@(private = "file")
choose_picture :: proc(e: ^Editor) {
	if !need_type(e) {
		return
	}
	if cm.name_str(&current_type(e).sprite_set) == "" {
		e.mode, e.row = .Setup, .Set
		step_set(e, 1)
		return
	}
	begin_sprite(e)
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	if col, row, ok := grid_cell_at(x, y); ok {
		if e.mode == .Sprite {
			if index := (e.pick_scroll + row) * GRID_COLS + col; index < sprite_count(e) {
				choose_sprite(e, index)
			}
			return
		}
		index := (e.scroll + row) * GRID_COLS + col
		if index < type_count(e) {
			if index == e.sel && e.mode == .Pick {
				choose_picture(e) // clicking the selected type again chooses its sprite
			} else {
				select(e, index)
				e.mode = .Pick
			}
		}
		return
	}
	if e.mode == .Sprite { 	// the only other control is BACK
		if rect_contains(BACK_BUTTON, x, y) {
			e.mode = e.back
		}
		return
	}
	setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
		e.mode, e.row = .Setup, row
		change_setting(e, row, delta)
	}
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		run_row(e, row)
	}
	switch {
	case rect_contains(SET_MINUS, x, y):
		setting(e, .Set, -1)
	case rect_contains(SET_PLUS, x, y):
		setting(e, .Set, 1)
	case rect_contains(SPRITE_MINUS, x, y):
		setting(e, .Sprite, -1)
	case rect_contains(SPRITE_PLUS, x, y):
		setting(e, .Sprite, 1)
	case rect_contains(STACK_MINUS, x, y):
		setting(e, .Stack, -1)
	case rect_contains(STACK_PLUS, x, y):
		setting(e, .Stack, 1)
	case rect_contains(STACK_VALUE, x, y):
		action(e, .Stack)
	case rect_contains(PROPS_BUTTON, x, y):
		action(e, .Props)
	case rect_contains(BG_SET_MINUS, x, y):
		setting(e, .Bg_Set, -1)
	case rect_contains(BG_SET_PLUS, x, y):
		setting(e, .Bg_Set, 1)
	case rect_contains(BG_TERRAIN_MINUS, x, y):
		setting(e, .Bg_Terrain, -1)
	case rect_contains(BG_TERRAIN_PLUS, x, y):
		setting(e, .Bg_Terrain, 1)
	case rect_contains(RENAME_BUTTON, x, y):
		action(e, .Rename)
	case rect_contains(NEW_BUTTON, x, y):
		action(e, .New)
	case rect_contains(DUPLICATE_BUTTON, x, y):
		action(e, .Duplicate)
	case rect_contains(DELETE_BUTTON, x, y):
		action(e, .Delete) // a second click confirms
	case rect_contains(PICK_BUTTON, x, y):
		action(e, .Choose)
	case rect_contains(TAGS_BUTTON, x, y):
		action(e, .Tags)
	case rect_contains(BACK_BUTTON, x, y):
		e.exit_requested = true
	}
}
