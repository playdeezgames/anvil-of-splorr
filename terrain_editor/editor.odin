package terrain_editor

import cm "../common"
import "core:fmt"
import "core:mem"

// The terrain set editor edits one terrain set of a world, in place, and is only ever hosted by the
// world editor, which owns the file. Each terrain has a name, a solid flag and a picture: an image
// of one of the world's tilesets.
//
// Red always means "back". Modes:
//   Pick:  d-pad moves over the terrains; green chooses the picture (Image mode, or Setup first if
//          the terrain has no tileset yet); yellow opens Setup; red leaves.
//   Setup: up/down choose a row; left/right change the value rows (tileset, image, solid) and
//          green runs the action rows: Rename (the keypad), New, Duplicate, Delete (green twice),
//          Make default, Choose image; red returns to Pick.
//   Image: a grid of the images of the terrain's tileset; d-pad moves, green chooses, red cancels.
//   Text:  the keypad, for names.
// The mouse works everywhere: click a thumbnail to select, again to choose its picture; every row
// has - and + buttons or a button of its own.
Mode :: enum {
	Pick,
	Setup,
	Image,
	Text,
	Tags, // the world's tags, set or cleared on this terrain
}

Setup_Row :: enum {
	Rename,
	New,
	Duplicate,
	Delete,
	Default,
	Tags,
	Tileset,
	Image,
	Choose,
}

Editor :: struct {
	world:          ^cm.World,
	set_index:      int,
	sel:            int, // the selected terrain
	scroll:         int, // the first visible grid row
	mode:           Mode,
	row:            Setup_Row,
	back:           Mode, // where Image / Text return to
	dirty:          bool, // the set changed since editor_begin
	exit_requested: bool,
	confirm_delete: bool,
	tags:           cm.Tag_List, // Tags mode: the selected tag
	note:           string,
	pick_sel:       int, // Image mode: the highlighted image
	pick_scroll:    int,
	entry:          cm.Text_Entry,
	labels:         ^cm.Input_Map,
}

NOTE_LAST_ONE :: "A SET NEEDS AT LEAST ONE TERRAIN"
NOTE_IS_DEFAULT :: "MAKE ANOTHER TERRAIN THE DEFAULT FIRST"
NOTE_FULL :: "THE SET HAS 256 TERRAINS"
NOTE_NO_TILESET :: "CHOOSE A TILESET FIRST"
NOTE_NO_IMAGES :: "NO TILESET HAS IMAGES YET"
NOTE_NAME_EMPTY :: "A NAME CANNOT BE EMPTY"
NOTE_NAME_USED :: "NAME ALREADY IN USE"
NOTE_NAME_BAD :: "UNUSABLE CHARACTER IN NAME"

// Starts editing terrain set `index` of the world in Pick mode on its default terrain.
editor_begin :: proc(e: ^Editor, world: ^cm.World, index: int) {
	labels := e.labels
	mem.zero_item(e)
	e.labels = labels
	e.world = world
	e.set_index = index
	e.sel = world.sets[index].default
	fix_selection(e)
}

editor_set_labels :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.labels = m
}

current_set :: proc(e: ^Editor) -> ^cm.Terrain_Set {
	return &e.world.sets[e.set_index]
}

current_terrain :: proc(e: ^Editor) -> ^cm.Terrain {
	return &current_set(e).terrains[e.sel]
}

terrain_name :: proc(e: ^Editor, index: int) -> string {
	return cm.name_str(&current_set(e).terrains[index].name)
}

fix_selection :: proc(e: ^Editor) {
	count := current_set(e).count
	e.sel = clamp(e.sel, 0, count - 1)
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

// --- Tileset and image choices ---

// The tilesets a terrain can use: those with at least one image. Index -1 (not set) comes first.
@(private = "file")
usable_tilesets :: proc(e: ^Editor) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	append(&out, -1)
	for i in 0 ..< e.world.tileset_count {
		if e.world.tilesets[i].count > 0 {
			append(&out, i)
		}
	}
	return out[:]
}

@(private = "file")
point_at :: proc(e: ^Editor, t: ^cm.Terrain, tileset, image: int) {
	if tileset < 0 {
		t.tileset, t.image = {}, {}
		return
	}
	t.tileset = e.world.tileset_names[tileset]
	cm.name_assign(&t.image, cm.tileset_name(&e.world.tilesets[tileset], image))
}

@(private = "file")
step_tileset :: proc(e: ^Editor, delta: int) {
	t := current_terrain(e)
	options := usable_tilesets(e)
	if len(options) == 1 {
		e.note = NOTE_NO_IMAGES
		return
	}
	cur := cm.world_find_tileset(e.world, cm.name_str(&t.tileset))
	pos := 0
	for o, i in options {
		if o == cur {
			pos = i
		}
	}
	next := options[((pos + delta) % len(options) + len(options)) % len(options)]
	if next != cur {
		point_at(e, t, next, 0)
		e.dirty = true
	}
}

@(private = "file")
step_image :: proc(e: ^Editor, delta: int) {
	t := current_terrain(e)
	ti := cm.world_find_tileset(e.world, cm.name_str(&t.tileset))
	if ti < 0 {
		e.note = NOTE_NO_TILESET
		return
	}
	ts := &e.world.tilesets[ti]
	cur := max(cm.tileset_find(ts, cm.name_str(&t.image)), 0)
	next := ((cur + delta) % ts.count + ts.count) % ts.count
	if next != cur {
		point_at(e, t, ti, next)
		e.dirty = true
	}
}

// What the selected terrain's tags are, for the tag list and the readouts.
tag_view :: proc(e: ^Editor) -> cm.Tag_View {
	return cm.Tag_View{set = current_terrain(e).tags}
}

@(private = "file")
begin_tags :: proc(e: ^Editor) {
	e.back = e.mode
	e.mode = .Tags
	cm.tag_list_fix(&e.tags, e.world.tag_count)
}

// Green on a tag: it is on for this terrain or it is not.
@(private = "file")
toggle_tag :: proc(e: ^Editor, tag: int) {
	if cm.world_toggle_terrain_tag(e.world, e.set_index, e.sel, tag) {
		e.dirty = true
	}
}

@(private = "file")
make_default :: proc(e: ^Editor) {
	if current_set(e).default != e.sel {
		current_set(e).default = e.sel
		e.dirty = true
	}
}

// Opens the grid of the terrain's tileset to choose the image from.
@(private = "file")
begin_image :: proc(e: ^Editor) {
	t := current_terrain(e)
	ti := cm.world_find_tileset(e.world, cm.name_str(&t.tileset))
	if ti < 0 {
		e.note = NOTE_NO_TILESET
		return
	}
	e.pick_sel = max(cm.tileset_find(&e.world.tilesets[ti], cm.name_str(&t.image)), 0)
	e.pick_scroll = scroll_to(0, e.pick_sel / GRID_COLS, grid_total_rows(e.world.tilesets[ti].count))
	e.back = e.mode
	e.mode = .Image
}

@(private = "file")
choose_image :: proc(e: ^Editor, index: int) {
	t := current_terrain(e)
	ti := cm.world_find_tileset(e.world, cm.name_str(&t.tileset))
	if ti >= 0 && index >= 0 && index < e.world.tilesets[ti].count {
		before := cm.name_str(&t.image)
		name := cm.tileset_name(&e.world.tilesets[ti], index)
		if before != name {
			point_at(e, t, ti, index)
			e.dirty = true
		}
	}
	e.mode = e.back
}

// --- Naming, new, duplicate, delete ---

@(private = "file")
begin_rename :: proc(e: ^Editor) {
	cm.text_entry_begin(&e.entry, "RENAME TERRAIN", terrain_name(e, e.sel), cm.NAME_MAX)
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
}

@(private = "file")
new_terrain :: proc(e: ^Editor) {
	if n := cm.world_add_terrain(e.world, e.set_index); n >= 0 {
		select(e, n)
		e.dirty = true
		begin_rename(e) // name it right away
	} else {
		e.note = NOTE_FULL
	}
}

@(private = "file")
duplicate_terrain :: proc(e: ^Editor) {
	if n := cm.world_duplicate_terrain(e.world, e.set_index, e.sel); n >= 0 {
		select(e, n)
		e.dirty = true
		begin_rename(e)
	} else {
		e.note = NOTE_FULL
	}
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_terrain :: proc(e: ^Editor) {
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	result, uses := cm.world_delete_terrain(e.world, e.set_index, e.sel)
	switch result {
	case .Deleted:
		fix_selection(e)
		e.dirty = true
	case .Last_One:
		e.note = NOTE_LAST_ONE
	case .Is_Default:
		e.note = NOTE_IS_DEFAULT
	case .In_Use:
		e.note = fmt.tprintf("IN USE BY %d MAP CELL%s", uses, uses == 1 ? "" : "S")
	}
}

@(private = "file")
handle_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = e.back
	case .Done:
		name := cm.text_entry_text(&e.entry)
		switch cm.terrain_check_name(current_set(e), e.sel, name) {
		case .None:
			if name != terrain_name(e, e.sel) {
				cm.name_assign(&current_terrain(e).name, name)
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
		new_terrain(e)
	case .Duplicate:
		duplicate_terrain(e)
	case .Delete:
		delete_terrain(e)
	case .Default:
		make_default(e)
	case .Choose:
		begin_image(e)
	case .Tags:
		begin_tags(e)
	case .Tileset, .Image:
		// Values, not actions: left/right change them.
	}
}

@(private = "file")
change_setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
	#partial switch row {
	case .Tileset:
		step_tileset(e, delta)
	case .Image:
		step_image(e, delta)
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
		if e.mode == .Image {
			e.pick_scroll = clamp(e.pick_scroll - v.dy, 0, max(grid_total_rows(image_count(e)) - GRID_ROWS, 0))
		} else {
			e.scroll = clamp(e.scroll - v.dy, 0, max(grid_total_rows(current_set(e).count) - GRID_ROWS, 0))
		}
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

@(private = "file")
image_count :: proc(e: ^Editor) -> int {
	ti := cm.world_find_tileset(e.world, cm.name_str(&current_terrain(e).tileset))
	return ti >= 0 ? e.world.tilesets[ti].count : 0
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	if !(e.mode == .Setup && e.row == .Delete && a == .Green) {
		e.confirm_delete = false
	}
	count := current_set(e).count
	switch e.mode {
	case .Pick:
		#partial switch a {
		case .Up:
			if e.sel - GRID_COLS >= 0 {
				select(e, e.sel - GRID_COLS)
			}
		case .Down:
			if e.sel + GRID_COLS < count {
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
	case .Image:
		n := image_count(e)
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
			choose_image(e, e.pick_sel)
		case .Red:
			e.mode = e.back
		}
		e.pick_scroll = scroll_to(e.pick_scroll, e.pick_sel / GRID_COLS, grid_total_rows(n))
	case .Text, .Tags:
	}
}

// Green on a terrain in Pick mode: its picture. A terrain without a tileset goes to Setup on the
// Tileset row first.
@(private = "file")
choose_picture :: proc(e: ^Editor) {
	if cm.name_str(&current_terrain(e).tileset) == "" {
		e.mode, e.row = .Setup, .Tileset
		step_tileset(e, 1)
		return
	}
	begin_image(e)
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	if col, row, ok := grid_cell_at(x, y); ok {
		if e.mode == .Image {
			if index := (e.pick_scroll + row) * GRID_COLS + col; index < image_count(e) {
				choose_image(e, index)
			}
			return
		}
		index := (e.scroll + row) * GRID_COLS + col
		if index < current_set(e).count {
			if index == e.sel && e.mode == .Pick {
				choose_picture(e) // clicking the selected terrain again chooses its picture
			} else {
				select(e, index)
				e.mode = .Pick
			}
		}
		return
	}
	if e.mode == .Image { 	// the only other control is BACK
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
	case rect_contains(TILESET_MINUS, x, y):
		setting(e, .Tileset, -1)
	case rect_contains(TILESET_PLUS, x, y):
		setting(e, .Tileset, 1)
	case rect_contains(IMAGE_MINUS, x, y):
		setting(e, .Image, -1)
	case rect_contains(IMAGE_PLUS, x, y):
		setting(e, .Image, 1)
	case rect_contains(TAGS_BUTTON, x, y):
		action(e, .Tags)
	case rect_contains(DEFAULT_SWITCH, x, y), rect_contains(DEFAULT_BUTTON, x, y):
		action(e, .Default)
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
