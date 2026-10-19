#+build !js
package glyph_editor

import cm "../common"
import "core:testing"

press :: proc(e: ^Editor, actions: ..cm.Action) {
	for a in actions {
		editor_handle_event(e, cm.Command{action = a})
	}
}

mouse :: proc(e: ^Editor, x, y: int, down: bool) {
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = down})
}

click_at :: proc(e: ^Editor, x, y: int) {
	mouse(e, x, y, true)
	mouse(e, x, y, false)
}

click_rect :: proc(e: ^Editor, r: Rect) {
	click_at(e, r.x + r.w / 2, r.y + r.h / 2)
}

take_exit :: proc(e: ^Editor) -> bool {
	tl := tool(e)
	return tl.take_exit(tl.data)
}

center_of_cell :: proc(e: ^Editor, x, y: int) -> (int, int) {
	r := cell_rect(e.bitmap.width, e.bitmap.height, x, y)
	return r.x + r.w / 2, r.y + r.h / 2
}

@(test)
test_starts_blank_8x8 :: proc(t: ^testing.T) {
	e := editor_init()
	testing.expect(t, e.bitmap.width == 8 && e.bitmap.height == 8)
	testing.expect(t, e.cx == 0 && e.cy == 0 && e.mode == .Draw && !e.dirty)
}

@(test)
test_cursor_moves_and_clamps :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Left, .Up) // already in the corner
	testing.expect(t, e.cx == 0 && e.cy == 0)
	press(&e, .Right, .Right, .Down)
	testing.expect(t, e.cx == 2 && e.cy == 1)
	for _ in 0 ..< 20 {
		press(&e, .Right, .Down)
	}
	testing.expect(t, e.cx == 7 && e.cy == 7) // stops at the far edge, no wrap
	testing.expect(t, !e.dirty) // moving changes nothing
}

@(test)
test_green_toggles_pixel_under_cursor :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Right, .Down, .Green)
	testing.expect(t, cm.bitmap_get(&e.bitmap, 1, 1) && e.dirty)
	testing.expect(t, !cm.bitmap_get(&e.bitmap, 0, 0)) // only that pixel
	press(&e, .Green)
	testing.expect(t, !cm.bitmap_get(&e.bitmap, 1, 1)) // toggles back
}

@(test)
test_size_mode_resizes_and_clamps_cursor :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Size)
	press(&e, .Right, .Right, .Up)
	testing.expect(t, e.bitmap.width == 10 && e.bitmap.height == 9 && e.dirty)
	press(&e, .Left, .Down, .Down)
	testing.expect(t, e.bitmap.width == 9 && e.bitmap.height == 7)
	// The d-pad resizes in Size mode; it does not move the cursor.
	testing.expect(t, e.cx == 0 && e.cy == 0)
	// Shrinking pulls the cursor inside.
	press(&e, .Red) // Draw
	for _ in 0 ..< 10 {
		press(&e, .Right, .Down)
	}
	testing.expect(t, e.cx == 8 && e.cy == 6)
	press(&e, .Yellow)
	for _ in 0 ..< 10 {
		press(&e, .Left, .Down)
	}
	testing.expect(t, e.bitmap.width == 1 && e.bitmap.height == 1) // stops at the minimum
	testing.expect(t, e.cx == 0 && e.cy == 0)
	for _ in 0 ..< 70 {
		press(&e, .Right, .Up)
	}
	testing.expect(t, e.bitmap.width == cm.BITMAP_MAX && e.bitmap.height == cm.BITMAP_MAX)
}

@(test)
test_resize_at_a_limit_is_not_a_change :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow)
	for _ in 0 ..< 10 {
		press(&e, .Left)
	}
	e.dirty = false
	press(&e, .Left) // already width 1
	testing.expect(t, !e.dirty)
}

@(test)
test_shrinking_then_growing_restores_pixels :: proc(t: ^testing.T) {
	e := editor_init()
	for _ in 0 ..< 7 {
		press(&e, .Right, .Down)
	}
	press(&e, .Green, .Yellow) // set (7,7); open Size
	for _ in 0 ..< 4 {
		press(&e, .Left, .Down)
	}
	testing.expect(t, !cm.bitmap_get(&e.bitmap, 7, 7))
	for _ in 0 ..< 4 {
		press(&e, .Right, .Up)
	}
	testing.expect(t, cm.bitmap_get(&e.bitmap, 7, 7))
}

@(test)
test_file_mode :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Blue, .Green)
	testing.expect(t, e.requests == {.Save} && e.mode == .Draw)
	e.requests = {}
	press(&e, .Blue, .Yellow)
	testing.expect(t, e.requests == {.Load} && e.mode == .Draw)
	e.requests = {}
	press(&e, .Blue, .Red)
	press(&e, .Blue, .Blue)
	testing.expect(t, e.requests == {} && e.mode == .Draw)
	press(&e, .Blue, .Up, .Left, .Right, .Down)
	testing.expect(t, e.mode == .File && e.cx == 0 && e.cy == 0 && e.requests == {}) // d-pad ignored
	// File is reachable from Size too.
	e = editor_init()
	press(&e, .Yellow, .Blue)
	testing.expect_value(t, e.mode, Mode.File)
}

@(test)
test_mouse_click_toggles_and_moves_cursor :: proc(t: ^testing.T) {
	e := editor_init()
	e.mode = .Size
	x, y := center_of_cell(&e, 3, 5)
	click_at(&e, x, y)
	testing.expect(t, cm.bitmap_get(&e.bitmap, 3, 5) && e.cx == 3 && e.cy == 5)
	testing.expect_value(t, e.mode, Mode.Draw)
	click_at(&e, x, y)
	testing.expect(t, !cm.bitmap_get(&e.bitmap, 3, 5))
	// A click just outside the drawn bitmap does nothing.
	e.dirty = false
	click_at(&e, CANVAS.x + 8 * cell_size(8, 8) + 1, CANVAS.y + 2)
	testing.expect(t, !e.dirty)
}

@(test)
test_mouse_drag_paints_the_value_just_set :: proc(t: ^testing.T) {
	e := editor_init()
	x0, y0 := center_of_cell(&e, 1, 1)
	mouse(&e, x0, y0, true) // turns (1,1) on
	for cx in 2 ..= 5 {
		x, y := center_of_cell(&e, cx, 1)
		editor_handle_event(&e, cm.Mouse_Move{x, y})
	}
	mouse(&e, 0, 0, false)
	for cx in 1 ..= 5 {
		testing.expectf(t, cm.bitmap_get(&e.bitmap, cx, 1), "pixel %d should be on", cx)
	}
	// Moving after release paints nothing.
	x, y := center_of_cell(&e, 6, 1)
	editor_handle_event(&e, cm.Mouse_Move{x, y})
	testing.expect(t, !cm.bitmap_get(&e.bitmap, 6, 1))
	// Dragging from an "on" pixel erases.
	mouse(&e, x0, y0, true) // (1,1) -> off
	for cx in 2 ..= 3 {
		x, y := center_of_cell(&e, cx, 1)
		editor_handle_event(&e, cm.Mouse_Move{x, y})
	}
	mouse(&e, 0, 0, false)
	testing.expect(t, !cm.bitmap_get(&e.bitmap, 1, 1) && !cm.bitmap_get(&e.bitmap, 3, 1) && cm.bitmap_get(&e.bitmap, 4, 1))
}

@(test)
test_mouse_size_buttons :: proc(t: ^testing.T) {
	e := editor_init()
	click_rect(&e, WIDTH_PLUS)
	click_rect(&e, WIDTH_PLUS)
	click_rect(&e, HEIGHT_MINUS)
	testing.expect(t, e.bitmap.width == 10 && e.bitmap.height == 7 && e.mode == .Size)
	click_rect(&e, WIDTH_MINUS)
	click_rect(&e, HEIGHT_PLUS)
	click_rect(&e, HEIGHT_PLUS)
	testing.expect(t, e.bitmap.width == 9 && e.bitmap.height == 9)
}

// --- Leaving ---

@(test)
test_red_exits_when_clean_and_goes_back_elsewhere :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow, .Red) // Size -> Draw, not out
	testing.expect(t, !take_exit(&e) && e.mode == .Draw)
	press(&e, .Blue, .Red)
	testing.expect(t, !take_exit(&e) && e.mode == .Draw)
	press(&e, .Red)
	testing.expect(t, take_exit(&e))
	testing.expect(t, !take_exit(&e)) // consumed
}

@(test)
test_unsaved_changes_need_a_second_red :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	press(&e, .Green, .Red)
	testing.expect(t, !take_exit(&e) && e.confirm_exit)
	testing.expect_value(t, banner_text(&e), "UNSAVED   RED: LEAVE ANYWAY")
	press(&e, .Red)
	testing.expect(t, take_exit(&e))
	press(&e, .Red) // dirty still: ask again
	press(&e, .Down) // any other command cancels
	testing.expect(t, !e.confirm_exit)
	press(&e, .Red)
	testing.expect(t, !take_exit(&e))
	editor_mark_saved(&e)
	press(&e, .Red)
	testing.expect(t, take_exit(&e))
}

@(test)
test_menu_button :: proc(t: ^testing.T) {
	e := editor_init()
	click_rect(&e, MENU_BUTTON)
	testing.expect(t, take_exit(&e))
	e.dirty = true
	click_rect(&e, MENU_BUTTON)
	testing.expect(t, !take_exit(&e) && e.confirm_exit)
	x, y := center_of_cell(&e, 0, 0)
	click_at(&e, x, y) // any other click cancels the prompt
	testing.expect(t, !e.confirm_exit)
}

// --- Tool adapter: files and lifecycle ---

@(test)
test_save_load_round_trip_through_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	tl := tool(&e)
	testing.expect_value(t, cm.tool_file_name(&tl), "glyph.json")
	_, saving := tl.take_save(tl.data)
	testing.expect(t, !saving)
	press(&e, .Right, .Green, .Down, .Green, .Yellow, .Left, .Up, .Red, .Blue, .Green)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok)
	tl.saved(tl.data)
	testing.expect(t, !e.dirty)

	other := editor_init()
	otl := tool(&other)
	testing.expect(t, otl.load(otl.data, transmute([]u8)text))
	testing.expect(t, other.bitmap == e.bitmap && !other.dirty)
	testing.expect(t, !otl.load(otl.data, transmute([]u8)string("nope")))
}

@(test)
test_load_clamps_the_cursor_to_the_new_size :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	for _ in 0 ..< 7 {
		press(&e, .Right, .Down)
	}
	tl := tool(&e)
	small := cm.bitmap_make(2, 3)
	testing.expect(t, tl.load(tl.data, transmute([]u8)cm.bitmap_to_json(&small)))
	testing.expect(t, e.cx == 1 && e.cy == 2)
}

@(test)
test_enter_starts_blank_and_loads :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Green, .Yellow, .Right)
	e.confirm_exit, e.exit_requested = true, true
	tl := tool(&e)
	tl.enter(tl.data)
	testing.expect(t, e.bitmap.width == 8 && !cm.bitmap_get(&e.bitmap, 0, 0)) // unsaved edits dropped
	testing.expect(t, e.mode == .Draw && !e.dirty && !e.confirm_exit && !e.exit_requested)
	testing.expect(t, tl.wants_load(tl.data) && !tl.wants_load(tl.data))
}

// --- Labels and layout ---

@(test)
test_text_follows_labels_and_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	lines, _ := help_lines(&e)
	testing.expect_value(t, lines[0], "UP/DOWN/LEFT/RIGHT: MOVE")
	testing.expect_value(t, banner_text(&e), "DRAWING   GREEN: TOGGLE")
	m := cm.default_input_map()
	cm.set_key_name(&m.labels[.Green], "SPACE")
	e.labels = &m
	testing.expect_value(t, banner_text(&e), "DRAWING   SPACE: TOGGLE")
	for a in cm.Action {
		cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW") // longest allowed
	}
	for mode in Mode {
		e.mode = mode
		for confirm in ([]bool{false, true}) {
			e.confirm_exit = confirm
			testing.expectf(t, cm.text_width(banner_text(&e)) + 8 <= BANNER.w, "banner too wide: %v", mode)
		}
		lines, n := help_lines(&e)
		for line in lines[:n] {
			testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
		}
		testing.expect(t, HELP_Y + n * cm.LINE_ADVANCE <= cm.SCREEN_H)
	}
}

@(test)
test_layout_is_on_screen_and_does_not_overlap :: proc(t: ^testing.T) {
	rects := [?]Rect{CANVAS, BANNER, WIDTH_MINUS, WIDTH_PLUS, HEIGHT_MINUS, HEIGHT_PLUS, PREVIEW_FRAME, SAVE_BUTTON, LOAD_BUTTON, MENU_BUTTON}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	testing.expect(t, SIZE_LABEL_X + cm.text_width("HEIGHT") < HEIGHT_MINUS.x) // label clears the buttons
	testing.expect(t, SIZE_VALUE_X > WIDTH_PLUS.x + WIDTH_PLUS.w && SIZE_VALUE_X + cm.text_width("64") <= cm.SCREEN_W)
	testing.expect(t, HELP_Y >= CANVAS.y + CANVAS.h) // help is below the canvas
	testing.expect(t, HELP_Y >= PREVIEW_FRAME.y + PREVIEW_FRAME.h)
	// The preview frame fits the largest bitmap.
	testing.expect(t, PREVIEW_FRAME.w >= cm.BITMAP_MAX + 2 && PREVIEW_FRAME.h >= cm.BITMAP_MAX + 2)
}

@(test)
test_cell_geometry_covers_every_size :: proc(t: ^testing.T) {
	for w in 1 ..= cm.BITMAP_MAX {
		for h in ([]int{1, 7, 33, cm.BITMAP_MAX}) {
			c := cell_size(w, h)
			testing.expect(t, c >= 1)
			testing.expect(t, w * c <= CANVAS.w || c == 1) // fits, unless even 1 px cells overflow
			// Every pixel's centre maps back to that pixel.
			for x in ([]int{0, w / 2, w - 1}) {
				r := cell_rect(w, h, x, h - 1)
				gx, gy, ok := cell_at(w, h, r.x + r.w / 2, r.y + r.h / 2)
				testing.expectf(t, ok && gx == x && gy == h - 1, "size %dx%d pixel (%d,%d)", w, h, x, h - 1)
			}
		}
	}
}

Draw_Count :: struct {
	rects, out_of_bounds, presents: int,
	lit_colors:                     int,
}

@(test)
test_draw_stays_on_screen_in_every_mode_and_size :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	count: Draw_Count
	r := cm.Renderer {
		data = &count,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^Draw_Count)(d)
			k.rects += 1
			if x < 0 || y < 0 || x + w > cm.SCREEN_W || y + h > cm.SCREEN_H {
				k.out_of_bounds += 1
			}
			if c == ON {
				k.lit_colors += 1
			}
		},
		present = proc(d: rawptr) {(^Draw_Count)(d).presents += 1},
	}
	sizes := [?][2]int{{1, 1}, {8, 8}, {3, 40}, {40, 3}, {64, 64}, {16, 9}}
	for sz in sizes {
		e := editor_init()
		cm.bitmap_resize(&e.bitmap, sz[0], sz[1])
		for y in 0 ..< sz[1] { 	// checkerboard: the worst case for run merging
			for x in 0 ..< sz[0] {
				cm.bitmap_set(&e.bitmap, x, y, (x + y) % 2 == 0)
			}
		}
		e.cx, e.cy = sz[0] - 1, sz[1] - 1
		for mode in Mode {
			e.mode = mode
			count = {}
			editor_draw(&e, &r)
			testing.expectf(t, count.out_of_bounds == 0, "%dx%d %v: %d rects off screen", sz[0], sz[1], mode, count.out_of_bounds)
			testing.expect_value(t, count.presents, 1)
			testing.expectf(t, count.rects < 9000, "%dx%d: %d rects is too many for one frame", sz[0], sz[1], count.rects)
		}
	}
}

// --- Parity: everything is reachable with the commands alone and with the mouse alone. ---

Input_Method :: enum {
	Commands,
	Mouse,
}

@(test)
test_every_pixel_reachable_and_toggleable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for size in ([]int{1, 5, 8, 17, 40}) {
			for target in ([]int{0, size / 2, size - 1}) {
				e := editor_init()
				cm.bitmap_resize(&e.bitmap, size, size)
				tx, ty := target, size - 1 - target
				switch m {
				case .Commands:
					for _ in 0 ..< tx {
						press(&e, .Right)
					}
					for _ in 0 ..< ty {
						press(&e, .Down)
					}
					press(&e, .Green)
				case .Mouse:
					x, y := center_of_cell(&e, tx, ty)
					click_at(&e, x, y)
				}
				got := cm.bitmap_get(&e.bitmap, tx, ty)
				testing.expectf(t, got && e.cx == tx && e.cy == ty, "%v size %d: pixel (%d,%d) not toggled", m, size, tx, ty)
			}
		}
	}
}

@(test)
test_every_size_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for w in ([]int{1, 2, 8, 9, 33, 64}) {
			for h in ([]int{1, 5, 8, 20, 64}) {
				e := editor_init()
				switch m {
				case .Commands:
					press(&e, .Yellow)
					for _ in 0 ..< 70 {
						press(&e, .Left, .Down) // to 1 x 1
					}
					for _ in 0 ..< w - 1 {
						press(&e, .Right)
					}
					for _ in 0 ..< h - 1 {
						press(&e, .Up)
					}
				case .Mouse:
					for _ in 0 ..< 70 {
						click_rect(&e, WIDTH_MINUS)
						click_rect(&e, HEIGHT_MINUS)
					}
					for _ in 0 ..< w - 1 {
						click_rect(&e, WIDTH_PLUS)
					}
					for _ in 0 ..< h - 1 {
						click_rect(&e, HEIGHT_PLUS)
					}
				}
				testing.expectf(t, e.bitmap.width == w && e.bitmap.height == h, "%v: wanted %dx%d got %dx%d", m, w, h, e.bitmap.width, e.bitmap.height)
			}
		}
	}
}

@(test)
test_save_load_and_leave_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for req in Request {
			e := editor_init()
			switch m {
			case .Commands:
				press(&e, .Blue, req == .Save ? .Green : .Yellow)
			case .Mouse:
				click_rect(&e, req == .Save ? SAVE_BUTTON : LOAD_BUTTON)
			}
			testing.expectf(t, req in e.requests, "%v could not request %v", m, req)
		}
		e := editor_init()
		switch m {
		case .Commands:
			press(&e, .Red)
		case .Mouse:
			click_rect(&e, MENU_BUTTON)
		}
		testing.expectf(t, take_exit(&e), "%v could not leave", m)
	}
}
