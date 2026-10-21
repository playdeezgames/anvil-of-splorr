#+build !js
package sprite_editor

import cm "../common"
import "core:strings"
import "core:testing"

// A world with tilesets "a" (images a0 a1 a2, tile size 4), "b" (b0) and "c" (no images), a terrain
// set "land" (grass using a/a0, rock using a/a1) and a sprite set "creatures" holding slime (a/a0,
// transparent 0) and bat (b/b0, no transparent colour).
make_world :: proc() -> ^cm.World {
	w := new(cm.World)
	cm.world_reset(w)
	cm.world_set_tile_size(w, 4, 4)
	a := cm.world_add_tileset(w, "a")
	b := cm.world_add_tileset(w, "b")
	cm.world_add_tileset(w, "c")
	for k in 0 ..< 3 {
		n := cm.tileset_insert_blank(&w.tilesets[a], k, "a0")
		cm.image4_set(&w.tilesets[a].images[n], k, 0, k + 1)
	}
	cm.tileset_insert_blank(&w.tilesets[b], 0, "b0")
	ts := cm.world_add_terrain_set(w, "land")
	cm.name_assign(&w.sets[ts].terrains[0].name, "grass")
	rock := cm.world_add_terrain(w, ts)
	cm.name_assign(&w.sets[ts].terrains[rock].name, "rock")
	cm.name_assign(&w.sets[ts].terrains[rock].image, "a0_2")
	si := cm.world_add_sprite_set(w, "creatures")
	slime := cm.world_add_sprite(w, si)
	cm.name_assign(&w.sprite_sets[si].sprites[slime].name, "slime")
	bat := cm.world_add_sprite(w, si)
	sp := &w.sprite_sets[si].sprites[bat]
	cm.name_assign(&sp.name, "bat")
	cm.name_assign(&sp.tileset, "b")
	cm.name_assign(&sp.image, "b0")
	sp.transparent = cm.SPRITE_NO_TRANSPARENT
	return w
}

new_editor :: proc() -> (e: ^Editor, world: ^cm.World) {
	world = make_world()
	e = new(Editor)
	editor_begin(e, world, 0)
	return
}

// An editor on a fresh empty sprite set of a world with tilesets but no sprites.
empty_editor :: proc() -> (e: ^Editor, world: ^cm.World) {
	world = make_world()
	cm.world_delete_sprite_set(world, 0)
	cm.world_add_sprite_set(world, "none")
	e = new(Editor)
	editor_begin(e, world, 0)
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
	testing.expect(t, e.mode == .Pick && e.sel == 0 && !e.dirty && !e.exit_requested && e.bg_set == NO_BG)
	testing.expect(t, backdrop(e) == nil)
	testing.expect_value(t, sprite_name(e, 1), "bat")
}

@(test)
test_moving_over_the_sprites_and_leaving :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	press(e, .Left, .Up)
	testing.expect_value(t, e.sel, 0)
	press(e, .Right, .Right, .Down)
	testing.expect_value(t, e.sel, 1)
	press(e, .Red)
	testing.expect(t, e.exit_requested)
}

@(test)
test_an_empty_set_says_so_instead_of_doing_things :: proc(t: ^testing.T) {
	e, world := empty_editor()
	defer free_both(e, world)
	press(e, .Green, .Left, .Right, .Up, .Down)
	testing.expect(t, e.mode == .Pick && e.sel == 0)
	for row in ([]Setup_Row{.Rename, .Duplicate, .Delete, .Transparent, .Tileset, .Image, .Choose}) {
		e.note = ""
		if row == .Transparent || row == .Tileset || row == .Image {
			goto_row(e, row)
			press(e, .Right)
		} else {
			run(e, row)
		}
		testing.expectf(t, e.note == NOTE_NO_SPRITES && !e.dirty && world.sprite_sets[0].count == 0, "%v on an empty set", row)
	}
}

@(test)
test_the_transparent_colour_steps_through_none_and_every_index :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	sp := current_sprite(e)
	testing.expect_value(t, sp.transparent, 0)
	goto_row(e, .Transparent)
	press(e, .Left)
	testing.expect(t, sp.transparent == cm.SPRITE_NO_TRANSPARENT && e.dirty)
	press(e, .Left)
	testing.expect_value(t, sp.transparent, 15) // wraps from none to the last colour
	press(e, .Right)
	testing.expect_value(t, sp.transparent, cm.SPRITE_NO_TRANSPARENT)
	for k in 0 ..< 16 {
		press(e, .Right)
		testing.expectf(t, sp.transparent == k, "step %d", k)
	}
	press(e, .Right)
	testing.expect_value(t, sp.transparent, cm.SPRITE_NO_TRANSPARENT)
	click_rect(e, TRANSPARENT_PLUS)
	testing.expect_value(t, sp.transparent, 0)
	click_rect(e, TRANSPARENT_MINUS)
	testing.expect_value(t, sp.transparent, cm.SPRITE_NO_TRANSPARENT)
}

@(test)
test_the_tileset_and_image_choices :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	sp := current_sprite(e)
	goto_row(e, .Tileset)
	press(e, .Right) // a -> b (c has no images)
	testing.expect(t, cm.name_str(&sp.tileset) == "b" && cm.name_str(&sp.image) == "b0" && e.dirty)
	press(e, .Right) // b -> not set
	testing.expect(t, cm.name_str(&sp.tileset) == "" && cm.name_str(&sp.image) == "")
	press(e, .Right)
	testing.expect(t, cm.name_str(&sp.tileset) == "a" && cm.name_str(&sp.image) == "a0")
	goto_row(e, .Image)
	press(e, .Right, .Right)
	testing.expect_value(t, cm.name_str(&sp.image), "a0_3")
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&sp.image), "a0")
	// An unset sprite must get a tileset first.
	sp.tileset, sp.image = {}, {}
	e.note = ""
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NO_TILESET)
	run(e, .Choose)
	testing.expect(t, e.mode == .Setup && e.note == NOTE_NO_TILESET)
}

@(test)
test_the_image_grid_chooses_by_commands_and_by_mouse :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Choose)
	testing.expect(t, e.mode == .Image && e.pick_sel == 0)
	press(e, .Right, .Right, .Right)
	testing.expect_value(t, e.pick_sel, 2) // three images: stops at the last
	press(e, .Red)
	testing.expect(t, e.mode == .Setup && cm.name_str(&current_sprite(e).image) == "a0" && !e.dirty)
	run(e, .Choose)
	press(e, .Right, .Green)
	testing.expect(t, e.mode == .Setup && cm.name_str(&current_sprite(e).image) == "a0_2" && e.dirty)
	e.mode = .Pick
	click_thumb(e, 0)
	testing.expect_value(t, e.mode, Mode.Image)
	click_thumb(e, 2)
	testing.expect(t, e.mode == .Pick && cm.name_str(&current_sprite(e).image) == "a0_3")
	click_thumb(e, 0)
	click_thumb(e, 5) // an empty slot does nothing
	testing.expect_value(t, e.mode, Mode.Image)
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.Pick)
	current_sprite(e).tileset, current_sprite(e).image = {}, {}
	press(e, .Green)
	testing.expect(t, e.mode == .Setup && e.row == .Tileset && cm.name_str(&current_sprite(e).tileset) == "a")
}

@(test)
test_new_names_the_sprite_straight_away :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .New)
	testing.expect(t, e.mode == .Text && world.sprite_sets[0].count == 3 && e.sel == 2)
	sp := current_sprite(e)
	testing.expect(t, cm.name_str(&sp.name) == "sprite" && sp.transparent == 0 && cm.name_str(&sp.tileset) == "a" && cm.name_str(&sp.image) == "a0")
	name_typed(e, "ogre")
	testing.expect(t, e.mode == .Setup && sprite_name(e, 2) == "ogre" && e.dirty)
	run(e, .Duplicate)
	testing.expect_value(t, sprite_name(e, 3), "ogre_copy")
	name_typed(e, "slime") // taken
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed(e, "")
	testing.expect_value(t, e.mode, Mode.Text)
	press_keypad_action(e, .Cancel) // keeps the suggested name
	testing.expect(t, e.mode == .Setup && sprite_name(e, 3) == "ogre_copy")
	// A first sprite in an empty set.
	e2, w2 := empty_editor()
	defer free_both(e2, w2)
	run(e2, .New)
	press_keypad_action(e2, .Done)
	testing.expect(t, e2.mode == .Setup && w2.sprite_sets[0].count == 1 && sprite_name(e2, 0) == "sprite")
}

@(test)
test_rename_checks_the_name :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Rename)
	name_typed(e, "bat")
	testing.expect(t, e.mode == .Text && strings.contains(e.entry.note, "USE"))
	name_typed(e, "goo")
	testing.expect(t, e.mode == .Setup && sprite_name(e, 0) == "goo" && e.dirty)
	e.dirty = false
	run(e, .Rename)
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Setup && !e.dirty)
}

@(test)
test_delete_needs_a_second_press :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	e.sel = 1
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && world.sprite_sets[0].count == 2)
	press(e, .Up)
	testing.expect(t, !e.confirm_delete)
	e.row = .Delete
	press(e, .Green, .Green)
	testing.expect(t, world.sprite_sets[0].count == 1 && e.sel == 0 && e.dirty)
	run(e, .Delete)
	press(e, .Green)
	testing.expect_value(t, world.sprite_sets[0].count, 0) // a set may become empty
	run(e, .Delete)
	testing.expect_value(t, e.note, NOTE_NO_SPRITES)
}

@(test)
test_full_set_refuses_more :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	for world.sprite_sets[0].count < cm.SPRITE_MAX {
		cm.world_add_sprite(world, 0)
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
	testing.expect(t, e.bg_set == 0 && backdrop(e) != nil && cm.name_str(&backdrop(e).name) == "grass")
	testing.expect(t, !e.dirty) // looking only: nothing to save
	goto_row(e, .Bg_Terrain)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&backdrop(e).name), "rock")
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&backdrop(e).name), "grass")
	press(e, .Left)
	testing.expect_value(t, cm.name_str(&backdrop(e).name), "rock")
	goto_row(e, .Bg_Set)
	press(e, .Right) // only one set: back to none
	testing.expect(t, e.bg_set == NO_BG && backdrop(e) == nil)
	press(e, .Left)
	testing.expect_value(t, e.bg_set, 0)
	// By mouse; and a backdrop that no longer exists falls back to the checkerboard.
	click_rect(e, BG_SET_MINUS)
	testing.expect(t, e.bg_set == NO_BG)
	click_rect(e, BG_SET_PLUS)
	click_rect(e, BG_TERRAIN_PLUS)
	testing.expect_value(t, e.bg_terrain, 1)
	cm.world_delete_terrain_set(world, 0)
	testing.expect(t, backdrop(e) == nil)
	e.bg_terrain = 99
	e.bg_set = NO_BG
	testing.expect(t, backdrop(e) == nil)
}

Colour_Log :: struct {
	rects:  int,
	colors: [dynamic]cm.Color,
}

colour_renderer :: proc(l: ^Colour_Log) -> cm.Renderer {
	return cm.Renderer {
		data = l,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^Colour_Log)(d)
			k.rects += 1
			append(&k.colors, c)
		},
		present = proc(d: rawptr) {},
	}
}

@(test)
test_a_sprite_leaves_its_transparent_colour_out :: proc(t: ^testing.T) {
	log: Colour_Log
	defer delete(log.colors)
	r := colour_renderer(&log)
	e, world := new_editor()
	defer free_both(e, world)
	world.palette[0] = {1, 2, 3} // black is not drawn for the slime, so this colour must never appear
	area := Rect{0, 0, 16, 16}
	draw_sprite(e, &r, area, &world.sprite_sets[0].sprites[0])
	for c in log.colors {
		testing.expect(t, c != cm.Color{1, 2, 3})
	}
	testing.expect(t, len(log.colors) > 2) // checkerboard and the sprite's dots
	// The bat has no transparent colour: its background colour is drawn.
	clear(&log.colors)
	draw_sprite(e, &r, area, &world.sprite_sets[0].sprites[1])
	found := false
	for c in log.colors {
		found ||= c == cm.Color{1, 2, 3}
	}
	testing.expect(t, found)
	// Over a terrain backdrop the checkerboard colours are not used at all.
	clear(&log.colors)
	e.bg_set, e.bg_terrain = 0, 1
	draw_sprite(e, &r, area, &world.sprite_sets[0].sprites[0])
	for c in log.colors {
		testing.expect(t, c != CHECK_A && c != CHECK_B)
	}
	// A sprite without a picture is a dark red block, also over the backdrop.
	clear(&log.colors)
	world.sprite_sets[0].sprites[0].tileset = {}
	world.sprite_sets[0].sprites[0].image = {}
	draw_sprite(e, &r, area, &world.sprite_sets[0].sprites[0])
	testing.expect_value(t, log.colors[len(log.colors) - 1], UNSET)
}

// --- Parity ---

Input_Method :: enum {
	Commands,
	Mouse,
}

@(test)
test_every_function_is_reachable_by_each_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for m in Input_Method {
		e, world := new_editor()
		s := &world.sprite_sets[0]
		// Transparent colour
		switch m {
		case .Commands:
			goto_row(e, .Transparent)
			press(e, .Left)
		case .Mouse:
			click_rect(e, TRANSPARENT_MINUS)
		}
		testing.expectf(t, s.sprites[0].transparent == cm.SPRITE_NO_TRANSPARENT, "%v transparent", m)
		// Tileset and image
		switch m {
		case .Commands:
			goto_row(e, .Tileset)
			press(e, .Right)
		case .Mouse:
			click_rect(e, TILESET_PLUS)
		}
		testing.expectf(t, cm.name_str(&s.sprites[0].tileset) == "b", "%v tileset", m)
		switch m {
		case .Commands:
			press(e, .Left)
			goto_row(e, .Image)
			press(e, .Right)
		case .Mouse:
			click_rect(e, TILESET_MINUS)
			click_rect(e, IMAGE_PLUS)
		}
		testing.expectf(t, cm.name_str(&s.sprites[0].image) == "a0_2", "%v image", m)
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
		// New, Duplicate (keypad cancelled to keep the suggested names), Delete
		switch m {
		case .Commands:
			run(e, .New)
		case .Mouse:
			click_rect(e, NEW_BUTTON)
		}
		press_keypad_action(e, .Cancel)
		testing.expectf(t, s.count == 3, "%v new", m)
		switch m {
		case .Commands:
			run(e, .Duplicate)
		case .Mouse:
			click_rect(e, DUPLICATE_BUTTON)
		}
		press_keypad_action(e, .Cancel)
		testing.expectf(t, s.count == 4, "%v duplicate", m)
		switch m {
		case .Commands:
			run(e, .Delete)
			press(e, .Green)
		case .Mouse:
			click_rect(e, DELETE_BUTTON)
			click_rect(e, DELETE_BUTTON)
		}
		testing.expectf(t, s.count == 3, "%v delete", m)
		// Rename
		switch m {
		case .Commands:
			run(e, .Rename)
		case .Mouse:
			click_rect(e, RENAME_BUTTON)
		}
		testing.expectf(t, e.mode == .Text, "%v rename", m)
		press_keypad_action(e, .Cancel)
		// Pick an image from the grid, then leave
		e.sel = 0
		switch m {
		case .Commands:
			run(e, .Choose)
		case .Mouse:
			click_rect(e, PICK_BUTTON)
		}
		testing.expectf(t, e.mode == .Image, "%v pick image", m)
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

// --- Layout, drawing and text ---

@(test)
test_layout_fits_the_screen_and_does_not_overlap :: proc(t: ^testing.T) {
	rects := make([dynamic]Rect, context.temp_allocator)
	append(&rects, Rect{GRID_X - 1, GRID_Y - 1, GRID_COLS * GRID_PITCH + 1, GRID_ROWS * GRID_PITCH + 1}, BANNER)
	append(&rects, TILESET_MINUS, TILESET_PLUS, IMAGE_MINUS, IMAGE_PLUS, TRANSPARENT_MINUS, TRANSPARENT_PLUS, BG_SET_MINUS, BG_SET_PLUS, BG_TERRAIN_MINUS, BG_TERRAIN_PLUS, PREVIEW_FRAME)
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
	testing.expect(t, ROW_LABEL_X + cm.text_width("TILESET") < TILESET_MINUS.x && ROW_LABEL_X + cm.text_width("TRANSP") < TRANSPARENT_MINUS.x && ROW_LABEL_X + cm.text_width("BG TILE") < BG_TERRAIN_MINUS.x)
	testing.expect(t, ROW_VALUE_X > TILESET_PLUS.x + TILESET_PLUS.w && ROW_VALUE_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W - 2)
	testing.expect(t, INFO_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W)
	testing.expect(t, HELP_Y >= BACK_BUTTON.y + BACK_BUTTON.h && HELP_Y + MAX_HELP_LINES * cm.LINE_ADVANCE <= cm.SCREEN_H)
	// The transparent colour's chip fits right of the longest value ("NONE" or two digits).
	testing.expect(t, ROW_VALUE_X + cm.text_width("NONE") + 4 + 8 < cm.SCREEN_W)
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
	testing.expect_value(t, grid_total_rows(256), 32)
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
		for mode in ([]Mode{.Pick, .Setup, .Image}) {
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
	for note in ([]string{NOTE_NO_SPRITES, NOTE_FULL, NOTE_NO_TILESET, NOTE_NO_IMAGES, NOTE_NO_BG_SET, NOTE_NAME_EMPTY, NOTE_NAME_USED, NOTE_NAME_BAD, "SPRITE 256 OF 256 *", "NO SPRITES YET *"}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 2, "note: %s", note)
	}
	for word in ([]string{"NOT SET", "NONE", "TRANSP", "BG SET", "BG TILE", "15", "-"}) {
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
				n := cm.world_add_sprite(world, 0)
				world.sprite_sets[0].sprites[n].transparent = n % 17 - 1
			}
			for _ in 0 ..< 200 {
				cm.tileset_insert_blank(&world.tilesets[1], world.tilesets[1].count, "more")
			}
			if backdrop_on {
				e.bg_set, e.bg_terrain = 0, 1
			}
			for mode in ([]Mode{.Pick, .Setup, .Image, .Text}) {
				for sel in ([]int{0, 100, 255}) {
					e.sel = sel
					fix_selection(e)
					e.mode = mode
					if mode == .Text {
						cm.text_entry_begin(&e.entry, "RENAME SPRITE", sprite_name(e, e.sel), cm.NAME_MAX)
					}
					if mode == .Image {
						current_sprite(e).tileset = world.tileset_names[1]
						e.pick_sel = 150
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
	// An empty set draws too.
	e, world := empty_editor()
	defer free_both(e, world)
	for mode in ([]Mode{.Pick, .Setup, .Image}) {
		e.mode = mode
		log = {}
		editor_draw(e, &r)
		testing.expect_value(t, log.out_of_bounds, 0)
	}
}
