#+build !js
package world_editor

import cm "../common"
import "core:strings"
import "core:testing"

new_editor :: proc() -> ^Editor {
	e := new(Editor)
	editor_init(e)
	return e
}

press :: proc(e: ^Editor, actions: ..cm.Action) {
	for a in actions {
		editor_handle_event(e, cm.Command{action = a})
	}
}

click_at :: proc(e: ^Editor, x, y: int) {
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = true})
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = false})
}

click_rect :: proc(e: ^Editor, rc: Rect) {
	click_at(e, rc.x + rc.w / 2, rc.y + rc.h / 2)
}

click_item :: proc(e: ^Editor, index: int) {
	rc := list_row_rect(index - e.scroll)
	click_at(e, rc.x + 4, rc.y + 3)
}

click_hub :: proc(e: ^Editor, row: Hub_Row) {
	rc := hub_row_rect(int(row))
	click_at(e, rc.x + 30, rc.y + 4)
}

goto_hub :: proc(e: ^Editor, row: Hub_Row) {
	for e.hub != row {
		press(e, .Down)
	}
}

// Opens a list from the hub with the commands.
open :: proc(e: ^Editor, s: Section) {
	e.mode = .Hub
	goto_hub(e, Hub_Row(int(Hub_Row.Tilesets) + int(s)))
	press(e, .Green)
}

goto_row :: proc(e: ^Editor, row: Setup_Row) {
	if e.mode == .List {
		press(e, .Yellow)
	}
	for e.row != row {
		press(e, .Down)
	}
}

run :: proc(e: ^Editor, row: Setup_Row) {
	goto_row(e, row)
	press(e, .Green)
}

type_with_commands :: proc(e: ^Editor, text: string, entry: ^cm.Text_Entry = nil) {
	entry := entry
	if entry == nil {
		entry = &e.entry
	}
	for i in 0 ..< len(text) {
		ch := text[i]
		if entry.row == cm.TEXT_ENTRY_ROWS - 1 {
			press(e, .Up)
		}
		tcol, trow := -1, -1
		for r in 0 ..< cm.TEXT_ENTRY_CHAR_ROWS {
			for c in 0 ..< cm.TEXT_ENTRY_COLS {
				if g, ok := cm.text_entry_char_at(c, r); ok && g == ch {
					tcol, trow = c, r
				}
			}
		}
		rights := (tcol - entry.col + cm.TEXT_ENTRY_COLS) % cm.TEXT_ENTRY_COLS
		downs := (trow - entry.row + cm.TEXT_ENTRY_ROWS) % cm.TEXT_ENTRY_ROWS
		for _ in 0 ..< rights {
			press(e, .Right)
		}
		for _ in 0 ..< downs {
			press(e, .Down)
		}
		press(e, .Green)
	}
}

press_keypad_action :: proc(e: ^Editor, a: cm.Text_Entry_Action, entry: ^cm.Text_Entry = nil) {
	entry := entry
	if entry == nil {
		entry = &e.entry
	}
	for entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(entry.col) != a {
		press(e, .Right)
	}
	press(e, .Green)
}

name_typed :: proc(e: ^Editor, name: string, entry: ^cm.Text_Entry = nil) {
	press_keypad_action(e, .Clear, entry)
	type_with_commands(e, name, entry)
	press_keypad_action(e, .Done, entry)
}

// New item named `name`, then back out of the editor it opens.
add :: proc(e: ^Editor, s: Section, name: string) {
	open(e, s)
	run(e, .New)
	name_typed(e, name)
	for e.mode != .List {
		press(e, .Red)
	}
	e.mode = .Hub
}

// A world in the editor with tileset "ground" (images g1 g2) and "empty", terrain set "land"
// (terrains grass, rock using g1 / g2) and map "start" of 3 x 3.
with_content :: proc() -> ^Editor {
	e := new_editor()
	w := &e.world
	cm.world_set_tile_size(w, 4, 4)
	g := cm.world_add_tileset(w, "ground")
	cm.tileset_insert_blank(&w.tilesets[g], 0, "g1")
	cm.tileset_insert_blank(&w.tilesets[g], 1, "g2")
	cm.world_add_tileset(w, "empty")
	s := cm.world_add_terrain_set(w, "land")
	cm.name_assign(&w.sets[s].terrains[0].name, "grass")
	rock := cm.world_add_terrain(w, s)
	cm.name_assign(&w.sets[s].terrains[rock].name, "rock")
	cm.name_assign(&w.sets[s].terrains[rock].image, "g2")
	m := cm.world_add_map(w, s, "start")
	cm.world_map_set_size(w, m, 3, 3)
	return e
}

@(test)
test_starts_in_the_hub_with_an_empty_default_world :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	testing.expect(t, e.mode == .Hub && e.hub == .Palette && !e.dirty && !e.exit_requested)
	testing.expect(t, e.world.tile_w == 16 && e.world.tileset_count == 0 && e.world.palette == cm.default_palette())
}

@(test)
test_hub_navigation_and_tile_size :: proc(t: ^testing.T) {
	e := with_content()
	defer free(e)
	press(e, .Up)
	testing.expect_value(t, e.hub, Hub_Row.Maps) // wraps
	press(e, .Down)
	testing.expect_value(t, e.hub, Hub_Row.Palette)
	goto_hub(e, .Tile_Width)
	press(e, .Right)
	testing.expect(t, e.world.tile_w == 5 && e.world.tilesets[0].width == 5 && e.world.tilesets[0].images[0].width == 5 && e.dirty)
	press(e, .Left, .Left)
	testing.expect_value(t, e.world.tile_w, 3)
	press(e, .Down, .Right)
	testing.expect_value(t, e.world.tile_h, 5)
	for _ in 0 ..< 70 {
		press(e, .Right)
	}
	testing.expect_value(t, e.world.tile_h, 64)
	for _ in 0 ..< 70 {
		press(e, .Left)
	}
	testing.expect_value(t, e.world.tile_h, 1)
	press(e, .Left) // the other rows ignore left and right
	press(e, .Down, .Left, .Right)
	testing.expect_value(t, e.world.tile_h, 1)
}

@(test)
test_the_palette_is_edited_in_place_and_red_returns :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Palette)
	testing.expect(t, e.palette_ed.embedded)
	press(e, .Green, .Right) // edit the red value of colour 0
	testing.expect(t, e.world.palette[0].r != cm.default_palette()[0].r || e.palette_ed.palette[0].r != cm.default_palette()[0].r)
	testing.expect(t, e.dirty)
	press(e, .Red, .Red)
	testing.expect_value(t, e.mode, Mode.Hub)
	testing.expect(t, e.world.palette[0] != cm.default_palette()[0])
	// A world's tilesets draw with that palette.
	e2 := with_content()
	defer free(e2)
	e2.world.palette[3] = {1, 2, 3}
	open(e2, .Tilesets)
	press(e2, .Green)
	testing.expect_value(t, e2.tileset_ed.palette[3], cm.Color{1, 2, 3})
}

@(test)
test_new_tileset_asks_for_a_name_and_then_opens_the_tileset_editor :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	open(e, .Tilesets)
	testing.expect_value(t, e.mode, Mode.List)
	testing.expect_value(t, e.note, "")
	press(e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Setup)
	run(e, .New)
	testing.expect(t, e.mode == .Text && e.world.tileset_count == 1 && e.dirty)
	name_typed(e, "Ground")
	testing.expect(t, e.mode == .Tileset && cm.name_str(&e.world.tileset_names[0]) == "Ground")
	testing.expect(t, e.tileset_ed.embedded && e.tileset_ed.tileset.width == 16)
	// Make an image in it, then come back: the world has the image.
	press(e, .Yellow, .Down, .Green) // Setup -> New
	press_keypad_action(e, .Cancel, &e.tileset_ed.entry) // keep the suggested name; the image editor opens
	press(e, .Red, .Red) // image editor -> tiles -> leave
	testing.expect_value(t, e.mode, Mode.List)
	testing.expect_value(t, e.world.tilesets[0].count, 1)
}

@(test)
test_the_tileset_editor_cannot_change_the_tile_size :: proc(t: ^testing.T) {
	e := with_content()
	defer free(e)
	open(e, .Tilesets)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Tileset)
	press(e, .Yellow)
	for e.tileset_ed.row != .Width {
		press(e, .Down)
	}
	press(e, .Right)
	testing.expect_value(t, e.tileset_ed.tileset.width, 4)
	press(e, .Red, .Red)
	testing.expect_value(t, e.world.tilesets[0].width, 4)
}

@(test)
test_renaming_an_image_in_a_world_updates_terrains :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	open(e, .Tilesets)
	press(e, .Green) // tileset "ground"
	press(e, .Right) // image g2, which the terrain "rock" uses
	press(e, .Yellow)
	press(e, .Green) // Rename
	name_typed(e, "stone", &e.tileset_ed.entry)
	press(e, .Red, .Red)
	testing.expect_value(t, cm.name_str(&e.world.sets[0].terrains[1].image), "stone")
	testing.expect_value(t, cm.tileset_name(&e.world.tilesets[0], 1), "stone")
}

@(test)
test_a_tileset_in_use_cannot_be_deleted_until_it_is_free :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	open(e, .Tilesets)
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && e.world.tileset_count == 2)
	press(e, .Green)
	testing.expect(t, e.world.tileset_count == 2 && e.note == "USED BY 2 TERRAINS")
	// The unused one goes after a second press.
	e.mode = .List
	press(e, .Down)
	run(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.world.tileset_count == 1 && e.sel[.Tilesets] == 0 && e.dirty)
	// Anything else cancels the confirmation.
	run(e, .Delete)
	testing.expect(t, e.confirm_delete)
	press(e, .Up)
	testing.expect(t, !e.confirm_delete)
}

@(test)
test_renaming_a_tileset_follows_in_terrains_and_a_set_in_maps :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	open(e, .Tilesets)
	run(e, .Rename)
	name_typed(e, "terra")
	testing.expect(t, e.mode == .List && cm.name_str(&e.world.tileset_names[0]) == "terra")
	testing.expect_value(t, cm.name_str(&e.world.sets[0].terrains[0].tileset), "terra")
	e.mode = .Hub
	open(e, .Terrain_Sets)
	run(e, .Rename)
	name_typed(e, "world1")
	testing.expect_value(t, cm.name_str(&e.world.maps[0].set), "world1")
	// A name that is taken keeps the keypad up and changes nothing.
	e.mode = .Hub
	open(e, .Tilesets)
	run(e, .Rename)
	name_typed(e, "empty")
	testing.expect(t, e.mode == .Text && strings.contains(e.entry.note, "USE"))
	press_keypad_action(e, .Cancel)
	testing.expect_value(t, cm.name_str(&e.world.tileset_names[0]), "terra")
}

@(test)
test_terrain_sets_and_maps_open_their_editors_after_naming :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	open(e, .Terrain_Sets)
	run(e, .New)
	name_typed(e, "snow")
	testing.expect(t, e.mode == .Terrain && e.world.set_count == 2 && e.sel[.Terrain_Sets] == 1)
	testing.expect_value(t, cm.name_str(&e.world.sets[1].terrains[0].tileset), "ground") // the first tileset with an image
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.List)
	e.mode = .Hub
	open(e, .Maps)
	run(e, .New)
	name_typed(e, "cave")
	testing.expect(t, e.mode == .Map && e.world.map_count == 2 && cm.name_str(&e.world.maps[1].set) == "land")
	testing.expect(t, e.map_ed.index == 1)
	e.map_ed.terrain = 1
	press(e, .Green) // paint the cell under the cursor
	testing.expect_value(t, e.world.maps[1].cells[0][0], 1)
	testing.expect(t, e.dirty)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.List)
}

@(test)
test_a_new_map_needs_a_terrain_set :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	open(e, .Maps)
	run(e, .New)
	testing.expect(t, e.mode == .Setup && e.note == NOTE_NEED_SET && e.world.map_count == 0 && !e.dirty)
}

@(test)
test_duplicate_names_the_copy_and_opens_it :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	open(e, .Maps)
	run(e, .Duplicate)
	testing.expect(t, e.mode == .Text && e.world.map_count == 2 && cm.name_str(&e.world.maps[1].name) == "start_copy")
	press_keypad_action(e, .Done) // keep the suggested name
	testing.expect(t, e.mode == .Map && e.map_ed.index == 1)
	press(e, .Red)
	// Terrain sets: a copy keeps its terrains.
	e.mode = .Hub
	open(e, .Terrain_Sets)
	run(e, .Duplicate)
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Terrain && e.world.set_count == 2 && e.world.sets[1].count == 2)
}

@(test)
test_an_unused_map_and_a_set_with_a_map_are_deleted_by_the_rules :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	open(e, .Terrain_Sets)
	run(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.world.set_count == 1 && e.note == "USED BY 1 MAP")
	e.mode = .Hub
	open(e, .Maps)
	run(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.world.map_count == 0)
	e.mode = .Hub
	open(e, .Terrain_Sets)
	run(e, .Delete)
	press(e, .Green)
	testing.expect_value(t, e.world.set_count, 0)
	// Nothing left to open, rename, delete or duplicate.
	for row in ([]Setup_Row{.Open, .Rename, .Duplicate, .Delete}) {
		e.note = ""
		e.mode = .List
		run(e, row)
		testing.expectf(t, e.note == NOTE_EMPTY, "%v with nothing there", row)
	}
}

@(test)
test_lists_have_limits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	for e.world.tileset_count < cm.WORLD_MAX_TILESETS {
		cm.world_add_tileset(&e.world)
	}
	open(e, .Tilesets)
	run(e, .New)
	testing.expect(t, e.note == NOTE_FULL && e.mode == .Setup && e.world.tileset_count == 16)
	run(e, .Duplicate)
	testing.expect_value(t, e.note, NOTE_FULL)
	for e.world.map_count < cm.WORLD_MAX_MAPS {
		cm.world_add_map(&e.world, 0)
	}
	e.mode = .Hub
	open(e, .Maps)
	e.note = ""
	run(e, .New)
	testing.expect_value(t, e.note, NOTE_FULL)
	// The list scrolls to keep the selection visible.
	for _ in 0 ..< 60 {
		press(e, .Down)
	}
	testing.expect(t, e.mode == .Setup) // Down in Setup moves the action row, not the list
	e.mode = .List
	for _ in 0 ..< 60 {
		press(e, .Down)
	}
	testing.expect(t, e.sel[.Maps] == 60 && e.scroll == 60 - LIST_ROWS + 1)
	press(e, .Up)
	testing.expect_value(t, e.scroll, 60 - LIST_ROWS + 1)
	for _ in 0 ..< 70 {
		press(e, .Up)
	}
	testing.expect(t, e.sel[.Maps] == 0 && e.scroll == 0)
	editor_handle_event(e, cm.Mouse_Wheel{dy = -3})
	testing.expect_value(t, e.scroll, 3)
	for _ in 0 ..< 100 {
		editor_handle_event(e, cm.Mouse_Wheel{dy = -3})
	}
	testing.expect_value(t, e.scroll, cm.WORLD_MAX_MAPS - LIST_ROWS)
}

@(test)
test_import_adds_a_tileset_of_the_right_size :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	open(e, .Tilesets)
	run(e, .Import)
	testing.expect(t, e.aux_requests == {.Tileset} && e.note == NOTE_IMPORT_ASKED)
	tl := tool(e)
	testing.expect(t, tl.wants_aux_load(tl.data) && !tl.wants_aux_load(tl.data))
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "tileset.json")
	src := new(cm.Tileset)
	defer free(src)
	cm.tileset_reset(src, 8, 8)
	cm.tileset_insert_blank(src, 0, "img")
	testing.expect(t, !tl.load_aux(tl.data, transmute([]u8)cm.tileset_to_json(src)))
	testing.expect(t, e.note == "TILESET IS 8X8, WORLD 4X4" && e.world.tileset_count == 2)
	cm.tileset_reset(src, 4, 4)
	cm.tileset_insert_blank(src, 0, "img")
	cm.image4_set(&src.images[0], 1, 1, 6)
	testing.expect(t, tl.load_aux(tl.data, transmute([]u8)cm.tileset_to_json(src)))
	testing.expect(t, e.mode == .Text && e.world.tileset_count == 3 && cm.name_str(&e.world.tileset_names[2]) == "imported")
	name_typed(e, "fromfile")
	testing.expect(t, e.mode == .Tileset && e.world.tilesets[2].images[0].pixels[1][1] == 6)
	press(e, .Red)
	testing.expect(t, !tl.load_aux(tl.data, transmute([]u8)string("not a tileset")))
	testing.expect_value(t, e.note, NOTE_IMPORT_BAD)
	// Import is only offered for tilesets, and not when the list is full.
	e.mode = .Hub
	open(e, .Maps)
	press(e, .Yellow)
	for _ in 0 ..< 8 {
		press(e, .Down)
		testing.expect(t, e.row != .Import)
	}
	e.mode = .Hub
	for e.world.tileset_count < cm.WORLD_MAX_TILESETS {
		cm.world_add_tileset(&e.world)
	}
	open(e, .Tilesets)
	e.aux_requests = {}
	run(e, .Import)
	testing.expect(t, e.aux_requests == {} && e.note == NOTE_FULL)
}

@(test)
test_the_world_saves_and_loads_through_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	tl := tool(e)
	testing.expect_value(t, tl.default_file, "world.json")
	e.dirty = true
	press(e, .Blue, .Green)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok && e.mode == .Hub)
	_, again := tl.take_save(tl.data)
	testing.expect(t, !again)
	tl.saved(tl.data)
	testing.expect(t, !tl.is_dirty(tl.data))
	// Another editor loads that text.
	e2 := new_editor()
	defer free(e2)
	tl2 := tool(e2)
	e2.mode = .List
	e2.sel[.Maps] = 5
	e2.dirty = true
	testing.expect(t, tl2.load(tl2.data, transmute([]u8)text))
	testing.expect(t, e2.mode == .Hub && !e2.dirty && e2.sel[.Maps] == 0)
	testing.expect(t, e2.world.tileset_count == 2 && e2.world.set_count == 1 && e2.world.map_count == 1 && e2.world.tile_w == 4)
	testing.expect_value(t, cm.world_to_json(&e2.world), text)
	// A bad file is refused and changes nothing.
	testing.expect(t, !tl2.load(tl2.data, transmute([]u8)string("{}")))
	testing.expect_value(t, cm.world_to_json(&e2.world), text)
	// Load and Save by buttons, load by the commands.
	click_rect(e2, SAVE_BUTTON)
	click_rect(e2, LOAD_BUTTON)
	testing.expect(t, e2.requests == {.Save, .Load})
	e2.requests = {}
	press(e2, .Blue, .Yellow)
	testing.expect(t, e2.requests == {.Load} && e2.mode == .Hub)
	press(e2, .Blue, .Red)
	testing.expect(t, e2.requests == {.Load} && e2.mode == .Hub)
}

@(test)
test_entering_starts_blank_and_asks_for_the_file :: proc(t: ^testing.T) {
	e := with_content()
	defer free(e)
	m := cm.default_input_map()
	editor_set_labels(e, &m)
	e.dirty, e.mode = true, .List
	tl := tool(e)
	tl.enter(tl.data)
	testing.expect(t, e.world.tileset_count == 0 && e.mode == .Hub && !e.dirty && e.world.tile_w == 16)
	testing.expect(t, e.labels == &m && e.palette_ed.labels == &m && e.tileset_ed.labels == &m)
	testing.expect(t, tl.wants_load(tl.data) && !tl.wants_load(tl.data))
}

@(test)
test_leaving_and_closing_are_guarded_when_unsaved :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	tl := tool(e)
	press(e, .Red)
	testing.expect(t, e.exit_requested && !e.confirm_exit)
	e.exit_requested = false
	e.dirty = true
	press(e, .Red)
	testing.expect(t, e.confirm_exit && !e.exit_requested)
	press(e, .Down) // any other command cancels the prompt
	testing.expect(t, !e.confirm_exit)
	press(e, .Red, .Red)
	testing.expect(t, e.exit_requested)
	e.exit_requested = false
	click_rect(e, MENU_BUTTON)
	click_rect(e, MENU_BUTTON)
	testing.expect(t, e.exit_requested)
	// The window.
	e.confirm_exit = false
	testing.expect(t, !tl.allow_close(tl.data) && e.confirm_exit)
	testing.expect(t, tl.allow_close(tl.data))
	e.dirty, e.confirm_exit = false, false
	testing.expect(t, tl.allow_close(tl.data))
	// Unhanded-over work in an embedded editor counts as unsaved too.
	press(e, .Green)
	press(e, .Green, .Right)
	testing.expect(t, tl.is_dirty(tl.data))
}

// --- Parity ---

Input_Method :: enum {
	Commands,
	Mouse,
}

@(test)
test_every_part_can_be_opened_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for row in ([]Hub_Row{.Palette, .Tilesets, .Terrain_Sets, .Maps}) {
			e := with_content()
			switch m {
			case .Commands:
				goto_hub(e, row)
				press(e, .Green)
			case .Mouse:
				click_hub(e, row)
			}
			want: Mode
			#partial switch row {
			case .Palette:
				want = .Palette
			case:
				want = .List
			}
			ok := e.mode == want
			free(e)
			testing.expectf(t, ok, "%v could not open %v", m, row)
		}
	}
}

@(test)
test_every_tile_size_is_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for w in ([]int{1, 20, 64}) {
			for h in ([]int{1, 33, 64}) {
				e := new_editor()
				switch m {
				case .Commands:
					goto_hub(e, .Tile_Width)
					for _ in 0 ..< 70 {
						press(e, .Left)
					}
					for _ in 0 ..< w - 1 {
						press(e, .Right)
					}
					press(e, .Down)
					for _ in 0 ..< 70 {
						press(e, .Left)
					}
					for _ in 0 ..< h - 1 {
						press(e, .Right)
					}
				case .Mouse:
					for _ in 0 ..< 70 {
						click_rect(e, WIDTH_MINUS)
						click_rect(e, HEIGHT_MINUS)
					}
					for _ in 0 ..< w - 1 {
						click_rect(e, WIDTH_PLUS)
					}
					for _ in 0 ..< h - 1 {
						click_rect(e, HEIGHT_PLUS)
					}
				}
				ok := e.world.tile_w == w && e.world.tile_h == h
				free(e)
				testing.expectf(t, ok, "%v: wanted %dx%d", m, w, h)
			}
		}
	}
}

@(test)
test_every_list_action_is_reachable_by_each_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for m in Input_Method {
		for s in Section {
			e := with_content()
			e.section = s
			open(e, s)
			do_row :: proc(e: ^Editor, m: Input_Method, row: Setup_Row, button: Rect) {
				switch m {
				case .Commands:
					run(e, row)
				case .Mouse:
					e.mode = .List
					click_rect(e, button)
				}
			}
			before := section_count(e, s)
			do_row(e, m, .New, NEW_BUTTON)
			ok := e.mode == .Text && section_count(e, s) == before + 1
			press_keypad_action(e, .Cancel) // the keypad closes; the new item's editor opens
			ok &&= e.mode != .Text && e.mode != .List
			for e.mode != .List {
				press(e, .Red)
			}
			do_row(e, m, .Duplicate, DUPLICATE_BUTTON)
			ok &&= e.mode == .Text && section_count(e, s) == before + 2
			press_keypad_action(e, .Cancel)
			for e.mode != .List {
				press(e, .Red)
			}
			do_row(e, m, .Rename, RENAME_BUTTON)
			ok &&= e.mode == .Text
			press_keypad_action(e, .Cancel)
			do_row(e, m, .Open, OPEN_BUTTON)
			ok &&= e.mode != .List && e.mode != .Setup && e.mode != .Text
			for e.mode != .List {
				press(e, .Red)
			}
			// The last two are the new copies: free to delete (the originals are in use).
			do_row(e, m, .Delete, DELETE_BUTTON)
			switch m {
			case .Commands:
				press(e, .Green)
			case .Mouse:
				click_rect(e, DELETE_BUTTON)
			}
			ok &&= section_count(e, s) == before + 1
			// Back.
			switch m {
			case .Commands:
				e.mode = .List
				press(e, .Red)
			case .Mouse:
				click_rect(e, BACK_BUTTON)
			}
			ok &&= e.mode == .Hub
			free(e)
			testing.expectf(t, ok, "%v could not run the actions of %v", m, s)
		}
	}
}

@(test)
test_every_item_can_be_chosen_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for target in ([]int{0, 1, 10, 11, 30, 63}) {
			e := new_editor()
			cm.world_add_terrain_set(&e.world)
			for _ in 0 ..< 64 {
				cm.world_add_map(&e.world, 0)
			}
			open(e, .Maps)
			switch m {
			case .Commands:
				for _ in 0 ..< target {
					press(e, .Down)
				}
			case .Mouse:
				for _ in 0 ..< 70 {
					if target >= e.scroll + LIST_ROWS {
						editor_handle_event(e, cm.Mouse_Wheel{dy = -1})
					}
				}
				already := selected(e) == target
				click_item(e, target)
				if already { 	// clicking the selected item opens it
					ok_open := e.mode == .Map && e.map_ed.index == target
					free(e)
					testing.expectf(t, ok_open, "%v could not open map %d", m, target)
					continue
				}
			}
			ok := selected(e) == target && e.mode == .List
			if m == .Mouse {
				click_item(e, target) // a second click opens it
				ok &&= e.mode == .Map && e.map_ed.index == target
			}
			free(e)
			testing.expectf(t, ok, "%v could not choose map %d", m, target)
		}
	}
}

// --- Layout, drawing and text ---

@(test)
test_layout_fits_the_screen_and_does_not_overlap :: proc(t: ^testing.T) {
	rects := make([dynamic]Rect, context.temp_allocator)
	append(&rects, BANNER, WIDTH_MINUS, WIDTH_PLUS, HEIGHT_MINUS, HEIGHT_PLUS, SAVE_BUTTON, LOAD_BUTTON, MENU_BUTTON)
	append(&rects, Rect{LIST_X, LIST_Y, LIST_W, LIST_ROWS * LIST_PITCH})
	for b in list_buttons() {
		append(&rects, b.rc)
		testing.expectf(t, cm.text_width(b.text) <= b.rc.w - 2 && cm.GLYPH_H <= b.rc.h && cm.text_is_drawable(b.text), "label %s", b.text)
	}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			// The hub buttons and the list share the screen at different times: only check within a screen.
			hub_i := i < 8
			hub_j := j < 8
			if i < j && hub_i == hub_j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	// The hub rows clear their buttons, and the list's detail column clears the name column.
	testing.expect(t, HUB_X + cm.text_width("TERRAIN SETS") < HUB_VALUE_X && HUB_VALUE_X + 16 * 8 <= cm.SCREEN_W)
	testing.expect(t, HUB_VALUE_X + cm.text_width("16 OF 16") < WIDTH_MINUS.x)
	testing.expect(t, HUB_Y + HUB_ROWS * HUB_PITCH <= SAVE_BUTTON.y && SAVE_BUTTON.y + SAVE_BUTTON.h <= HELP_Y)
	// A 32 character name and the right-aligned detail both fit the list.
	testing.expect(t, 2 + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") + cm.text_width("16 TERRAINS") + 6 <= LIST_W)
	testing.expect(t, LIST_Y + LIST_ROWS * LIST_PITCH <= HELP_Y)
}

@(test)
test_row_geometry_round_trips :: proc(t: ^testing.T) {
	for row in 0 ..< LIST_ROWS {
		rc := list_row_rect(row)
		for p in ([][2]int{{0, 0}, {LIST_W - 1, LIST_PITCH - 1}}) {
			got, ok := list_row_at(rc.x + p.x, rc.y + p.y)
			testing.expectf(t, ok && got == row, "list row %d", row)
		}
	}
	_, ok := list_row_at(LIST_X - 1, LIST_Y)
	testing.expect(t, !ok)
	_, ok = list_row_at(LIST_X, LIST_Y + LIST_ROWS * LIST_PITCH)
	testing.expect(t, !ok)
	for row in 0 ..< HUB_ROWS {
		rc := hub_row_rect(row)
		got, ok2 := hub_row_at(rc.x + 3, rc.y + 3)
		testing.expectf(t, ok2 && got == row, "hub row %d", row)
	}
	_, ok = hub_row_at(HUB_MARKER_X, HUB_Y + HUB_ROWS * HUB_PITCH)
	testing.expect(t, !ok)
}

@(test)
test_all_on_screen_text_is_in_the_font_and_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	m := cm.default_input_map()
	editor_set_labels(e, &m)
	for round in 0 ..< 2 {
		if round == 1 {
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for mode in ([]Mode{.Hub, .List, .Setup, .File}) {
			for section in Section {
				for flag in 0 ..< 3 {
					e.mode, e.section = mode, section
					e.confirm_exit, e.confirm_delete = flag == 1, flag == 2
					text := banner_text(e)
					if round == 0 {
						testing.expectf(t, cm.text_is_drawable(text), "banner: %s", text)
					}
					testing.expectf(t, cm.text_width(text) + 8 <= BANNER.w, "banner too wide: %s", text)
				}
			}
			lines, n := help_lines(e)
			for line in lines[:n] {
				if round == 0 {
					testing.expectf(t, cm.text_is_drawable(line), "help: %s", line)
				}
				testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
			}
			testing.expect(t, HELP_Y + n * cm.LINE_ADVANCE <= cm.SCREEN_H)
		}
	}
	for note in ([]string{NOTE_NEED_SET, NOTE_EMPTY, NOTE_FULL, NOTE_NAME_EMPTY, NOTE_NAME_USED, NOTE_NAME_BAD, NOTE_IMPORT_ASKED, NOTE_IMPORT_BAD, "TILESET IS 64X64, WORLD 64X64", "USED BY 256 TERRAINS", "USED BY 64 MAPS", "UNSAVED CHANGES *", "NO UNSAVED CHANGES"}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 4, "note: %s", note)
	}
	for row in Hub_Row {
		testing.expect(t, cm.text_is_drawable(hub_label(row)))
	}
	for s in Section {
		testing.expect(t, cm.text_is_drawable(section_title(s)))
	}
	// The longest detail and info lines.
	for i in 0 ..< 3 {
		cm.name_assign(&e.world.maps[0].set, "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
		e.section = Section(i)
		e.dirty = true
		info := item_info(e)
		testing.expectf(t, cm.text_is_drawable(info) && INFO_X + cm.text_width(info) <= cm.SCREEN_W - 4, "info: %s", info)
	}
}

Draw_Log :: struct {
	rects, out_of_bounds, presents: int,
}

logging_renderer :: proc(l: ^Draw_Log) -> cm.Renderer {
	return cm.Renderer {
		data = l,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^Draw_Log)(d)
			k.rects += 1
			if x < 0 || y < 0 || x + w > cm.SCREEN_W || y + h > cm.SCREEN_H {
				k.out_of_bounds += 1
			}
		},
		present = proc(d: rawptr) {(^Draw_Log)(d).presents += 1},
	}
}

@(test)
test_every_screen_draws_on_screen_in_every_mode :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	e := with_content()
	defer free(e)
	for _ in 0 ..< 63 {
		cm.world_add_map(&e.world, 0)
	}
	for mode in Mode {
		for section in Section {
			e.section = section
			e.mode = mode
			switch mode {
			case .Palette:
				pe_open(e)
			case .Tileset:
				e.section = .Tilesets
				e.mode = .List
				press(e, .Green)
			case .Terrain:
				e.section = .Terrain_Sets
				e.mode = .List
				press(e, .Green)
			case .Map:
				e.section = .Maps
				e.mode = .List
				press(e, .Green)
			case .Text:
				e.mode = .List
				run(e, .Rename)
			case .Hub, .List, .Setup, .File:
			}
			e.sel[section] = section_count(e, section) - 1
			fix_selection(e)
			log = {}
			editor_draw(e, &r)
			testing.expectf(t, log.out_of_bounds == 0, "%v/%v: %d rects off screen", mode, section, log.out_of_bounds)
			testing.expect_value(t, log.presents, 1)
			testing.expectf(t, log.rects < 40000, "%v/%v: %d rects is too many", mode, section, log.rects)
			e.mode = .List
			for e.mode != .Hub && e.mode != .List {
				press(e, .Red)
			}
		}
	}
}

pe_open :: proc(e: ^Editor) {
	e.mode = .Hub
	e.hub = .Palette
	press(e, .Green)
}
