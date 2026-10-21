package sprite_editor

import cm "../common"
import "core:fmt"
import "core:mem"

// The sprite set editor edits one sprite set of a world, in place, and is only ever hosted by the
// world editor, which owns the file. A sprite is a tile (an image of one of the world's tilesets)
// with a transparent colour index (or none) that is not drawn. Sprites show over a checkerboard,
// or over a terrain of the world chosen as a background (only for looking; not saved).
//
// Red always means "back". Modes:
//   Pick:  d-pad moves over the sprites; green chooses the picture (Image mode, or Setup first if
//          the sprite has no tileset yet); yellow opens Setup; red leaves.
//   Setup: up/down choose a row; left/right change the value rows (tileset, image, transparent
//          colour, background set, background terrain) and green runs the action rows: Rename (the
//          keypad), New, Duplicate, Delete (green twice), Choose image; red returns to Pick.
//   Image: a grid of the images of the sprite's tileset; d-pad moves, green chooses, red cancels.
//   Text:  the keypad, for names.
// The mouse works everywhere: click a thumbnail to select, again to choose its picture; every row
// has - and + buttons or a button of its own.
Mode :: enum {
	Pick,
	Setup,
	Image,
	Text,
}

Setup_Row :: enum {
	Rename,
	New,
	Duplicate,
	Delete,
	Transparent,
	Tileset,
	Image,
	Choose,
	Bg_Set,
	Bg_Terrain,
}

Editor :: struct {
	world:          ^cm.World,
	set_index:      int,
	sel:            int, // the selected sprite (0 while the set is empty)
	scroll:         int, // the first visible grid row
	mode:           Mode,
	row:            Setup_Row,
	back:           Mode, // where Image / Text return to
	bg_set:         int, // the terrain set whose terrain is the backdrop, or NO_BG for the checkerboard
	bg_terrain:     int, // the backdrop terrain in that set
	dirty:          bool, // the set changed since editor_begin
	exit_requested: bool,
	confirm_delete: bool,
	note:           string,
	pick_sel:       int, // Image mode: the highlighted image
	pick_scroll:    int,
	entry:          cm.Text_Entry,
	labels:         ^cm.Input_Map,
}

NO_BG :: -1

NOTE_NO_SPRITES :: "NO SPRITES YET: USE NEW"
NOTE_FULL :: "THE SET HAS 256 SPRITES"
NOTE_NO_TILESET :: "CHOOSE A TILESET FIRST"
NOTE_NO_IMAGES :: "NO TILESET HAS IMAGES YET"
NOTE_NO_BG_SET :: "CHOOSE A BACKGROUND SET FIRST"
NOTE_NAME_EMPTY :: "A NAME CANNOT BE EMPTY"
NOTE_NAME_USED :: "NAME ALREADY IN USE"
NOTE_NAME_BAD :: "UNUSABLE CHARACTER IN NAME"

// Starts editing sprite set `index` of the world in Pick mode, with the checkerboard backdrop.
editor_begin :: proc(e: ^Editor, world: ^cm.World, index: int) {
	labels := e.labels
	mem.zero_item(e)
	e.labels = labels
	e.world = world
	e.set_index = index
	e.bg_set = NO_BG
}

editor_set_labels :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.labels = m
}

current_set :: proc(e: ^Editor) -> ^cm.Sprite_Set {
	return &e.world.sprite_sets[e.set_index]
}

has_sprites :: proc(e: ^Editor) -> bool {
	return current_set(e).count > 0
}

// The selected sprite (only valid while the set has one).
current_sprite :: proc(e: ^Editor) -> ^cm.Sprite {
	return &current_set(e).sprites[e.sel]
}

sprite_name :: proc(e: ^Editor, index: int) -> string {
	return cm.name_str(&current_set(e).sprites[index].name)
}

fix_selection :: proc(e: ^Editor) {
	count := current_set(e).count
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
need_sprite :: proc(e: ^Editor) -> bool {
	if !has_sprites(e) {
		e.note = NOTE_NO_SPRITES
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

// Steps the background set: none, then each terrain set, wrapping.
@(private = "file")
step_bg_set :: proc(e: ^Editor, delta: int) {
	n := e.world.set_count + 1 // none + the sets
	cur := e.bg_set + 1
	cur = ((cur + delta) % n + n) % n
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

// --- Tileset, image and transparent colour ---

// The tilesets a sprite can use: those with at least one image. Index -1 (not set) comes first.
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
point_at :: proc(e: ^Editor, sp: ^cm.Sprite, tileset, image: int) {
	if tileset < 0 {
		sp.tileset, sp.image = {}, {}
		return
	}
	sp.tileset = e.world.tileset_names[tileset]
	cm.name_assign(&sp.image, cm.tileset_name(&e.world.tilesets[tileset], image))
}

@(private = "file")
step_tileset :: proc(e: ^Editor, delta: int) {
	if !need_sprite(e) {
		return
	}
	sp := current_sprite(e)
	options := usable_tilesets(e)
	if len(options) == 1 {
		e.note = NOTE_NO_IMAGES
		return
	}
	cur := cm.world_find_tileset(e.world, cm.name_str(&sp.tileset))
	pos := 0
	for o, i in options {
		if o == cur {
			pos = i
		}
	}
	next := options[((pos + delta) % len(options) + len(options)) % len(options)]
	if next != cur {
		point_at(e, sp, next, 0)
		e.dirty = true
	}
}

@(private = "file")
step_image :: proc(e: ^Editor, delta: int) {
	if !need_sprite(e) {
		return
	}
	sp := current_sprite(e)
	ti := cm.world_find_tileset(e.world, cm.name_str(&sp.tileset))
	if ti < 0 {
		e.note = NOTE_NO_TILESET
		return
	}
	ts := &e.world.tilesets[ti]
	cur := max(cm.tileset_find(ts, cm.name_str(&sp.image)), 0)
	next := ((cur + delta) % ts.count + ts.count) % ts.count
	if next != cur {
		point_at(e, sp, ti, next)
		e.dirty = true
	}
}

// Steps the transparent colour: none, 0 .. 15, wrapping.
@(private = "file")
step_transparent :: proc(e: ^Editor, delta: int) {
	if !need_sprite(e) {
		return
	}
	sp := current_sprite(e)
	n := cm.IMAGE_COLORS + 1
	cur := sp.transparent + 1 // none is 0, colour k is k + 1
	next := ((cur + delta) % n + n) % n - 1
	sp.transparent = next
	e.dirty = true
}

// Opens the grid of the sprite's tileset to choose the image from.
@(private = "file")
begin_image :: proc(e: ^Editor) {
	if !need_sprite(e) {
		return
	}
	sp := current_sprite(e)
	ti := cm.world_find_tileset(e.world, cm.name_str(&sp.tileset))
	if ti < 0 {
		e.note = NOTE_NO_TILESET
		return
	}
	e.pick_sel = max(cm.tileset_find(&e.world.tilesets[ti], cm.name_str(&sp.image)), 0)
	e.pick_scroll = scroll_to(0, e.pick_sel / GRID_COLS, grid_total_rows(e.world.tilesets[ti].count))
	e.back = e.mode
	e.mode = .Image
}

@(private = "file")
choose_image :: proc(e: ^Editor, index: int) {
	sp := current_sprite(e)
	ti := cm.world_find_tileset(e.world, cm.name_str(&sp.tileset))
	if ti >= 0 && index >= 0 && index < e.world.tilesets[ti].count {
		if cm.name_str(&sp.image) != cm.tileset_name(&e.world.tilesets[ti], index) {
			point_at(e, sp, ti, index)
			e.dirty = true
		}
	}
	e.mode = e.back
}

// --- Naming, new, duplicate, delete ---

@(private = "file")
begin_rename :: proc(e: ^Editor) {
	if !need_sprite(e) {
		return
	}
	cm.text_entry_begin(&e.entry, "RENAME SPRITE", sprite_name(e, e.sel), cm.NAME_MAX)
	e.back = e.mode == .Text ? e.back : e.mode
	e.mode = .Text
}

@(private = "file")
new_sprite :: proc(e: ^Editor) {
	if n := cm.world_add_sprite(e.world, e.set_index); n >= 0 {
		select(e, n)
		e.dirty = true
		begin_rename(e) // name it right away
	} else {
		e.note = NOTE_FULL
	}
}

@(private = "file")
duplicate_sprite :: proc(e: ^Editor) {
	if !need_sprite(e) {
		return
	}
	if n := cm.world_duplicate_sprite(e.world, e.set_index, e.sel); n >= 0 {
		select(e, n)
		e.dirty = true
		begin_rename(e)
	} else {
		e.note = NOTE_FULL
	}
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_sprite :: proc(e: ^Editor) {
	if !need_sprite(e) {
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.world_delete_sprite(e.world, e.set_index, e.sel)
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
		switch cm.sprite_check_name(current_set(e), e.sel, name) {
		case .None:
			if name != sprite_name(e, e.sel) {
				cm.name_assign(&current_sprite(e).name, name)
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
		new_sprite(e)
	case .Duplicate:
		duplicate_sprite(e)
	case .Delete:
		delete_sprite(e)
	case .Choose:
		begin_image(e)
	case .Transparent, .Tileset, .Image, .Bg_Set, .Bg_Terrain:
		// Values, not actions: left/right change them.
	}
}

@(private = "file")
change_setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
	#partial switch row {
	case .Transparent:
		step_transparent(e, delta)
	case .Tileset:
		step_tileset(e, delta)
	case .Image:
		step_image(e, delta)
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
		if e.mode == .Image {
			e.pick_scroll = clamp(e.pick_scroll - v.dy, 0, max(grid_total_rows(image_count(e)) - GRID_ROWS, 0))
		} else {
			e.scroll = clamp(e.scroll - v.dy, 0, max(grid_total_rows(current_set(e).count) - GRID_ROWS, 0))
		}
	}
}

@(private = "file")
image_count :: proc(e: ^Editor) -> int {
	if !has_sprites(e) {
		return 0
	}
	ti := cm.world_find_tileset(e.world, cm.name_str(&current_sprite(e).tileset))
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
			if has_sprites(e) && e.sel - GRID_COLS >= 0 {
				select(e, e.sel - GRID_COLS)
			}
		case .Down:
			if has_sprites(e) && e.sel + GRID_COLS < count {
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
	case .Text:
	}
}

// Green on a sprite in Pick mode: its picture. A sprite without a tileset goes to Setup on the
// Tileset row first.
@(private = "file")
choose_picture :: proc(e: ^Editor) {
	if !need_sprite(e) {
		return
	}
	if cm.name_str(&current_sprite(e).tileset) == "" {
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
				choose_picture(e) // clicking the selected sprite again chooses its picture
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
	case rect_contains(TRANSPARENT_MINUS, x, y):
		setting(e, .Transparent, -1)
	case rect_contains(TRANSPARENT_PLUS, x, y):
		setting(e, .Transparent, 1)
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
