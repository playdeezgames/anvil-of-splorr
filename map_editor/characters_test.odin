#+build !js
package map_editor

import cm "../common"
import "core:strings"
import "core:testing"

// The map editor's world (tileset "t", sets "s" and "other", map "m" 6 x 4) plus a sprite set
// "creatures" (slime, bat), character types "slime" and "bat", and characters Goo (slime, at 1,0),
// Flap (bat, off the map) and Pip (slime, off the map).
char_world :: proc(w := 6, h := 4) -> ^cm.World {
	world := make_world(5, w, h)
	cm.world_seed_uuids(world, 77)
	creatures := cm.world_add_sprite_set(world, "creatures")
	for name in ([]string{"slime", "bat"}) {
		n := cm.world_add_sprite(world, creatures)
		cm.name_assign(&world.sprite_sets[creatures].sprites[n].name, name)
	}
	cm.name_assign(&world.sprite_sets[creatures].sprites[1].image, "i_2")
	slime := cm.world_add_char_type(world, "slime")
	bat := cm.world_add_char_type(world, "bat")
	cm.name_assign(&world.char_types[bat].sprite, "bat")
	for spec in ([][2]string{{"Goo", "slime"}, {"Flap", "bat"}, {"Pip", "slime"}}) {
		n := cm.world_add_character(world, spec[1] == "bat" ? bat : slime)
		cm.name_assign(&world.characters[n].name, spec[0])
	}
	cm.world_place_character(world, 0, 1, 0, world.characters[0].uuid)
	return world
}

char_editor :: proc(w := 6, h := 4) -> (e: ^Editor, world: ^cm.World) {
	world = char_world(w, h)
	e = new(Editor)
	editor_begin(e, world, 0)
	toggle_layer(e)
	return
}

name_typed_in_map :: proc(e: ^Editor, name: string) {
	for e.entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(e.entry.col) != .Clear {
		press(e, .Right)
	}
	press(e, .Green)
	for i in 0 ..< len(name) {
		ch := name[i]
		if e.entry.row == cm.TEXT_ENTRY_ROWS - 1 {
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
		rights := (tcol - e.entry.col + cm.TEXT_ENTRY_COLS) % cm.TEXT_ENTRY_COLS
		downs := (trow - e.entry.row + cm.TEXT_ENTRY_ROWS) % cm.TEXT_ENTRY_ROWS
		for _ in 0 ..< rights {
			press(e, .Right)
		}
		for _ in 0 ..< downs {
			press(e, .Down)
		}
		press(e, .Green)
	}
	for e.entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(e.entry.col) != .Done {
		press(e, .Right)
	}
	press(e, .Green)
}

keypad_cancel :: proc(e: ^Editor) {
	for e.entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(e.entry.col) != .Cancel {
		press(e, .Right)
	}
	press(e, .Green)
}

@(test)
test_the_layer_switch_and_the_rows_each_layer_offers :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	testing.expect_value(t, e.layer, Layer.Terrain)
	goto_row(e, .Layer)
	press(e, .Green)
	testing.expect(t, e.layer == .Characters && e.row == .Character)
	// Up and down cycle only the character rows (plus zoom and layer).
	seen: bit_set[Setup_Row]
	for _ in 0 ..< 12 {
		seen += {e.row}
		press(e, .Down)
	}
	testing.expect(t, seen == {.Character, .Char_Type, .Char_Player, .Char_Rename, .Char_New, .Char_Unplace, .Char_Delete, .Zoom, .Layer, .Tags})
	e.row = .Layer
	press(e, .Green) // characters -> features -> terrain
	testing.expect(t, e.layer == .Features && e.row == .Feature)
	seen = {}
	for _ in 0 ..< 12 {
		seen += {e.row}
		press(e, .Down)
	}
	testing.expect(t, seen == {.Feature, .Feat_Type, .Feat_Rename, .Feat_New, .Feat_Unplace, .Feat_Delete, .Zoom, .Layer, .Tags})
	e.row = .Layer
	press(e, .Green) // features -> items -> terrain
	testing.expect(t, e.layer == .Items && e.row == .Cell_Open)
	seen = {}
	for _ in 0 ..< 12 {
		seen += {e.row}
		press(e, .Down)
	}
	testing.expect(t, seen == {.Cell_Open, .Cell_Clear, .Zoom, .Layer}) // no tags: an inventory has none of its own
	e.row = .Layer
	press(e, .Green)
	testing.expect(t, e.layer == .Terrain && e.row == .Terrain)
	seen = {}
	for _ in 0 ..< 20 {
		seen += {e.row}
		press(e, .Down)
	}
	testing.expect(t, .Character not_in seen && .Flip_Horizontal in seen && .Layer in seen && .Clear in seen && .Tags in seen)
	click_rect(e, LAYER_BUTTON)
	testing.expect_value(t, e.layer, Layer.Characters)
	click_rect(e, LAYER_BUTTON)
	testing.expect_value(t, e.layer, Layer.Features)
	click_rect(e, LAYER_BUTTON)
	testing.expect_value(t, e.layer, Layer.Items)
	click_rect(e, LAYER_BUTTON)
	testing.expect_value(t, e.layer, Layer.Terrain)
	// Switching abandons an armed tool.
	click_rect(e, FRAME_BUTTON)
	click_rect(e, LAYER_BUTTON)
	testing.expect_value(t, e.shape, cm.Shape.None)
}

@(test)
test_the_player_is_the_first_current_character :: proc(t: ^testing.T) {
	world := char_world()
	defer free(world)
	world.player = world.characters[2].uuid
	e := new(Editor)
	defer free(e)
	editor_begin(e, world, 0)
	testing.expect_value(t, e.cur_char, 2)
	world.player = cm.UUID_NONE
	editor_begin(e, world, 0)
	testing.expect_value(t, e.cur_char, 0)
}

@(test)
test_green_places_picks_and_moves_characters :: proc(t: ^testing.T) {
	e, world := char_editor()
	defer free_both(e, world)
	goo, flap := world.characters[0].uuid, world.characters[1].uuid
	// Green on Goo's cell makes Goo current (it already is); on an empty cell it moves Goo there.
	e.cx, e.cy = 3, 2
	press(e, .Green)
	testing.expect(t, e.dirty && cm.world_character_at(world, 0, 3, 2) == 0 && cm.world_character_at(world, 0, 1, 0) == -1)
	// Pick Flap with the picker: it is off the map; green on an empty cell puts it there.
	e.cur_char = 1
	e.cx, e.cy = 0, 0
	press(e, .Green)
	testing.expect_value(t, cm.world_character_at(world, 0, 0, 0), 1)
	// Green on a cell with another character makes that one current (nothing is replaced).
	e.cx, e.cy = 3, 2
	press(e, .Green)
	testing.expect(t, e.cur_char == 0 && cm.world_character_at(world, 0, 0, 0) == 1 && cm.world_character_at(world, 0, 3, 2) == 0)
	_ = goo
	_ = flap
	// Moving the cursor and pressing green again with Goo current moves Goo.
	press(e, .Left, .Green)
	testing.expect_value(t, cm.world_character_at(world, 0, 2, 2), 0)
	testing.expect_value(t, cm.world_map_character_count(world, 0), 2)
	// Placing a character that stands on another map moves it here.
	m2 := cm.world_add_map(world, 0, "second")
	cm.world_place_character(world, m2, 0, 0, world.characters[2].uuid)
	e.cur_char = 2
	e.cx, e.cy = 5, 3
	press(e, .Green)
	testing.expect(t, cm.world_character_at(world, 0, 5, 3) == 2 && cm.world_character_at(world, m2, 0, 0) == -1)
}

@(test)
test_the_readout_and_setup_rows_of_the_characters_layer :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := char_editor()
	defer free_both(e, world)
	goto_row(e, .Character)
	press(e, .Right) // Flap: off the map, so the cursor stays
	testing.expect(t, e.cur_char == 1 && e.cx == 0 && e.cy == 0)
	testing.expect_value(t, char_place_text(e, 1), "OFF MAP")
	press(e, .Left) // Goo stands at 1,0: the cursor goes there
	testing.expect(t, e.cur_char == 0 && e.cx == 1 && e.cy == 0)
	testing.expect_value(t, char_place_text(e, 0), "AT 1,0")
	press(e, .Left) // wraps to the last
	testing.expect_value(t, e.cur_char, 2)
	// Standing on another map is shown by that map's name.
	m2 := cm.world_add_map(world, 0, "second")
	cm.world_place_character(world, m2, 2, 2, world.characters[2].uuid)
	testing.expect_value(t, char_place_text(e, 2), "ON second")
	// Type.
	goto_row(e, .Char_Type)
	press(e, .Right)
	testing.expect(t, cm.name_str(&world.characters[2].type) == "bat" && e.dirty)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&world.characters[2].type), "slime")
	// Player.
	goto_row(e, .Char_Player)
	press(e, .Right)
	testing.expect_value(t, world.player, world.characters[2].uuid)
	press(e, .Left) // either direction toggles
	testing.expect(t, cm.uuid_is_none(world.player))
	// Blue steps the current character by a page (3 characters: wraps to itself).
	press(e, .Blue)
	testing.expect_value(t, e.cur_char, (2 + CHAR_PAGE) % 3)
}

@(test)
test_rename_new_unplace_and_delete_characters_from_the_map :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := char_editor()
	defer free_both(e, world)
	// Rename Goo by keypad.
	e.cur_char = 0
	run(e, .Char_Rename)
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed_in_map(e, "Slimer")
	testing.expect(t, e.mode == .Setup && character_name(e, 0) == "Slimer" && e.dirty)
	run(e, .Char_Rename)
	keypad_cancel(e)
	testing.expect(t, e.mode == .Setup && character_name(e, 0) == "Slimer")
	// New: the current character's type, put at the cursor when free, then named.
	e.cx, e.cy = 4, 3
	e.cur_char = 1 // a bat
	run(e, .Char_New)
	testing.expect(t, e.mode == .Text && world.character_count == 4 && e.cur_char == 3)
	testing.expect(t, cm.name_str(&world.characters[3].type) == "bat" && cm.world_character_at(world, 0, 4, 3) == 3)
	name_typed_in_map(e, "Zed")
	testing.expect_value(t, character_name(e, 3), "Zed")
	// New on a taken cell leaves the new character off the map.
	e.cx, e.cy = 4, 3
	run(e, .Char_New)
	press_keypad_name_done(e)
	testing.expect(t, world.character_count == 5 && cm.world_character_at(world, 0, 4, 3) == 3 && cm.world_map_character_count(world, 0) == 2)
	// Unplace.
	e.cur_char = 3
	run(e, .Char_Unplace)
	testing.expect(t, cm.world_character_at(world, 0, 4, 3) == -1 && e.dirty)
	e.note = ""
	run(e, .Char_Unplace)
	testing.expect_value(t, e.note, NOTE_NOT_PLACED)
	// Delete asks twice.
	e.cur_char = 0
	cm.world_set_player(world, world.characters[0].uuid)
	run(e, .Char_Delete)
	testing.expect(t, e.confirm_delete && world.character_count == 5)
	press(e, .Up)
	testing.expect(t, !e.confirm_delete)
	e.row = .Char_Delete
	press(e, .Green, .Green)
	testing.expect(t, world.character_count == 4 && cm.uuid_is_none(world.player) && cm.world_character_at(world, 0, 1, 0) == -1)
}

press_keypad_name_done :: proc(e: ^Editor) {
	for e.entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(e.entry.col) != .Done {
		press(e, .Right)
	}
	press(e, .Green)
}

@(test)
test_the_characters_layer_says_what_is_missing :: proc(t: ^testing.T) {
	e, world := char_editor()
	defer free_both(e, world)
	world.char_type_count = 0
	run(e, .Char_New)
	testing.expect(t, e.note == NOTE_NEED_TYPE && world.character_count == 3)
	world.character_count = 0
	world.char_type_count = 2
	for row in ([]Setup_Row{.Char_Rename, .Char_Unplace, .Char_Delete, .Char_Player}) {
		e.note = ""
		run(e, row)
		testing.expectf(t, e.note == NOTE_NO_CHARACTERS, "%v with no characters", row)
	}
	goto_row(e, .Character)
	e.note = ""
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NO_CHARACTERS)
	goto_row(e, .Char_Type)
	e.note = ""
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NO_CHARACTERS)
	e.mode = .Draw
	e.note = ""
	press(e, .Green)
	testing.expect_value(t, e.note, NOTE_NO_CHARACTERS)
	// A full table.
	for world.character_count < cm.WORLD_MAX_CHARACTERS {
		cm.world_add_character(world, 0)
	}
	run(e, .Char_New)
	testing.expect_value(t, e.note, NOTE_CHAR_FULL)
	// A character whose type was deleted out from under it: no types to step to.
	world.char_type_count = 0
	e.note = ""
	goto_row(e, .Char_Type)
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NEED_TYPE)
}

@(test)
test_picking_characters_with_the_mouse :: proc(t: ^testing.T) {
	e, world := char_editor()
	defer free_both(e, world)
	for world.character_count < 40 {
		cm.world_add_character(world, 0)
	}
	// Right click on Goo's cell takes it and shows it in Setup.
	rc := cell_rect(e, 1, 0)
	e.cur_char = 2
	mouse(e, rc.x + 1, rc.y + 1, true, .Right)
	testing.expect(t, e.cur_char == 0 && e.mode == .Setup && e.row == .Character && e.cx == 1)
	// Right click on an empty cell does nothing to the choice.
	rc2 := cell_rect(e, 4, 3)
	mouse(e, rc2.x + 1, rc2.y + 1, true, .Right)
	testing.expect_value(t, e.cur_char, 0)
	// The picker: left click chooses, the page follows the current character.
	click_at(e, picker_rect(5).x + 2, picker_rect(5).y + 2)
	testing.expect(t, e.cur_char == 5 && e.mode == .Setup)
	mouse(e, picker_rect(3).x + 2, picker_rect(3).y + 2, true, .Right)
	testing.expect_value(t, e.cur_char, 3)
	editor_handle_event(e, cm.Mouse_Move{picker_rect(2).x, picker_rect(2).y})
	editor_handle_event(e, cm.Mouse_Wheel{dy = -1}) // down: the next page
	testing.expect_value(t, e.cur_char, 19)
	idx, ok := char_picker_at(e, picker_rect(1).x, picker_rect(1).y)
	testing.expect(t, ok && idx == 17)
	e.cur_char = 33 // the last page holds only 32..39
	_, ok = char_picker_at(e, picker_rect(9).x, picker_rect(9).y)
	testing.expect(t, !ok)
	// Left click on a cell does what green does.
	e.cur_char = 4
	click_cell(e, 2, 1)
	testing.expect_value(t, cm.world_character_at(world, 0, 2, 1), 4)
	click_cell(e, 1, 0) // empty now? no: Goo is still at 1,0: pick
	testing.expect_value(t, e.cur_char, 0)
}

@(test)
test_every_character_function_is_reachable_by_each_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for m in Input_Method {
		e, world := char_editor()
		goo := world.characters[0].uuid
		// Choose Pip with the Character row / the picker.
		switch m {
		case .Commands:
			goto_row(e, .Character)
			press(e, .Left)
		case .Mouse:
			click_at(e, picker_rect(2).x + 2, picker_rect(2).y + 2)
		}
		testing.expectf(t, e.cur_char == 2, "%v choose", m)
		// Put it at 3,2.
		switch m {
		case .Commands:
			e.mode = .Draw
			for e.cx < 3 {
				press(e, .Right)
			}
			for e.cy < 2 {
				press(e, .Down)
			}
			press(e, .Green)
		case .Mouse:
			click_cell(e, 3, 2)
		}
		testing.expectf(t, cm.world_character_at(world, 0, 3, 2) == 2, "%v place", m)
		// Type, player
		switch m {
		case .Commands:
			goto_row(e, .Char_Type)
			press(e, .Right)
		case .Mouse:
			click_rect(e, COLUMNS_PLUS)
		}
		testing.expectf(t, cm.name_str(&world.characters[2].type) == "bat", "%v type", m)
		switch m {
		case .Commands:
			run(e, .Char_Player)
		case .Mouse:
			click_rect(e, CHAR_PLAYER_BUTTON)
		}
		testing.expectf(t, world.player == world.characters[2].uuid, "%v player", m)
		// Unplace and rename
		switch m {
		case .Commands:
			run(e, .Char_Unplace)
		case .Mouse:
			click_rect(e, CHAR_UNPLACE_BUTTON)
		}
		testing.expectf(t, cm.world_character_at(world, 0, 3, 2) == -1, "%v unplace", m)
		switch m {
		case .Commands:
			run(e, .Char_Rename)
		case .Mouse:
			click_rect(e, CHAR_RENAME_BUTTON)
		}
		testing.expectf(t, e.mode == .Text, "%v rename", m)
		keypad_cancel(e)
		// New and delete
		switch m {
		case .Commands:
			run(e, .Char_New)
		case .Mouse:
			click_rect(e, CHAR_NEW_BUTTON)
		}
		keypad_cancel(e)
		testing.expectf(t, world.character_count == 4, "%v new", m)
		switch m {
		case .Commands:
			run(e, .Char_Delete)
			press(e, .Green)
		case .Mouse:
			click_rect(e, CHAR_DELETE_BUTTON)
			click_rect(e, CHAR_DELETE_BUTTON)
		}
		testing.expectf(t, world.character_count == 3, "%v delete", m)
		_ = goo
		// Layer and back
		switch m {
		case .Commands:
			run(e, .Layer)
		case .Mouse:
			click_rect(e, LAYER_BUTTON)
		}
		testing.expectf(t, e.layer == .Features, "%v layer", m) // the next layer after characters
		e.layer = .Characters
		switch m {
		case .Commands:
			e.mode = .Draw
			press(e, .Red)
		case .Mouse:
			click_rect(e, BACK_BUTTON)
		}
		testing.expectf(t, e.exit_requested, "%v leave", m)
		free_both(e, world)
	}
}

@(test)
test_flips_rotations_and_resizing_carry_characters_in_the_editor :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := char_editor(3, 3)
	defer free_both(e, world)
	toggle_layer(e) // features
	toggle_layer(e) // items
	toggle_layer(e) // terrain tools
	// Goo is at 1,0: a flip of the columns leaves it, a flip of the rows moves it.
	run(e, .Flip_Vertical)
	testing.expect_value(t, cm.world_character_at(world, 0, 1, 2), 0)
	run(e, .Rotate_Right)
	_, x, y, _ := cm.world_character_location(world, world.characters[0].uuid)
	testing.expect(t, x == 0 && y == 1) // the bottom row became the left column
	run(e, .Rotate_Left)
	run(e, .Rotate_180)
	_, x, y, _ = cm.world_character_location(world, world.characters[0].uuid)
	testing.expect(t, x == 1 && y == 0)
	// Shrinking over a character is refused with the count.
	goto_row(e, .Columns)
	press(e, .Left)
	testing.expect_value(t, current_map(e).width, 2) // Goo at column 1 still fits
	press(e, .Left)
	testing.expect(t, current_map(e).width == 2 && e.note == "1 THING IN THE WAY")
	goto_row(e, .Rows)
	press(e, .Left)
	testing.expect(t, current_map(e).height == 2 && cm.world_character_at(world, 0, 1, 0) == 0)
	goto_row(e, .Columns)
	press(e, .Right, .Right)
	testing.expect_value(t, current_map(e).width, 4)
}

Colour_Log :: struct {
	colors: [dynamic]cm.Color,
	rects:  [dynamic]Rect,
}

colour_renderer :: proc(l: ^Colour_Log) -> cm.Renderer {
	return cm.Renderer {
		data = l,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^Colour_Log)(d)
			append(&k.colors, c)
			append(&k.rects, Rect{x, y, w, h})
		},
		present = proc(d: rawptr) {},
	}
}

@(test)
test_characters_are_drawn_over_the_terrain_in_both_layers :: proc(t: ^testing.T) {
	log: Colour_Log
	defer delete(log.colors)
	defer delete(log.rects)
	r := colour_renderer(&log)
	e, world := char_editor()
	defer free_both(e, world)
	world.palette[7] = {200, 1, 2} // a colour only the creatures' tile uses
	for i in 0 ..< world.tilesets[0].count {
		cm.image4_set(&world.tilesets[0].images[i], 0, 0, 7)
	}
	cell := cell_rect(e, 1, 0)
	for layer in Layer {
		e.layer = layer
		clear(&log.colors)
		clear(&log.rects)
		editor_draw(e, &r)
		inside := 0
		for rc, i in log.rects {
			if rc.x >= cell.x && rc.y >= cell.y && rc.x + rc.w <= cell.x + cell.w + 1 && rc.y + rc.h <= cell.y + cell.h + 1 && log.colors[i] == (cm.Color{200, 1, 2}) {
				inside += 1
			}
		}
		testing.expectf(t, inside > 0, "%v: Goo's sprite is not on its cell", layer)
	}
	// The player is marked in the cell's corner (cells here are 23 pixels).
	world.player = world.characters[0].uuid
	clear(&log.colors)
	clear(&log.rects)
	editor_draw(e, &r)
	marked := false
	for rc, i in log.rects {
		marked ||= rc.x == cell.x && rc.y == cell.y && log.colors[i] == HILITE && rc.w < cell.w
	}
	testing.expect(t, marked)
}

@(test)
test_the_characters_layer_text_is_in_the_font_and_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := char_editor()
	defer free_both(e, world)
	m := cm.default_input_map()
	editor_set_labels(e, &m)
	for round in 0 ..< 2 {
		if round == 1 {
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for mode in ([]Mode{.Draw, .Setup, .Tags}) {
			for confirm in 0 ..< 2 {
				e.mode = mode
				e.confirm_delete = confirm == 1
				text := banner_text(e)
				if round == 0 {
					testing.expectf(t, cm.text_is_drawable(text), "banner: %s", text)
				}
				testing.expectf(t, cm.text_width(text) + 8 <= BANNER.w, "banner too wide: %s", text)
			}
			lines, n := help_lines(e)
			for line in lines[:n] {
				if round == 0 {
					testing.expectf(t, cm.text_is_drawable(line), "help: %s", line)
				}
				testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
			}
		}
	}
	for note in ([]string{NOTE_NO_CHARACTERS, NOTE_NEED_TYPE, NOTE_CELL_TAKEN, NOTE_CELL_FEATURE, NOTE_NOT_PLACED, NOTE_CHAR_FULL, NOTE_NAME_EMPTY, NOTE_NAME_BAD, "2048 THINGS IN THE WAY"}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 2, "note: %s", note)
	}
	for word in ([]string{"CHAR", "TYPE", "PLAYER", "PLACE", "NEW", "UNPLACE", "DEL", "RENAME", "LAYER", "NONE", "YES", "NO", "OFF MAP", "AT 63,63"}) {
		testing.expect(t, cm.text_is_drawable(word))
	}
	for b in char_buttons() {
		testing.expectf(t, cm.text_width(b.txt) <= b.rc.w - 2 && cm.text_is_drawable(b.txt), "label %s", b.txt)
	}
	// The layout of the Characters layer's buttons clears the picker and each other.
	rects := make([dynamic]Rect, context.temp_allocator)
	for b in char_buttons() {
		append(&rects, b.rc)
	}
	append(&rects, Rect{PICKER_X, PICKER_Y, PICKER_COLS * PICKER_PITCH - 1, PICKER_ROWS * PICKER_PITCH - 1})
	for a, i in rects {
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	testing.expect(t, ROW_VALUE_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W) // the CHAR row is cut to VALUE_CHARS
	testing.expect(t, LAYER_BUTTON.x + LAYER_BUTTON.w <= cm.SCREEN_W && LAYER_BUTTON.y + LAYER_BUTTON.h <= HELP_Y)
}

@(test)
test_the_busiest_map_draws_on_screen_at_every_zoom_in_both_layers :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	e, world := char_editor(64, 64)
	defer free_both(e, world)
	for world.character_count < cm.WORLD_MAX_CHARACTERS {
		cm.world_add_character(world, world.character_count % 2)
	}
	for k in 0 ..< 1024 {
		cm.world_place_character(world, 0, k % 64, k / 64, world.characters[k].uuid)
	}
	world.player = world.characters[100].uuid
	for layer in Layer {
		for zoom in 0 ..< 8 {
			e.layer = layer
			e.zoom = zoom
			for pos in ([][2]int{{0, 0}, {63, 63}}) {
				e.cx, e.cy = pos.x, pos.y
				press(e, .Left, .Right)
				for mode in ([]Mode{.Draw, .Setup}) {
					e.mode = mode
					log = {}
					editor_draw(e, &r)
					testing.expectf(t, log.out_of_bounds == 0, "%v zoom %d %v: %d rects off screen", layer, zoom, mode, log.out_of_bounds)
					testing.expectf(t, log.rects < 60000, "%v zoom %d: %d rects", layer, zoom, log.rects)
				}
			}
		}
	}
	// The keypad screen draws too.
	e.layer = .Characters
	e.mode = .Setup
	e.row = .Char_Rename
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Text)
	log = {}
	editor_draw(e, &r)
	testing.expect(t, log.out_of_bounds == 0 && log.presents == 1)
}

@(test)
test_a_cells_tags_inherit_its_terrain_then_set_then_clear :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	cm.world_add_tag(world, "water")
	cm.world_toggle_terrain_tag(world, 0, 0, TAG_WATER) // the default terrain 0 is "water"
	e.cx, e.cy = 2, 1
	run(e, .Tags)
	testing.expect_value(t, e.mode, Mode.Tags)
	testing.expect_value(t, cm.tag_names_text(world, tag_view(e)), "WATER") // inherited from its terrain
	testing.expect_value(t, cm.tag_source_text(tag_view(e), TAG_WATER), "TYPE ON")
	press(e, .Down, .Green) // water: inherit -> set
	press(e, .Green) // -> cleared: this one cell is dry
	testing.expect(t, e.dirty && !cm.world_cell_has_tag(world, 0, 2, 1, TAG_WATER) && cm.world_cell_has_tag(world, 0, 3, 1, TAG_WATER))
	testing.expect_value(t, world.maps[0].cell_tags[1][2], cm.Cell_Tags{cleared = cm.tag_bit(TAG_WATER)})
	press(e, .Up, .Green) // solid on for this cell only
	testing.expect(t, cm.world_cell_has_tag(world, 0, 2, 1, cm.TAG_SOLID) && !cm.world_cell_has_tag(world, 0, 3, 1, cm.TAG_SOLID))
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Setup)
	// Painting the terrain does not touch a cell's own tags; the cursor's cell decides which is shown.
	e.mode = .Draw
	e.terrain = 1
	press(e, .Green)
	testing.expect(t, cm.world_cell_has_tag(world, 0, 2, 1, cm.TAG_SOLID))
	press(e, .Left)
	click_rect(e, TAGS_BUTTON)
	testing.expect_value(t, e.mode, Mode.Tags)
	testing.expect_value(t, cm.tag_names_text(world, tag_view(e)), "WATER") // the cell to its left
	rc := cm.tag_list_rect(1)
	click_at(e, rc.x + 5, rc.y + 3)
	testing.expect_value(t, world.maps[0].cell_tags[1][1].set, cm.tag_bit(TAG_WATER))
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.Setup)
}

TAG_WATER :: 1

@(test)
test_a_characters_tags_are_edited_from_the_map_too :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := char_editor()
	defer free_both(e, world)
	cm.world_add_tag(world, "water")
	cm.world_toggle_char_type_tag(world, 0, TAG_WATER) // slimes are "water"
	e.cur_char = 0
	run(e, .Tags)
	testing.expect_value(t, e.mode, Mode.Tags)
	testing.expect_value(t, cm.tag_source_text(tag_view(e), TAG_WATER), "TYPE ON")
	press(e, .Down, .Green, .Green) // inherit -> set -> cleared
	testing.expect(t, !cm.world_character_has_tag(world, 0, TAG_WATER) && e.dirty)
	testing.expect_value(t, world.characters[0].tags_cleared, cm.tag_bit(TAG_WATER))
	// Cells are not touched by character tags.
	testing.expect_value(t, world.maps[0].cell_tags[0][1], cm.Cell_Tags{})
	press(e, .Red)
	click_rect(e, TAGS_BUTTON)
	testing.expect_value(t, e.mode, Mode.Tags)
	click_rect(e, BACK_BUTTON)
	// With no characters the Characters layer has nothing to tag; the Terrain layer still does.
	world.character_count = 0
	e.mode = .Setup
	e.row = .Tags
	press(e, .Green)
	testing.expect(t, e.mode == .Setup && e.note == NOTE_NO_CHARACTERS)
	toggle_layer(e) // features (none yet)
	toggle_layer(e) // items
	toggle_layer(e) // terrain
	e.mode = .Setup
	e.row = .Tags
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Tags)
	// A busy world's many tags scroll.
	for world.tag_count < 40 {
		cm.world_add_tag(world)
	}
	for _ in 0 ..< 50 {
		press(e, .Down)
	}
	testing.expect(t, e.tags.sel == 39 && e.tags.scroll == 40 - cm.TAG_LIST_ROWS)
}

@(test)
test_the_tags_screen_draws_on_screen_for_both_layers :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	e, world := char_editor()
	defer free_both(e, world)
	for world.tag_count < cm.WORLD_MAX_TAGS {
		cm.world_add_tag(world, "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
	}
	cm.world_add_feature(world, cm.world_add_feature_type(world, "tree")) // the Features layer needs one to tag
	for layer in Layer {
		if layer == .Items {
			continue // (an inventory has no tags of its own)
		}
		e.layer = layer
		e.mode = .Setup
		e.row = .Tags
		press(e, .Green)
		testing.expect_value(t, e.mode, Mode.Tags)
		for sel in ([]int{0, 30, 63}) {
			e.tags.sel = sel
			cm.tag_list_fix(&e.tags, world.tag_count)
			log = {}
			editor_draw(e, &r)
			testing.expectf(t, log.out_of_bounds == 0, "%v: %d rects off screen", layer, log.out_of_bounds)
			testing.expect_value(t, log.presents, 1)
		}
		press(e, .Red)
	}
}
