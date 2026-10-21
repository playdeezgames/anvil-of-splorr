#+build !js
package world_editor

import rt "../anvil_runtime"
import cm "../common"
import spe "../sprite_editor"
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

row_index :: proc(row: Hub_Row) -> int {
	for r, i in section_rows(hub_row_section(row)) {
		if r == row {
			return i
		}
	}
	return 0
}

// Clicks a hub row, going up and into its section first when needed.
click_hub :: proc(e: ^Editor, row: Hub_Row) {
	s := hub_row_section(row)
	if e.hub_level == .Inside && e.hub_section != s {
		click_rect(e, SECTION_BACK)
	}
	if e.hub_level == .Top {
		click_rect(e, top_row_rect(int(s)))
	}
	rc := hub_row_rect(row_index(row))
	click_at(e, rc.x + 30, rc.y + 4)
}

// Moves the highlight to a hub row with the commands, going up and into its section first when needed.
goto_hub :: proc(e: ^Editor, row: Hub_Row) {
	s := hub_row_section(row)
	if e.hub_level == .Inside && e.hub_section != s {
		press(e, .Red)
	}
	if e.hub_level == .Top {
		for e.top != s {
			press(e, .Down)
		}
		press(e, .Green)
	}
	for e.hub != row {
		press(e, .Down)
	}
}

// Opens a list from the hub with the commands.
open :: proc(e: ^Editor, s: Section) {
	e.mode = .Hub
	row: Hub_Row
	switch s {
	case .Tags:
		row = .Tags
	case .Params:
		row = .Params
	case .Tilesets:
		row = .Tilesets
	case .Terrain_Sets:
		row = .Terrain_Sets
	case .Sprite_Sets:
		row = .Sprite_Sets
	case .Maps:
		row = .Maps
	}
	goto_hub(e, row)
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
	ss := cm.world_add_sprite_set(w, "creatures")
	sp := cm.world_add_sprite(w, ss)
	cm.name_assign(&w.sprite_sets[ss].sprites[sp].name, "slime")
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
	goto_hub(e, .Palette)
	press(e, .Up)
	testing.expect_value(t, e.hub, Hub_Row.Sprite_Sets) // wraps within the section
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
test_hub_sections_open_go_up_and_leave :: proc(t: ^testing.T) {
	e := with_content()
	defer free(e)
	testing.expect(t, e.hub_level == .Top && e.top == .Look)
	press(e, .Up)
	testing.expect_value(t, e.top, Hub_Section.Actors) // wraps
	press(e, .Left, .Right) // no tile size at the top
	testing.expect_value(t, e.world.tile_w, 4)
	press(e, .Green)
	testing.expect(t, e.hub_level == .Inside && e.hub_section == .Actors && e.hub == .Character_Types)
	press(e, .Up)
	testing.expect_value(t, e.hub, Hub_Row.Maps)
	press(e, .Red)
	testing.expect(t, e.hub_level == .Top && e.top == .Actors && !e.exit_requested)
	press(e, .Red)
	testing.expect(t, e.exit_requested || e.dirty || e.hub_level == .Top)
	// Yellow and blue work at both levels.
	e2 := with_content()
	defer free(e2)
	press(e2, .Blue)
	testing.expect_value(t, e2.mode, Mode.File)
	press(e2, .Red)
	press(e2, .Green, .Blue)
	testing.expect_value(t, e2.mode, Mode.File)
}

@(test)
test_hub_summaries_fit_at_their_longest :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	e.world.tile_w, e.world.tile_h = 64, 64
	e.world.tileset_count, e.world.set_count, e.world.sprite_set_count = 16, 16, 16
	e.world.tag_count, e.world.param_count = 64, 64
	e.world.char_type_count, e.world.character_count, e.world.map_count = 64, 1024, 64
	for s in Hub_Section {
		text := hub_section_summary(e, s)
		testing.expectf(t, cm.text_is_drawable(text), "summary: %s", text)
		extra := s == .Rules ? cm.text_width("64 MISSING") + 8 : 0
		testing.expectf(t, HUB_X + cm.text_width(text) + extra <= cm.SCREEN_W - 4, "summary too wide: %s", text)
	}
}

@(test)
test_hub_section_rows_cover_every_row_once :: proc(t: ^testing.T) {
	seen: [HUB_ROWS]int
	for s in Hub_Section {
		for row in section_rows(s) {
			seen[int(row)] += 1
			testing.expect(t, hub_row_section(row) == s)
		}
	}
	for n in seen {
		testing.expect_value(t, n, 1)
	}
	for s in Hub_Section {
		testing.expect(t, cm.text_is_drawable(hub_section_title(s)))
	}
}

@(test)
test_the_palette_is_edited_in_place_and_red_returns :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Green, .Green) // the LOOK section, then the palette
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
	testing.expect(t, e.world.tileset_count == 2 && e.note == "USED BY 2 TERRAINS AND 1 SPRITE")
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
	e.aux_requests -= {.Game_Tags} // (opening the tags list asked for game_tags.json too; not this test's business)
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "tileset.json") // named by what is pending
	testing.expect(t, tl.wants_aux_load(tl.data) && !tl.wants_aux_load(tl.data))
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "") // nothing pending: no file
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
	goto_hub(e, .Palette)
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
		for row in ([]Hub_Row{.Palette, .Tags, .Tilesets, .Terrain_Sets, .Sprite_Sets, .Character_Types, .Characters, .Maps}) {
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
			case .Character_Types:
				want = .Char_Type
			case .Characters:
				want = .Character
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
					click_rect(e, top_row_rect(int(Hub_Section.Look)))
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
			if s == .Tags {
				continue // a tag has no editor to open and cannot be copied (see test_tags_are_listed_...)
			}
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
	testing.expect(t, HUB_Y + len(LOOK_ROWS) * HUB_PITCH <= SECTION_BACK.y && SECTION_BACK.y + SECTION_BACK.h <= HELP_Y && TOP_Y + HUB_SECTIONS * TOP_PITCH <= SAVE_BUTTON.y && SAVE_BUTTON.y + SAVE_BUTTON.h <= HELP_Y)
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
	for note in ([]string{NOTE_NEED_SET, NOTE_EMPTY, NOTE_FULL, NOTE_NAME_EMPTY, NOTE_NAME_USED, NOTE_NAME_BAD, NOTE_IMPORT_ASKED, NOTE_IMPORT_BAD, NOTE_TAG_OPEN, NOTE_TAG_COPY, NOTE_TAG_RESERVED, "REMOVED FROM 4096 THINGS", "THIS TAG IS USED BY 4096 THINGS", "TILESET IS 64X64, WORLD 64X64", "USED BY 256 TERRAINS", "USED BY 64 MAPS", "UNSAVED CHANGES *", "NO UNSAVED CHANGES"}) {
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
			case .Sprite:
				e.section = .Sprite_Sets
				e.mode = .List
				press(e, .Green)
			case .Play:
				add_player(e)
				e.mode = .Hub
				press(e, .Yellow)
			case .Value:
				e.section = .Params
				e.mode = .List
				if e.world.param_count == 0 {
					cm.world_add_param(&e.world)
				}
				press(e, .Green)
			case .Char_Type:
				e.mode = .Hub
				e.hub = .Character_Types
				press(e, .Green)
			case .Character:
				e.mode = .Hub
				e.hub = .Characters
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

@(test)
test_sprite_sets_are_listed_named_and_opened_in_the_sprite_editor :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	e.mode = .Hub
	goto_hub(e, .Sprite_Sets)
	press(e, .Green)
	testing.expect(t, e.mode == .List && e.section == .Sprite_Sets && section_count(e, .Sprite_Sets) == 1)
	testing.expect_value(t, item_detail(e, .Sprite_Sets, 0), "1 SPRITE")
	testing.expect_value(t, item_info(e), "1 OF 1")
	run(e, .New)
	testing.expect(t, e.mode == .Text && e.world.sprite_set_count == 2 && e.sel[.Sprite_Sets] == 1)
	name_typed(e, "items")
	testing.expect(t, e.mode == .Sprite && cm.name_str(&e.world.sprite_sets[1].name) == "items" && e.sprite_ed.set_index == 1)
	testing.expect(t, e.dirty)
	// The sprite editor works in place: a new sprite in the empty set.
	press(e, .Yellow, .Down, .Green) // Setup -> New
	press_keypad_action_in(e, &e.sprite_ed.entry, .Done)
	testing.expect_value(t, e.world.sprite_sets[1].count, 1)
	press(e, .Red, .Red)
	testing.expect_value(t, e.mode, Mode.List)
	testing.expect_value(t, item_detail(e, .Sprite_Sets, 1), "1 SPRITE")
	// Rename and duplicate follow the usual rules; names are unique among sprite sets.
	run(e, .Rename)
	name_typed(e, "creatures")
	testing.expect(t, e.mode == .Text && strings.contains(e.entry.note, "USE"))
	name_typed(e, "things")
	testing.expect_value(t, cm.name_str(&e.world.sprite_sets[1].name), "things")
	run(e, .Duplicate)
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Sprite && e.world.sprite_set_count == 3 && e.world.sprite_sets[2].count == 1)
	press(e, .Red)
	// Nothing uses a sprite set, so deleting is free (after the second press).
	run(e, .Delete)
	press(e, .Green)
	testing.expect_value(t, e.world.sprite_set_count, 2)
	// The limit.
	for e.world.sprite_set_count < cm.WORLD_MAX_SPRITE_SETS {
		cm.world_add_sprite_set(&e.world)
	}
	e.note = ""
	run(e, .New)
	testing.expect_value(t, e.note, NOTE_FULL)
}

press_keypad_action_in :: proc(e: ^Editor, entry: ^cm.Text_Entry, a: cm.Text_Entry_Action) {
	for entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(entry.col) != a {
		press(e, .Right)
	}
	press(e, .Green)
}

@(test)
test_the_sprite_editor_sees_the_worlds_terrains_and_palette :: proc(t: ^testing.T) {
	e := with_content()
	defer free(e)
	e.world.palette[5] = {7, 7, 7}
	e.mode = .Hub
	goto_hub(e, .Sprite_Sets)
	press(e, .Green, .Green)
	testing.expect_value(t, e.mode, Mode.Sprite)
	press(e, .Yellow)
	for e.sprite_ed.row != .Bg_Set {
		press(e, .Down)
	}
	press(e, .Right)
	testing.expect(t, spe_backdrop_name(e) == "grass")
	testing.expect(t, !e.dirty) // looking only
	press(e, .Red, .Red)
	testing.expect_value(t, e.mode, Mode.List)
}

spe_backdrop_name :: proc(e: ^Editor) -> string {
	if bg := spe.backdrop(&e.sprite_ed); bg != nil {
		return cm.name_str(&bg.name)
	}
	return ""
}

@(test)
test_a_tileset_or_image_used_by_a_sprite_cannot_be_deleted_in_a_world :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	// Only sprites use "ground" and its image g1 here.
	for ti in 0 ..< e.world.sets[0].count {
		e.world.sets[0].terrains[ti].tileset, e.world.sets[0].terrains[ti].image = {}, {}
	}
	open(e, .Tilesets)
	run(e, .Delete)
	press(e, .Green)
	testing.expect_value(t, e.note, "USED BY 0 TERRAINS AND 1 SPRITE")
	testing.expect_value(t, e.world.tileset_count, 2)
	// In its editor the image is protected too, and a rename follows into the sprite.
	e.mode = .List
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Tileset)
	press(e, .Yellow)
	for e.tileset_ed.row != .Delete {
		press(e, .Down)
	}
	press(e, .Green, .Green)
	testing.expect(t, e.tileset_ed.note == "IMAGE USED BY 0 TERRAINS AND 1 SPRITE" && e.tileset_ed.tileset.count == 2)
	e.tileset_ed.mode = .Setup
	for e.tileset_ed.row != .Rename {
		press(e, .Up)
	}
	press(e, .Green)
	name_typed(e, "stone", &e.tileset_ed.entry)
	testing.expect_value(t, cm.name_str(&e.world.sprite_sets[0].sprites[0].image), "stone")
}

@(test)
test_sprite_sets_survive_save_and_load_in_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	e.world.sprite_sets[0].sprites[0].transparent = cm.SPRITE_NO_TRANSPARENT
	tl := tool(e)
	press(e, .Blue, .Green)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok && strings.contains(text, `"transparent": null`))
	e2 := new_editor()
	defer free(e2)
	tl2 := tool(e2)
	testing.expect(t, tl2.load(tl2.data, transmute([]u8)text))
	testing.expect(t, e2.world.sprite_set_count == 1 && e2.world.sprite_sets[0].sprites[0].transparent == cm.SPRITE_NO_TRANSPARENT)
}

@(test)
test_every_sprite_set_part_is_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		e := with_content()
		switch m {
		case .Commands:
			goto_hub(e, .Sprite_Sets)
			press(e, .Green)
		case .Mouse:
			click_hub(e, .Sprite_Sets)
		}
		ok := e.mode == .List && e.section == .Sprite_Sets
		free(e)
		testing.expectf(t, ok, "%v could not open the sprite sets", m)
	}
}

@(test)
test_a_sprite_set_a_character_type_uses_cannot_be_deleted :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	sp := cm.world_add_sprite(&e.world, 0)
	cm.world_add_char_type(&e.world, "t")
	_ = sp
	open(e, .Sprite_Sets)
	run(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.world.sprite_set_count == 1 && e.note == "USED BY 1 CHARACTER TYPE")
	e.world.char_type_count = 0 // free again
	e.mode = .List
	run(e, .Delete)
	press(e, .Green)
	testing.expect_value(t, e.world.sprite_set_count, 0)
}

@(test)
test_character_types_and_characters_have_their_own_hub_rows :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	e.mode = .Hub
	goto_hub(e, .Character_Types)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Char_Type)
	// A new type takes the first sprite and asks for its name.
	press(e, .Yellow, .Down, .Green) // Setup -> New
	press_keypad_action_in(e, &e.char_type_ed.entry, .Cancel)
	testing.expect(t, e.world.char_type_count == 1 && e.dirty)
	testing.expect_value(t, cm.name_str(&e.world.char_types[0].sprite_set), "creatures")
	press(e, .Red, .Red)
	testing.expect_value(t, e.mode, Mode.Hub)
	// The character editor can now make a character of it.
	goto_hub(e, .Characters)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Character)
	press(e, .Yellow, .Down, .Green) // Setup -> New
	press_keypad_action_in(e, &e.character_ed.entry, .Done)
	testing.expect(t, e.world.character_count == 1 && !cm.uuid_is_none(e.world.characters[0].uuid))
	testing.expect_value(t, cm.name_str(&e.world.characters[0].type), "character_type")
	press(e, .Red, .Red)
	testing.expect_value(t, e.mode, Mode.Hub)
	// The hub shows the counts.
	testing.expect_value(t, cm.name_str(&e.world.char_types[0].name), "character_type")
	// The type cannot be deleted while the character has it (the type editor says so).
	goto_hub(e, .Character_Types)
	press(e, .Green, .Yellow)
	for e.char_type_ed.row != .Delete {
		press(e, .Down)
	}
	press(e, .Green)
	testing.expect_value(t, e.char_type_ed.note, "USED BY 1 CHARACTER")
}

@(test)
test_characters_survive_save_and_load_in_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	cm.world_seed_uuids(&e.world, 31)
	ct := cm.world_add_char_type(&e.world, "slime")
	c := cm.world_add_character(&e.world, ct)
	cm.world_place_character(&e.world, 0, 2, 1, e.world.characters[c].uuid)
	cm.world_set_player(&e.world, e.world.characters[c].uuid)
	tl := tool(e)
	press(e, .Blue, .Green)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok && strings.contains(text, cm.uuid_to_string(e.world.player)))
	e2 := new_editor()
	defer free(e2)
	tl2 := tool(e2)
	testing.expect(t, tl2.load(tl2.data, transmute([]u8)text))
	testing.expect(t, e2.world.character_count == 1 && e2.world.player == e.world.player && cm.world_character_at(&e2.world, 0, 2, 1) == 0)
	testing.expect_value(t, cm.world_to_json(&e2.world), text)
}

@(test)
test_entering_seeds_the_uuid_generator_from_the_clock :: proc(t: ^testing.T) {
	e := with_content()
	defer free(e)
	tl := tool(e)
	tl.enter(tl.data)
	first := e.world.uuid_state
	testing.expect(t, first != 0x9E3779B97F4A7C15 && first != 0)
	tl.enter(tl.data)
	testing.expect(t, e.world.uuid_state != first) // the clock moved on
}

@(test)
test_a_map_opened_from_the_world_places_characters_that_stay_in_the_world :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	ct := cm.world_add_char_type(&e.world, "slime")
	c := cm.world_add_character(&e.world, ct)
	open(e, .Maps)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Map)
	e.dirty = false
	press(e, .Yellow)
	for e.map_ed.row != .Layer {
		press(e, .Down)
	}
	press(e, .Green) // the Characters layer
	press(e, .Red) // Setup -> Draw
	press(e, .Right, .Down, .Green) // put the character at 1,1
	testing.expect(t, e.dirty && cm.world_character_at(&e.world, 0, 1, 1) == c)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.List)
	testing.expect_value(t, cm.world_character_at(&e.world, 0, 1, 1), c)
}

@(test)
test_tags_are_listed_named_and_deleted_from_the_world_editor :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	e.mode = .Hub
	goto_hub(e, .Tags)
	press(e, .Green)
	testing.expect(t, e.mode == .List && e.section == .Tags && section_count(e, .Tags) == 1)
	testing.expect_value(t, item_detail(e, .Tags, 0), "FIXED")
	// The solid tag is fixed: no rename, no delete, and "open" says what a tag is.
	run(e, .Rename)
	testing.expect(t, e.mode == .Setup && e.note == NOTE_TAG_RESERVED)
	e.note = ""
	run(e, .Delete)
	testing.expect(t, e.note == NOTE_TAG_RESERVED && !e.confirm_delete && e.world.tag_count == 1)
	e.note = ""
	run(e, .Open)
	testing.expect_value(t, e.note, NOTE_TAG_OPEN)
	e.note = ""
	run(e, .Duplicate)
	testing.expect_value(t, e.note, NOTE_TAG_COPY)
	// New: the keypad names it and nothing opens afterwards.
	run(e, .New)
	testing.expect(t, e.mode == .Text && e.world.tag_count == 2 && e.sel[.Tags] == 1 && e.dirty)
	name_typed(e, "water")
	testing.expect(t, e.mode == .List && cm.name_str(&e.world.tags[1]) == "water")
	// A taken name keeps the keypad up (solid is taken too).
	run(e, .Rename)
	name_typed(e, "solid")
	testing.expect(t, e.mode == .Text && strings.contains(e.entry.note, "USE"))
	name_typed(e, "wet")
	testing.expect_value(t, cm.name_str(&e.world.tags[1]), "wet")
	// Use it, then delete it: the confirmation says how many things use it, and it is cleared.
	ct := cm.world_add_char_type(&e.world, "slime")
	cm.world_add_character(&e.world, ct)
	cm.world_toggle_terrain_tag(&e.world, 0, 0, 1)
	cm.world_cycle_character_tag(&e.world, 0, 1)
	cm.world_cycle_cell_tag(&e.world, 0, 0, 0, 1)
	e.mode = .List
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && e.world.tag_count == 2)
	testing.expect_value(t, item_info(e), "THIS TAG IS USED BY 3 THINGS")
	testing.expect(t, cm.text_is_drawable(item_info(e)))
	press(e, .Green)
	testing.expect(t, e.world.tag_count == 1 && e.note == "REMOVED FROM 3 THINGS" && e.dirty)
	testing.expect(t, e.world.sets[0].terrains[0].tags == 0 && e.world.characters[0].tags_set == 0 && e.world.maps[0].cell_tags[0][0] == cm.Cell_Tags{})
	testing.expect_value(t, e.sel[.Tags], 0)
	// The limit.
	for e.world.tag_count < cm.WORLD_MAX_TAGS {
		cm.world_add_tag(&e.world)
	}
	e.note = ""
	run(e, .New)
	testing.expect_value(t, e.note, NOTE_FULL)
}

@(test)
test_tags_survive_save_and_load_in_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	cm.world_add_tag(&e.world, "water")
	cm.world_toggle_terrain_tag(&e.world, 0, 1, 1)
	cm.world_cycle_cell_tag(&e.world, 0, 2, 0, cm.TAG_SOLID)
	tl := tool(e)
	press(e, .Blue, .Green)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok && strings.contains(text, `"tags": ["solid", "water"]`))
	e2 := new_editor()
	defer free(e2)
	tl2 := tool(e2)
	testing.expect(t, tl2.load(tl2.data, transmute([]u8)text))
	testing.expect(t, e2.world.tag_count == 2 && e2.world.sets[0].terrains[1].tags == cm.tag_bit(1))
	testing.expect_value(t, cm.world_to_json(&e2.world), text)
}

// --- game_tags.json ---

GAME_TAGS_TEXT :: `{"tags": [{"name": "solid", "note": "blocks the player"}, {"name": "thing", "note": "what the player picks up"}, {"name": "spawn", "note": "where the thing may appear"}]}`

// An editor whose world has the extra tag "spare" and which has read game tags solid, thing, spawn.
with_game_tags :: proc() -> (^Editor, cm.Tool) {
	e := with_content()
	cm.world_add_tag(&e.world, "spare")
	tl := tool(e)
	e.aux_requests = {.Game_Tags}
	_ = tl.wants_aux_load(tl.data)
	tl.load_aux(tl.data, transmute([]u8)string(GAME_TAGS_TEXT))
	return e, tl
}

@(test)
test_the_editor_asks_for_each_aux_file_in_turn_and_reads_the_game_tags :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	tl := tool(e)
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "")
	tl.enter(tl.data) // opening the tool asks for the game's tags
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "game_tags.json")
	e.aux_requests += {.Tileset}
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "tileset.json") // the tileset first
	testing.expect(t, tl.wants_aux_load(tl.data))
	testing.expect(t, !tl.load_aux(tl.data, transmute([]u8)string("not a tileset")))
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "game_tags.json")
	testing.expect(t, tl.wants_aux_load(tl.data))
	testing.expect(t, tl.load_aux(tl.data, transmute([]u8)string(GAME_TAGS_TEXT)))
	testing.expect(t, e.game_tags.count == 3 && cm.game_tag_name(&e.game_tags, 1) == "thing")
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "")
	// A bad file says so and keeps what was read before.
	e.aux_requests = {.Game_Tags}
	testing.expect(t, tl.wants_aux_load(tl.data))
	testing.expect(t, !tl.load_aux(tl.data, transmute([]u8)string(`{"tags": ["a", "a"]}`)))
	testing.expect(t, e.note == NOTE_GAME_TAGS_BAD && e.game_tags.count == 3)
	// Opening the Tags list reads the file again.
	e.mode = .Hub
	goto_hub(e, .Tags)
	press(e, .Green)
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "game_tags.json")
}

@(test)
test_the_tags_list_marks_needed_tags_and_lists_the_missing_ones :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, tl := with_game_tags()
	defer free(e)
	_ = tl
	e.mode = .Hub
	goto_hub(e, .Tags)
	press(e, .Green)
	// Rows: solid, spare, then the missing thing and spawn.
	testing.expect_value(t, section_count(e, .Tags), 4)
	testing.expect_value(t, tags_missing(e), 2)
	names := [4]string{"solid", "spare", "thing", "spawn"}
	for name, i in names {
		testing.expectf(t, section_item_name(e, .Tags, i) == name, "row %d is %s", i, section_item_name(e, .Tags, i))
	}
	testing.expect_value(t, tag_detail(e, 0), "FIXED, NEEDED") // rock uses solid, so it is not "unused"
	testing.expect_value(t, tag_detail(e, 1), "")
	testing.expect_value(t, tag_detail(e, 2), "MISSING")
	testing.expect_value(t, tag_detail(e, 3), "MISSING")
	for i in 0 ..< 4 {
		testing.expect(t, cm.text_is_drawable(tag_detail(e, i)))
	}
	// The info line carries the game's note for the selected tag.
	e.sel[.Tags] = 0
	testing.expect_value(t, item_info(e), "1 OF 4  blocks the player")
	e.sel[.Tags] = 2
	testing.expect_value(t, item_info(e), "3 OF 4  what the player picks up")
	e.sel[.Tags] = 1
	testing.expect_value(t, item_info(e), "2 OF 4")
	// A needed tag nothing uses is "unused" until something sets it.
	cm.world_add_tag(&e.world, "thing") // (creates tag 2 by hand: now present in the world)
	testing.expect_value(t, tag_detail(e, 2), "NEEDED, UNUSED")
	cm.world_toggle_terrain_tag(&e.world, 0, 0, 2) // a terrain has it now
	testing.expect_value(t, tag_detail(e, 2), "NEEDED")
	testing.expect_value(t, section_count(e, .Tags), 4) // spare, thing... and spawn still missing
	// The hub shows how many are missing.
	e.mode = .Hub
	testing.expect_value(t, tags_missing(e), 1)
}

@(test)
test_missing_tags_cannot_be_renamed_deleted_or_opened_and_create_adds_them :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, _ := with_game_tags()
	defer free(e)
	e.mode = .Hub
	goto_hub(e, .Tags)
	press(e, .Green)
	e.sel[.Tags] = 2 // the missing "thing"
	for row in ([]Setup_Row{.Rename, .Delete, .Open}) {
		e.note = ""
		e.mode = .List
		run(e, row)
		testing.expectf(t, e.note == NOTE_TAG_MISSING && e.mode == .Setup && !e.confirm_delete && !e.confirm_rename, "%v on a missing tag", row)
	}
	// Create adds them all, in the file's order, in one action.
	e.dirty = false
	run(e, .Create)
	testing.expect(t, e.note == "CREATED 2 TAGS" && e.dirty && e.world.tag_count == 4)
	testing.expect(t, cm.name_str(&e.world.tags[2]) == "thing" && cm.name_str(&e.world.tags[3]) == "spawn")
	testing.expect(t, tags_missing(e) == 0 && section_count(e, .Tags) == 4)
	e.note = ""
	run(e, .Create)
	testing.expect_value(t, e.note, NOTE_NOTHING_MISSING)
	// The button does the same (and needs no file to be read first: the list has what it read).
	cm.world_delete_tag(&e.world, 3)
	e.mode = .List
	e.note = ""
	click_rect(e, IMPORT_BUTTON)
	testing.expect(t, e.note == "CREATED 1 TAG" && e.world.tag_count == 4)
	// With no game tags file read there is nothing to create: it asks for the file.
	e2 := new_editor()
	defer free(e2)
	open(e2, .Tags)
	e2.aux_requests = {}
	run(e2, .Create)
	testing.expect(t, e2.note == NOTE_GAME_TAGS_ASKED && e2.aux_requests == {.Game_Tags})
	// A full world creates what fits and says so.
	e3, _ := with_game_tags()
	defer free(e3)
	for e3.world.tag_count < cm.WORLD_MAX_TAGS - 1 {
		cm.world_add_tag(&e3.world)
	}
	open(e3, .Tags)
	run(e3, .Create)
	testing.expect(t, e3.note == NOTE_FULL && e3.world.tag_count == cm.WORLD_MAX_TAGS)
}

@(test)
test_a_needed_tag_asks_twice_before_a_rename_or_a_delete :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, _ := with_game_tags()
	defer free(e)
	cm.world_create_missing_tags(&e.world, &e.game_tags) // solid, spare, thing, spawn
	e.mode = .Hub
	goto_hub(e, .Tags)
	press(e, .Green)
	e.sel[.Tags] = 2 // thing: needed
	// Rename: the first green warns, any other command cancels the warning, the second green goes on.
	run(e, .Rename)
	testing.expect(t, e.confirm_rename && e.mode == .Setup)
	testing.expect_value(t, banner_text(e), "NEEDED BY THE GAME  GREEN: RENAME")
	press(e, .Up)
	testing.expect(t, !e.confirm_rename)
	e.row = .Rename
	press(e, .Green)
	testing.expect(t, e.confirm_rename && e.mode == .Setup)
	press(e, .Green)
	testing.expect(t, !e.confirm_rename && e.mode == .Text)
	name_typed(e, "item")
	testing.expect(t, cm.name_str(&e.world.tags[2]) == "item" && e.mode == .List)
	testing.expect_value(t, tag_detail(e, 2), "") // "item" is not needed; the needed "thing" is missing again
	testing.expect_value(t, tags_missing(e), 1)
	// Delete: the banner changes and it takes the usual two presses.
	e.sel[.Tags] = 3 // spawn: needed
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && e.world.tag_count == 4)
	testing.expect_value(t, banner_text(e), "NEEDED BY THE GAME  GREEN: DELETE")
	press(e, .Green)
	testing.expect(t, e.world.tag_count == 3 && cm.world_find_tag(&e.world, "spawn") < 0)
	// A tag the game does not need gets the plain question.
	e.sel[.Tags] = 1
	run(e, .Delete)
	testing.expect_value(t, banner_text(e), "DELETE IT?  GREEN: CONFIRM")
	// By mouse: RENAME twice for a needed tag.
	e.confirm_delete = false
	e.mode = .List
	e.sel[.Tags] = 0 // solid: needed and fixed -> the fixed note wins
	e.note = ""
	click_rect(e, RENAME_BUTTON)
	testing.expect_value(t, e.note, NOTE_TAG_RESERVED)
	cm.world_create_missing_tags(&e.world, &e.game_tags) // thing and spawn again
	e.sel[.Tags] = e.world.tag_count - 1
	click_rect(e, RENAME_BUTTON)
	testing.expect(t, e.confirm_rename && e.mode == .Setup)
	click_rect(e, NEW_BUTTON) // another click cancels
	testing.expect(t, !e.confirm_rename)
	// A tag the user just made is named at once, even if "tag" were a needed name.
	e.mode = .List
	run(e, .New)
	testing.expect_value(t, e.mode, Mode.Text)
}

@(test)
test_the_tags_text_and_buttons_fit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, _ := with_game_tags()
	defer free(e)
	m := cm.default_input_map()
	editor_set_labels(e, &m)
	for round in 0 ..< 2 {
		if round == 1 {
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for text in ([]string{"NEEDED BY THE GAME  %s: RENAME", "NEEDED BY THE GAME  %s: DELETE"}) {
			label := cm.action_label(&m, .Green)
			banner := text == "NEEDED BY THE GAME  %s: RENAME" ? "NEEDED BY THE GAME  " : "NEEDED BY THE GAME  "
			full := strings.concatenate({banner, label, text == "NEEDED BY THE GAME  %s: RENAME" ? ": RENAME" : ": DELETE"}, context.temp_allocator)
			testing.expectf(t, cm.text_width(full) + 8 <= BANNER.w, "banner too wide: %s", full)
			if round == 0 {
				testing.expectf(t, cm.text_is_drawable(full), "banner: %s", full)
			}
		}
	}
	for word in ([]string{"CREATE", "MISSING", "FIXED, NEEDED", "NEEDED, UNUSED", "NEEDED", "9 MISSING", NOTE_TAG_MISSING, NOTE_GAME_TAGS_ASKED, NOTE_GAME_TAGS_BAD, NOTE_NOTHING_MISSING, "CREATED 64 TAGS"}) {
		testing.expectf(t, cm.text_is_drawable(word) && INFO_X + cm.text_width(word) <= cm.SCREEN_W - 4, "text: %s", word)
	}
	testing.expect(t, cm.text_width("CREATE") <= IMPORT_BUTTON.w - 2)
	// The longest info line: a long note after a full position.
	long := strings.repeat("W", 44, context.temp_allocator)
	line := strings.concatenate({"64 OF 64  ", long, "  *"}, context.temp_allocator)
	testing.expect(t, INFO_X + cm.text_width(line) <= cm.SCREEN_W)
	testing.expect(t, LIST_X + 2 + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") + cm.text_width("NEEDED, UNUSED") + 6 <= LIST_W)
}

// --- Game parameters ---

// Opens the Params list from the hub and returns.
open_params :: proc(e: ^Editor) {
	e.mode = .Hub
	goto_hub(e, .Params)
	press(e, .Green)
}

@(test)
test_parse_whole_number_accepts_only_32_bit_integers :: proc(t: ^testing.T) {
	cases := []struct {
		text:     string,
		value:    int,
		ok, fits: bool,
	} {
		{"0", 0, true, true},
		{"60", 60, true, true},
		{"007", 7, true, true},
		{"-12", -12, true, true},
		{"2147483647", 2147483647, true, true},
		{"-2147483648", -2147483648, true, true},
		{"2147483648", 0, true, false},
		{"-2147483649", 0, true, false},
		{"99999999999999999999999999", 0, true, false},
		{"", 0, false, true},
		{"-", 0, false, true},
		{"12a", 0, false, true},
		{"1 2", 0, false, true},
		{"+5", 0, false, true},
		{"99999999999999999999x", 0, false, true},
		{"--5", 0, false, true},
	}
	for c in cases {
		v, ok, fits := parse_whole_number(c.text)
		testing.expectf(t, ok == c.ok && fits == c.fits && (!c.ok || !c.fits || v == c.value), "%q: got %d %v %v", c.text, v, ok, fits)
	}
}

@(test)
test_new_parameter_is_named_then_edited_as_a_number :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	open_params(e)
	testing.expect(t, e.mode == .List && e.section == .Params)
	press(e, .Yellow)
	for e.row != .New {
		press(e, .Down)
	}
	press(e, .Green)
	testing.expect(t, e.mode == .Text && e.world.param_count == 1 && e.dirty)
	name_typed(e, "round")
	testing.expect_value(t, e.mode, Mode.Value) // named, then its value screen
	testing.expect(t, cm.name_str(&e.world.params[0].name) == "round" && e.world.params[0].kind == .Number)
	press(e, .Right, .Right, .Up)
	testing.expect_value(t, e.world.params[0].number, 12)
	press(e, .Left, .Down, .Down)
	testing.expect_value(t, e.world.params[0].number, -9)
	editor_handle_event(e, cm.Mouse_Wheel{dy = 4})
	testing.expect_value(t, e.world.params[0].number, -5)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.List)
	testing.expect_value(t, item_detail(e, .Params, 0), "-5")
}

@(test)
test_a_number_can_be_typed_and_a_bad_one_asks_again :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	cm.world_add_param(&e.world, "round")
	open_params(e)
	press(e, .Green) // open the value
	testing.expect_value(t, e.mode, Mode.Value)
	press(e, .Green) // the keypad, starting with the current digits
	testing.expect(t, e.mode == .Text && e.text_target == .Number && cm.text_entry_text(&e.entry) == "0")
	name_typed(e, "250")
	testing.expect(t, e.mode == .Value && e.world.params[0].number == 250 && e.text_target == .Name)
	for bad, i in ([]string{"12a", "-", "99999999999", "x"}) {
		press(e, .Green)
		name_typed(e, bad)
		testing.expectf(t, e.mode == .Text && e.entry.note != "" && e.world.params[0].number == 250, "%q was accepted", bad)
		testing.expect(t, cm.text_is_drawable(e.entry.note) && cm.text_width(e.entry.note) <= cm.SCREEN_W)
		press_keypad_action(e, .Cancel) // back to the value screen, unchanged
		testing.expect_value(t, e.mode, Mode.Value)
		_ = i
	}
	press(e, .Green)
	name_typed(e, "-5")
	testing.expect_value(t, e.world.params[0].number, -5)
	press(e, .Green)
	name_typed(e, "2147483647")
	testing.expect_value(t, e.world.params[0].number, 2147483647)
	press(e, .Right) // stays at the top
	testing.expect_value(t, e.world.params[0].number, 2147483647)
}

@(test)
test_a_text_parameter_is_typed_and_kind_switches :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	cm.world_add_param(&e.world, "title")
	cm.world_set_param_number(&e.world, 0, 77)
	open_params(e)
	press(e, .Green)
	press(e, .Yellow) // number -> text (empty at first)
	testing.expect(t, e.world.params[0].kind == .Text && e.dirty)
	press(e, .Right, .Up) // a text has no steps
	testing.expect_value(t, e.world.params[0].number, 77)
	press(e, .Green)
	testing.expect(t, e.mode == .Text && e.text_target == .Text_Value)
	name_typed(e, "Go Get It!")
	testing.expect(t, e.mode == .Value && cm.name_str(&e.world.params[0].text) == "Go Get It!")
	testing.expect_value(t, item_detail(e, .Params, 0), "\"Go Get It!\"") // the list shows it in quotes
	// An empty text is fine.
	press(e, .Green)
	press_keypad_action(e, .Clear)
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Value && cm.name_str(&e.world.params[0].text) == "")
	// Back to number: the old number returns.
	press(e, .Yellow)
	testing.expect(t, e.world.params[0].kind == .Number && e.world.params[0].number == 77)
	// A long text is cut in the list.
	cm.world_set_param_text(&e.world, 0, "WWWWWWWWWWWWWWWWWWWWWWWW")
	testing.expect(t, cm.text_width(item_detail(e, .Params, 0)) + 2 + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") + 6 <= LIST_W)
}

@(test)
test_the_value_screen_has_a_button_for_everything :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	cm.world_add_param(&e.world, "round")
	open_params(e)
	click_item(e, 0) // the selected one again: opens it
	testing.expect_value(t, e.mode, Mode.Value)
	for step in ([]struct {
			rc:   Rect,
			want: int,
		}{{VALUE_PLUS10, 10}, {VALUE_PLUS1, 11}, {VALUE_MINUS1, 10}, {VALUE_MINUS10, 0}}) {
		click_rect(e, step.rc)
		testing.expectf(t, e.world.params[0].number == step.want, "after a click: %d", e.world.params[0].number)
	}
	click_rect(e, VALUE_EDIT)
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed(e, "42")
	testing.expect_value(t, e.world.params[0].number, 42)
	click_rect(e, VALUE_KIND)
	testing.expect_value(t, e.world.params[0].kind, cm.Param_Kind.Text)
	click_rect(e, VALUE_PLUS10) // no effect on a text
	testing.expect_value(t, e.world.params[0].number, 42)
	click_rect(e, VALUE_KIND)
	click_rect(e, VALUE_BACK)
	testing.expect_value(t, e.mode, Mode.List)
	// The KIND button of the list does the same without opening the value.
	click_rect(e, IMPORT_BUTTON)
	testing.expect_value(t, e.world.params[0].kind, cm.Param_Kind.Text)
	press(e, .Yellow)
	for e.row != .Kind {
		press(e, .Down)
	}
	press(e, .Green)
	testing.expect_value(t, e.world.params[0].kind, cm.Param_Kind.Number)
}

@(test)
test_parameters_are_renamed_duplicated_and_deleted_from_the_list :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	a := cm.world_add_param(&e.world, "round")
	cm.world_set_param_number(&e.world, a, 60)
	cm.world_add_param(&e.world, "points")
	open_params(e)
	run(e, .Rename)
	name_typed(e, "points") // taken
	testing.expect(t, e.mode == .Text && strings.contains(e.entry.note, "USE"))
	name_typed(e, "seconds")
	testing.expect(t, e.mode == .List && cm.name_str(&e.world.params[0].name) == "seconds")
	run(e, .Duplicate)
	testing.expect(t, e.mode == .Text && e.world.param_count == 3 && cm.name_str(&e.world.params[1].name) == "seconds_copy" && e.world.params[1].number == 60)
	press_keypad_action(e, .Done)
	testing.expect_value(t, e.mode, Mode.Value) // a copy opens its value
	press(e, .Red)
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && e.world.param_count == 3)
	press(e, .Green)
	testing.expect(t, e.world.param_count == 2 && cm.name_str(&e.world.params[1].name) == "points")
	for e.world.param_count < cm.WORLD_MAX_PARAMS {
		cm.world_add_param(&e.world)
	}
	e.note = ""
	run(e, .New)
	testing.expect_value(t, e.note, NOTE_FULL)
	// An empty list has nothing to open, rename or switch.
	e2 := new_editor()
	defer free(e2)
	open_params(e2)
	press(e2, .Green)
	testing.expect(t, e2.mode == .List && e2.note == NOTE_EMPTY)
	run(e2, .Kind)
	testing.expect_value(t, e2.note, NOTE_EMPTY)
}

@(test)
test_parameters_survive_save_and_load_in_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	n := cm.world_add_param(&e.world, "round_seconds")
	cm.world_set_param_number(&e.world, n, 90)
	s := cm.world_add_param(&e.world, "title")
	cm.world_set_param_text(&e.world, s, "Hi")
	tl := tool(e)
	press(e, .Blue, .Green)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok && strings.contains(text, `{"name": "round_seconds", "number": 90}`))
	e2 := new_editor()
	defer free(e2)
	tl2 := tool(e2)
	testing.expect(t, tl2.load(tl2.data, transmute([]u8)text))
	testing.expect(t, e2.world.param_count == 2 && cm.world_param_number(&e2.world, "round_seconds", 0) == 90 && cm.world_param_text(&e2.world, "title", "") == "Hi")
	// The hub shows the count.
	e2.mode = .Hub
	testing.expect_value(t, section_count(e2, .Params), 2)
}

@(test)
test_the_value_screen_text_and_layout_fit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	m := cm.default_input_map()
	editor_set_labels(e, &m)
	cm.world_add_param(&e.world, "round")
	for round in 0 ..< 2 {
		if round == 1 {
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		banner := value_banner_text(e)
		lines, n := value_help_lines(e)
		if round == 0 {
			testing.expectf(t, cm.text_is_drawable(banner), "banner: %s", banner)
		}
		testing.expectf(t, cm.text_width(banner) + 8 <= BANNER.w, "banner too wide: %s", banner)
		for line in lines[:n] {
			if round == 0 {
				testing.expectf(t, cm.text_is_drawable(line), "help: %s", line)
			}
			testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
		}
	}
	for text in ([]string{NOTE_NOT_A_NUMBER, NOTE_OUT_OF_RANGE, NOTE_TEXT_BAD, NOTE_PARAM_NOTHING, "(EMPTY)", "A WHOLE NUMBER", "A SHORT TEXT", "-2147483648", "KIND", "EDIT", "PARAMS", "64 OF 64"}) {
		testing.expectf(t, cm.text_is_drawable(text) && INFO_X + cm.text_width(text) <= cm.SCREEN_W - 4, "text: %s", text)
	}
	// A 32 character text at double size fits the screen from the value's x.
	testing.expect(t, VALUE_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW", 2) <= cm.SCREEN_W - 4)
	testing.expect(t, VALUE_X + cm.text_width("-2147483648", 2) <= cm.SCREEN_W)
	rects := [?]Rect{VALUE_MINUS10, VALUE_MINUS1, VALUE_PLUS1, VALUE_PLUS10, VALUE_EDIT, VALUE_KIND, VALUE_BACK, BANNER}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	testing.expect(t, VALUE_BACK.y + VALUE_BACK.h <= HELP_Y && VALUE_PLUS10.y + VALUE_PLUS10.h < VALUE_BACK.y)
	for label in ([]string{"-10", "-1", "+1", "+10"}) {
		testing.expect(t, cm.text_width(label) <= VALUE_MINUS1.w - 2 && cm.text_is_drawable(label))
	}
}

// --- Play mode ---

// Gives the world a player (a character of a new type) standing at (px, py) of map 0, and makes the
// rock terrain solid.
add_player :: proc(e: ^Editor, px := 1, py := 1) -> int {
	if e.world.char_type_count == 0 {
		cm.world_add_char_type(&e.world, "hero")
	}
	ci := cm.world_add_character(&e.world, 0)
	cm.name_assign(&e.world.characters[ci].name, "Hero")
	cm.world_place_character(&e.world, 0, px, py, e.world.characters[ci].uuid)
	cm.world_set_player(&e.world, e.world.characters[ci].uuid)
	e.world.sets[0].terrains[1].tags = cm.tag_bit(cm.TAG_SOLID) // rock is solid
	return ci
}

@(test)
test_play_needs_a_player_on_a_map :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	press(e, .Yellow)
	testing.expect(t, e.mode == .Hub && e.note == NOTE_NO_PLAYER)
	cm.world_add_char_type(&e.world, "hero")
	ci := cm.world_add_character(&e.world, 0)
	cm.world_set_player(&e.world, e.world.characters[ci].uuid) // the player stands nowhere
	press(e, .Yellow)
	testing.expect(t, e.mode == .Hub && e.note == NOTE_PLAYER_OFF_MAP)
	cm.world_place_character(&e.world, 0, 0, 0, e.world.characters[ci].uuid)
	press(e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Play)
	// The button does the same.
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Hub)
	click_rect(e, PLAY_BUTTON)
	testing.expect_value(t, e.mode, Mode.Play)
}

@(test)
test_the_player_steps_and_is_stopped_by_solid_cells_edges_and_characters :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content() // map "start": 3 x 3, everything grass
	defer free(e)
	add_player(e, 1, 1)
	e.world.maps[0].cells[1][2] = 1 // a rock (solid) at 2,1
	other := cm.world_add_character(&e.world, 0)
	cm.name_assign(&e.world.characters[other].name, "Goblin")
	cm.world_place_character(&e.world, 0, 1, 2, e.world.characters[other].uuid)
	before := cm.world_to_json(&e.world)
	press(e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Play)
	pos :: proc(e: ^Editor) -> [2]int {
		p := rt.play_position(&e.play, e.play_player)
		return {p.x, p.y}
	}
	press(e, .Right)
	testing.expect(t, e.note == "BLOCKED: SOLID" && pos(e) == [2]int{1, 1} && e.play_steps == 0)
	press(e, .Down)
	testing.expect(t, e.note == "BLOCKED BY Goblin" && pos(e) == [2]int{1, 1})
	press(e, .Up)
	testing.expect(t, e.note == "" && pos(e) == [2]int{1, 0} && e.play_steps == 1)
	press(e, .Up)
	testing.expect(t, e.note == "THE EDGE OF THE MAP" && pos(e) == [2]int{1, 0})
	press(e, .Left, .Left)
	testing.expect(t, pos(e) == [2]int{0, 0} && e.note == "THE EDGE OF THE MAP")
	press(e, .Down, .Down)
	testing.expect(t, pos(e) == [2]int{0, 2} && e.play_steps == 4)
	// Other commands do nothing; red leaves and the world is exactly as it was.
	press(e, .Green, .Yellow, .Blue)
	testing.expect(t, e.mode == .Play && pos(e) == [2]int{0, 2})
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Hub)
	testing.expect_value(t, cm.world_to_json(&e.world), before)
	testing.expect_value(t, cm.world_character_at(&e.world, 0, 1, 1), 0) // the player is back where it was authored
	press(e, .Yellow) // playing again starts there
	testing.expect(t, e.mode == .Play && pos(e) == [2]int{1, 1} && e.play_steps == 0)
	// A cell that clears solid is a doorway.
	press(e, .Red)
	cm.world_cycle_cell_tag(&e.world, 0, 2, 1, cm.TAG_SOLID) // set
	cm.world_cycle_cell_tag(&e.world, 0, 2, 1, cm.TAG_SOLID) // cleared
	press(e, .Yellow, .Right)
	testing.expect(t, e.note == "" && pos(e) == [2]int{2, 1})
}

@(test)
test_the_mouse_steps_to_neighbouring_cells_and_back_leaves :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content()
	defer free(e)
	add_player(e, 1, 1)
	e.world.maps[0].cells[2][1] = 1 // rock below the player
	press(e, .Yellow)
	d := play_window(e)
	cell :: proc(d: rt.World_Draw, x, y: int) -> (int, int) {
		rc := cm.world_cell_rect(d, x, y)
		return rc.x + rc.w / 2, rc.y + rc.h / 2
	}
	pos :: proc(e: ^Editor) -> [2]int {
		p := rt.play_position(&e.play, e.play_player)
		return {p.x, p.y}
	}
	x, y := cell(d, 2, 1)
	click_at(e, x, y)
	testing.expect(t, pos(e) == [2]int{2, 1} && e.play_steps == 1)
	x, y = cell(d, 0, 0)
	click_at(e, x, y) // two cells away
	testing.expect(t, e.note == NOTE_CLICK_NEXT_TO && pos(e) == [2]int{2, 1})
	x, y = cell(d, 2, 1)
	click_at(e, x, y) // the player's own cell: nothing
	testing.expect(t, e.note == "" && pos(e) == [2]int{2, 1})
	x, y = cell(d, 1, 1)
	click_at(e, x, y)
	x, y = cell(d, 1, 2)
	click_at(e, x, y) // the rock below
	testing.expect(t, e.note == "BLOCKED: SOLID" && pos(e) == [2]int{1, 1})
	click_at(e, 2, 2) // the strip, not a cell
	testing.expect_value(t, e.mode, Mode.Play)
	click_rect(e, PLAY_BACK)
	testing.expect_value(t, e.mode, Mode.Hub)
}

@(test)
test_the_view_fits_a_small_map_and_follows_the_player_on_a_big_one :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_content() // tiles 4 x 4, map 3 x 3
	defer free(e)
	add_player(e, 1, 1)
	// Small map: the biggest zoom that fits (3 cells of 4 pixels: zoom 8 gives 96 x 96 pixels, fits).
	testing.expect_value(t, play_zoom(&e.world, 0), 8)
	press(e, .Yellow)
	d := play_window(e)
	testing.expect(t, d.cols == 3 && d.rows == 3 && d.cell_w == 32 && d.col == 0 && d.row == 0)
	testing.expect(t, d.x == (cm.SCREEN_W - 96) / 2 && d.y >= PLAY_MAP_Y && d.y + 96 <= cm.SCREEN_H) // centred below the strip
	// A big map does not fit: zoom 1 and a window that follows the player.
	press(e, .Red)
	cm.world_set_tile_size(&e.world, 16, 16)
	cm.world_map_set_size(&e.world, 0, 64, 64)
	testing.expect_value(t, play_zoom(&e.world, 0), 1)
	cm.world_unplace_character(&e.world, e.world.characters[0].uuid)
	cm.world_place_character(&e.world, 0, 60, 60, e.world.characters[0].uuid)
	press(e, .Yellow)
	d = play_window(e)
	testing.expect(t, d.cols == 20 && d.rows == PLAY_MAP_H / 16 && d.col == 64 - 20 && d.row == 64 - d.rows) // clamped at the far corner
	cell := cm.world_cell_rect(d, 60, 60)
	testing.expect(t, cell.x >= 0 && cell.x + cell.w <= cm.SCREEN_W && cell.y >= PLAY_MAP_Y && cell.y + cell.h <= cm.SCREEN_H) // the player is on screen
	press(e, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left)
	d = play_window(e)
	p := rt.play_position(&e.play, e.play_player)
	testing.expect(t, p.x == 0 && d.col == 0)
	cell = cm.world_cell_rect(d, p.x, p.y)
	testing.expect(t, cell.x >= 0 && cell.y >= PLAY_MAP_Y && cell.y + cell.h <= cm.SCREEN_H)
}

@(test)
test_play_text_and_layout_fit :: proc(t: ^testing.T) {
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
		banner := play_banner_text(e)
		help := play_help_text(e)
		if round == 0 {
			testing.expect(t, cm.text_is_drawable(banner) && cm.text_is_drawable(help))
		}
		// The banner and the status share the strip: the banner ends before the status.
		testing.expectf(t, 4 + cm.text_width(banner) <= PLAY_STATUS_X, "banner too wide: %s", banner)
		testing.expectf(t, 8 + cm.text_width(help) <= cm.SCREEN_W - 8, "help too wide: %s", help)
		lines, n := help_lines(e)
		for line in lines[:n] {
			testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "hub help too wide: %s", line)
		}
	}
	// The longest messages fit between PLAY_STATUS_X and BACK.
	for note in ([]string{NOTE_NO_PLAYER, NOTE_PLAYER_OFF_MAP, NOTE_CLICK_NEXT_TO, "BLOCKED: SOLID", "THE EDGE OF THE MAP", "BLOCKED BY WWWWWWWWWWWWWWWWWWWW", "AT 63,63  STEPS 99999"}) {
		testing.expectf(t, cm.text_is_drawable(note), "note: %s", note)
		if len(note) <= 31 && note != NOTE_NO_PLAYER && note != NOTE_PLAYER_OFF_MAP && note != NOTE_CLICK_NEXT_TO {
			testing.expectf(t, PLAY_STATUS_X + cm.text_width(note) <= PLAY_BACK.x, "status too wide: %s", note)
		}
		testing.expectf(t, INFO_X + cm.text_width(note) <= cm.SCREEN_W - 4, "hub note too wide: %s", note)
	}
	testing.expect(t, PLAY_BACK.x + PLAY_BACK.w <= cm.SCREEN_W && PLAY_BACK.y + PLAY_BACK.h <= PLAY_STRIP_H)
	testing.expect(t, PLAY_BUTTON.x >= MENU_BUTTON.x + MENU_BUTTON.w && PLAY_BUTTON.x + PLAY_BUTTON.w <= cm.SCREEN_W && PLAY_BUTTON.y + PLAY_BUTTON.h <= HELP_Y)
	testing.expect(t, cm.text_width("PLAY") <= PLAY_BUTTON.w - 2)
}
