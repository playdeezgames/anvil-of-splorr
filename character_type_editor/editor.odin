package character_type_editor

import cm "../common"
import "core:fmt"
import "core:mem"

// The character type editor edits the character types of a world, in place, and is only ever hosted
// by the world editor, which owns the file. A type has a name and a sprite (one of the world's sprite
// sets and a sprite in it) that every character of the type draws. Types show over a checkerboard,
// or over a terrain of the world chosen as a background (only for looking; not saved).
//
// Red always means "back". Modes:
//   Pick:   d-pad moves over the types; green chooses the sprite (Sprite mode, or Setup first if the
//           type has no sprite set yet); yellow opens Setup; red leaves.
//   Setup:  up/down choose a row; left/right change the value rows (sprite set, sprite, background
//           set, background terrain) and green runs the action rows: Rename (the keypad), New,
//           Duplicate, Delete (green twice; refused while characters have the type), Choose sprite;
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
}

Setup_Row :: enum {
	Rename,
	New,
	Duplicate,
	Delete,
	Set,
	Sprite,
	Choose,
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
	note:           string,
	pick_sel:       int, // Sprite mode: the highlighted sprite
	pick_scroll:    int,
	entry:          cm.Text_Entry,
	labels:         ^cm.Input_Map,
}

NO_BG :: -1

NOTE_NO_TYPES :: "NO TYPES YET: USE NEW"
NOTE_FULL :: "THE WORLD HAS 64 TYPES"
NOTE_NO_SET :: "CHOOSE A SPRITE SET FIRST"
NOTE_NO_SPRITES :: "NO SPRITE SET HAS SPRITES YET"
NOTE_NO_BG_SET :: "CHOOSE A BACKGROUND SET FIRST"
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
	return e.world.char_type_count
}

has_types :: proc(e: ^Editor) -> bool {
	return type_count(e) > 0
}

// The selected type (only valid while there is one).
current_type :: proc(e: ^Editor) -> ^cm.Character_Type {
	return &e.world.char_types[e.sel]
}

type_name :: proc(e: ^Editor, index: int) -> string {
	return cm.name_str(&e.world.char_types[index].name)
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
point_at :: proc(e: ^Editor, ct: ^cm.Character_Type, set, sprite: int) {
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

@(private = "file")
begin_rename :: proc(e: ^Editor) {
	if !need_type(e) {
		return
	}
	cm.text_entry_begin(&e.entry, "RENAME TYPE", type_name(e, e.sel), cm.NAME_MAX)
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
}

@(private = "file")
new_type :: proc(e: ^Editor) {
	if n := cm.world_add_char_type(e.world); n >= 0 {
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
	if n := cm.world_duplicate_char_type(e.world, e.sel); n >= 0 {
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
	if uses := cm.world_char_type_uses(e.world, type_name(e, e.sel)); uses > 0 {
		e.confirm_delete = false
		e.note = fmt.tprintf("USED BY %d CHARACTER%s", uses, uses == 1 ? "" : "S")
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.world_delete_char_type(e.world, e.sel)
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
		name := cm.text_entry_text(&e.entry)
		switch cm.world_check_char_type_name(e.world, e.sel, name) {
		case .None:
			if name != type_name(e, e.sel) {
				cm.world_rename_char_type(e.world, e.sel, name) // its characters follow
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
	case .Text:
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
	case rect_contains(BACK_BUTTON, x, y):
		e.exit_requested = true
	}
}
