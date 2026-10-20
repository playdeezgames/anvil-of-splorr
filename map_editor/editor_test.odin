#+build !js
package map_editor

import cm "../common"
import "core:strings"
import "core:testing"

// A world with a 4 x 4 tile size, tileset "t" (4 images), set "s" with `terrains` terrains named
// t0, t1, ... (t0 the default) pointing at the images in turn, set "other" (t0 and t1 only) and a
// map "m" of `w` x `h` cells using "s".
make_world :: proc(terrains := 5, w := 6, h := 4) -> ^cm.World {
	world := new(cm.World)
	cm.world_reset(world)
	cm.world_set_tile_size(world, 4, 4)
	ti := cm.world_add_tileset(world, "t")
	for k in 0 ..< 4 {
		n := cm.tileset_insert_blank(&world.tilesets[ti], k, "i")
		cm.image4_set(&world.tilesets[ti].images[n], k, 0, k + 1)
	}
	si := cm.world_add_terrain_set(world, "s")
	for k in 0 ..< terrains {
		if k > 0 {
			cm.world_add_terrain(world, si)
		}
		t := &world.sets[si].terrains[k]
		cm.name_assign(&t.name, k < 10 ? string([]u8{'t', u8('0' + k)}) : "tt")
		if k >= 10 {
			cm.name_assign(&t.name, "tt")
			t.name.text[2] = u8('a' + k % 26)
			t.name.text[3] = u8('a' + k / 26)
			t.name.len = 4
		}
		cm.name_assign(&t.image, cm.tileset_name(&world.tilesets[ti], k % 4))
	}
	oi := cm.world_add_terrain_set(world, "other")
	cm.world_add_terrain(world, oi)
	cm.name_assign(&world.sets[oi].terrains[0].name, "t0")
	cm.name_assign(&world.sets[oi].terrains[1].name, "t1")
	mi := cm.world_add_map(world, si, "m")
	cm.world_map_set_size(world, mi, w, h)
	return world
}

new_editor :: proc(terrains := 5, w := 6, h := 4) -> (e: ^Editor, world: ^cm.World) {
	world = make_world(terrains, w, h)
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

mouse :: proc(e: ^Editor, x, y: int, down: bool, button := cm.Mouse_Button.Left) {
	editor_handle_event(e, cm.Mouse_Button_Event{button = button, x = x, y = y, down = down})
}

click_at :: proc(e: ^Editor, x, y: int) {
	mouse(e, x, y, true)
	mouse(e, x, y, false)
}

click_rect :: proc(e: ^Editor, rc: Rect) {
	click_at(e, rc.x + rc.w / 2, rc.y + rc.h / 2)
}

click_cell :: proc(e: ^Editor, x, y: int) {
	m := current_map(e)
	rc := cell_rect(e, x, y)
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

cell :: proc(e: ^Editor, x, y: int) -> int {
	return int(current_map(e).cells[y][x])
}

@(test)
test_begin_starts_in_draw_with_the_default_terrain :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	world.sets[0].default = 2
	editor_begin(e, world, 0)
	testing.expect(t, e.mode == .Draw && e.terrain == 2 && e.cx == 0 && e.cy == 0 && !e.dirty && !e.exit_requested)
	testing.expect_value(t, terrain_name(e, 2), "t2")
	testing.expect_value(t, terrain_count(e), 5)
}

@(test)
test_the_cursor_moves_and_stops_at_the_edges :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	press(e, .Up, .Left)
	testing.expect(t, e.cx == 0 && e.cy == 0)
	for _ in 0 ..< 20 {
		press(e, .Right, .Down)
	}
	testing.expect(t, e.cx == 5 && e.cy == 3)
	press(e, .Left, .Up)
	testing.expect(t, e.cx == 4 && e.cy == 2)
}

@(test)
test_green_paints_with_the_current_terrain_and_marks_the_map_changed :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	press(e, .Green) // already the default there
	testing.expect(t, !e.dirty)
	e.terrain = 3
	press(e, .Green)
	testing.expect(t, e.dirty && cell(e, 0, 0) == 3)
	press(e, .Right, .Green)
	testing.expect(t, cell(e, 1, 0) == 3 && cell(e, 2, 0) == 0)
	testing.expect_value(t, world.maps[0].cells[0][1], 3) // edited in the world itself
}

@(test)
test_red_leaves_and_yellow_opens_setup :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	press(e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Setup)
	press(e, .Blue) // steps the terrain by 16 in Setup too (5 terrains: wraps to 1)
	testing.expect_value(t, e.terrain, 1)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Draw)
	testing.expect(t, !e.exit_requested)
	press(e, .Red)
	testing.expect(t, e.exit_requested)
}

@(test)
test_terrain_steps_wrap_and_blue_pages :: proc(t: ^testing.T) {
	e, world := new_editor(40)
	defer free_both(e, world)
	goto_row(e, .Terrain)
	press(e, .Left)
	testing.expect_value(t, e.terrain, 39)
	press(e, .Right)
	testing.expect_value(t, e.terrain, 0)
	press(e, .Blue)
	testing.expect_value(t, e.terrain, 16)
	press(e, .Blue, .Blue)
	testing.expect_value(t, e.terrain, 8) // 48 wraps to 8
	e.mode = .Draw
	press(e, .Blue)
	testing.expect_value(t, e.terrain, 24)
}

@(test)
test_columns_and_rows_resize_the_map_with_default_cells :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	e.cx, e.cy = 5, 3
	goto_row(e, .Columns)
	press(e, .Left, .Left)
	testing.expect(t, current_map(e).width == 4 && e.cx == 3 && e.dirty) // the cursor stays inside
	press(e, .Right)
	testing.expect_value(t, cell(e, 4, 0), 0)
	goto_row(e, .Rows)
	for _ in 0 ..< 70 {
		press(e, .Right)
	}
	testing.expect_value(t, current_map(e).height, cm.MAP_MAX)
	for _ in 0 ..< 70 {
		press(e, .Left)
	}
	testing.expect_value(t, current_map(e).height, 1)
	testing.expect_value(t, e.cy, 0)
}

@(test)
test_changing_the_set_keeps_terrains_by_name_or_refuses :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	current_map(e).cells[0][1] = 3 // t3 is not in "other"
	e.terrain = 3
	goto_row(e, .Set)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&current_map(e).set), "s") // refused
	testing.expect(t, strings.contains(e.note, "other") && strings.contains(e.note, "t3") && cm.text_is_drawable(e.note))
	testing.expect(t, cm.text_width(e.note) + INFO_X <= cm.SCREEN_W - 2)
	testing.expect(t, !e.dirty)
	for y in 0 ..< 4 { 	// now every cell is t0 or t1
		for x in 0 ..< 6 {
			current_map(e).cells[y][x] = u8((x + y) % 2)
		}
	}
	e.terrain = 4 // not in the other set: falls back to its default
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&current_map(e).set), "other")
	testing.expect(t, e.dirty && e.terrain == 0)
	e.terrain = 1
	press(e, .Right) // wraps back to "s"; t1 exists there
	testing.expect_value(t, cm.name_str(&current_map(e).set), "s")
	testing.expect_value(t, e.terrain, 1)
	// With a single set there is nothing to change to.
	cm.world_delete_terrain_set(world, 1)
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_ONE_SET)
}

@(test)
test_flips_and_rotations :: proc(t: ^testing.T) {
	e, world := new_editor(5, 3, 3)
	defer free_both(e, world)
	m := current_map(e)
	for y in 0 ..< 3 {
		for x in 0 ..< 3 {
			m.cells[y][x] = u8(y * 3 + x) % 5
		}
	}
	run(e, .Flip_Horizontal)
	testing.expect(t, e.dirty && m.cells[0][0] == 2 && m.cells[0][2] == 0)
	run(e, .Flip_Horizontal)
	run(e, .Rotate_Right)
	testing.expect_value(t, m.cells[0][2], 0) // the top row became the right column
	run(e, .Rotate_Left)
	testing.expect_value(t, m.cells[0][0], 0)
	run(e, .Rotate_180)
	testing.expect(t, m.cells[2][2] == 0)
	run(e, .Flip_Vertical)
	testing.expect(t, m.cells[0][2] == 0)
	cm.world_map_set_size(world, 0, 4, 3)
	e.note = ""
	run(e, .Rotate_Left)
	testing.expect_value(t, e.note, NOTE_NO_TURN)
	testing.expect_value(t, m.width, 4)
}

@(test)
test_flood_returns_to_drawing_and_reports_nothing_to_do :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	e.terrain = 0
	run(e, .Flood_Fill) // already terrain 0 everywhere
	testing.expect(t, e.note == NOTE_SAME_FILL && e.mode == .Setup && !e.dirty)
	e.terrain = 2
	press(e, .Up) // clears the note
	e.row = .Flood_Fill
	press(e, .Green)
	testing.expect(t, e.mode == .Draw && e.dirty && cell(e, 5, 3) == 2)
	run(e, .Replace)
	testing.expect_value(t, e.note, NOTE_SAME_REPLACE)
	e.terrain = 4
	press(e, .Up)
	e.row = .Replace
	press(e, .Green)
	testing.expect(t, e.mode == .Setup && cell(e, 0, 0) == 4)
	e.terrain = 4
	run(e, .Clear)
	testing.expect_value(t, e.note, NOTE_SAME_CLEAR)
	e.terrain = 1
	press(e, .Up)
	e.row = .Clear
	press(e, .Green)
	testing.expect(t, cell(e, 3, 2) == 1 && cell(e, 0, 0) == 1)
}

@(test)
test_rectangles_by_keyboard :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	e.terrain = 3
	e.cx, e.cy = 1, 1
	run(e, .Frame)
	testing.expect_value(t, e.mode, Mode.Rect)
	press(e, .Right, .Right, .Down)
	press(e, .Green)
	testing.expect(t, e.mode == .Draw && cell(e, 1, 1) == 3 && cell(e, 3, 2) == 3 && cell(e, 2, 1) == 3)
	e.terrain = 2
	run(e, .Fill)
	press(e, .Left)
	press(e, .Red) // cancels
	testing.expect(t, e.mode == .Draw && e.shape == .None && e.dirty)
	testing.expect_value(t, cell(e, 1, 1), 3)
	run(e, .Fill)
	press(e, .Green)
	testing.expect_value(t, cell(e, 2, 2), 2) // a one-cell rectangle paints just that cell
}

@(test)
test_mouse_paints_drags_and_picks :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	e.terrain = 2
	m := current_map(e)
	rc := cell_rect(e, 1, 1)
	mouse(e, rc.x + 1, rc.y + 1, true)
	testing.expect(t, cell(e, 1, 1) == 2 && e.cx == 1 && e.cy == 1)
	rc2 := cell_rect(e, 3, 1)
	editor_handle_event(e, cm.Mouse_Move{rc2.x + 1, rc2.y + 1})
	testing.expect(t, cell(e, 3, 1) == 2)
	mouse(e, rc2.x, rc2.y, false)
	rc3 := cell_rect(e, 4, 1)
	editor_handle_event(e, cm.Mouse_Move{rc3.x + 1, rc3.y + 1}) // no longer painting
	testing.expect_value(t, cell(e, 4, 1), 0)
	// Right click takes the terrain under the pointer and shows it in Setup.
	rc4 := cell_rect(e, 1, 1)
	e.terrain = 0
	mouse(e, rc4.x + 1, rc4.y + 1, true, .Right)
	testing.expect(t, e.terrain == 2 && e.mode == .Setup && e.row == .Terrain)
	// ... and so does the picker (right click or left click).
	mouse(e, picker_rect(4).x + 1, picker_rect(4).y + 1, true, .Right)
	testing.expect_value(t, e.terrain, 4)
	click_at(e, picker_rect(1).x + 3, picker_rect(1).y + 3)
	testing.expect_value(t, e.terrain, 1)
	click_at(e, picker_rect(9).x + 3, picker_rect(9).y + 3) // empty slot: nothing
	testing.expect_value(t, e.terrain, 1)
}

@(test)
test_picker_shows_the_page_of_the_current_terrain :: proc(t: ^testing.T) {
	e, world := new_editor(40)
	defer free_both(e, world)
	e.terrain = 20 // page 1 holds terrains 16..31
	i, ok := picker_terrain_at(e, picker_rect(0).x, picker_rect(0).y)
	testing.expect(t, ok && i == 16)
	i, ok = picker_terrain_at(e, picker_rect(15).x + 2, picker_rect(15).y + 2)
	testing.expect(t, ok && i == 31)
	e.terrain = 39 // the last page holds only 32..39
	_, ok = picker_terrain_at(e, picker_rect(8).x, picker_rect(8).y)
	testing.expect(t, !ok)
	// The gap between thumbnails belongs to the one before it.
	i, ok = picker_terrain_at(e, picker_rect(1).x - 1, picker_rect(1).y)
	testing.expect(t, ok && i == 32)
	// The wheel over the picker pages through the terrains.
	e.terrain = 3
	editor_handle_event(e, cm.Mouse_Move{picker_rect(2).x, picker_rect(2).y})
	editor_handle_event(e, cm.Mouse_Wheel{dy = -1})
	testing.expect_value(t, e.terrain, 19)
	editor_handle_event(e, cm.Mouse_Wheel{dy = 1})
	testing.expect_value(t, e.terrain, 3)
	editor_handle_event(e, cm.Mouse_Move{5, 5}) // not over the picker: nothing
	editor_handle_event(e, cm.Mouse_Wheel{dy = -1})
	testing.expect_value(t, e.terrain, 3)
}

@(test)
test_armed_mouse_tools :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	m := current_map(e)
	e.terrain = 2
	click_rect(e, FRAME_BUTTON)
	testing.expect(t, e.shape == .Frame && e.mode == .Draw)
	rc := cell_rect(e, 1, 0)
	mouse(e, rc.x + 1, rc.y + 1, true)
	testing.expect(t, e.rect_drag && e.mode == .Rect)
	rc2 := cell_rect(e, 4, 2)
	editor_handle_event(e, cm.Mouse_Move{rc2.x + 1, rc2.y + 1})
	mouse(e, rc2.x + 1, rc2.y + 1, false)
	testing.expect(t, e.shape == .None && e.mode == .Draw && cell(e, 1, 0) == 2 && cell(e, 4, 2) == 2 && cell(e, 2, 1) == 0)
	click_rect(e, FLOOD_BUTTON)
	testing.expect_value(t, e.point_tool, Point_Tool.Flood_Fill)
	click_rect(e, FLOOD_BUTTON) // again disarms
	testing.expect_value(t, e.point_tool, Point_Tool.None)
	click_rect(e, FLOOD_BUTTON)
	e.terrain = 4
	click_cell(e, 2, 1) // the inside of the frame
	testing.expect(t, cell(e, 2, 1) == 4 && cell(e, 3, 1) == 4 && cell(e, 0, 0) == 0 && e.point_tool == .None)
	click_rect(e, REPLACE_BUTTON)
	e.terrain = 3
	click_cell(e, 2, 1)
	testing.expect(t, cell(e, 2, 1) == 3 && cell(e, 1, 0) == 2)
	click_rect(e, FILL_BUTTON)
	press(e, .Red) // red disarms
	testing.expect_value(t, e.shape, cm.Shape.None)
	testing.expect(t, !e.exit_requested)
}

@(test)
test_buttons_run_their_rows_and_back_leaves :: proc(t: ^testing.T) {
	e, world := new_editor(5, 3, 3)
	defer free_both(e, world)
	m := current_map(e)
	m.cells[0][0] = 1
	click_rect(e, FLIP_H_BUTTON)
	testing.expect(t, m.cells[0][2] == 1 && e.row == .Flip_Horizontal && e.mode == .Setup)
	click_rect(e, FLIP_V_BUTTON)
	testing.expect(t, m.cells[2][2] == 1)
	click_rect(e, ROT_R_BUTTON)
	testing.expect(t, m.cells[2][0] == 1)
	click_rect(e, ROT_L_BUTTON)
	testing.expect(t, m.cells[2][2] == 1)
	click_rect(e, ROT_180_BUTTON)
	testing.expect(t, m.cells[0][0] == 1)
	e.terrain = 3
	click_rect(e, CLEAR_BUTTON)
	testing.expect(t, m.cells[1][1] == 3 && e.row == .Clear)
	click_rect(e, TERRAIN_PLUS)
	testing.expect_value(t, e.terrain, 4)
	click_rect(e, TERRAIN_MINUS)
	click_rect(e, TERRAIN_MINUS)
	testing.expect_value(t, e.terrain, 2)
	click_rect(e, COLUMNS_PLUS)
	click_rect(e, ROWS_MINUS)
	testing.expect(t, m.width == 4 && m.height == 2)
	click_rect(e, COLUMNS_MINUS)
	click_rect(e, ROWS_PLUS)
	testing.expect(t, m.width == 3 && m.height == 3)
	click_rect(e, SET_PLUS) // "other" lacks t3 and t4, which the map's cells use
	testing.expect(t, cm.name_str(&m.set) == "s" && e.note != "")
	click_rect(e, BACK_BUTTON)
	testing.expect(t, e.exit_requested)
}

@(test)
test_a_note_clears_on_the_next_input_but_not_on_mouse_movement :: proc(t: ^testing.T) {
	e, world := new_editor()
	defer free_both(e, world)
	run(e, .Flood_Fill)
	testing.expect_value(t, e.note, NOTE_SAME_FILL)
	editor_handle_event(e, cm.Mouse_Move{3, 3})
	mouse(e, 0, 0, false)
	testing.expect_value(t, e.note, NOTE_SAME_FILL)
	press(e, .Up)
	testing.expect_value(t, e.note, "")
}

// --- Parity ---

Input_Method :: enum {
	Commands,
	Mouse,
}

@(test)
test_every_terrain_can_be_chosen_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for target in ([]int{0, 1, 15, 16, 17, 100, 255}) {
			e, world := new_editor(256)
			switch m {
			case .Commands:
				goto_row(e, .Terrain)
				for _ in 0 ..< target / PICKER_PAGE {
					press(e, .Blue)
				}
				for _ in 0 ..< target % PICKER_PAGE {
					press(e, .Right)
				}
			case .Mouse:
				e.terrain = target / PICKER_PAGE * PICKER_PAGE // the page: reachable with the wheel
				for _ in 0 ..< 20 {
					editor_handle_event(e, cm.Mouse_Move{picker_rect(0).x, picker_rect(0).y})
				}
				e.terrain = 0
				for _ in 0 ..< target / PICKER_PAGE {
					editor_handle_event(e, cm.Mouse_Wheel{dy = -1})
				}
				click_at(e, picker_rect(target % PICKER_PAGE).x + 2, picker_rect(target % PICKER_PAGE).y + 2)
			}
			ok := e.terrain == target
			free_both(e, world)
			testing.expectf(t, ok, "%v could not choose terrain %d", m, target)
		}
	}
}

@(test)
test_every_cell_can_be_painted_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for size in ([][2]int{{1, 1}, {6, 4}, {64, 64}, {33, 7}}) {
			e, world := new_editor(5, size[0], size[1])
			e.terrain = 3
			for y in 0 ..< size[1] {
				for x in 0 ..< size[0] {
					switch m {
					case .Commands:
						e.cx, e.cy = 0, 0
						for _ in 0 ..< x {
							press(e, .Right)
						}
						for _ in 0 ..< y {
							press(e, .Down)
						}
						press(e, .Green)
					case .Mouse:
						click_cell(e, x, y)
					}
				}
			}
			ok := true
			for y in 0 ..< size[1] {
				for x in 0 ..< size[0] {
					ok &&= cell(e, x, y) == 3
				}
			}
			free_both(e, world)
			testing.expectf(t, ok, "%v could not paint a %d x %d map", m, size[0], size[1])
		}
	}
}

@(test)
test_every_size_is_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for w in ([]int{1, 2, 33, 64} ) {
			for h in ([]int{1, 17, 64}) {
				e, world := new_editor()
				switch m {
				case .Commands:
					goto_row(e, .Columns)
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
						click_rect(e, COLUMNS_MINUS)
						click_rect(e, ROWS_MINUS)
					}
					for _ in 0 ..< w - 1 {
						click_rect(e, COLUMNS_PLUS)
					}
					for _ in 0 ..< h - 1 {
						click_rect(e, ROWS_PLUS)
					}
				}
				ok := current_map(e).width == w && current_map(e).height == h
				free_both(e, world)
				testing.expectf(t, ok, "%v: wanted %d x %d", m, w, h)
			}
		}
	}
}

@(test)
test_every_tool_is_reachable_by_each_input :: proc(t: ^testing.T) {
	buttons_for := [Setup_Row]Rect {
		.Terrain         = TERRAIN_PLUS,
		.Columns         = COLUMNS_PLUS,
		.Rows            = ROWS_PLUS,
		.Set             = SET_PLUS,
		.Zoom            = ZOOM_PLUS,
		.Flip_Horizontal = FLIP_H_BUTTON,
		.Flip_Vertical   = FLIP_V_BUTTON,
		.Rotate_Left     = ROT_L_BUTTON,
		.Rotate_Right    = ROT_R_BUTTON,
		.Rotate_180      = ROT_180_BUTTON,
		.Frame           = FRAME_BUTTON,
		.Fill            = FILL_BUTTON,
		.Flood_Fill      = FLOOD_BUTTON,
		.Replace         = REPLACE_BUTTON,
		.Clear           = CLEAR_BUTTON,
	}
	for row in Setup_Row {
		found := false
		for b in buttons() {
			if b.rc == buttons_for[row] {
				found = true
			}
		}
		if row == .Terrain || row == .Columns || row == .Rows || row == .Set || row == .Zoom {
			continue // these have - and + buttons beside the value
		}
		testing.expectf(t, found, "%v has no button", row)
	}
	// Frame by each input: the same rectangle.
	results: [Input_Method][6]int
	for m in Input_Method {
		e, world := new_editor()
		e.terrain = 4
		switch m {
		case .Commands:
			e.cx, e.cy = 1, 1
			run(e, .Frame)
			press(e, .Right, .Right, .Down, .Green)
		case .Mouse:
			click_rect(e, FRAME_BUTTON)
			rc := cell_rect(e, 1, 1)
			mouse(e, rc.x + 1, rc.y + 1, true)
			rc2 := cell_rect(e, 3, 2)
			editor_handle_event(e, cm.Mouse_Move{rc2.x + 1, rc2.y + 1})
			mouse(e, rc2.x + 1, rc2.y + 1, false)
		}
		results[m] = {cell(e, 1, 1), cell(e, 3, 1), cell(e, 1, 2), cell(e, 3, 2), cell(e, 2, 1), cell(e, 0, 0)}
		free_both(e, world)
	}
	testing.expect_value(t, results[.Commands], results[.Mouse])
	testing.expect_value(t, results[.Commands], [6]int{4, 4, 4, 4, 4, 0})
}

// --- Layout, drawing and text ---

@(test)
test_layout_fits_the_screen_and_does_not_overlap :: proc(t: ^testing.T) {
	rects := make([dynamic]Rect, context.temp_allocator)
	append(&rects, CANVAS, BANNER, TERRAIN_MINUS, TERRAIN_PLUS, COLUMNS_MINUS, COLUMNS_PLUS, ROWS_MINUS, ROWS_PLUS, SET_MINUS, SET_PLUS, ZOOM_MINUS, ZOOM_PLUS, VBAR, HBAR)
	append(&rects, Rect{PICKER_X, PICKER_Y, PICKER_COLS * PICKER_PITCH - 1, PICKER_ROWS * PICKER_PITCH - 1})
	for b in buttons() {
		append(&rects, b.rc)
		testing.expectf(t, cm.text_width(b.txt) <= b.rc.w - 2 && cm.GLYPH_H <= b.rc.h && cm.text_is_drawable(b.txt), "label %s does not fit its button", b.txt)
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
	// The value text of every row fits right of its buttons, and the help clears the buttons.
	testing.expect(t, ROW_VALUE_X > SET_PLUS.x + SET_PLUS.w && ROW_LABEL_X + cm.text_width("COLUMNS") < COLUMNS_MINUS.x)
	testing.expect(t, ROW_VALUE_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W - 2) // VALUE_CHARS wide
	testing.expect(t, HELP_Y >= BACK_BUTTON.y + BACK_BUTTON.h && HELP_Y + MAX_HELP_LINES * cm.LINE_ADVANCE <= cm.SCREEN_H)
	testing.expect(t, ROW_MARKER_X + cm.text_width(">") < ROW_LABEL_X)
}

@(test)
test_picker_geometry_round_trips :: proc(t: ^testing.T) {
	for slot in 0 ..< PICKER_PAGE {
		rc := picker_rect(slot)
		for p in ([][2]int{{0, 0}, {PICKER_THUMB - 1, PICKER_THUMB - 1}, {PICKER_THUMB, PICKER_THUMB}}) {
			got, ok := picker_slot_at(rc.x + p.x, rc.y + p.y)
			testing.expectf(t, ok && got == slot, "slot %d point %v", slot, p)
		}
	}
	_, ok := picker_slot_at(PICKER_X - 1, PICKER_Y)
	testing.expect(t, !ok)
	_, ok = picker_slot_at(PICKER_X + PICKER_COLS * PICKER_PITCH, PICKER_Y)
	testing.expect(t, !ok)
	_, ok = picker_slot_at(PICKER_X, PICKER_Y + PICKER_ROWS * PICKER_PITCH)
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
		if round == 1 { 	// the longest labels allowed
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for mode in Mode {
			for armed in 0 ..< 4 {
				e.mode = mode
				e.shape = armed == 1 ? .Frame : (armed == 2 ? .Fill : .None)
				e.point_tool = armed == 3 ? .Flood_Fill : .None
				text := banner_text(e)
				if round == 0 {
					testing.expectf(t, cm.text_is_drawable(text), "banner: %s", text)
				}
				testing.expectf(t, cm.text_width(text) + 8 <= BANNER.w, "banner too wide: %s", text)
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
	}
	for note in ([]string{NOTE_SAME_FILL, NOTE_SAME_REPLACE, NOTE_SAME_CLEAR, NOTE_NO_TURN, NOTE_ONE_SET}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 2, "note: %s", note)
	}
	// The readout with the longest names.
	testing.expect(t, cm.text_is_drawable("CURSOR: 63,63  *"))
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
test_every_screen_draws_on_screen_in_every_mode_and_size :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	for size in ([][2]int{{1, 1}, {6, 4}, {64, 64}, {64, 5}, {5, 64}, {33, 33}}) {
		e, world := new_editor(256, size[0], size[1])
		// A busy map: every cell different, and tiles with every colour.
		for y in 0 ..< size[1] {
			for x in 0 ..< size[0] {
				current_map(e).cells[y][x] = u8((x * 7 + y * 3) % 256)
			}
		}
		for k in 0 ..< 16 {
			world.sets[0].terrains[k].solid = k % 2 == 0
		}
		cm.name_assign(&world.sets[0].terrains[3].image, "nope") // not set: drawn dark red
		e.cx, e.cy = size[0] - 1, size[1] - 1
		for mode in Mode {
			e.mode = mode
			e.shape = mode == .Rect ? .Fill : .None
			e.ax, e.ay = 0, 0
			for terrain in ([]int{0, 100, 255}) {
				e.terrain = terrain
				log = {}
				editor_draw(e, &r)
				testing.expectf(t, log.out_of_bounds == 0, "%dx%d %v: %d rects off screen", size[0], size[1], mode, log.out_of_bounds)
				testing.expect_value(t, log.presents, 1)
				testing.expectf(t, log.rects < 40000, "%dx%d %v: %d rects is too many for one frame", size[0], size[1], mode, log.rects)
			}
		}
		free_both(e, world)
	}
}

// --- Zoom and scrolling ---

@(test)
test_zoom_steps_through_fit_and_the_pixel_sizes :: proc(t: ^testing.T) {
	e, world := new_editor(5, 40, 40)
	defer free_both(e, world)
	testing.expect(t, e.zoom == 0 && view_cell(e) == 3) // 140 / 40
	vw, vh := view_size(e)
	testing.expect(t, vw == 40 && vh == 40 && !bar_shown(e, .Horizontal) && !bar_shown(e, .Vertical))
	goto_row(e, .Zoom)
	press(e, .Right)
	testing.expect(t, e.zoom == 1 && view_cell(e) == 4)
	vw, vh = view_size(e)
	testing.expect(t, vw == 35 && vh == 35 && bar_shown(e, .Horizontal) && bar_shown(e, .Vertical))
	for _ in 0 ..< 20 {
		press(e, .Right)
	}
	testing.expect(t, e.zoom == 7 && view_cell(e) == 32)
	vw, vh = view_size(e)
	testing.expect_value(t, vw, 4)
	for _ in 0 ..< 20 {
		press(e, .Left)
	}
	testing.expect_value(t, e.zoom, 0)
	// A small map never shows scroll bars, and the zoom cannot show more than the map.
	small, w2 := new_editor(5, 6, 4)
	defer free_both(small, w2)
	goto_row(small, .Zoom)
	press(small, .Right, .Right)
	vw, vh = view_size(small)
	testing.expect(t, vw == 6 && vh == 4 && !bar_shown(small, .Horizontal))
}

@(test)
test_the_view_follows_the_cursor :: proc(t: ^testing.T) {
	e, world := new_editor(5, 40, 40)
	defer free_both(e, world)
	e.zoom = 7 // 32 px: 4 x 4 cells
	press(e, .Right, .Right, .Right)
	testing.expect_value(t, e.vx, 0)
	press(e, .Right)
	testing.expect(t, e.cx == 4 && e.vx == 1)
	for _ in 0 ..< 60 {
		press(e, .Right, .Down)
	}
	testing.expect(t, e.cx == 39 && e.vx == 36 && e.vy == 36) // stops at the last full window
	for _ in 0 ..< 60 {
		press(e, .Left, .Up)
	}
	testing.expect(t, e.cx == 0 && e.vx == 0 && e.vy == 0)
	// Zooming keeps the cursor visible and roughly centred.
	e.cx, e.cy = 20, 20
	e.zoom = 0
	goto_row(e, .Zoom)
	press(e, .Right, .Right, .Right, .Right, .Right, .Right, .Right)
	testing.expect(t, cell_visible(e, 20, 20) && e.vx >= 18 && e.vx <= 19)
	// Shrinking the map keeps the view valid.
	goto_row(e, .Columns)
	for _ in 0 ..< 36 {
		press(e, .Left)
	}
	testing.expect(t, current_map(e).width == 4 && e.vx == 0 && cell_visible(e, e.cx, e.cy))
}

@(test)
test_cells_are_found_and_drawn_relative_to_the_view :: proc(t: ^testing.T) {
	e, world := new_editor(5, 40, 40)
	defer free_both(e, world)
	e.zoom = 7
	e.vx, e.vy = 10, 20
	x, y, ok := cell_at(e, CANVAS.x + 1, CANVAS.y + 1)
	testing.expect(t, ok && x == 10 && y == 20)
	x, y, ok = cell_at(e, CANVAS.x + 3 * 32 + 5, CANVAS.y + 2 * 32)
	testing.expect(t, ok && x == 13 && y == 22)
	_, _, ok = cell_at(e, CANVAS.x + 4 * 32, CANVAS.y) // the view is 4 cells wide
	testing.expect(t, !ok)
	rc := cell_rect(e, 11, 21)
	testing.expect(t, rc.x == CANVAS.x + 32 && rc.y == CANVAS.y + 32 && rc.w == 32)
	testing.expect(t, cell_visible(e, 13, 23) && !cell_visible(e, 14, 20) && !cell_visible(e, 9, 20))
	// A click paints the cell it shows, not the one at the same place when zoomed out.
	e.terrain = 3
	click_cell(e, 12, 21)
	testing.expect_value(t, cell(e, 12, 21), 3)
	testing.expect_value(t, cell(e, 2, 1), 0)
}

@(test)
test_the_wheel_zooms_over_the_map :: proc(t: ^testing.T) {
	e, world := new_editor(5, 40, 40)
	defer free_both(e, world)
	editor_handle_event(e, cm.Mouse_Move{CANVAS.x + 20, CANVAS.y + 20})
	editor_handle_event(e, cm.Mouse_Wheel{dy = 1})
	testing.expect_value(t, e.zoom, 1)
	editor_handle_event(e, cm.Mouse_Wheel{dy = 3})
	testing.expect_value(t, e.zoom, 4)
	editor_handle_event(e, cm.Mouse_Wheel{dy = -1})
	testing.expect_value(t, e.zoom, 3)
	editor_handle_event(e, cm.Mouse_Wheel{dy = -20})
	testing.expect_value(t, e.zoom, 0)
	editor_handle_event(e, cm.Mouse_Move{5, 5}) // outside the map: nothing
	editor_handle_event(e, cm.Mouse_Wheel{dy = 1})
	testing.expect_value(t, e.zoom, 0)
	click_rect(e, ZOOM_PLUS)
	click_rect(e, ZOOM_PLUS)
	testing.expect(t, e.zoom == 2 && e.mode == .Setup && e.row == .Zoom)
	click_rect(e, ZOOM_MINUS)
	testing.expect_value(t, e.zoom, 1)
}

@(test)
test_scroll_bars_jump_and_drag :: proc(t: ^testing.T) {
	e, world := new_editor(5, 40, 40)
	defer free_both(e, world)
	e.zoom = 7 // 4 x 4 cells of 40: a long way to scroll
	// The thumb grows with the view and moves with the origin.
	start, size := bar_thumb(40, 4, 0, HBAR.w)
	testing.expect(t, start == 0 && size == 14)
	start, size = bar_thumb(40, 4, 36, HBAR.w)
	testing.expect(t, start + size == HBAR.w)
	// Clicking the track centres the thumb there; dragging follows the pointer.
	click_at(e, HBAR.x + HBAR.w / 2, HBAR.y + 1)
	testing.expect(t, e.vx >= 17 && e.vx <= 19 && e.vy == 0)
	mouse(e, HBAR.x + 10, HBAR.y + 1, true)
	testing.expect(t, e.bar_drag == Bar.Horizontal)
	editor_handle_event(e, cm.Mouse_Move{HBAR.x + HBAR.w + 30, 100}) // beyond the end: clamped
	testing.expect_value(t, e.vx, 36)
	editor_handle_event(e, cm.Mouse_Move{HBAR.x - 30, 3})
	testing.expect_value(t, e.vx, 0)
	mouse(e, HBAR.x, HBAR.y, false)
	testing.expect(t, e.bar_drag == nil)
	editor_handle_event(e, cm.Mouse_Move{HBAR.x + 100, 3}) // no longer dragging
	testing.expect_value(t, e.vx, 0)
	click_at(e, VBAR.x + 1, VBAR.y + VBAR.h - 1)
	testing.expect_value(t, e.vy, 36)
	// Dragging a bar does not paint or move the cursor; the bars are hidden when the map fits.
	testing.expect(t, e.cx == 0 && e.cy == 0 && cell(e, 0, 0) == 0 && !e.dirty)
	e.zoom = 0
	e.vx = 0
	click_at(e, HBAR.x + 50, HBAR.y + 1) // bar hidden at 3 px cells? still too big: it is shown
	small, w2 := new_editor(5, 6, 4)
	defer free_both(small, w2)
	click_at(small, HBAR.x + 50, HBAR.y + 1)
	testing.expect(t, small.vx == 0 && !small.dirty)
}

@(test)
test_bar_origin_round_trips :: proc(t: ^testing.T) {
	for total in ([]int{5, 33, 64}) {
		for view in ([]int{1, 4, 35}) {
			if view >= total {
				continue
			}
			for origin in 0 ..= total - view {
				start, size := bar_thumb(total, view, origin, 140)
				got := bar_origin(total, view, 140, start + size / 2)
				testing.expectf(t, abs(got - origin) <= 1 + total / 70, "total %d view %d: origin %d came back as %d", total, view, origin, got)
				testing.expect(t, start >= 0 && start + size <= 140)
			}
		}
	}
}

@(test)
test_every_cell_of_a_big_map_can_be_painted_by_each_input_at_every_zoom :: proc(t: ^testing.T) {
	for m in Input_Method {
		for zoom in ([]int{0, 3, 7}) {
			e, world := new_editor(5, 64, 64)
			e.terrain = 2
			e.zoom = zoom
			for target in ([][2]int{{0, 0}, {63, 63}, {63, 0}, {0, 63}, {31, 40}}) {
				switch m {
				case .Commands:
					for e.cx > target.x {
						press(e, .Left)
					}
					for e.cx < target.x {
						press(e, .Right)
					}
					for e.cy > target.y {
						press(e, .Up)
					}
					for e.cy < target.y {
						press(e, .Down)
					}
					press(e, .Green)
				case .Mouse:
					// Scroll the cell into view with the bars, then click it.
					vw, vh := view_size(e)
					if bar_shown(e, .Horizontal) {
						click_at(e, HBAR.x + (HBAR.w * target.x) / 64, HBAR.y + 1)
					}
					if bar_shown(e, .Vertical) {
						click_at(e, VBAR.x + 1, VBAR.y + (VBAR.h * target.y) / 64)
					}
					_ = vw
					_ = vh
					e.vx = clamp(e.vx, 0, 64 - vw) // (the bars may land a cell short of the target)
					if !cell_visible(e, target.x, target.y) {
						e.vx = clamp(target.x - vw / 2, 0, 64 - vw)
						e.vy = clamp(target.y - vh / 2, 0, 64 - vh)
					}
					click_cell(e, target.x, target.y)
				}
			}
			ok := true
			for target in ([][2]int{{0, 0}, {63, 63}, {63, 0}, {0, 63}, {31, 40}}) {
				ok &&= cell(e, target.x, target.y) == 2
			}
			free_both(e, world)
			testing.expectf(t, ok, "%v at zoom %d could not paint every corner", m, zoom)
		}
	}
}

@(test)
test_zoomed_screens_draw_on_screen :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	for zoom in 0 ..< 8 {
		for size in ([][2]int{{64, 64}, {64, 3}, {2, 64}, {33, 17}}) {
			e, world := new_editor(256, size[0], size[1])
			for y in 0 ..< size[1] {
				for x in 0 ..< size[0] {
					current_map(e).cells[y][x] = u8((x * 7 + y * 3) % 256)
				}
			}
			e.zoom = zoom
			for pos in ([][2]int{{0, 0}, {size[0] - 1, size[1] - 1}}) {
				e.cx, e.cy = pos.x, pos.y
				press(e, .Left, .Right) // scrolls to the cursor
				for mode in Mode {
					e.mode = mode
					e.shape = mode == .Rect ? .Frame : .None
					log = {}
					editor_draw(e, &r)
					testing.expectf(t, log.out_of_bounds == 0, "zoom %d %dx%d %v: %d rects off screen", zoom, size[0], size[1], mode, log.out_of_bounds)
					testing.expectf(t, log.rects < 40000, "zoom %d: %d rects", zoom, log.rects)
				}
			}
			free_both(e, world)
		}
	}
}
