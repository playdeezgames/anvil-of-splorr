#+build !js
package character_type_editor

import cm "../common"
import "core:strings"
import "core:testing"

// A world (tile size 4) with tileset "a" (images a0 a1 a2), terrain set "land" (grass, rock),
// sprite sets "creatures" (slime, bat), "items" (sword) and "empty" (no sprites), character types
// "slime" (creatures/slime) and "bat" (creatures/bat), and one character, Goo, of type slime.
make_world :: proc() -> ^cm.World {
	w := new(cm.World)
	cm.world_reset(w)
	cm.world_seed_uuids(w, 5)
	cm.world_set_tile_size(w, 4, 4)
	a := cm.world_add_tileset(w, "a")
	for k in 0 ..< 3 {
		n := cm.tileset_insert_blank(&w.tilesets[a], k, "a0")
		cm.image4_set(&w.tilesets[a].images[n], k, 0, k + 1)
	}
	ts := cm.world_add_terrain_set(w, "land")
	cm.name_assign(&w.sets[ts].terrains[0].name, "grass")
	rock := cm.world_add_terrain(w, ts)
	cm.name_assign(&w.sets[ts].terrains[rock].name, "rock")
	cm.name_assign(&w.sets[ts].terrains[rock].image, "a0_2")
	creatures := cm.world_add_sprite_set(w, "creatures")
	for name in ([]string{"slime", "bat"}) {
		n := cm.world_add_sprite(w, creatures)
		cm.name_assign(&w.sprite_sets[creatures].sprites[n].name, name)
	}
	cm.name_assign(&w.sprite_sets[creatures].sprites[1].image, "a0_2")
	items := cm.world_add_sprite_set(w, "items")
	sword := cm.world_add_sprite(w, items)
	cm.name_assign(&w.sprite_sets[items].sprites[sword].name, "sword")
	cm.world_add_sprite_set(w, "empty")
	slime := cm.world_add_char_type(w, "slime")
	bat := cm.world_add_char_type(w, "bat")
	cm.name_assign(&w.char_types[bat].sprite, "bat")
	goo := cm.world_add_character(w, slime)
	cm.name_assign(&w.characters[goo].name, "Goo")
	_ = bat
	return w
}

new_editor :: proc() -> (e: ^Editor, world: ^cm.World) {
	world = make_world()
	e = new(Editor)
	editor_begin(e, world)
	return
}

// An editor on a world that has sprites but no character types.
empty_editor :: proc() -> (e: ^Editor, world: ^cm.World) {
	world = make_world()
	world.character_count = 0
	world.char_type_count = 0
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

click_thumb :: proc(e: ^Editor, index: int) {
	rc := grid_cell_rect(index % GRID_COLS, index / GRID_COLS - e.scroll)
	click_at(e, rc.x + rc.w / 2, rc.y + rc.h / 2)
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
test_begin_starts_in_pick_with_the_checkerboard :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	testing.expect(t, e.mode == .Pick && e.sel == 0 && !e.dirty && !e.exit_requested && e.bg_set == NO_BG && backdrop(e) == nil)
	testing.expect_value(t, type_name(e, 1), "bat")
	press(e, .Left, .Up, .Right, .Right, .Down)
	testing.expect_value(t, e.sel, 1) // two types: the ends stop it
	press(e, .Red)
	testing.expect(t, e.exit_requested)
}

@(test)
test_an_empty_world_list_says_so_instead_of_doing_things :: proc(t: ^testing.T) {
	e, world := empty_editor()
	defer free_both(e, world)
	press(e, .Green, .Left, .Right, .Up, .Down)
	testing.expect(t, e.mode == .Pick && e.sel == 0)
	for row in ([]Setup_Row{.Rename, .Duplicate, .Delete, .Set, .Sprite, .Choose}) {
		e.note = ""
		if row == .Set || row == .Sprite {
			goto_row(e, row)
			press(e, .Right)
		} else {
			run(e, row)
		}
		testing.expectf(t, e.note == NOTE_NO_TYPES && !e.dirty && world.char_type_count == 0, "%v with no types", row)
	}
}

@(test)
test_the_sprite_set_and_sprite_choices :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	ct := current_type(e)
	goto_row(e, .Set)
	press(e, .Right) // creatures -> items (the empty set is skipped)
	testing.expect(t, cm.name_str(&ct.sprite_set) == "items" && cm.name_str(&ct.sprite) == "sword" && e.dirty)
	press(e, .Right) // items -> not set
	testing.expect(t, cm.name_str(&ct.sprite_set) == "" && cm.name_str(&ct.sprite) == "")
	press(e, .Right)
	testing.expect(t, cm.name_str(&ct.sprite_set) == "creatures" && cm.name_str(&ct.sprite) == "slime")
	press(e, .Left)
	testing.expect_value(t, cm.name_str(&ct.sprite_set), "")
	press(e, .Left, .Left)
	testing.expect_value(t, cm.name_str(&ct.sprite_set), "creatures")
	goto_row(e, .Sprite)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&ct.sprite), "bat")
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&ct.sprite), "slime")
	press(e, .Left)
	testing.expect_value(t, cm.name_str(&ct.sprite), "bat")
	// An unset type must get a set first.
	ct.sprite_set, ct.sprite = {}, {}
	e.note = ""
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NO_SET)
	run(e, .Choose)
	testing.expect(t, e.mode == .Setup && e.note == NOTE_NO_SET)
	// With no sprites anywhere there is nothing to choose.
	for i in 0 ..< world.sprite_set_count {
		world.sprite_sets[i].count = 0
	}
	goto_row(e, .Set)
	e.note = ""
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NO_SPRITES)
}

@(test)
test_the_sprite_grid_chooses_by_commands_and_by_mouse :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Choose)
	testing.expect(t, e.mode == .Sprite && e.pick_sel == 0)
	press(e, .Right, .Right, .Right)
	testing.expect_value(t, e.pick_sel, 1) // two sprites: stops at the last
	press(e, .Red)
	testing.expect(t, e.mode == .Setup && cm.name_str(&current_type(e).sprite) == "slime" && !e.dirty)
	run(e, .Choose)
	press(e, .Right, .Green)
	testing.expect(t, e.mode == .Setup && cm.name_str(&current_type(e).sprite) == "bat" && e.dirty)
	e.mode = .Pick
	click_thumb(e, 0)
	testing.expect_value(t, e.mode, Mode.Sprite)
	click_thumb(e, 0)
	testing.expect(t, e.mode == .Pick && cm.name_str(&current_type(e).sprite) == "slime")
	click_thumb(e, 0)
	click_thumb(e, 5) // an empty slot does nothing
	testing.expect_value(t, e.mode, Mode.Sprite)
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.Pick)
	current_type(e).sprite_set, current_type(e).sprite = {}, {}
	press(e, .Green)
	testing.expect(t, e.mode == .Setup && e.row == .Set && cm.name_str(&current_type(e).sprite_set) == "creatures")
}

@(test)
test_new_and_duplicate_name_the_type_straight_away :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .New)
	testing.expect(t, e.mode == .Text && world.char_type_count == 3 && e.sel == 2)
	ct := current_type(e)
	testing.expect(t, cm.name_str(&ct.name) == "character_type" && cm.name_str(&ct.sprite_set) == "creatures" && cm.name_str(&ct.sprite) == "slime")
	name_typed(e, "ogre")
	testing.expect(t, e.mode == .Setup && type_name(e, 2) == "ogre" && e.dirty)
	run(e, .Duplicate)
	testing.expect_value(t, type_name(e, 3), "ogre_copy")
	name_typed(e, "slime") // taken
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed(e, "")
	testing.expect_value(t, e.mode, Mode.Text)
	press_keypad_action(e, .Cancel)
	testing.expect(t, e.mode == .Setup && type_name(e, 3) == "ogre_copy")
	// A first type in an empty list.
	e2, w2 := empty_editor()
	defer free_both(e2, w2)
	run(e2, .New)
	press_keypad_action(e2, .Done)
	testing.expect(t, e2.mode == .Setup && w2.char_type_count == 1 && type_name(e2, 0) == "character_type")
}

@(test)
test_renaming_a_type_renames_it_for_its_characters :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Rename)
	name_typed(e, "bat")
	testing.expect(t, e.mode == .Text && strings.contains(e.entry.note, "USE"))
	name_typed(e, "goop")
	testing.expect(t, e.mode == .Setup && type_name(e, 0) == "goop" && e.dirty)
	testing.expect_value(t, cm.name_str(&world.characters[0].type), "goop")
	e.dirty = false
	run(e, .Rename)
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Setup && !e.dirty)
}

@(test)
test_delete_needs_a_second_press_and_a_type_without_characters :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Delete) // slime: Goo has it
	testing.expect(t, e.note == "USED BY 1 CHARACTER" && !e.confirm_delete && world.char_type_count == 2)
	e.sel = 1 // bat: free
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && world.char_type_count == 2)
	press(e, .Up) // anything else cancels
	testing.expect(t, !e.confirm_delete)
	e.row = .Delete
	press(e, .Green, .Green)
	testing.expect(t, world.char_type_count == 1 && e.sel == 0 && e.dirty)
	world.character_count = 0
	run(e, .Delete)
	press(e, .Green)
	testing.expect_value(t, world.char_type_count, 0)
	run(e, .Delete)
	testing.expect_value(t, e.note, NOTE_NO_TYPES)
}

@(test)
test_full_world_refuses_more_types :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	for world.char_type_count < cm.WORLD_MAX_CHARACTER_TYPES {
		cm.world_add_char_type(world)
	}
	run(e, .New)
	testing.expect(t, e.note == NOTE_FULL && e.mode == .Setup)
	run(e, .Duplicate)
	testing.expect_value(t, e.note, NOTE_FULL)
}

@(test)
test_the_backdrop_is_a_terrain_chosen_by_set_and_tile :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	goto_row(e, .Bg_Terrain)
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NO_BG_SET)
	goto_row(e, .Bg_Set)
	press(e, .Right)
	testing.expect(t, e.bg_set == 0 && backdrop(e) != nil && cm.name_str(&backdrop(e).name) == "grass" && !e.dirty)
	goto_row(e, .Bg_Terrain)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&backdrop(e).name), "rock")
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&backdrop(e).name), "grass")
	goto_row(e, .Bg_Set)
	press(e, .Right)
	testing.expect(t, e.bg_set == NO_BG && backdrop(e) == nil)
	click_rect(e, BG_SET_PLUS)
	click_rect(e, BG_TERRAIN_PLUS)
	testing.expect_value(t, e.bg_terrain, 1)
	cm.world_delete_terrain_set(world, 0)
	testing.expect(t, backdrop(e) == nil)
}

Colour_Log :: struct {
	colors: [dynamic]cm.Color,
}

colour_renderer :: proc(l: ^Colour_Log) -> cm.Renderer {
	return cm.Renderer {
		data = l,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {append(&(^Colour_Log)(d).colors, c)},
		present = proc(d: rawptr) {},
	}
}

@(test)
test_a_type_is_drawn_without_its_sprites_transparent_colour :: proc(t: ^testing.T) {
	log: Colour_Log
	defer delete(log.colors)
	r := colour_renderer(&log)
	e, world := new_editor()
	defer free_both(e, world)
	world.palette[0] = {1, 2, 3} // the slime sprite makes colour 0 transparent
	area := Rect{0, 0, 16, 16}
	draw_type(e, &r, area, &world.char_types[0])
	for c in log.colors {
		testing.expect(t, c != cm.Color{1, 2, 3})
	}
	testing.expect(t, len(log.colors) > 2)
	// Over a terrain backdrop the checkerboard is not used.
	clear(&log.colors)
	e.bg_set, e.bg_terrain = 0, 1
	draw_type(e, &r, area, &world.char_types[0])
	for c in log.colors {
		testing.expect(t, c != CHECK_A && c != CHECK_B)
	}
	// A type with no sprite is a dark red block.
	clear(&log.colors)
	world.char_types[0].sprite_set, world.char_types[0].sprite = {}, {}
	draw_type(e, &r, area, &world.char_types[0])
	testing.expect_value(t, log.colors[len(log.colors) - 1], UNSET)
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
		world.character_count = 0 // so the types can be deleted
		// Set and sprite
		switch m {
		case .Commands:
			goto_row(e, .Set)
			press(e, .Right)
		case .Mouse:
			click_rect(e, SET_PLUS)
		}
		testing.expectf(t, cm.name_str(&world.char_types[0].sprite_set) == "items", "%v set", m)
		switch m {
		case .Commands:
			press(e, .Left)
			goto_row(e, .Sprite)
			press(e, .Right)
		case .Mouse:
			click_rect(e, SET_MINUS)
			click_rect(e, SPRITE_PLUS)
		}
		testing.expectf(t, cm.name_str(&world.char_types[0].sprite) == "bat", "%v sprite", m)
		// Backdrop
		switch m {
		case .Commands:
			goto_row(e, .Bg_Set)
			press(e, .Right)
			goto_row(e, .Bg_Terrain)
			press(e, .Right)
		case .Mouse:
			click_rect(e, BG_SET_PLUS)
			click_rect(e, BG_TERRAIN_PLUS)
		}
		testing.expectf(t, e.bg_set == 0 && e.bg_terrain == 1, "%v backdrop", m)
		// New, Duplicate, Delete, Rename, Choose, Back
		switch m {
		case .Commands:
			run(e, .New)
		case .Mouse:
			click_rect(e, NEW_BUTTON)
		}
		press_keypad_action(e, .Cancel)
		testing.expectf(t, world.char_type_count == 3, "%v new", m)
		switch m {
		case .Commands:
			run(e, .Duplicate)
		case .Mouse:
			click_rect(e, DUPLICATE_BUTTON)
		}
		press_keypad_action(e, .Cancel)
		testing.expectf(t, world.char_type_count == 4, "%v duplicate", m)
		switch m {
		case .Commands:
			run(e, .Delete)
			press(e, .Green)
		case .Mouse:
			click_rect(e, DELETE_BUTTON)
			click_rect(e, DELETE_BUTTON)
		}
		testing.expectf(t, world.char_type_count == 3, "%v delete", m)
		switch m {
		case .Commands:
			run(e, .Rename)
		case .Mouse:
			click_rect(e, RENAME_BUTTON)
		}
		testing.expectf(t, e.mode == .Text, "%v rename", m)
		press_keypad_action(e, .Cancel)
		e.sel = 0
		switch m {
		case .Commands:
			run(e, .Choose)
		case .Mouse:
			click_rect(e, PICK_BUTTON)
		}
		testing.expectf(t, e.mode == .Sprite, "%v choose", m)
		press(e, .Red)
		switch m {
		case .Commands:
			e.mode = .Pick
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
	append(&rects, Rect{GRID_X - 1, GRID_Y - 1, GRID_COLS * GRID_PITCH + 1, GRID_ROWS * GRID_PITCH + 1}, BANNER)
	append(&rects, SET_MINUS, SET_PLUS, SPRITE_MINUS, SPRITE_PLUS, BG_SET_MINUS, BG_SET_PLUS, BG_TERRAIN_MINUS, BG_TERRAIN_PLUS, PREVIEW_FRAME)
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
	testing.expect(t, ROW_LABEL_X + cm.text_width("SPRITE") < SPRITE_MINUS.x && ROW_LABEL_X + cm.text_width("BG TILE") < BG_TERRAIN_MINUS.x)
	testing.expect(t, ROW_VALUE_X > SET_PLUS.x + SET_PLUS.w && ROW_VALUE_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W - 2)
	testing.expect(t, INFO_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W)
	testing.expect(t, INFO_X + 90 + cm.text_width("1024 CHARACTERS") <= cm.SCREEN_W && USES_Y > BG_TERRAIN_MINUS.y + BG_TERRAIN_MINUS.h && USES_Y + cm.GLYPH_H <= PREVIEW_FRAME.y)
	testing.expect(t, HELP_Y >= BACK_BUTTON.y + BACK_BUTTON.h && HELP_Y + MAX_HELP_LINES * cm.LINE_ADVANCE <= cm.SCREEN_H)
}

@(test)
test_grid_geometry_round_trips :: proc(t: ^testing.T) {
	for row in 0 ..< GRID_ROWS {
		for col in 0 ..< GRID_COLS {
			rc := grid_cell_rect(col, row)
			for p in ([][2]int{{0, 0}, {THUMB - 1, THUMB - 1}, {THUMB, THUMB}}) {
				c, r, ok := grid_cell_at(rc.x + p.x, rc.y + p.y)
				testing.expectf(t, ok && c == col && r == row, "cell (%d,%d)", col, row)
			}
		}
	}
	_, _, ok := grid_cell_at(GRID_X - 1, GRID_Y)
	testing.expect(t, !ok)
	testing.expect_value(t, grid_total_rows(0), 0)
	testing.expect_value(t, grid_total_rows(64), 8)
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
		for mode in ([]Mode{.Pick, .Setup, .Sprite, .Tags}) {
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
	for note in ([]string{NOTE_NO_TYPES, NOTE_FULL, NOTE_NO_SET, NOTE_NO_SPRITES, NOTE_NO_BG_SET, NOTE_NAME_EMPTY, NOTE_NAME_USED, NOTE_NAME_BAD, "USED BY 1024 CHARACTERS", "TYPE 64 OF 64 *", "NO TYPES YET *"}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 2, "note: %s", note)
	}
	for word in ([]string{"NOT SET", "NONE", "SET", "BG SET", "BG TILE", "-", "NO CHARACTERS", "1 CHARACTER"}) {
		testing.expect(t, cm.text_is_drawable(word))
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
test_every_screen_draws_on_screen :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	for size in ([]int{1, 16, 64}) {
		for backdrop_on in ([]bool{false, true}) {
			e, world := new_editor()
			cm.world_set_tile_size(world, size, size)
			for k in 0 ..< 3 {
				for i in 0 ..< world.tilesets[0].count {
					for d in 0 ..< size {
						cm.image4_set(&world.tilesets[0].images[i], d, (d * 3 + k) % size, (d + i + k) % 16)
					}
				}
			}
			for world.sprite_sets[0].count < cm.SPRITE_MAX {
				cm.world_add_sprite(world, 0)
			}
			for world.char_type_count < cm.WORLD_MAX_CHARACTER_TYPES {
				cm.world_add_char_type(world)
			}
			if backdrop_on {
				e.bg_set, e.bg_terrain = 0, 1
			}
			for mode in ([]Mode{.Pick, .Setup, .Sprite, .Text, .Tags}) {
				for sel in ([]int{0, 30, 63}) {
					e.sel = sel
					fix_selection(e)
					e.mode = mode
					if mode == .Text {
						cm.text_entry_begin(&e.entry, "RENAME TYPE", type_name(e, e.sel), cm.NAME_MAX)
					}
					if mode == .Sprite {
						e.pick_sel = 100
						e.pick_scroll = 10
					}
					log = {}
					editor_draw(e, &r)
					testing.expectf(t, log.out_of_bounds == 0, "%d %v: %d rects off screen", size, mode, log.out_of_bounds)
					testing.expect_value(t, log.presents, 1)
					testing.expectf(t, log.rects < 45000, "%d %v: %d rects is too many", size, mode, log.rects)
				}
			}
			free_both(e, world)
		}
	}
	e, world := empty_editor()
	defer free_both(e, world)
	for mode in ([]Mode{.Pick, .Setup, .Sprite, .Tags}) {
		e.mode = mode
		log = {}
		editor_draw(e, &r)
		testing.expect_value(t, log.out_of_bounds, 0)
	}
}

@(test)
test_the_tag_list_sets_and_clears_tags_on_a_type_and_its_characters_inherit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	cm.world_add_tag(world, "water")
	cm.world_add_tag(world, "hostile")
	run(e, .Tags) // slime
	testing.expect_value(t, e.mode, Mode.Tags)
	testing.expect_value(t, cm.tag_count_text(world, tag_view(e)), "NO TAGS")
	press(e, .Down, .Green) // water
	testing.expect(t, world.char_types[0].tags == cm.tag_bit(1) && e.dirty)
	testing.expect_value(t, cm.tag_names_text(world, tag_view(e)), "WATER")
	press(e, .Down, .Green, .Up, .Green) // hostile on, water off
	testing.expect_value(t, world.char_types[0].tags, cm.tag_bit(2))
	press(e, .Up, .Up, .Up)
	testing.expect_value(t, e.tags.sel, 0)
	testing.expect_value(t, world.char_types[1].tags, cm.Tag_Mask(0)) // the bat is untouched
	// Goo is a slime: it inherits; its own setting wins.
	testing.expect(t, cm.world_character_has_tag(world, 0, 2))
	cm.world_cycle_character_tag(world, 0, 2) // set
	cm.world_cycle_character_tag(world, 0, 2) // cleared
	testing.expect(t, !cm.world_character_has_tag(world, 0, 2))
	// Red returns to Setup; the mouse also toggles a row and BACK leaves.
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Setup)
	click_rect(e, TAGS_BUTTON)
	rc := cm.tag_list_rect(0)
	click_at(e, rc.x + 5, rc.y + 3)
	testing.expect_value(t, world.char_types[0].tags, cm.tag_bit(2) | cm.tag_bit(0))
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.Setup)
	// With no types there is nothing to tag.
	e2, w2 := empty_editor()
	defer free_both(e2, w2)
	run(e2, .Tags)
	testing.expect(t, e2.mode == .Setup && e2.note == NOTE_NO_TYPES)
	// A world's many tags scroll in the list.
	for world.tag_count < 40 {
		cm.world_add_tag(world)
	}
	e.mode = .Tags
	for _ in 0 ..< 50 {
		press(e, .Down)
	}
	testing.expect(t, e.tags.sel == 39 && e.tags.scroll == 40 - cm.TAG_LIST_ROWS)
}
