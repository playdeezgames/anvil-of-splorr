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
test_setup_mode_resizes_and_clamps_cursor :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Setup)
	testing.expect_value(t, e.row, Setup_Row.Width) // first row
	press(&e, .Right, .Right) // width 10
	press(&e, .Down, .Right) // height row, height 9
	testing.expect(t, e.bitmap.width == 10 && e.bitmap.height == 9 && e.dirty)
	press(&e, .Left, .Left) // height 7
	press(&e, .Up, .Left) // width row, width 9
	testing.expect(t, e.bitmap.width == 9 && e.bitmap.height == 7)
	testing.expect(t, e.cx == 0 && e.cy == 0) // the d-pad changes settings, it does not move the cursor
	// Shrinking pulls the cursor inside.
	press(&e, .Red) // Draw
	for _ in 0 ..< 10 {
		press(&e, .Right, .Down)
	}
	testing.expect(t, e.cx == 8 && e.cy == 6)
	press(&e, .Yellow)
	for _ in 0 ..< 10 {
		press(&e, .Left)
	}
	press(&e, .Down)
	for _ in 0 ..< 10 {
		press(&e, .Left)
	}
	testing.expect(t, e.bitmap.width == 1 && e.bitmap.height == 1) // stops at the minimum
	testing.expect(t, e.cx == 0 && e.cy == 0)
	for _ in 0 ..< 70 {
		press(&e, .Right)
	}
	press(&e, .Up)
	for _ in 0 ..< 70 {
		press(&e, .Right)
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
	press(&e, .Green, .Yellow) // set (7,7); open Setup on the width row
	for _ in 0 ..< 4 {
		press(&e, .Left)
	}
	press(&e, .Down)
	for _ in 0 ..< 4 {
		press(&e, .Left)
	}
	testing.expect(t, e.bitmap.width == 4 && e.bitmap.height == 4)
	testing.expect(t, !cm.bitmap_get(&e.bitmap, 7, 7))
	for _ in 0 ..< 4 {
		press(&e, .Right)
	}
	press(&e, .Up)
	for _ in 0 ..< 4 {
		press(&e, .Right)
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
	e.mode = .Setup
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
	testing.expect(t, e.bitmap.width == 10 && e.bitmap.height == 7 && e.mode == .Setup)
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
	strip := Rect{PALETTE_X, PALETTE_Y, SWATCH_W * cm.PALETTE_SIZE, SWATCH_W}
	rects := [?]Rect{CANVAS, BANNER, WIDTH_MINUS, WIDTH_PLUS, HEIGHT_MINUS, HEIGHT_PLUS, FG_CHIP, BG_CHIP, strip, PREVIEW_FRAME, SAVE_BUTTON, LOAD_BUTTON, MENU_BUTTON, FLIP_H_BUTTON, FLIP_V_BUTTON, ROT_L_BUTTON, ROT_R_BUTTON, ROT_180_BUTTON, FRAME_BUTTON, FILL_BUTTON, INVERT_BUTTON}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	// Text columns clear the controls they sit beside.
	testing.expect(t, ROW_LABEL_X + cm.text_width("HEIGHT") < HEIGHT_MINUS.x)
	testing.expect(t, ROW_LABEL_X + cm.text_width("BACK") < BG_CHIP.x - 1)
	testing.expect(t, ROW_VALUE_X > WIDTH_PLUS.x + WIDTH_PLUS.w && ROW_VALUE_X + cm.text_width("64") <= cm.SCREEN_W)
	testing.expect(t, ROW_MARKER_X + cm.text_width(">") < ROW_LABEL_X && ROW_MARKER_X > CANVAS.x + CANVAS.w)
	testing.expect(t, INFO_Y > BANNER.y + BANNER.h)
	testing.expect(t, HELP_Y >= CANVAS.y + CANVAS.h && HELP_Y >= PREVIEW_FRAME.y + PREVIEW_FRAME.h)
	// The inner preview area is inside its frame; "CLIPPED" fits beside the frame, clear of buttons.
	in_ := PREVIEW_INNER
	testing.expect(t, in_.x > PREVIEW_FRAME.x && in_.y > PREVIEW_FRAME.y && in_.x + in_.w < PREVIEW_FRAME.x + PREVIEW_FRAME.w && in_.y + in_.h < PREVIEW_FRAME.y + PREVIEW_FRAME.h)
	testing.expect(t, CLIPPED_X > PREVIEW_FRAME.x + PREVIEW_FRAME.w && CLIPPED_X + cm.text_width("CLIPPED") <= cm.SCREEN_W)
	testing.expect(t, CLIPPED_Y > MENU_BUTTON.y + MENU_BUTTON.h && CLIPPED_Y + cm.GLYPH_H <= HELP_Y)
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
					press(&e, .Yellow) // Setup, width row
					for _ in 0 ..< 70 {
						press(&e, .Left) // width 1
					}
					press(&e, .Down) // height row
					for _ in 0 ..< 70 {
						press(&e, .Left) // height 1
					}
					for _ in 0 ..< h - 1 {
						press(&e, .Right)
					}
					press(&e, .Up) // back to the width row
					for _ in 0 ..< w - 1 {
						press(&e, .Right)
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

@(test)
test_closing_the_window_warns_about_unsaved_changes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	tl := tool(&e)
	testing.expect(t, tl.allow_close(tl.data)) // clean: closes at once
	press(&e, .Green) // toggle a pixel
	testing.expect(t, e.dirty)
	testing.expect(t, !tl.allow_close(tl.data)) // first close: held, prompt shown
	testing.expect(t, e.confirm_exit)
	testing.expect_value(t, banner_text(&e), "UNSAVED   RED: LEAVE ANYWAY")
	testing.expect(t, tl.allow_close(tl.data)) // closing again while the prompt is up goes through

	// Any other command cancels the prompt, so the next close warns again.
	e.confirm_exit = true
	press(&e, .Down)
	testing.expect(t, !e.confirm_exit)
	testing.expect(t, !tl.allow_close(tl.data))

	// Saving makes it clean again.
	e.confirm_exit = false
	editor_mark_saved(&e)
	testing.expect(t, tl.allow_close(tl.data))
}

// --- Setup rows, preview colours and the palette ---

@(test)
test_setup_row_selection_wraps :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow, .Up)
	testing.expect_value(t, e.row, Setup_Row.Fill) // wrapped from the first row
	press(&e, .Down)
	testing.expect_value(t, e.row, Setup_Row.Width)
	press(&e, .Down, .Down, .Down)
	testing.expect_value(t, e.row, Setup_Row.Background)
	press(&e, .Red, .Yellow) // the row is remembered
	testing.expect_value(t, e.row, Setup_Row.Background)
}

@(test)
test_foreground_and_background_default_and_wrap :: proc(t: ^testing.T) {
	e := editor_init()
	testing.expect(t, e.fg == 15 && e.bg == 0)
	press(&e, .Yellow, .Down, .Down) // foreground row
	press(&e, .Right) // 15 -> 0
	testing.expect_value(t, e.fg, 0)
	press(&e, .Left, .Left)
	testing.expect_value(t, e.fg, 14)
	press(&e, .Down, .Left) // background row, 0 -> 15
	testing.expect_value(t, e.bg, 15)
	testing.expect(t, !e.dirty) // colours are not part of the image
}

@(test)
test_colours_are_not_saved_in_the_image :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	before := cm.bitmap_to_json(&e.bitmap)
	press(&e, .Yellow, .Down, .Down, .Right, .Right, .Down, .Left)
	after := cm.bitmap_to_json(&e.bitmap)
	testing.expect_value(t, before, after)
}

@(test)
test_mouse_palette_left_sets_foreground_right_sets_background :: proc(t: ^testing.T) {
	e := editor_init()
	r := swatch_rect(6)
	click_at(&e, r.x + 2, r.y + 2)
	testing.expect(t, e.fg == 6 && e.bg == 0 && e.mode == .Setup && e.row == .Foreground)
	r = swatch_rect(11)
	editor_handle_event(&e, cm.Mouse_Button_Event{button = .Right, x = r.x + 2, y = r.y + 2, down = true})
	editor_handle_event(&e, cm.Mouse_Button_Event{button = .Right, x = r.x + 2, y = r.y + 2, down = false})
	testing.expect(t, e.bg == 11 && e.fg == 6 && e.row == .Background)
	testing.expect(t, !e.dirty)
	// A right click elsewhere does nothing, and neither paints nor toggles.
	x, y := center_of_cell(&e, 2, 2)
	editor_handle_event(&e, cm.Mouse_Button_Event{button = .Right, x = x, y = y, down = true})
	testing.expect(t, !cm.bitmap_get(&e.bitmap, 2, 2) && !e.dirty)
}

@(test)
test_every_preview_colour_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for target in 0 ..< cm.PALETTE_SIZE {
			e := editor_init()
			switch m {
			case .Commands:
				press(&e, .Yellow, .Down, .Down) // foreground row
				fg_steps := (target - e.fg + cm.PALETTE_SIZE) % cm.PALETTE_SIZE
				for _ in 0 ..< fg_steps {
					press(&e, .Right)
				}
				press(&e, .Down) // background row
				bg_steps := (target - e.bg + cm.PALETTE_SIZE) % cm.PALETTE_SIZE
				for _ in 0 ..< bg_steps {
					press(&e, .Right)
				}
			case .Mouse:
				r := swatch_rect(target)
				click_at(&e, r.x + 2, r.y + 2)
				editor_handle_event(&e, cm.Mouse_Button_Event{button = .Right, x = r.x + 2, y = r.y + 2, down = true})
			}
			testing.expectf(t, e.fg == target && e.bg == target, "%v could not reach colour %d (fg %d bg %d)", m, target, e.fg, e.bg)
		}
	}
}

@(test)
test_palette_comes_from_the_aux_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	tl := tool(&e)
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "palette.json")
	testing.expect(t, e.palette == cm.default_palette()) // before any file: the default
	testing.expect(t, !tl.wants_aux_load(tl.data)) // nothing asked yet
	tl.enter(tl.data)
	testing.expect(t, tl.wants_aux_load(tl.data) && !tl.wants_aux_load(tl.data)) // once per enter

	custom := cm.default_palette()
	custom[3] = {9, 8, 7}
	testing.expect(t, tl.load_aux(tl.data, transmute([]u8)cm.palette_to_json(custom)))
	testing.expect(t, e.palette[3] == cm.Color{9, 8, 7})
	// A bad file is rejected and leaves the palette alone.
	testing.expect(t, !tl.load_aux(tl.data, transmute([]u8)string("not json")))
	testing.expect(t, e.palette[3] == cm.Color{9, 8, 7})
	// Loading a palette is not an edit.
	testing.expect(t, !e.dirty)
}

@(test)
test_enter_resets_colours_and_asks_for_the_palette :: proc(t: ^testing.T) {
	e := editor_init()
	e.fg, e.bg = 3, 4
	e.palette[0] = {1, 1, 1}
	tl := tool(&e)
	tl.enter(tl.data)
	testing.expect(t, e.fg == 15 && e.bg == 0 && e.palette == cm.default_palette())
	testing.expect(t, e.aux_requests == {.Palette} && e.requests == {.Load})
}

@(test)
test_preview_scale_and_clipping :: proc(t: ^testing.T) {
	testing.expect_value(t, preview_scale(8, 8), 2)
	testing.expect_value(t, preview_scale(5, 5), 4)
	testing.expect_value(t, preview_scale(1, 1), 20)
	testing.expect_value(t, preview_scale(20, 20), 1)
	testing.expect_value(t, preview_scale(64, 64), 1) // never below 1
	testing.expect_value(t, preview_scale(8, 30), 1) // the taller side decides
	testing.expect(t, !preview_clipped(8, 8))
	testing.expect(t, !preview_clipped(20, 20))
	testing.expect(t, preview_clipped(21, 21))
	testing.expect(t, preview_clipped(64, 1))
	for w in 1 ..= cm.BITMAP_MAX {
		for h in ([]int{1, 8, 20, 21, cm.BITMAP_MAX}) {
			s := preview_scale(w, h)
			testing.expect(t, s >= 1)
			if !preview_clipped(w, h) {
				testing.expect(t, TILES * w * s <= PREVIEW_INNER.w && TILES * h * s <= PREVIEW_INNER.h)
			}
		}
	}
}

@(test)
test_intersect :: proc(t: ^testing.T) {
	r, ok := intersect(Rect{0, 0, 10, 10}, Rect{5, 5, 10, 10})
	testing.expect(t, ok && r == Rect{5, 5, 5, 5})
	_, ok = intersect(Rect{0, 0, 5, 5}, Rect{5, 0, 5, 5}) // touching edges do not overlap
	testing.expect(t, !ok)
	_, ok = intersect(Rect{0, 0, 5, 5}, Rect{20, 20, 5, 5})
	testing.expect(t, !ok)
}

Colour_Log :: struct {
	fg_rects, bg_fills: int,
	fg, bg:             cm.Color,
	clipped_text:       bool,
}

@(test)
test_preview_is_drawn_in_the_chosen_colours_nine_times :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log := Colour_Log {
		fg = {201, 202, 203},
		bg = {101, 102, 103},
	}
	r := cm.Renderer {
		data = &log,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			l := (^Colour_Log)(d)
			if c == l.fg {
				l.fg_rects += 1
			}
			if c == l.bg {
				l.bg_fills += 1
			}
		},
		present = proc(d: rawptr) {},
	}
	e := editor_init()
	e.palette[5], e.palette[9] = log.fg, log.bg
	e.fg, e.bg = 5, 9
	editor_draw(&e, &r) // blank bitmap: only the chip and the palette strip use the foreground colour
	baseline := log.fg_rects
	testing.expect_value(t, baseline, 2)
	testing.expect(t, log.bg_fills >= 1)

	// One lone pixel is one run in each of the 3 x 3 tiles.
	log.fg_rects = 0
	cm.bitmap_set(&e.bitmap, 1, 1, true)
	editor_draw(&e, &r)
	testing.expect_value(t, log.fg_rects - baseline, 9)

	// Two pixels in a row are still one run per tile; adding one below makes two runs per tile.
	log.fg_rects = 0
	cm.bitmap_set(&e.bitmap, 2, 1, true)
	editor_draw(&e, &r)
	testing.expect_value(t, log.fg_rects - baseline, 9)
	log.fg_rects = 0
	cm.bitmap_set(&e.bitmap, 1, 2, true)
	editor_draw(&e, &r)
	testing.expect_value(t, log.fg_rects - baseline, 18)
}

@(test)
test_all_on_screen_text_is_in_the_font :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	for mode in Mode {
		e.mode = mode
		for confirm in ([]bool{false, true}) {
			e.confirm_exit = confirm
			testing.expectf(t, cm.text_is_drawable(banner_text(&e)), "banner has a character the font lacks: %s", banner_text(&e))
			lines, n := help_lines(&e)
			for line in lines[:n] {
				testing.expectf(t, cm.text_is_drawable(line), "help line has a character the font lacks: %s", line)
			}
		}
	}
	// The default labels are fine too (user labels are the user's responsibility).
	for a in cm.Action {
		testing.expect(t, cm.text_is_drawable(cm.DEFAULT_LABELS[a]))
	}
}

// --- Invert, flips, rotation and rectangles ---

goto_row :: proc(e: ^Editor, row: Setup_Row) {
	press(e, .Yellow)
	for e.row != row {
		press(e, .Down)
	}
}

right_click_at :: proc(e: ^Editor, x, y: int) {
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Right, x = x, y = y, down = true})
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Right, x = x, y = y, down = false})
}

lit :: proc(e: ^Editor, x, y: int) -> bool {
	return cm.bitmap_get(&e.bitmap, x, y)
}

lit_count :: proc(e: ^Editor) -> (n: int) {
	for y in 0 ..< e.bitmap.height {
		for x in 0 ..< e.bitmap.width {
			if lit(e, x, y) {
				n += 1
			}
		}
	}
	return
}

// 3 x 2: row 0 = # . #   row 1 = # . .
fixture :: proc() -> Editor {
	e := editor_init()
	cm.bitmap_resize(&e.bitmap, 3, 2)
	cm.bitmap_set(&e.bitmap, 0, 0, true)
	cm.bitmap_set(&e.bitmap, 2, 0, true)
	cm.bitmap_set(&e.bitmap, 0, 1, true)
	return e
}

@(test)
test_invert_swaps_every_pixel :: proc(t: ^testing.T) {
	e := fixture()
	goto_row(&e, .Invert)
	press(&e, .Green)
	testing.expect(t, !lit(&e, 0, 0) && lit(&e, 1, 0) && !lit(&e, 2, 0) && !lit(&e, 0, 1) && lit(&e, 1, 1) && lit(&e, 2, 1))
	testing.expect(t, e.dirty && e.mode == .Setup)
	press(&e, .Green) // again: back to how it was
	testing.expect(t, lit(&e, 0, 0) && !lit(&e, 1, 0) && lit(&e, 2, 0) && lit(&e, 0, 1) && !lit(&e, 1, 1))
	// A blank glyph inverts to a full one, and that is an edit.
	e = editor_init()
	goto_row(&e, .Invert)
	press(&e, .Green)
	testing.expect_value(t, lit_count(&e), 64)
	testing.expect(t, e.dirty)
}

@(test)
test_invert_button :: proc(t: ^testing.T) {
	e := fixture()
	click_rect(&e, INVERT_BUTTON)
	testing.expect(t, e.mode == .Setup && e.row == .Invert && lit_count(&e) == 3 && !lit(&e, 0, 0))
}

@(test)
test_flip_rows_and_buttons :: proc(t: ^testing.T) {
	e := fixture()
	goto_row(&e, .Flip_Horizontal)
	press(&e, .Green)
	testing.expect(t, lit(&e, 2, 0) && lit(&e, 0, 0) && lit(&e, 2, 1) && !lit(&e, 0, 1)) // row 1 moved right
	press(&e, .Green)
	testing.expect(t, lit(&e, 0, 1) && !lit(&e, 2, 1))
	press(&e, .Down, .Green) // vertical
	testing.expect(t, lit(&e, 0, 0) && lit(&e, 0, 1) && lit(&e, 2, 1) && !lit(&e, 2, 0))
	e = fixture()
	click_rect(&e, FLIP_V_BUTTON)
	testing.expect(t, e.row == .Flip_Vertical && lit(&e, 0, 0) && lit(&e, 2, 1))
	click_rect(&e, FLIP_H_BUTTON)
	testing.expect(t, e.row == .Flip_Horizontal && lit(&e, 2, 0) && lit(&e, 0, 1))
}

@(test)
test_flips_and_rotations_that_change_nothing_are_not_edits :: proc(t: ^testing.T) {
	e := editor_init() // blank 8 x 8
	for row in ([]Setup_Row{.Flip_Horizontal, .Flip_Vertical, .Rotate_Left, .Rotate_Right, .Rotate_180}) {
		goto_row(&e, row)
		press(&e, .Green)
		testing.expectf(t, !e.dirty, "%v on a blank square marked it changed", row)
	}
	e.bitmap = cm.bitmap_make(3, 5) // blank but not square: a quarter turn changes its size
	goto_row(&e, .Rotate_Left)
	press(&e, .Green)
	testing.expect(t, e.dirty && e.bitmap.width == 5 && e.bitmap.height == 3)
}

@(test)
test_rotate_rows_and_buttons :: proc(t: ^testing.T) {
	e := fixture()
	goto_row(&e, .Rotate_Right)
	press(&e, .Green)
	testing.expect(t, e.bitmap.width == 2 && e.bitmap.height == 3)
	// Clockwise: the top row (# . #) becomes the right column, top to bottom.
	testing.expect(t, lit(&e, 1, 0) && !lit(&e, 1, 1) && lit(&e, 1, 2) && lit(&e, 0, 0) && !lit(&e, 0, 1))
	press(&e, .Up, .Green) // Rotate left undoes it
	testing.expect(t, e.bitmap.width == 3 && e.bitmap.height == 2 && lit(&e, 0, 0) && lit(&e, 2, 0) && lit(&e, 0, 1))
	e = fixture()
	click_rect(&e, ROT_180_BUTTON)
	testing.expect(t, e.bitmap.width == 3 && lit(&e, 2, 1) && lit(&e, 0, 1) && lit(&e, 2, 0) && !lit(&e, 0, 0))
	e = fixture()
	click_rect(&e, ROT_L_BUTTON)
	testing.expect(t, e.bitmap.width == 2 && e.bitmap.height == 3 && e.row == .Rotate_Left)
	click_rect(&e, ROT_R_BUTTON)
	testing.expect(t, e.bitmap.width == 3 && lit(&e, 0, 0) && lit(&e, 2, 0) && lit(&e, 0, 1))
}

@(test)
test_rotation_keeps_the_cursor_inside :: proc(t: ^testing.T) {
	e := editor_init()
	cm.bitmap_resize(&e.bitmap, 8, 2)
	e.cx, e.cy = 7, 1
	goto_row(&e, .Rotate_Left)
	press(&e, .Green)
	testing.expect(t, e.bitmap.width == 2 && e.bitmap.height == 8 && e.cx == 1 && e.cy == 1)
}

@(test)
test_frame_draws_from_a_clear_corner :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Right, .Down) // (1,1)
	goto_row(&e, .Frame)
	press(&e, .Green)
	testing.expect(t, e.mode == .Rect && e.shape == .Frame && e.shape_on && !e.dirty)
	press(&e, .Right, .Right, .Right, .Down, .Down, .Green) // to (4,3)
	testing.expect(t, e.mode == .Draw && e.shape == .None && e.dirty)
	testing.expect_value(t, lit_count(&e), 10) // a 4 x 3 outline
	testing.expect(t, lit(&e, 1, 1) && lit(&e, 4, 3) && !lit(&e, 2, 2) && !lit(&e, 3, 2) == true)
}

@(test)
test_fill_from_a_lit_corner_erases :: proc(t: ^testing.T) {
	e := editor_init()
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			cm.bitmap_set(&e.bitmap, x, y, true)
		}
	}
	e.cx, e.cy = 2, 2
	goto_row(&e, .Fill)
	press(&e, .Green)
	testing.expect(t, e.mode == .Rect && !e.shape_on) // starting on a lit pixel erases
	press(&e, .Right, .Right, .Down, .Green)
	testing.expect_value(t, lit_count(&e), 64 - 3 * 2)
	testing.expect(t, !lit(&e, 2, 2) && !lit(&e, 4, 3) && lit(&e, 5, 3) && lit(&e, 1, 2))
}

@(test)
test_rectangle_corners_can_be_in_any_order :: proc(t: ^testing.T) {
	e := editor_init()
	e.cx, e.cy = 5, 5
	goto_row(&e, .Fill)
	press(&e, .Green, .Left, .Left, .Left, .Up, .Up, .Green)
	testing.expect_value(t, lit_count(&e), 4 * 3)
	testing.expect(t, lit(&e, 2, 3) && lit(&e, 5, 5) && !lit(&e, 1, 3))
}

@(test)
test_rectangles_cancel_cleanly_and_ignore_other_commands :: proc(t: ^testing.T) {
	e := editor_init()
	goto_row(&e, .Fill)
	press(&e, .Green, .Right, .Down, .Yellow, .Blue)
	testing.expect(t, e.mode == .Rect && e.requests == {}) // other commands are ignored
	press(&e, .Red)
	testing.expect(t, e.mode == .Draw && e.shape == .None && !e.dirty && lit_count(&e) == 0)
	testing.expect(t, !(func_take_exit(&e)))
	press(&e, .Red)
	testing.expect(t, func_take_exit(&e))
	e = editor_init()
	goto_row(&e, .Frame)
	press(&e, .Green)
	for _ in 0 ..< 20 {
		press(&e, .Right, .Down)
	}
	testing.expect(t, e.cx == 7 && e.cy == 7) // the corner stays inside
}

func_take_exit :: proc(e: ^Editor) -> bool {
	tl := tool(e)
	return tl.take_exit(tl.data)
}

@(test)
test_mouse_drag_draws_a_rectangle_with_an_armed_tool :: proc(t: ^testing.T) {
	e := editor_init()
	click_rect(&e, FRAME_BUTTON)
	testing.expect(t, e.shape == .Frame && e.mode == .Draw)
	x0, y0 := center_of_cell(&e, 1, 1)
	mouse(&e, x0, y0, true)
	testing.expect(t, e.rect_drag && e.mode == .Rect && e.shape_on && lit_count(&e) == 0)
	x, y := center_of_cell(&e, 5, 4)
	editor_handle_event(&e, cm.Mouse_Move{x, y})
	mouse(&e, x, y, false)
	testing.expect(t, !e.rect_drag && e.mode == .Draw && e.shape == .None && e.dirty)
	testing.expect_value(t, lit_count(&e), 2 * 5 + 2 * 2) // a 5 x 4 outline: 14
	// The tool is spent: the next click toggles one pixel as usual.
	x, y = center_of_cell(&e, 7, 7)
	click_at(&e, x, y)
	testing.expect(t, lit(&e, 7, 7) && lit_count(&e) == 15)
}

@(test)
test_dragging_from_a_lit_pixel_erases_a_region :: proc(t: ^testing.T) {
	e := editor_init()
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			cm.bitmap_set(&e.bitmap, x, y, true)
		}
	}
	click_rect(&e, FILL_BUTTON)
	x0, y0 := center_of_cell(&e, 2, 2)
	mouse(&e, x0, y0, true)
	testing.expect(t, !e.shape_on)
	x, y := center_of_cell(&e, 4, 3)
	editor_handle_event(&e, cm.Mouse_Move{x, y})
	mouse(&e, x, y, false)
	testing.expect_value(t, lit_count(&e), 64 - 6)
}

@(test)
test_tool_button_toggles_and_red_disarms :: proc(t: ^testing.T) {
	e := editor_init()
	click_rect(&e, FRAME_BUTTON)
	click_rect(&e, FRAME_BUTTON)
	testing.expect_value(t, e.shape, cm.Shape.None)
	click_rect(&e, FRAME_BUTTON)
	click_rect(&e, FILL_BUTTON)
	testing.expect_value(t, e.shape, cm.Shape.Fill)
	press(&e, .Red)
	testing.expect(t, e.shape == .None && !func_take_exit(&e)) // red disarmed it instead of leaving
	x, y := center_of_cell(&e, 3, 3)
	click_at(&e, x, y)
	testing.expect(t, lit(&e, 3, 3))
}

@(test)
test_a_click_places_the_second_corner_of_a_keyboard_rectangle :: proc(t: ^testing.T) {
	e := editor_init()
	e.cx, e.cy = 1, 1
	goto_row(&e, .Fill)
	press(&e, .Green)
	x, y := center_of_cell(&e, 3, 4)
	click_at(&e, x, y)
	testing.expect(t, e.mode == .Draw && e.shape == .None)
	testing.expect_value(t, lit_count(&e), 3 * 4)
}

@(test)
test_other_buttons_abandon_a_rectangle_but_colour_choices_do_not :: proc(t: ^testing.T) {
	e := editor_init()
	goto_row(&e, .Frame)
	press(&e, .Green)
	r := swatch_rect(6)
	click_at(&e, r.x + 2, r.y + 2) // choosing the foreground keeps going
	testing.expect(t, e.mode == .Rect && e.shape == .Frame && e.fg == 6)
	right_click_at(&e, r.x + 2, r.y + 2) // so does choosing the background
	testing.expect(t, e.mode == .Rect && e.bg == 6)
	press(&e, .Green)
	testing.expect(t, e.mode == .Draw)
	goto_row(&e, .Frame)
	press(&e, .Green)
	click_rect(&e, WIDTH_PLUS) // any other button abandons it
	testing.expect(t, e.shape == .None && e.mode == .Setup && !e.rect_drag)
}

@(test)
test_rectangle_preview_colours :: proc(t: ^testing.T) {
	count: [2]int // yellow squares, red squares
	r := cm.Renderer {
		data = &count,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^[2]int)(d)
			// Preview squares are smaller than a canvas cell; only they use these colours at that size.
			if w == 8 && h == 8 {
				if c == HILITE {
					k[0] += 1
				}
				if c == WARN {
					k[1] += 1
				}
			}
		},
		present = proc(d: rawptr) {},
	}
	e := editor_init() // 8 x 8: cells are 17 px, so the preview squares are 8 px
	e.mode, e.shape = .Rect, .Frame
	e.ax, e.ay, e.cx, e.cy = 1, 1, 4, 3
	e.shape_on = true
	editor_draw(&e, &r)
	testing.expect(t, count[0] == 10 && count[1] == 0) // drawing: yellow, one per frame pixel
	count = {}
	e.shape_on = false
	editor_draw(&e, &r)
	testing.expect(t, count[0] == 0 && count[1] == 10) // erasing: red
}

@(test)
test_new_text_is_drawable_and_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	m := cm.default_input_map()
	e.labels = &m
	for round in 0 ..< 2 {
		if round == 1 {
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for shape in ([]cm.Shape{.None, .Frame, .Fill}) {
			e.shape = shape
			for mode in Mode {
				e.mode = mode
				for confirm in ([]bool{false, true}) {
					e.confirm_exit = confirm
					text := banner_text(&e)
					if round == 0 {
						testing.expectf(t, cm.text_is_drawable(text), "banner: %s", text)
					}
					testing.expectf(t, cm.text_width(text) + 8 <= BANNER.w, "banner too wide: %s", text)
				}
				lines, n := help_lines(&e)
				for line in lines[:n] {
					if round == 0 {
						testing.expectf(t, cm.text_is_drawable(line), "help: %s", line)
					}
					testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
				}
			}
		}
	}
	for pair in ([]struct {
			text: string,
			rc:   Rect,
		}{{"SAVE", SAVE_BUTTON}, {"FLIP H", FLIP_H_BUTTON}, {"ROT 180", ROT_180_BUTTON}, {"FRAME", FRAME_BUTTON}, {"INVERT", INVERT_BUTTON}}) {
		testing.expectf(t, cm.text_width(pair.text) <= pair.rc.w - 2, "label %s does not fit its button", pair.text)
	}
}

@(test)
test_new_actions_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for row in ([]Setup_Row{.Invert, .Flip_Horizontal, .Flip_Vertical, .Rotate_Left, .Rotate_Right, .Rotate_180}) {
			e := fixture()
			switch m {
			case .Commands:
				goto_row(&e, row)
				press(&e, .Green)
			case .Mouse:
				btn: Rect
				#partial switch row {
				case .Invert:
					btn = INVERT_BUTTON
				case .Flip_Horizontal:
					btn = FLIP_H_BUTTON
				case .Flip_Vertical:
					btn = FLIP_V_BUTTON
				case .Rotate_Left:
					btn = ROT_L_BUTTON
				case .Rotate_Right:
					btn = ROT_R_BUTTON
				case .Rotate_180:
					btn = ROT_180_BUTTON
				}
				click_rect(&e, btn)
			}
			testing.expectf(t, e.dirty, "%v could not run %v", m, row)
		}
		for shape in ([]cm.Shape{.Frame, .Fill}) {
			e := editor_init()
			switch m {
			case .Commands:
				e.cx, e.cy = 1, 1
				goto_row(&e, shape == .Frame ? .Frame : .Fill)
				press(&e, .Green, .Right, .Right, .Down, .Down, .Green)
			case .Mouse:
				click_rect(&e, shape == .Frame ? FRAME_BUTTON : FILL_BUTTON)
				x0, y0 := center_of_cell(&e, 1, 1)
				mouse(&e, x0, y0, true)
				x, y := center_of_cell(&e, 3, 3)
				editor_handle_event(&e, cm.Mouse_Move{x, y})
				mouse(&e, x, y, false)
			}
			testing.expectf(t, lit_count(&e) == (shape == .Frame ? 8 : 9), "%v %v drew %d pixels", m, shape, lit_count(&e))
		}
	}
}
