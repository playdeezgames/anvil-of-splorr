#+build !js
package terrain_editor

import cm "../common"
import "core:strings"
import "core:testing"

// A world with tilesets "a" (images a0 a1 a2), "b" (b0) and "c" (no images); a terrain set "s"
// with terrains grass (default, a/a0), rock (solid, a/a1) and water (b/b0), and a map "m" using it.
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
	si := cm.world_add_terrain_set(w, "s")
	cm.name_assign(&w.sets[si].terrains[0].name, "grass")
	rock := cm.world_add_terrain(w, si)
	water := cm.world_add_terrain(w, si)
	cm.name_assign(&w.sets[si].terrains[rock].name, "rock")
	cm.name_assign(&w.sets[si].terrains[rock].image, "a0_2")
	w.sets[si].terrains[rock].tags = cm.tag_bit(cm.TAG_SOLID)
	cm.name_assign(&w.sets[si].terrains[water].name, "water")
	cm.name_assign(&w.sets[si].terrains[water].tileset, "b")
	cm.name_assign(&w.sets[si].terrains[water].image, "b0")
	mi := cm.world_add_map(w, si, "m")
	cm.world_map_set_size(w, mi, 3, 2)
	return w
}

new_editor :: proc() -> (e: ^Editor, world: ^cm.World) {
	world = make_world()
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
test_begin_selects_the_default_terrain :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	world.sets[0].default = 2
	editor_begin(e, world, 0)
	testing.expect(t, e.mode == .Pick && e.sel == 2 && !e.dirty && !e.exit_requested)
	testing.expect_value(t, terrain_name(e, 2), "water")
}

@(test)
test_moving_over_the_terrains_and_leaving :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	press(e, .Left, .Up)
	testing.expect_value(t, e.sel, 0)
	press(e, .Right, .Right, .Right, .Down)
	testing.expect_value(t, e.sel, 2) // three terrains: the ends stop it
	press(e, .Red)
	testing.expect(t, e.exit_requested)
}

@(test)
test_default_changes_and_tags_open_the_tag_list :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	e.mode = .Pick
	press(e, .Right)
	run(e, .Default)
	testing.expect_value(t, world.sets[0].default, 1)
	e.dirty = false
	run(e, .Default) // already the default: nothing changes
	testing.expect(t, !e.dirty)
	// The Tags row opens the list for the selected terrain and red comes back to where it was.
	e.sel = 1
	run(e, .Tags)
	testing.expect_value(t, e.mode, Mode.Tags)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Setup)
	click_rect(e, TAGS_BUTTON)
	testing.expect_value(t, e.mode, Mode.Tags)
	e.mode = .Pick
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Image) // green in Pick is still the picture
}

@(test)
test_the_tag_list_sets_and_clears_tags_on_a_terrain :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	cm.world_add_tag(world, "water")
	cm.world_add_tag(world, "hostile")
	e.sel = 0 // grass: no tags
	run(e, .Tags)
	press(e, .Green) // solid
	testing.expect(t, world.sets[0].terrains[0].tags == 1 && e.dirty)
	press(e, .Down, .Down, .Green)
	testing.expect_value(t, world.sets[0].terrains[0].tags, cm.tag_bit(0) | cm.tag_bit(2))
	press(e, .Up, .Up, .Green) // solid off again
	testing.expect_value(t, world.sets[0].terrains[0].tags, cm.tag_bit(2))
	press(e, .Up, .Up, .Up, .Up, .Up)
	testing.expect_value(t, e.tags.sel, 0) // the ends stop it
	press(e, .Down, .Down, .Down, .Down)
	testing.expect_value(t, e.tags.sel, 2)
	// The readout shows the tags that are on; other terrains are untouched.
	testing.expect_value(t, cm.tag_names_text(world, tag_view(e)), "HOSTILE")
	testing.expect_value(t, world.sets[0].terrains[1].tags, cm.tag_bit(0)) // rock: still just solid
	// By mouse: a click selects the row and toggles it; BACK returns.
	rc := cm.tag_list_rect(1)
	click_at(e, rc.x + 5, rc.y + 3)
	testing.expect(t, e.tags.sel == 1 && world.sets[0].terrains[0].tags == cm.tag_bit(1) | cm.tag_bit(2))
	click_at(e, rc.x + 5, rc.y + 3)
	testing.expect_value(t, world.sets[0].terrains[0].tags, cm.tag_bit(2))
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.Setup)
	// Many tags scroll.
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

@(test)
test_the_tileset_choice_skips_empty_tilesets_and_includes_not_set :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	goto_row(e, .Tileset)
	press(e, .Right) // a -> b (c has no images)
	tr := current_terrain(e)
	testing.expect(t, cm.name_str(&tr.tileset) == "b" && cm.name_str(&tr.image) == "b0" && e.dirty)
	press(e, .Right) // b -> not set
	testing.expect(t, cm.name_str(&tr.tileset) == "" && cm.name_str(&tr.image) == "")
	press(e, .Right) // not set -> a, its first image
	testing.expect(t, cm.name_str(&tr.tileset) == "a" && cm.name_str(&tr.image) == "a0")
	press(e, .Left, .Left)
	testing.expect_value(t, cm.name_str(&tr.tileset), "b")
	// With no image anywhere there is nothing to choose.
	for i in 0 ..< world.tileset_count {
		world.tilesets[i].count = 0
	}
	e.note = ""
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NO_IMAGES)
}

@(test)
test_the_image_choice_steps_and_wraps :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	goto_row(e, .Image)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&current_terrain(e).image), "a0_2")
	press(e, .Right, .Right)
	testing.expect_value(t, cm.name_str(&current_terrain(e).image), "a0")
	press(e, .Left)
	testing.expect_value(t, cm.name_str(&current_terrain(e).image), "a0_3")
	// An unset terrain must get a tileset first.
	current_terrain(e).tileset, current_terrain(e).image = {}, {}
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
	press(e, .Right, .Right, .Right, .Left) // three images: stops at the last
	testing.expect_value(t, e.pick_sel, 1)
	press(e, .Down, .Up)
	testing.expect_value(t, e.pick_sel, 1)
	press(e, .Red) // cancels
	testing.expect(t, e.mode == .Setup && cm.name_str(&current_terrain(e).image) == "a0" && !e.dirty)
	run(e, .Choose)
	press(e, .Right, .Right, .Green)
	testing.expect(t, e.mode == .Setup && cm.name_str(&current_terrain(e).image) == "a0_3" && e.dirty)
	// By mouse from Pick: a second click on the selected terrain opens the grid, a click picks.
	e.mode = .Pick
	click_thumb(e, 0)
	testing.expect_value(t, e.mode, Mode.Image)
	click_thumb(e, 1)
	testing.expect(t, e.mode == .Pick && cm.name_str(&current_terrain(e).image) == "a0_2")
	click_thumb(e, 0)
	testing.expect_value(t, e.mode, Mode.Image)
	click_thumb(e, 5) // an empty slot does nothing
	testing.expect_value(t, e.mode, Mode.Image)
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.Pick)
	// Green on an unset terrain first picks a tileset, then (green again) the image.
	current_terrain(e).tileset, current_terrain(e).image = {}, {}
	press(e, .Green)
	testing.expect(t, e.mode == .Setup && e.row == .Tileset && cm.name_str(&current_terrain(e).tileset) == "a")
}

@(test)
test_new_names_the_terrain_straight_away :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	press(e, .Yellow)
	goto_row(e, .New)
	press(e, .Green)
	testing.expect(t, e.mode == .Text && world.sets[0].count == 4 && e.sel == 3)
	tr := current_terrain(e)
	testing.expect(t, cm.name_str(&tr.name) == "terrain" && cm.name_str(&tr.tileset) == "a" && cm.name_str(&tr.image) == "a0")
	name_typed(e, "sand")
	testing.expect(t, e.mode == .Setup && terrain_name(e, 3) == "sand" && e.dirty)
	// A refused name keeps the keypad up; cancelling keeps the suggested one.
	run(e, .Duplicate)
	testing.expect_value(t, terrain_name(e, 4), "sand_copy")
	name_typed(e, "grass")
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed(e, "")
	testing.expect_value(t, e.mode, Mode.Text)
	press_keypad_action(e, .Cancel)
	testing.expect(t, e.mode == .Setup && terrain_name(e, 4) == "sand_copy")
	testing.expect(t, cm.name_str(&world.sets[0].terrains[4].image) == cm.name_str(&world.sets[0].terrains[3].image))
}

@(test)
test_rename_checks_the_name :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Rename)
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed(e, "rock") // used by another terrain
	testing.expect(t, e.mode == .Text && strings.contains(e.entry.note, "USE"))
	name_typed(e, "lawn")
	testing.expect(t, e.mode == .Setup && terrain_name(e, 0) == "lawn" && e.dirty)
	e.dirty = false
	run(e, .Rename)
	press_keypad_action(e, .Done) // the same name again: fine, nothing changes
	testing.expect(t, e.mode == .Setup && !e.dirty)
}

@(test)
test_delete_needs_a_second_press_and_has_rules :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	e.sel = 2 // water, unused
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && world.sets[0].count == 3)
	press(e, .Up) // anything else cancels
	testing.expect(t, !e.confirm_delete)
	e.row = .Delete
	press(e, .Green, .Green)
	testing.expect(t, world.sets[0].count == 2 && e.sel == 1 && e.dirty)
	// The default cannot go.
	e.sel = 0
	run(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.note == NOTE_IS_DEFAULT && world.sets[0].count == 2)
	// A terrain map cells use cannot go either.
	e.sel = 1
	world.maps[0].cells[0][0] = 1
	world.maps[0].cells[1][1] = 1
	run(e, .Delete)
	press(e, .Green)
	testing.expect_value(t, e.note, "IN USE BY 2 MAP CELLS")
	world.maps[0].cells[1][1] = 0
	run(e, .Delete)
	press(e, .Green)
	testing.expect_value(t, e.note, "IN USE BY 1 MAP CELL")
	// And the last one stays.
	world.maps[0].cells[0][0] = 0
	run(e, .Delete)
	press(e, .Green)
	testing.expect(t, world.sets[0].count == 1)
	run(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.note == NOTE_LAST_ONE && world.sets[0].count == 1)
}

@(test)
test_full_set_refuses_more :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	for world.sets[0].count < cm.TERRAIN_MAX {
		cm.world_add_terrain(world, 0)
	}
	run(e, .New)
	testing.expect(t, e.note == NOTE_FULL && e.mode == .Setup && world.sets[0].count == cm.TERRAIN_MAX)
	run(e, .Duplicate)
	testing.expect_value(t, e.note, NOTE_FULL)
}

@(test)
test_many_terrains_scroll_the_grid :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	for world.sets[0].count < 100 {
		cm.world_add_terrain(world, 0)
	}
	for _ in 0 ..< 10 {
		press(e, .Down)
	}
	testing.expect(t, e.sel == 80 && e.scroll == 3) // row 10 is the last row shown
	editor_handle_event(e, cm.Mouse_Wheel{dy = 2})
	testing.expect_value(t, e.scroll, 1)
	click_thumb(e, 20)
	testing.expect_value(t, e.sel, 20)
	for _ in 0 ..< 40 {
		editor_handle_event(e, cm.Mouse_Wheel{dy = -1})
	}
	testing.expect_value(t, e.scroll, grid_total_rows(100) - GRID_ROWS)
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
		s := &world.sets[0]
		// Tags: open the list, set a tag, come back
		switch m {
		case .Commands:
			goto_row(e, .Tags)
			press(e, .Green, .Green, .Red)
		case .Mouse:
			click_rect(e, TAGS_BUTTON)
			rc := cm.tag_list_rect(0)
			click_at(e, rc.x + 5, rc.y + 3)
			click_rect(e, BACK_BUTTON)
		}
		testing.expectf(t, s.terrains[0].tags == 1 && e.mode == .Setup, "%v tags", m)
		// Tileset and image
		switch m {
		case .Commands:
			goto_row(e, .Tileset)
			press(e, .Right)
			goto_row(e, .Image)
		case .Mouse:
			click_rect(e, TILESET_PLUS)
		}
		testing.expectf(t, cm.name_str(&s.terrains[0].tileset) == "b", "%v tileset", m)
		switch m {
		case .Commands:
			goto_row(e, .Tileset)
			press(e, .Left)
		case .Mouse:
			click_rect(e, TILESET_MINUS)
		}
		switch m {
		case .Commands:
			goto_row(e, .Image)
			press(e, .Right)
		case .Mouse:
			click_rect(e, IMAGE_PLUS)
		}
		testing.expectf(t, cm.name_str(&s.terrains[0].image) == "a0_2", "%v image", m)
		// Default
		e.sel = 1
		switch m {
		case .Commands:
			run(e, .Default)
		case .Mouse:
			click_rect(e, DEFAULT_BUTTON)
		}
		testing.expectf(t, s.default == 1, "%v default", m)
		// New, Duplicate (keypad cancelled to keep the suggested names), Delete
		switch m {
		case .Commands:
			run(e, .New)
		case .Mouse:
			click_rect(e, NEW_BUTTON)
		}
		press_keypad_action(e, .Cancel)
		testing.expectf(t, s.count == 4, "%v new", m)
		switch m {
		case .Commands:
			run(e, .Duplicate)
		case .Mouse:
			click_rect(e, DUPLICATE_BUTTON)
		}
		press_keypad_action(e, .Cancel)
		testing.expectf(t, s.count == 5, "%v duplicate", m)
		switch m {
		case .Commands:
			run(e, .Delete)
			press(e, .Green)
		case .Mouse:
			click_rect(e, DELETE_BUTTON)
			click_rect(e, DELETE_BUTTON)
		}
		testing.expectf(t, s.count == 4, "%v delete", m)
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
	append(&rects, Rect{GRID_X - 1, GRID_Y - 1, GRID_COLS * GRID_PITCH + 1, GRID_ROWS * GRID_PITCH + 1}, BANNER, TILESET_MINUS, TILESET_PLUS, IMAGE_MINUS, IMAGE_PLUS, DEFAULT_SWITCH, PREVIEW_FRAME)
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
	testing.expect(t, ROW_LABEL_X + cm.text_width("TILESET") < TILESET_MINUS.x && ROW_LABEL_X + cm.text_width("DEFAULT") < DEFAULT_SWITCH.x)
	testing.expect(t, ROW_VALUE_X > TILESET_PLUS.x + TILESET_PLUS.w && ROW_VALUE_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W - 2)
	testing.expect(t, INFO_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W) // a 32 character name
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
	_, _, ok = grid_cell_at(GRID_X, GRID_Y + GRID_ROWS * GRID_PITCH)
	testing.expect(t, !ok)
	testing.expect_value(t, grid_total_rows(0), 0)
	testing.expect_value(t, grid_total_rows(9), 2)
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
		for mode in ([]Mode{.Pick, .Setup, .Image, .Tags}) {
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
	for note in ([]string{NOTE_LAST_ONE, NOTE_IS_DEFAULT, NOTE_FULL, NOTE_NO_TILESET, NOTE_NO_IMAGES, NOTE_NAME_EMPTY, NOTE_NAME_USED, NOTE_NAME_BAD, "IN USE BY 65536 MAP CELLS", "TERRAIN 256 OF 256 *"}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 2, "note: %s", note)
	}
	testing.expect(t, cm.text_is_drawable("NOT SET") && cm.text_is_drawable("SET") && cm.text_is_drawable("YES") && cm.text_is_drawable("NO"))
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
		for k in 0 ..< 3 {
			for i in 0 ..< world.tilesets[0].count {
				cm.image4_set(&world.tilesets[0].images[i], k, k, k + i)
			}
		}
		for world.tag_count < cm.WORLD_MAX_TAGS {
			cm.world_add_tag(world, "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
		}
		for world.sets[0].count < cm.TERRAIN_MAX {
			n := cm.world_add_terrain(world, 0)
			world.sets[0].terrains[n].tags = n % 3 == 0 ? cm.tag_bit(cm.TAG_SOLID) : 0
		}
		for k in 0 ..< 200 {
			cm.tileset_insert_blank(&world.tilesets[1], world.tilesets[1].count, "more")
			_ = k
		}
		for mode in ([]Mode{.Pick, .Setup, .Image, .Text, .Tags}) {
			for sel in ([]int{0, 100, 255}) {
				e.sel = sel
				fix_selection(e)
				e.mode = mode
				if mode == .Text {
					cm.text_entry_begin(&e.entry, "RENAME TERRAIN", terrain_name(e, e.sel), cm.NAME_MAX)
				}
				if mode == .Image {
					current_terrain(e).tileset = world.tileset_names[1]
					e.pick_sel = 150
					e.pick_scroll = 10
				}
				log = {}
				editor_draw(e, &r)
				testing.expectf(t, log.out_of_bounds == 0, "%d %v: %d rects off screen", size, mode, log.out_of_bounds)
				testing.expect_value(t, log.presents, 1)
				testing.expectf(t, log.rects < 30000, "%d %v: %d rects is too many", size, mode, log.rects)
			}
		}
		free_both(e, world)
	}
}
