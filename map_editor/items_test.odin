#+build !js
package map_editor

import cm "../common"
import "core:testing"

// The character world plus item types "sword" (never stacks) and "gold" (stacks to 100), the sword
// type drawing the "bat" sprite (a picture that shows), and 5 gold in the cell 3,2.
item_world :: proc(w := 6, h := 4) -> ^cm.World {
	world := char_world(w, h)
	sword := cm.world_add_item_type(world, "sword")
	cm.name_assign(&world.item_types[sword].sprite, "bat")
	for si in 0 ..< world.sprite_set_count {
		for k in 0 ..< world.sprite_sets[si].count {
			world.sprite_sets[si].sprites[k].transparent = cm.SPRITE_NO_TRANSPARENT // every pixel of a picture draws
		}
	}
	gold := cm.world_add_item_type(world, "gold")
	cm.world_set_item_type_max_stack(world, gold, 100)
	cm.world_owner_add(world, cm.owner_cell(0, 3, 2), gold, 5)
	return world
}

// An editor in the Items layer.
item_editor :: proc(w := 6, h := 4) -> (e: ^Editor, world: ^cm.World) {
	world = item_world(w, h)
	e = new(Editor)
	editor_begin(e, world, 0)
	toggle_layer(e) // characters
	toggle_layer(e) // features
	toggle_layer(e) // items
	return
}

@(test)
test_green_asks_the_host_to_open_the_cell_under_the_cursor :: proc(t: ^testing.T) {
	e, world := item_editor()
	defer free_both(e, world)
	testing.expect(t, e.layer == .Items && e.row == .Cell_Open && !e.items_requested)
	goto_cell(e, 3, 2)
	press(e, .Green)
	testing.expect(t, e.items_requested && !e.dirty)
	testing.expect_value(t, cursor_owner(e), cm.owner_cell(0, 3, 2))
	testing.expect_value(t, cell_entry_count(e), 1)
	e.items_requested = false
	// An empty cell opens too (the inventory screen makes the inventory when something is added).
	goto_cell(e, 0, 0)
	press(e, .Green)
	testing.expect(t, e.items_requested && cell_entry_count(e) == 0 && cursor_owner(e) == cm.owner_cell(0, 0, 0))
	e.items_requested = false
	// The cursor moves with the d-pad and stays inside the map.
	press(e, .Left, .Up, .Right, .Right, .Down)
	testing.expect(t, e.cx == 2 && e.cy == 1 && e.mode == .Draw)
	for _ in 0 ..< 10 {
		press(e, .Right, .Down)
	}
	testing.expect(t, e.cx == 5 && e.cy == 3)
	press(e, .Red)
	testing.expect(t, e.exit_requested)
}

@(test)
test_clear_asks_first_and_only_clears_the_cell_under_the_cursor :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := item_editor()
	defer free_both(e, world)
	cm.world_owner_add(world, cm.owner_cell(0, 0, 0), 0, 1)
	goto_cell(e, 3, 2)
	press(e, .Yellow)
	run(e, .Cell_Clear)
	testing.expect(t, e.confirm_delete && cell_entry_count(e) == 1)
	testing.expect_value(t, banner_text(e), "CLEAR THE CELL?  GREEN: CONFIRM")
	press(e, .Down) // anything else cancels
	testing.expect(t, !e.confirm_delete && cell_entry_count(e) == 1)
	e.row = .Cell_Clear
	press(e, .Green, .Green)
	testing.expect(t, e.dirty && cell_entry_count(e) == 0 && world.inventory_count == 1)
	testing.expect_value(t, world.maps[0].inventories[2][3], cm.UUID_NONE)
	// An empty cell says so and does not arm.
	e.row = .Cell_Clear
	press(e, .Green)
	testing.expect(t, e.note == NOTE_NOTHING_HERE && !e.confirm_delete)
}

@(test)
test_every_items_layer_function_is_reachable_by_each_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for m in Input_Method {
		e, world := item_editor()
		cell := cell_rect(e, 3, 2)
		// Open: a cell by green, or by clicking it (which also moves the cursor); right click only moves.
		switch m {
		case .Commands:
			goto_cell(e, 3, 2)
			press(e, .Green)
		case .Mouse:
			editor_handle_event(e, cm.Mouse_Button_Event{button = .Right, x = cell.x + 2, y = cell.y + 2, down = true})
			testing.expectf(t, e.cx == 3 && e.cy == 2 && !e.items_requested, "%v right click", m)
			click_at(e, cell.x + 2, cell.y + 2)
		}
		testing.expectf(t, e.items_requested && cursor_owner(e) == cm.owner_cell(0, 3, 2), "%v open", m)
		e.items_requested = false
		switch m {
		case .Commands:
			run(e, .Cell_Open)
		case .Mouse:
			click_rect(e, ITEM_OPEN_BUTTON)
		}
		testing.expectf(t, e.items_requested, "%v open button", m)
		// Zoom.
		before := e.zoom
		switch m {
		case .Commands:
			goto_row(e, .Zoom)
			press(e, .Right)
		case .Mouse:
			click_rect(e, ZOOM_PLUS)
		}
		testing.expectf(t, e.zoom == before + 1, "%v zoom", m)
		// Clear, twice.
		switch m {
		case .Commands:
			run(e, .Cell_Clear)
			press(e, .Green)
		case .Mouse:
			click_rect(e, ITEM_CLEAR_BUTTON)
			click_rect(e, ITEM_CLEAR_BUTTON)
		}
		testing.expectf(t, cell_entry_count(e) == 0 && e.dirty, "%v clear", m)
		// Layer and leave.
		switch m {
		case .Commands:
			run(e, .Layer)
		case .Mouse:
			click_rect(e, LAYER_BUTTON)
		}
		testing.expectf(t, e.layer == .Triggers, "%v layer", m)
		e.layer = .Items
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
test_items_show_on_the_map_in_every_layer_and_text_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	e, world := item_editor()
	defer free_both(e, world)
	// A sword lying at 0,0 (a picture that shows) draws something inside its cell, and nothing without it.
	d := cm.world_zoom_draw(world, 0, 0, 0, 6, 4, CANVAS.x, CANVAS.y, 4)
	d.clip = CANVAS
	log = {}
	cm.world_draw_authored_inventories(&r, world, d)
	gold_only := log.rects
	testing.expect(t, gold_only > 0) // the gold at 3,2 (its picture shows too)
	cm.world_owner_add(world, cm.owner_cell(0, 0, 0), 0, 1)
	log = {}
	cm.world_draw_authored_inventories(&r, world, d)
	testing.expect(t, log.rects > gold_only)
	for layer in Layer {
		e.layer = layer
		e.mode = .Draw
		log = {}
		editor_draw(e, &r)
		testing.expect(t, log.rects > 0)
		testing.expectf(t, log.out_of_bounds == 0, "%v: %d rects off screen", layer, log.out_of_bounds)
	}
	// The Items layer: texts are in the font and fit; a long list says how many more.
	e.layer = .Items
	for _ in 0 ..< 8 {
		cm.world_owner_add(world, cm.owner_cell(0, 3, 2), 0, 1)
	}
	goto_cell(e, 3, 2)
	for mode in ([]Mode{.Draw, .Setup}) {
		e.mode = mode
		for armed in ([]bool{false, true}) {
			e.confirm_delete = armed
			text := banner_text(e)
			testing.expectf(t, cm.text_is_drawable(text) && BANNER.x + 4 + cm.text_width(text) <= BANNER.x + BANNER.w, "banner %s", text)
		}
		lines, n := help_lines(e)
		for line in lines[:n] {
			testing.expectf(t, cm.text_is_drawable(line) && cm.text_width(line) <= cm.SCREEN_W - 16, "help %s", line)
		}
	}
	for text in ([]string{NOTE_NOTHING_HERE, cell_items_text(e), item_list_line(e, 0), "AND 99 MORE", "63,63", "4096 CELLS", "ON MAP", "HERE", "CELL", "OPEN", "CLEAR", "1000000000 ENTRIES"}) {
		testing.expectf(t, cm.text_is_drawable(text), "%s", text)
	}
	testing.expect(t, INFO_X + cm.text_width("CURSOR: 63,63  256 ENTRIES *") <= cm.SCREEN_W)
	testing.expect(t, PICKER_Y + 2 + ITEM_LIST_LINES * cm.LINE_ADVANCE + cm.GLYPH_H <= PICKER_Y + PICKER_ROWS * PICKER_PITCH) // (the "AND n MORE" line is the one after the entries)
	testing.expect(t, ROW_VALUE_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W)
	e.mode = .Draw
	log = {}
	editor_draw(e, &r)
	testing.expectf(t, log.out_of_bounds == 0 && log.presents == 1, "%d off screen", log.out_of_bounds)
	// The tags button is not offered here.
	click_rect(e, TAGS_BUTTON)
	testing.expect(t, e.mode != .Tags)
}

@(test)
test_a_map_cannot_shrink_over_a_cell_that_holds_items :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := item_editor()
	defer free_both(e, world)
	e.layer = .Terrain
	e.mode = .Setup
	e.row = .Columns
	press(e, .Left, .Left, .Left, .Left, .Left)
	testing.expect_value(t, current_map(e).width, 4) // 6 -> 4: the cell at column 3 is still inside
	press(e, .Left)
	testing.expect(t, current_map(e).width == 4 && e.note == "1 THING IN THE WAY")
	cm.world_owner_clear_inventory(world, cm.owner_cell(0, 3, 2))
	press(e, .Left)
	testing.expect_value(t, current_map(e).width, 3)
}
