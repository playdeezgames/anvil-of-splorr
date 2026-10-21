#+build !js
package character_editor

import cm "../common"
import "core:strings"
import "core:testing"

// A world with a sprite ("slime" and "bat" in set "creatures"), character types "slime" and "bat",
// a map "m" (3 x 2) and characters Goo (slime, at 1,0 of m), Flap (bat, off the map), Pip (slime, off
// the map). Goo is not the player.
make_world :: proc() -> ^cm.World {
	w := new(cm.World)
	cm.world_reset(w)
	cm.world_seed_uuids(w, 9)
	cm.world_set_tile_size(w, 4, 4)
	a := cm.world_add_tileset(w, "a")
	cm.tileset_insert_blank(&w.tilesets[a], 0, "a0")
	ts := cm.world_add_terrain_set(w, "land")
	cm.name_assign(&w.sets[ts].terrains[0].name, "grass")
	creatures := cm.world_add_sprite_set(w, "creatures")
	for name in ([]string{"slime", "bat"}) {
		n := cm.world_add_sprite(w, creatures)
		cm.name_assign(&w.sprite_sets[creatures].sprites[n].name, name)
	}
	slime := cm.world_add_char_type(w, "slime")
	bat := cm.world_add_char_type(w, "bat")
	cm.name_assign(&w.char_types[bat].sprite, "bat")
	for spec in ([][2]string{{"Goo", "slime"}, {"Flap", "bat"}, {"Pip", "slime"}}) {
		n := cm.world_add_character(w, spec[1] == "bat" ? bat : slime)
		cm.name_assign(&w.characters[n].name, spec[0])
	}
	m := cm.world_add_map(w, ts, "m")
	cm.world_map_set_size(w, m, 3, 2)
	cm.world_place_character(w, m, 1, 0, w.characters[0].uuid)
	return w
}

new_editor :: proc() -> (e: ^Editor, world: ^cm.World) {
	world = make_world()
	e = new(Editor)
	editor_begin(e, world)
	return
}

// A world with types but no characters.
empty_editor :: proc() -> (e: ^Editor, world: ^cm.World) {
	world = make_world()
	world.character_count = 0
	e = new(Editor)
	editor_begin(e, world)
	return
}

free_both :: proc(e: ^Editor, world: ^cm.World) {
	free(e)
	free(world)
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

goto_row :: proc(e: ^Editor, row: Setup_Row) {
	e.mode = .Setup
	for e.row != row {
		press(e, .Down)
	}
}

run :: proc(e: ^Editor, row: Setup_Row) {
	goto_row(e, row)
	press(e, .Green)
}

type_with_commands :: proc(e: ^Editor, text: string) {
	for i in 0 ..< len(text) {
		ch := text[i]
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
}

press_keypad_action :: proc(e: ^Editor, a: cm.Text_Entry_Action) {
	for e.entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(e.entry.col) != a {
		press(e, .Right)
	}
	press(e, .Green)
}

name_typed :: proc(e: ^Editor, name: string) {
	press_keypad_action(e, .Clear)
	type_with_commands(e, name)
	press_keypad_action(e, .Done)
}

@(test)
test_the_list_starts_on_the_first_character :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	testing.expect(t, e.mode == .List && e.sel == 0 && !e.dirty && !e.exit_requested)
	press(e, .Up)
	testing.expect_value(t, e.sel, 0)
	press(e, .Down, .Down, .Down, .Down)
	testing.expect_value(t, e.sel, 2)
	press(e, .Red)
	testing.expect(t, e.exit_requested)
}

@(test)
test_an_empty_table_says_so_instead_of_doing_things :: proc(t: ^testing.T) {
	e, world := empty_editor()
	defer free_both(e, world)
	press(e, .Green, .Up, .Down)
	testing.expect(t, e.mode == .List && e.note == "" || e.note == NOTE_NO_CHARACTERS)
	for row in ([]Setup_Row{.Rename, .Duplicate, .Delete, .Player, .Unplace}) {
		e.note = ""
		e.mode = .List
		run(e, row)
		testing.expectf(t, e.note == NOTE_NO_CHARACTERS && !e.dirty, "%v with no characters", row)
	}
	e.note = ""
	goto_row(e, .Type)
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NO_CHARACTERS)
}

@(test)
test_new_needs_a_type_and_names_the_character_straight_away :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	e.sel = 1 // Flap, a bat: the new character gets that type
	run(e, .New)
	testing.expect(t, e.mode == .Text && world.character_count == 4 && e.sel == 3)
	testing.expect(t, cm.name_str(&current(e).type) == "bat" && character_name(e, 3) == "character" && e.dirty)
	name_typed(e, "Zed")
	testing.expect(t, e.mode == .Setup && character_name(e, 3) == "Zed")
	testing.expect(t, !cm.uuid_is_none(current(e).uuid))
	testing.expect_value(t, place_text(e, 3), "OFF MAP")
	// Names are labels: a name already used is fine; empty is not.
	run(e, .Rename)
	name_typed(e, "Goo")
	testing.expect(t, e.mode == .Setup && character_name(e, 3) == "Goo")
	run(e, .Rename)
	name_typed(e, "")
	testing.expect_value(t, e.mode, Mode.Text)
	press_keypad_action(e, .Cancel)
	// In a world with no types there is nothing to be.
	e2, w2 := new_editor()
	defer free_both(e2, w2)
	w2.character_count = 0
	w2.char_type_count = 0
	run(e2, .New)
	testing.expect(t, e2.note == NOTE_NEED_TYPE && e2.mode == .Setup && w2.character_count == 0)
	// An empty table with types: the first type.
	e3, w3 := empty_editor()
	defer free_both(e3, w3)
	run(e3, .New)
	press_keypad_action(e3, .Done)
	testing.expect(t, w3.character_count == 1 && cm.name_str(&w3.characters[0].type) == "slime")
}

@(test)
test_green_in_the_list_renames :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed(e, "Gloop")
	testing.expect(t, e.mode == .List && character_name(e, 0) == "Gloop" && e.dirty)
	press(e, .Green)
	press_keypad_action(e, .Cancel)
	testing.expect(t, e.mode == .List && character_name(e, 0) == "Gloop")
}

@(test)
test_duplicate_makes_a_new_uuid_off_the_map :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Duplicate)
	testing.expect(t, e.mode == .Text && world.character_count == 4 && character_name(e, 3) == "Goo_copy")
	testing.expect(t, world.characters[3].uuid != world.characters[0].uuid && place_text(e, 3) == "OFF MAP" && place_text(e, 0) == "AT 1,0")
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Setup && e.sel == 3)
}

@(test)
test_the_type_steps_through_the_worlds_types :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	goto_row(e, .Type)
	press(e, .Right)
	testing.expect(t, cm.name_str(&current(e).type) == "bat" && e.dirty)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&current(e).type), "slime") // wraps
	press(e, .Left)
	testing.expect_value(t, cm.name_str(&current(e).type), "bat")
	click_rect(e, TYPE_PLUS)
	testing.expect_value(t, cm.name_str(&current(e).type), "slime")
	click_rect(e, TYPE_MINUS)
	testing.expect_value(t, cm.name_str(&current(e).type), "bat")
	world.char_type_count = 0
	e.note = ""
	press(e, .Right)
	// With the types gone the character's type name has nothing to step to.
	testing.expect_value(t, e.note, NOTE_NEED_TYPE)
}

@(test)
test_player_toggles_and_unplace_takes_a_character_off_its_map :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Player)
	testing.expect(t, world.player == world.characters[0].uuid && is_player(e, 0) && e.dirty)
	e.sel = 1
	run(e, .Player) // moves the role to Flap
	testing.expect(t, world.player == world.characters[1].uuid && !is_player(e, 0))
	run(e, .Player) // again: nobody
	testing.expect(t, cm.uuid_is_none(world.player))
	// Unplace.
	e.sel = 0
	e.dirty = false
	run(e, .Unplace)
	testing.expect(t, e.dirty && place_text(e, 0) == "OFF MAP" && cm.world_character_at(world, 0, 1, 0) == -1)
	e.note = ""
	run(e, .Unplace)
	testing.expect_value(t, e.note, NOTE_NOT_PLACED)
}

@(test)
test_delete_takes_a_character_off_the_map_and_clears_the_player :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Player)
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && world.character_count == 3)
	press(e, .Up) // anything else cancels
	testing.expect(t, !e.confirm_delete)
	e.row = .Delete
	press(e, .Green, .Green)
	testing.expect(t, world.character_count == 2 && cm.uuid_is_none(world.player) && cm.world_character_at(world, 0, 1, 0) == -1 && e.dirty)
	testing.expect_value(t, character_name(e, 0), "Flap")
	for _ in 0 ..< 2 {
		run(e, .Delete)
		press(e, .Green)
	}
	testing.expect_value(t, world.character_count, 0)
}

@(test)
test_full_table_refuses_more :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	for world.character_count < cm.WORLD_MAX_CHARACTERS {
		cm.world_add_character(world, 0)
	}
	run(e, .New)
	testing.expect(t, e.note == NOTE_FULL && e.mode == .Setup)
	run(e, .Duplicate)
	testing.expect_value(t, e.note, NOTE_FULL)
}

@(test)
test_the_list_scrolls_with_the_selection_and_the_wheel :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	for world.character_count < 100 {
		cm.world_add_character(world, 0)
	}
	for _ in 0 ..< 60 {
		press(e, .Down)
	}
	testing.expect(t, e.sel == 60 && e.scroll == 60 - LIST_ROWS + 1)
	press(e, .Up)
	testing.expect_value(t, e.scroll, 60 - LIST_ROWS + 1)
	for _ in 0 ..< 70 {
		press(e, .Up)
	}
	testing.expect(t, e.sel == 0 && e.scroll == 0)
	editor_handle_event(e, cm.Mouse_Wheel{dy = -3})
	testing.expect_value(t, e.scroll, 3)
	for _ in 0 ..< 100 {
		editor_handle_event(e, cm.Mouse_Wheel{dy = -3})
	}
	testing.expect_value(t, e.scroll, 100 - LIST_ROWS)
	e.scroll = 45
	click_item(e, 50)
	testing.expect_value(t, e.sel, 50)
}

Input_Method :: enum {
	Commands,
	Mouse,
}

@(test)
test_every_function_is_reachable_by_each_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for m in Input_Method {
		e, world := new_editor()
		// Select the third character.
		switch m {
		case .Commands:
			press(e, .Down, .Down)
		case .Mouse:
			click_item(e, 2)
		}
		testing.expectf(t, e.sel == 2, "%v select", m)
		// Type, player, unplace (Goo is the one on the map)
		switch m {
		case .Commands:
			goto_row(e, .Type)
			press(e, .Right)
		case .Mouse:
			click_rect(e, TYPE_PLUS)
		}
		testing.expectf(t, cm.name_str(&current(e).type) == "bat", "%v type", m)
		switch m {
		case .Commands:
			run(e, .Player)
		case .Mouse:
			click_rect(e, PLAYER_BUTTON)
		}
		testing.expectf(t, is_player(e, 2), "%v player", m)
		e.sel = 0
		switch m {
		case .Commands:
			run(e, .Unplace)
		case .Mouse:
			click_rect(e, UNPLACE_BUTTON)
		}
		testing.expectf(t, cm.world_character_at(world, 0, 1, 0) == -1, "%v unplace", m)
		// New, Duplicate (keypad cancelled), Delete, Rename
		switch m {
		case .Commands:
			run(e, .New)
		case .Mouse:
			click_rect(e, NEW_BUTTON)
		}
		press_keypad_action(e, .Cancel)
		testing.expectf(t, world.character_count == 4, "%v new", m)
		switch m {
		case .Commands:
			run(e, .Duplicate)
		case .Mouse:
			click_rect(e, DUPLICATE_BUTTON)
		}
		press_keypad_action(e, .Cancel)
		testing.expectf(t, world.character_count == 5, "%v duplicate", m)
		switch m {
		case .Commands:
			run(e, .Delete)
			press(e, .Green)
		case .Mouse:
			click_rect(e, DELETE_BUTTON)
			click_rect(e, DELETE_BUTTON)
		}
		testing.expectf(t, world.character_count == 4, "%v delete", m)
		switch m {
		case .Commands:
			run(e, .Rename)
		case .Mouse:
			click_rect(e, RENAME_BUTTON)
		}
		testing.expectf(t, e.mode == .Text, "%v rename", m)
		press_keypad_action(e, .Cancel)
		switch m {
		case .Commands:
			e.mode = .List
			press(e, .Red)
		case .Mouse:
			click_rect(e, BACK_BUTTON)
		}
		testing.expectf(t, e.exit_requested, "%v leave", m)
		free_both(e, world)
	}
}

@(test)
test_layout_fits_the_screen_and_does_not_overlap :: proc(t: ^testing.T) {
	rects := make([dynamic]Rect, context.temp_allocator)
	append(&rects, BANNER, Rect{LIST_X, LIST_Y, LIST_W, LIST_ROWS * LIST_PITCH}, PREVIEW_FRAME, TYPE_MINUS, TYPE_PLUS)
	for b in buttons() {
		append(&rects, b.rc)
		testing.expectf(t, cm.text_width(b.text) <= b.rc.w - 2 && cm.GLYPH_H <= b.rc.h && cm.text_is_drawable(b.text), "label %s", b.text)
	}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	// A 32 character name and the place fit one list line; the id, the status and the type fit the panel.
	testing.expect(t, 9 + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") + cm.text_width("AT 63,63") + 6 <= LIST_W)
	testing.expect(t, ID_X + cm.text_width("ID 3F2A9C1E") <= cm.SCREEN_W && STATUS_X + cm.text_width("THE PLAYER") <= cm.SCREEN_W)
	testing.expect(t, PANEL_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W - 2 && PANEL_X + cm.text_width("TYPE") < TYPE_MINUS.x)
	testing.expect(t, LIST_X + LIST_W < PANEL_X && LIST_Y + LIST_ROWS * LIST_PITCH <= HELP_Y)
	testing.expect(t, HELP_Y >= BACK_BUTTON.y + BACK_BUTTON.h && HELP_Y + MAX_HELP_LINES * cm.LINE_ADVANCE <= cm.SCREEN_H)
	testing.expect(t, TYPE_NAME_Y + cm.GLYPH_H <= RENAME_BUTTON.y && PREVIEW_FRAME.y + PREVIEW_FRAME.h <= TYPE_MINUS.y)
}

@(test)
test_list_geometry_round_trips :: proc(t: ^testing.T) {
	for row in 0 ..< LIST_ROWS {
		rc := list_row_rect(row)
		for p in ([][2]int{{0, 0}, {LIST_W - 1, LIST_PITCH - 1}}) {
			got, ok := list_row_at(rc.x + p.x, rc.y + p.y)
			testing.expectf(t, ok && got == row, "row %d", row)
		}
	}
	_, ok := list_row_at(LIST_X - 1, LIST_Y)
	testing.expect(t, !ok)
	_, ok = list_row_at(LIST_X, LIST_Y + LIST_ROWS * LIST_PITCH)
	testing.expect(t, !ok)
}

@(test)
test_all_on_screen_text_is_in_the_font_and_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	m := cm.default_input_map()
	editor_set_labels(e, &m)
	for round in 0 ..< 2 {
		if round == 1 {
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for mode in ([]Mode{.List, .Setup, .Tags}) {
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
	// The longest info line: a long map name at the end of a full table.
	cm.name_assign(&world.maps[0].name, "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
	e.sel = 0
	e.dirty = true
	info := info_text(e)
	testing.expect(t, cm.text_is_drawable(info) && INFO_X + cm.text_width(info) <= cm.SCREEN_W - 4)
	testing.expect(t, cm.text_is_drawable("1024 OF 1024  MAP  *"))
	for note in ([]string{NOTE_NO_CHARACTERS, NOTE_NEED_TYPE, NOTE_FULL, NOTE_NOT_PLACED, NOTE_NAME_EMPTY, NOTE_NAME_BAD, "NO CHARACTERS YET *"}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 2, "note: %s", note)
	}
	for word in ([]string{"OFF MAP", "AT 63,63", "THE PLAYER", "TYPE", "ID 3F2A9C1E"}) {
		testing.expect(t, cm.text_is_drawable(word))
	}
	testing.expect_value(t, upper("3f2a9c1e"), "3F2A9C1E")
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
test_every_screen_draws_on_screen :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	for size in ([]int{1, 16, 64}) {
		e, world := new_editor()
		cm.world_set_tile_size(world, size, size)
		for d in 0 ..< size {
			cm.image4_set(&world.tilesets[0].images[0], d, (d * 3) % size, d % 16)
		}
		for world.character_count < cm.WORLD_MAX_CHARACTERS {
			cm.world_add_character(world, world.character_count % 2)
		}
		world.player = world.characters[500].uuid
		for world.tag_count < cm.WORLD_MAX_TAGS {
			cm.world_add_tag(world, "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
		}
		for mode in ([]Mode{.List, .Setup, .Text, .Tags}) {
			for sel in ([]int{0, 500, 1023}) {
				e.sel = sel
				fix_selection(e)
				e.mode = mode
				if mode == .Text {
					cm.text_entry_begin(&e.entry, "RENAME CHARACTER", character_name(e, e.sel), cm.NAME_MAX)
				}
				log = {}
				editor_draw(e, &r)
				testing.expectf(t, log.out_of_bounds == 0, "%d %v: %d rects off screen", size, mode, log.out_of_bounds)
				testing.expect_value(t, log.presents, 1)
				testing.expectf(t, log.rects < 5000, "%d %v: %d rects is too many", size, mode, log.rects)
			}
		}
		free_both(e, world)
	}
	e, world := empty_editor()
	defer free_both(e, world)
	for mode in ([]Mode{.List, .Setup, .Tags}) {
		e.mode = mode
		log = {}
		editor_draw(e, &r)
		testing.expect_value(t, log.out_of_bounds, 0)
	}
}

@(test)
test_a_characters_tags_inherit_then_set_then_clear :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	cm.world_add_tag(world, "water")
	cm.world_add_tag(world, "hostile")
	cm.world_toggle_char_type_tag(world, 0, 1) // slimes are "water"
	run(e, .Tags) // Goo, a slime
	testing.expect_value(t, e.mode, Mode.Tags)
	testing.expect_value(t, cm.tag_names_text(world, tag_view(e)), "WATER") // from its type
	testing.expect_value(t, cm.tag_source_text(tag_view(e), 1), "TYPE ON")
	press(e, .Down, .Green) // water: inherit -> set
	testing.expect_value(t, cm.tag_source_text(tag_view(e), 1), "OWN ON")
	press(e, .Green) // set -> cleared
	testing.expect_value(t, cm.tag_source_text(tag_view(e), 1), "OWN OFF")
	testing.expect_value(t, cm.tag_names_text(world, tag_view(e)), "NONE")
	testing.expect(t, e.dirty && !cm.world_character_has_tag(world, 0, 1))
	press(e, .Green) // cleared -> inherit again
	testing.expect(t, world.characters[0].tags_set == 0 && world.characters[0].tags_cleared == 0 && cm.world_character_has_tag(world, 0, 1))
	// A tag its type lacks can be set on this character only.
	press(e, .Down, .Green)
	testing.expect(t, cm.world_character_has_tag(world, 0, 2) && !cm.world_character_has_tag(world, 2, 2)) // Pip, another slime
	press(e, .Up, .Up, .Up)
	testing.expect_value(t, e.tags.sel, 0)
	// Solid by its own setting, against a type that lacks it; red goes back.
	press(e, .Green)
	testing.expect(t, cm.world_character_has_tag(world, 0, cm.TAG_SOLID))
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Setup)
	// The mouse: a click cycles a row, BACK leaves; the TAGS button opens the list.
	click_rect(e, TAGS_BUTTON)
	testing.expect_value(t, e.mode, Mode.Tags)
	rc := cm.tag_list_rect(2)
	click_at(e, rc.x + 5, rc.y + 3)
	testing.expect_value(t, cm.tag_source_text(tag_view(e), 2), "OWN OFF")
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.Setup)
	// With no characters there is nothing to tag.
	e2, w2 := empty_editor()
	defer free_both(e2, w2)
	run(e2, .Tags)
	testing.expect(t, e2.mode == .Setup && e2.note == NOTE_NO_CHARACTERS)
	// Many tags scroll in the list.
	for world.tag_count < 40 {
		cm.world_add_tag(world)
	}
	e.mode = .Tags
	for _ in 0 ..< 50 {
		press(e, .Down)
	}
	testing.expect(t, e.tags.sel == 39 && e.tags.scroll == 40 - cm.TAG_LIST_ROWS)
	editor_handle_event(e, cm.Mouse_Wheel{dy = 100})
	testing.expect_value(t, e.tags.scroll, 0)
}
