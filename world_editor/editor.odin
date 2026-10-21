package world_editor

import cce "../character_editor"
import cm "../common"
import cte "../character_type_editor"
import me "../map_editor"
import pe "../palette_editor"
import spe "../sprite_editor"
import te "../tileset_editor"
import tre "../terrain_editor"
import "core:fmt"
import "core:mem"
import "core:time"

Request :: enum {
	Save,
	Load,
}

Aux_Request :: enum {
	Tileset, // import tileset.json
}

TILESET_FILE :: "tileset.json"

// The world editor edits one cm.World: its palette, tile size, tilesets, terrain sets and maps.
// Red always means "back". Modes:
//   Hub:   the parts of the world, one per row. Up/down choose; green opens the part (the palette
//          editor, or the list of tilesets / terrain sets / maps); left/right change the tile
//          size on its rows; blue opens File; red leaves for the main menu (twice if unsaved).
//   List:  the named items of one kind. Up/down choose; green opens the item in its editor (tileset
//          editor, terrain set editor, map editor); yellow opens Actions; red returns to the hub.
//   Setup: (Actions) up/down choose Open / Rename / New / Duplicate / Delete (green twice) /
//          Import (tilesets: tileset.json); green runs it; red returns to the list.
//   Text:  the keypad, for names. New and Duplicate ask for the name first, then open the item.
//   File:  green saves world.json, yellow loads it, red or blue cancel.
//   Palette, Tileset, Terrain, Map: the embedded editors; red in their top mode comes back here.
// The mouse works everywhere. The world is a ~17 MB global: this Editor must be created with
// editor_init in place, never copied.
Mode :: enum {
	Hub,
	List,
	Setup,
	Text,
	File,
	Palette,
	Tileset,
	Terrain,
	Sprite,
	Char_Type,
	Character,
	Map,
}

Section :: enum {
	Tilesets,
	Terrain_Sets,
	Sprite_Sets,
	Maps,
}

Hub_Row :: enum {
	Palette,
	Tile_Width,
	Tile_Height,
	Tilesets,
	Terrain_Sets,
	Sprite_Sets,
	Character_Types,
	Characters,
	Maps,
}

HUB_ROWS :: len(Hub_Row)

Setup_Row :: enum {
	Open,
	Rename,
	New,
	Duplicate,
	Delete,
	Import,
}

Editor :: struct {
	world:          cm.World,
	hub:            Hub_Row,
	section:        Section,
	sel:            [Section]int, // the selected item in each list
	scroll:         int,
	mode:           Mode,
	row:            Setup_Row,
	open_after:     bool, // the keypad was opened by New / Duplicate / Import: open the item when it closes
	dirty:          bool, // the world changed since the last save/load
	requests:       bit_set[Request],
	aux_requests:   bit_set[Aux_Request],
	exit_requested: bool,
	confirm_exit:   bool,
	confirm_delete: bool,
	note:           string,
	palette_ed:     pe.Editor,
	tileset_ed:     te.Editor, // about 1 MB
	terrain_ed:     tre.Editor,
	sprite_ed:      spe.Editor,
	char_type_ed:   cte.Editor,
	character_ed:   cce.Editor,
	map_ed:         me.Editor,
	opened:         int, // the tileset being edited in Tileset mode
	entry:          cm.Text_Entry,
	labels:         ^cm.Input_Map,
}

NOTE_NEED_SET :: "ADD A TERRAIN SET FIRST"
NOTE_EMPTY :: "NOTHING HERE YET: USE NEW"
NOTE_FULL :: "THAT LIST IS FULL"
NOTE_NAME_EMPTY :: "A NAME CANNOT BE EMPTY"
NOTE_NAME_USED :: "NAME ALREADY IN USE"
NOTE_NAME_BAD :: "UNUSABLE CHARACTER IN NAME"
NOTE_IMPORT_ASKED :: "LOOKING FOR TILESET.JSON"
NOTE_IMPORT_BAD :: "TILESET.JSON IS NOT A TILESET"

// Starts blank: no parts, 16 x 16 tiles, the default palette.
editor_init :: proc(e: ^Editor) {
	labels := e.labels
	mem.zero_item(e)
	e.labels = labels
	cm.world_reset(&e.world)
	e.palette_ed = pe.editor_init()
	set_sub_labels(e)
}

// Called each time the tool becomes the active one: start blank (so unsaved edits do not survive
// leaving), then ask the frontend for the saved world.
editor_enter :: proc(e: ^Editor) {
	editor_init(e)
	cm.world_seed_uuids(&e.world, u64(time.now()._nsec)) // new character uuids differ from run to run
	e.requests = {.Load}
}

editor_mark_saved :: proc(e: ^Editor) {
	e.dirty = false
}

editor_set_labels :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.labels = m
	set_sub_labels(e)
}

@(private = "file")
set_sub_labels :: proc(e: ^Editor) {
	e.palette_ed.labels = e.labels
	te.editor_set_labels(&e.tileset_ed, e.labels)
	tre.editor_set_labels(&e.terrain_ed, e.labels)
	spe.editor_set_labels(&e.sprite_ed, e.labels)
	cte.editor_set_labels(&e.char_type_ed, e.labels)
	cce.editor_set_labels(&e.character_ed, e.labels)
	me.editor_set_labels(&e.map_ed, e.labels)
}

// --- Lists ---

section_count :: proc(e: ^Editor, s: Section) -> int {
	switch s {
	case .Tilesets:
		return e.world.tileset_count
	case .Terrain_Sets:
		return e.world.set_count
	case .Sprite_Sets:
		return e.world.sprite_set_count
	case .Maps:
		return e.world.map_count
	}
	return 0
}

section_limit :: proc(s: Section) -> int {
	switch s {
	case .Tilesets:
		return cm.WORLD_MAX_TILESETS
	case .Terrain_Sets:
		return cm.WORLD_MAX_TERRAIN_SETS
	case .Sprite_Sets:
		return cm.WORLD_MAX_SPRITE_SETS
	case .Maps:
		return cm.WORLD_MAX_MAPS
	}
	return 0
}

section_item_name :: proc(e: ^Editor, s: Section, i: int) -> string {
	switch s {
	case .Tilesets:
		return cm.name_str(&e.world.tileset_names[i])
	case .Terrain_Sets:
		return cm.name_str(&e.world.sets[i].name)
	case .Sprite_Sets:
		return cm.name_str(&e.world.sprite_sets[i].name)
	case .Maps:
		return cm.name_str(&e.world.maps[i].name)
	}
	return ""
}

selected :: proc(e: ^Editor) -> int {
	return e.sel[e.section]
}

fix_selection :: proc(e: ^Editor) {
	n := section_count(e, e.section)
	e.sel[e.section] = clamp(e.sel[e.section], 0, max(n - 1, 0))
	row := e.sel[e.section]
	if row < e.scroll {
		e.scroll = row
	} else if row >= e.scroll + LIST_ROWS {
		e.scroll = row - LIST_ROWS + 1
	}
	e.scroll = clamp(e.scroll, 0, max(n - LIST_ROWS, 0))
}

@(private = "file")
select :: proc(e: ^Editor, index: int) {
	e.sel[e.section] = index
	fix_selection(e)
}

@(private = "file")
open_list :: proc(e: ^Editor, s: Section) {
	e.section = s
	e.scroll = 0
	e.mode = .List
	fix_selection(e)
}

@(private = "file")
touched :: proc(e: ^Editor) {
	e.dirty = true
}

@(private = "file")
need_item :: proc(e: ^Editor) -> bool {
	if section_count(e, e.section) == 0 {
		e.note = NOTE_EMPTY
		return false
	}
	return true
}

// --- Opening the embedded editors ---

@(private = "file")
open_palette :: proc(e: ^Editor) {
	pe.editor_begin_embedded(&e.palette_ed, &e.world.palette)
	e.palette_ed.labels = e.labels
	e.mode = .Palette
}

@(private = "file")
open_item :: proc(e: ^Editor) {
	if !need_item(e) {
		return
	}
	i := selected(e)
	switch e.section {
	case .Tilesets:
		te.editor_begin_embedded(&e.tileset_ed, &e.world, i)
		e.opened = i
		e.mode = .Tileset
	case .Terrain_Sets:
		tre.editor_begin(&e.terrain_ed, &e.world, i)
		e.mode = .Terrain
	case .Sprite_Sets:
		spe.editor_begin(&e.sprite_ed, &e.world, i)
		e.mode = .Sprite
	case .Maps:
		me.editor_begin(&e.map_ed, &e.world, i)
		e.mode = .Map
	}
}

// Takes the finished embedded editor's work back into the world and returns to where it was opened.
@(private = "file")
sync_embedded :: proc(e: ^Editor) {
	switch e.mode {
	case .Palette:
		if e.palette_ed.dirty {
			e.world.palette = e.palette_ed.palette
			e.palette_ed.dirty = false
			touched(e)
		}
		if e.palette_ed.exit_requested {
			e.world.palette = e.palette_ed.palette
			e.palette_ed.exit_requested = false
			e.mode = .Hub
		}
	case .Tileset:
		if e.tileset_ed.dirty {
			touched(e)
		}
		if e.tileset_ed.exit_requested {
			e.tileset_ed.exit_requested = false
			e.world.tilesets[e.opened] = e.tileset_ed.tileset
			e.mode = .List
		}
	case .Terrain:
		if e.terrain_ed.dirty {
			e.terrain_ed.dirty = false
			touched(e)
		}
		if e.terrain_ed.exit_requested {
			e.terrain_ed.exit_requested = false
			e.mode = .List
		}
	case .Char_Type:
		if e.char_type_ed.dirty {
			e.char_type_ed.dirty = false
			touched(e)
		}
		if e.char_type_ed.exit_requested {
			e.char_type_ed.exit_requested = false
			e.mode = .Hub
		}
	case .Character:
		if e.character_ed.dirty {
			e.character_ed.dirty = false
			touched(e)
		}
		if e.character_ed.exit_requested {
			e.character_ed.exit_requested = false
			e.mode = .Hub
		}
	case .Sprite:
		if e.sprite_ed.dirty {
			e.sprite_ed.dirty = false
			touched(e)
		}
		if e.sprite_ed.exit_requested {
			e.sprite_ed.exit_requested = false
			e.mode = .List
		}
	case .Map:
		if e.map_ed.dirty {
			e.map_ed.dirty = false
			touched(e)
		}
		if e.map_ed.exit_requested {
			e.map_ed.exit_requested = false
			e.mode = .List
		}
	case .Hub, .List, .Setup, .Text, .File:
	}
}

// --- Actions on the selected item ---

@(private = "file")
begin_rename :: proc(e: ^Editor) {
	if need_item(e) {
		cm.text_entry_begin(&e.entry, "RENAME", section_item_name(e, e.section, selected(e)), cm.NAME_MAX)
		e.mode = .Text
	}
}

// Adds an item of the current kind and asks for its name; it opens in its editor afterwards.
@(private = "file")
new_item :: proc(e: ^Editor) {
	n := -1
	switch e.section {
	case .Tilesets:
		n = cm.world_add_tileset(&e.world)
	case .Terrain_Sets:
		n = cm.world_add_terrain_set(&e.world)
	case .Sprite_Sets:
		n = cm.world_add_sprite_set(&e.world)
	case .Maps:
		if e.world.set_count == 0 {
			e.note = NOTE_NEED_SET
			return
		}
		n = cm.world_add_map(&e.world, 0) // the first terrain set; the map editor can change it
	}
	finish_add(e, n)
}

@(private = "file")
duplicate_item :: proc(e: ^Editor) {
	if !need_item(e) {
		return
	}
	n := -1
	switch e.section {
	case .Tilesets:
		n = cm.world_duplicate_tileset(&e.world, selected(e))
	case .Terrain_Sets:
		n = cm.world_duplicate_terrain_set(&e.world, selected(e))
	case .Sprite_Sets:
		n = cm.world_duplicate_sprite_set(&e.world, selected(e))
	case .Maps:
		n = cm.world_duplicate_map(&e.world, selected(e))
	}
	finish_add(e, n)
}

@(private = "file")
finish_add :: proc(e: ^Editor, n: int) {
	if n < 0 {
		e.note = NOTE_FULL
		return
	}
	select(e, n)
	touched(e)
	begin_rename(e) // name it first, then open it
	e.open_after = true
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_item :: proc(e: ^Editor) {
	if !need_item(e) {
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	switch e.section {
	case .Tilesets:
		name := cm.name_str(&e.world.tileset_names[selected(e)])
		sprites := cm.world_tileset_sprite_uses(&e.world, name)
		if uses := cm.world_delete_tileset(&e.world, selected(e)); uses > 0 {
			e.note = fmt.tprintf("USED BY %s", cm.uses_text(uses - sprites, sprites))
			return
		}
	case .Terrain_Sets:
		if uses := cm.world_delete_terrain_set(&e.world, selected(e)); uses > 0 {
			e.note = fmt.tprintf("USED BY %d MAP%s", uses, uses == 1 ? "" : "S")
			return
		}
	case .Sprite_Sets:
		name := cm.name_str(&e.world.sprite_sets[selected(e)].name)
		if uses := cm.world_sprite_set_uses(&e.world, name); uses > 0 {
			e.note = fmt.tprintf("USED BY %d CHARACTER TYPE%s", uses, uses == 1 ? "" : "S")
			return
		}
		cm.world_delete_sprite_set(&e.world, selected(e))
	case .Maps:
		cm.world_delete_map(&e.world, selected(e))
	}
	fix_selection(e)
	touched(e)
}

@(private = "file")
request_import :: proc(e: ^Editor) {
	if e.section != .Tilesets {
		return
	}
	if e.world.tileset_count >= cm.WORLD_MAX_TILESETS {
		e.note = NOTE_FULL
		return
	}
	e.aux_requests += {.Tileset}
	e.note = NOTE_IMPORT_ASKED
}

// The frontend read tileset.json: add it as a new tileset if it fits the world.
editor_import_tileset :: proc(e: ^Editor, bytes: []u8) -> bool {
	src := new(cm.Tileset, context.temp_allocator)
	if msg := cm.tileset_from_json(bytes, src); msg != "" {
		e.note = NOTE_IMPORT_BAD
		return false
	}
	n := cm.world_add_tileset_copy(&e.world, src, "imported")
	switch n {
	case -2:
		e.note = fmt.tprintf("TILESET IS %dX%d, WORLD %dX%d", src.width, src.height, e.world.tile_w, e.world.tile_h)
		return false
	case -1:
		e.note = NOTE_FULL
		return false
	}
	e.section = .Tilesets
	if e.mode == .Hub || e.mode == .File {
		e.scroll = 0
	}
	e.mode = .List
	finish_add(e, n)
	return true
}

@(private = "file")
run_row :: proc(e: ^Editor, row: Setup_Row) {
	switch row {
	case .Open:
		open_item(e)
	case .Rename:
		begin_rename(e)
	case .New:
		new_item(e)
	case .Duplicate:
		duplicate_item(e)
	case .Delete:
		delete_item(e)
	case .Import:
		request_import(e)
	}
}

// The rows offered in the current list (Import is for tilesets only).
@(private = "file")
row_offered :: proc(e: ^Editor, row: Setup_Row) -> bool {
	return row != .Import || e.section == .Tilesets
}

@(private = "file")
step_row :: proc(e: ^Editor, delta: int) {
	for {
		e.row = Setup_Row((int(e.row) + delta + len(Setup_Row)) % len(Setup_Row))
		if row_offered(e, e.row) {
			return
		}
	}
}

@(private = "file")
handle_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = .List
		finish_name(e)
	case .Done:
		name := cm.text_entry_text(&e.entry)
		i := selected(e)
		problem: cm.Name_Problem
		switch e.section {
		case .Tilesets:
			problem = cm.world_check_tileset_name(&e.world, i, name)
		case .Terrain_Sets:
			problem = cm.world_check_set_name(&e.world, i, name)
		case .Sprite_Sets:
			problem = cm.world_check_sprite_set_name(&e.world, i, name)
		case .Maps:
			problem = cm.world_check_map_name(&e.world, i, name)
		}
		switch problem {
		case .None:
			if name != section_item_name(e, e.section, i) {
				switch e.section {
				case .Tilesets:
					cm.world_rename_tileset(&e.world, i, name)
				case .Terrain_Sets:
					cm.world_rename_terrain_set(&e.world, i, name)
				case .Sprite_Sets:
					cm.world_rename_sprite_set(&e.world, i, name)
				case .Maps:
					cm.world_rename_map(&e.world, i, name)
				}
				touched(e)
			}
			e.mode = .List
			finish_name(e)
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
finish_name :: proc(e: ^Editor) {
	if e.open_after {
		e.open_after = false
		open_item(e)
	}
}

// --- The hub ---

@(private = "file")
change_tile_size :: proc(e: ^Editor, dw, dh: int) {
	if cm.world_set_tile_size(&e.world, e.world.tile_w + dw, e.world.tile_h + dh) {
		touched(e)
	}
}

@(private = "file")
run_hub :: proc(e: ^Editor, row: Hub_Row) {
	#partial switch row {
	case .Palette:
		open_palette(e)
	case .Tilesets:
		open_list(e, .Tilesets)
	case .Terrain_Sets:
		open_list(e, .Terrain_Sets)
	case .Sprite_Sets:
		open_list(e, .Sprite_Sets)
	case .Character_Types:
		cte.editor_begin(&e.char_type_ed, &e.world)
		e.mode = .Char_Type
	case .Characters:
		cce.editor_begin(&e.character_ed, &e.world)
		e.mode = .Character
	case .Maps:
		open_list(e, .Maps)
	}
}

// --- Events ---

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	// The keypad and the embedded editors see everything while they are up.
	switch e.mode {
	case .Text:
		handle_text(e, ev)
		return
	case .Palette:
		pe.editor_handle_event(&e.palette_ed, ev)
		sync_embedded(e)
		return
	case .Tileset:
		te.editor_handle_event(&e.tileset_ed, ev)
		sync_embedded(e)
		return
	case .Terrain:
		tre.editor_handle_event(&e.terrain_ed, ev)
		sync_embedded(e)
		return
	case .Sprite:
		spe.editor_handle_event(&e.sprite_ed, ev)
		sync_embedded(e)
		return
	case .Char_Type:
		cte.editor_handle_event(&e.char_type_ed, ev)
		sync_embedded(e)
		return
	case .Character:
		cce.editor_handle_event(&e.character_ed, ev)
		sync_embedded(e)
		return
	case .Map:
		me.editor_handle_event(&e.map_ed, ev)
		sync_embedded(e)
		return
	case .Hub, .List, .Setup, .File:
	}
	// Any command or button press clears the message; moving the mouse or letting go does not.
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
		if e.mode == .List || e.mode == .Setup {
			e.scroll = clamp(e.scroll - v.dy, 0, max(section_count(e, e.section) - LIST_ROWS, 0))
		}
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	if a != .Red {
		e.confirm_exit = false
	}
	if !(e.mode == .Setup && e.row == .Delete && a == .Green) {
		e.confirm_delete = false
	}
	switch e.mode {
	case .Hub:
		#partial switch a {
		case .Up:
			e.hub = Hub_Row((int(e.hub) + HUB_ROWS - 1) % HUB_ROWS)
		case .Down:
			e.hub = Hub_Row((int(e.hub) + 1) % HUB_ROWS)
		case .Left, .Right:
			d := a == .Left ? -1 : 1
			#partial switch e.hub {
			case .Tile_Width:
				change_tile_size(e, d, 0)
			case .Tile_Height:
				change_tile_size(e, 0, d)
			}
		case .Green:
			run_hub(e, e.hub)
		case .Blue:
			e.mode = .File
		case .Red:
			request_exit(e)
		}
	case .List:
		n := section_count(e, e.section)
		#partial switch a {
		case .Up:
			if n > 0 {
				select(e, max(selected(e) - 1, 0))
			}
		case .Down:
			if n > 0 {
				select(e, min(selected(e) + 1, n - 1))
			}
		case .Green:
			open_item(e)
		case .Yellow:
			e.mode = .Setup
			if !row_offered(e, e.row) {
				e.row = .Open
			}
		case .Red:
			e.mode = .Hub
		}
	case .Setup:
		#partial switch a {
		case .Up:
			step_row(e, -1)
		case .Down:
			step_row(e, 1)
		case .Green:
			run_row(e, e.row)
		case .Red:
			e.mode = .List
		}
	case .File:
		#partial switch a {
		case .Green:
			e.requests += {.Save}
			e.mode = .Hub
		case .Yellow:
			e.requests += {.Load}
			e.mode = .Hub
		case .Red, .Blue:
			e.mode = .Hub
		}
	case .Text, .Palette, .Tileset, .Terrain, .Sprite, .Char_Type, .Character, .Map:
		// Handled before this point: those modes own the input.
	}
}

// Leaving with unsaved changes needs a second request.
@(private = "file")
request_exit :: proc(e: ^Editor) {
	if e.dirty && !e.confirm_exit {
		e.confirm_exit = true
		return
	}
	e.confirm_exit = false
	e.exit_requested = true
}

// The window is closing. Clean: fine. Dirty: the first ask shows the "unsaved" prompt and says no;
// asking again while the prompt is still up says yes.
editor_allow_close :: proc(e: ^Editor) -> bool {
	if !editor_dirty(e) || e.confirm_exit {
		return true
	}
	e.confirm_exit = true
	return false
}

// Unsaved changes, including those an embedded editor has not handed over yet.
editor_dirty :: proc(e: ^Editor) -> bool {
	return e.dirty || (e.mode == .Palette && e.palette_ed.dirty) || (e.mode == .Tileset && e.tileset_ed.dirty)
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(MENU_BUTTON, x, y) {
		e.confirm_exit = false
	}
	if !rect_contains(DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	if e.mode == .File {
		e.mode = .Hub
	}
	if e.mode == .Hub {
		switch {
		case rect_contains(WIDTH_MINUS, x, y):
			e.hub = .Tile_Width
			change_tile_size(e, -1, 0)
			return
		case rect_contains(WIDTH_PLUS, x, y):
			e.hub = .Tile_Width
			change_tile_size(e, 1, 0)
			return
		case rect_contains(HEIGHT_MINUS, x, y):
			e.hub = .Tile_Height
			change_tile_size(e, 0, -1)
			return
		case rect_contains(HEIGHT_PLUS, x, y):
			e.hub = .Tile_Height
			change_tile_size(e, 0, 1)
			return
		case rect_contains(SAVE_BUTTON, x, y):
			e.requests += {.Save}
			return
		case rect_contains(LOAD_BUTTON, x, y):
			e.requests += {.Load}
			return
		case rect_contains(MENU_BUTTON, x, y):
			request_exit(e)
			return
		}
		if row, ok := hub_row_at(x, y); ok {
			e.hub = Hub_Row(row)
			if e.hub != .Tile_Width && e.hub != .Tile_Height {
				run_hub(e, e.hub)
			}
		}
		return
	}
	// List and Setup share the screen: the list on the left, the action buttons on the right.
	if row, ok := list_row_at(x, y); ok {
		index := e.scroll + row
		if index < section_count(e, e.section) {
			if index == selected(e) && e.mode == .List {
				open_item(e) // clicking the selected item again opens it
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
	case rect_contains(OPEN_BUTTON, x, y):
		action(e, .Open)
	case rect_contains(RENAME_BUTTON, x, y):
		action(e, .Rename)
	case rect_contains(NEW_BUTTON, x, y):
		action(e, .New)
	case rect_contains(DUPLICATE_BUTTON, x, y):
		action(e, .Duplicate)
	case rect_contains(DELETE_BUTTON, x, y):
		action(e, .Delete) // a second click confirms
	case rect_contains(IMPORT_BUTTON, x, y):
		if e.section == .Tilesets {
			action(e, .Import)
		}
	case rect_contains(BACK_BUTTON, x, y):
		e.mode = .Hub
	}
}
