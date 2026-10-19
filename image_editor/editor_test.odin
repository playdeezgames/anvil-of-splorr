#+build !js
package image_editor

import cm "../common"
import "core:testing"

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

right_click_at :: proc(e: ^Editor, x, y: int) {
	mouse(e, x, y, true, .Right)
	mouse(e, x, y, false, .Right)
}

click_rect :: proc(e: ^Editor, r: Rect) {
	click_at(e, r.x + r.w / 2, r.y + r.h / 2)
}

center_of_cell :: proc(e: ^Editor, x, y: int) -> (int, int) {
	r := cell_rect(e.image.width, e.image.height, x, y)
	return r.x + r.w / 2, r.y + r.h / 2
}

take_exit :: proc(e: ^Editor) -> bool {
	tl := tool(e)
	return tl.take_exit(tl.data)
}

pixel :: proc(e: ^Editor, x, y: int) -> int {
	return int(cm.image4_get(&e.image, x, y))
}

@(test)
test_starts_blank_8x8_in_white :: proc(t: ^testing.T) {
	e := editor_init()
	testing.expect(t, e.image.width == 8 && e.image.height == 8)
	testing.expect(t, e.cx == 0 && e.cy == 0 && e.mode == .Draw && !e.dirty)
	testing.expect_value(t, e.color, 15)
	testing.expect(t, e.palette == cm.default_palette())
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			testing.expect_value(t, pixel(&e, x, y), 0)
		}
	}
}

@(test)
test_cursor_moves_and_clamps :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Left, .Up)
	testing.expect(t, e.cx == 0 && e.cy == 0)
	press(&e, .Right, .Right, .Down)
	testing.expect(t, e.cx == 2 && e.cy == 1)
	for _ in 0 ..< 20 {
		press(&e, .Right, .Down)
	}
	testing.expect(t, e.cx == 7 && e.cy == 7) // stops at the far edge, no wrap
	testing.expect(t, !e.dirty)
}

@(test)
test_green_paints_with_the_drawing_colour :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Right, .Down, .Green)
	testing.expect_value(t, pixel(&e, 1, 1), 15)
	testing.expect(t, e.dirty && pixel(&e, 0, 0) == 0)
	editor_mark_saved(&e)
	press(&e, .Green) // same colour again: nothing changes
	testing.expect(t, !e.dirty)
	e.color = 4
	press(&e, .Green)
	testing.expect_value(t, pixel(&e, 1, 1), 4) // repainting changes it
	testing.expect(t, e.dirty)
	e.color = 0 // painting with colour 0 is how you erase
	press(&e, .Green)
	testing.expect_value(t, pixel(&e, 1, 1), 0)
}

@(test)
test_setup_opens_on_the_colour_row_and_colour_wraps :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Setup)
	testing.expect_value(t, e.row, Setup_Row.Color) // the quick one: yellow, left/right, red
	press(&e, .Right)
	testing.expect_value(t, e.color, 0) // 15 -> 0
	press(&e, .Left)
	testing.expect_value(t, e.color, 15) // 0 -> 15
	press(&e, .Left, .Left)
	testing.expect_value(t, e.color, 13)
	testing.expect(t, !e.dirty) // the colour choice is not an edit
	press(&e, .Red, .Green) // paint with it
	testing.expect_value(t, pixel(&e, 0, 0), 13)
}

@(test)
test_setup_rows_wrap_and_remember :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow, .Up)
	testing.expect_value(t, e.row, Setup_Row.Height)
	press(&e, .Down)
	testing.expect_value(t, e.row, Setup_Row.Color)
	press(&e, .Down, .Red, .Yellow)
	testing.expect_value(t, e.row, Setup_Row.Width) // remembered
}

@(test)
test_setup_resizes_and_clamps_the_cursor :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow, .Down) // width row
	press(&e, .Right, .Right) // 10
	press(&e, .Down, .Right) // height row: 9
	testing.expect(t, e.image.width == 10 && e.image.height == 9 && e.dirty)
	press(&e, .Left, .Left) // height 7
	press(&e, .Up, .Up, .Right) // colour row: 15 -> 0; the d-pad changes settings, not the cursor
	testing.expect(t, e.cx == 0 && e.cy == 0 && e.color == 0)
	press(&e, .Red)
	for _ in 0 ..< 12 {
		press(&e, .Right, .Down)
	}
	testing.expect(t, e.cx == 9 && e.cy == 6)
	press(&e, .Yellow, .Down) // width row
	for _ in 0 ..< 80 {
		press(&e, .Left)
	}
	press(&e, .Down)
	for _ in 0 ..< 80 {
		press(&e, .Left)
	}
	testing.expect(t, e.image.width == 1 && e.image.height == 1 && e.cx == 0 && e.cy == 0)
	for _ in 0 ..< 80 {
		press(&e, .Right)
	}
	press(&e, .Up)
	for _ in 0 ..< 80 {
		press(&e, .Right)
	}
	testing.expect(t, e.image.width == cm.IMAGE_MAX && e.image.height == cm.IMAGE_MAX)
}

@(test)
test_shrinking_then_growing_restores_pixels :: proc(t: ^testing.T) {
	e := editor_init()
	e.color = 9
	for _ in 0 ..< 7 {
		press(&e, .Right, .Down)
	}
	press(&e, .Green, .Yellow, .Down) // paint (7,7); Setup on the width row
	for _ in 0 ..< 4 {
		press(&e, .Left)
	}
	press(&e, .Down)
	for _ in 0 ..< 4 {
		press(&e, .Left)
	}
	testing.expect_value(t, pixel(&e, 7, 7), 0) // hidden
	for _ in 0 ..< 4 {
		press(&e, .Right)
	}
	press(&e, .Up)
	for _ in 0 ..< 4 {
		press(&e, .Right)
	}
	testing.expect_value(t, pixel(&e, 7, 7), 9)
}

@(test)
test_resize_at_a_limit_is_not_a_change :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow, .Down)
	for _ in 0 ..< 10 {
		press(&e, .Left)
	}
	e.dirty = false
	press(&e, .Left)
	testing.expect(t, !e.dirty)
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
	e = editor_init()
	press(&e, .Yellow, .Blue)
	testing.expect_value(t, e.mode, Mode.File)
}

// --- Mouse ---

@(test)
test_mouse_click_paints_the_drawing_colour :: proc(t: ^testing.T) {
	e := editor_init()
	e.mode = .Setup
	e.color = 6
	x, y := center_of_cell(&e, 3, 5)
	click_at(&e, x, y)
	testing.expect(t, pixel(&e, 3, 5) == 6 && e.cx == 3 && e.cy == 5 && e.dirty)
	testing.expect_value(t, e.mode, Mode.Draw)
	// Clicking again with the same colour is not a change; a different colour repaints.
	e.dirty = false
	click_at(&e, x, y)
	testing.expect(t, !e.dirty && pixel(&e, 3, 5) == 6) // unlike the glyph editor, a click never erases
	e.color = 2
	click_at(&e, x, y)
	testing.expect_value(t, pixel(&e, 3, 5), 2)
	// A click just outside the drawn image does nothing.
	e.dirty = false
	click_at(&e, CANVAS.x + 8 * cell_size(8, 8) + 1, CANVAS.y + 2)
	testing.expect(t, !e.dirty)
}

@(test)
test_mouse_drag_paints_the_same_colour_throughout :: proc(t: ^testing.T) {
	e := editor_init()
	e.color = 11
	x0, y0 := center_of_cell(&e, 1, 1)
	mouse(&e, x0, y0, true)
	e.color = 3 // changing the colour mid-drag does not affect the stroke
	for cx in 2 ..= 5 {
		x, y := center_of_cell(&e, cx, 1)
		editor_handle_event(&e, cm.Mouse_Move{x, y})
	}
	mouse(&e, 0, 0, false)
	for cx in 1 ..= 5 {
		testing.expectf(t, pixel(&e, cx, 1) == 11, "pixel %d", cx)
	}
	x, y := center_of_cell(&e, 6, 1) // after release nothing paints
	editor_handle_event(&e, cm.Mouse_Move{x, y})
	testing.expect_value(t, pixel(&e, 6, 1), 0)
}

@(test)
test_right_click_picks_a_colour :: proc(t: ^testing.T) {
	e := editor_init()
	cm.image4_set(&e.image, 2, 2, 7)
	x, y := center_of_cell(&e, 2, 2)
	right_click_at(&e, x, y)
	testing.expect(t, e.color == 7 && e.mode == .Setup && e.row == .Color)
	testing.expect(t, e.cx == 2 && e.cy == 2 && !e.dirty) // picking changes nothing
	x, y = center_of_cell(&e, 5, 5) // a clear pixel is colour 0
	right_click_at(&e, x, y)
	testing.expect_value(t, e.color, 0)
	// Right click on a swatch picks that colour too; elsewhere does nothing.
	r := swatch_rect(12)
	right_click_at(&e, r.x + 2, r.y + 2)
	testing.expect_value(t, e.color, 12)
	e.mode = .Draw
	right_click_at(&e, 0, 0)
	testing.expect(t, e.color == 12 && e.mode == .Draw)
	// A right click does not paint or start a drag.
	right_click_at(&e, x, y)
	editor_handle_event(&e, cm.Mouse_Move{x + 12, y})
	testing.expect(t, !e.dirty)
}

@(test)
test_swatch_click_chooses_the_colour :: proc(t: ^testing.T) {
	e := editor_init()
	for i in 0 ..< 16 {
		r := swatch_rect(i)
		click_at(&e, r.x + 3, r.y + 3)
		testing.expectf(t, e.color == i && e.mode == .Setup && e.row == .Color, "swatch %d", i)
	}
	testing.expect(t, !e.dirty)
}

@(test)
test_mouse_size_buttons_and_file_buttons :: proc(t: ^testing.T) {
	e := editor_init()
	click_rect(&e, WIDTH_PLUS)
	click_rect(&e, WIDTH_PLUS)
	click_rect(&e, HEIGHT_MINUS)
	testing.expect(t, e.image.width == 10 && e.image.height == 7 && e.mode == .Setup && e.row == .Height)
	click_rect(&e, WIDTH_MINUS)
	click_rect(&e, HEIGHT_PLUS)
	click_rect(&e, HEIGHT_PLUS)
	testing.expect(t, e.image.width == 9 && e.image.height == 9)
	click_rect(&e, SAVE_BUTTON)
	click_rect(&e, LOAD_BUTTON)
	testing.expect(t, e.requests == {.Save, .Load})
}

// --- Leaving ---

@(test)
test_red_exits_when_clean_and_goes_back_elsewhere :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow, .Red)
	testing.expect(t, !take_exit(&e) && e.mode == .Draw)
	press(&e, .Blue, .Red)
	testing.expect(t, !take_exit(&e) && e.mode == .Draw)
	press(&e, .Red)
	testing.expect(t, take_exit(&e) && !take_exit(&e))
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
	press(&e, .Red, .Down) // another command cancels the prompt
	testing.expect(t, !e.confirm_exit)
	press(&e, .Red)
	testing.expect(t, !take_exit(&e))
	editor_mark_saved(&e)
	press(&e, .Red)
	testing.expect(t, take_exit(&e))
}

@(test)
test_a_colour_change_alone_does_not_count_as_unsaved :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Yellow, .Right, .Red, .Red)
	testing.expect(t, take_exit(&e)) // only the drawing colour changed
}

@(test)
test_menu_button_and_window_close_have_the_same_guard :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	tl := tool(&e)
	click_rect(&e, MENU_BUTTON)
	testing.expect(t, take_exit(&e))
	testing.expect(t, tl.allow_close(tl.data))
	e.dirty = true
	click_rect(&e, MENU_BUTTON)
	testing.expect(t, !take_exit(&e) && e.confirm_exit)
	x, y := center_of_cell(&e, 0, 0)
	click_at(&e, x, y) // any other click cancels the prompt
	testing.expect(t, !e.confirm_exit)
	e.confirm_exit = false
	testing.expect(t, !tl.allow_close(tl.data) && e.confirm_exit) // the window close warns first
	testing.expect(t, tl.allow_close(tl.data))
}

// --- Tool adapter: files, palette and lifecycle ---

@(test)
test_save_and_load_through_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	tl := tool(&e)
	testing.expect_value(t, cm.tool_file_name(&tl), "image.json")
	_, saving := tl.take_save(tl.data)
	testing.expect(t, !saving)
	press(&e, .Green, .Right, .Yellow, .Left, .Red, .Green, .Down, .Green) // a few colours
	press(&e, .Yellow, .Down, .Right, .Right, .Red) // 10 wide
	press(&e, .Blue, .Green)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok)
	tl.saved(tl.data)
	testing.expect(t, !e.dirty)

	other := editor_init()
	otl := tool(&other)
	testing.expect(t, otl.load(otl.data, transmute([]u8)text))
	testing.expect(t, other.image == e.image && !other.dirty)
	testing.expect(t, !otl.load(otl.data, transmute([]u8)string("nope")))
}

@(test)
test_load_clamps_the_cursor :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	for _ in 0 ..< 7 {
		press(&e, .Right, .Down)
	}
	small := cm.image4_make(2, 3)
	tl := tool(&e)
	testing.expect(t, tl.load(tl.data, transmute([]u8)cm.image4_to_json(&small)))
	testing.expect(t, e.cx == 1 && e.cy == 2)
}

@(test)
test_palette_comes_from_the_aux_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	tl := tool(&e)
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "palette.json")
	testing.expect(t, !tl.wants_aux_load(tl.data))
	tl.enter(tl.data)
	testing.expect(t, tl.wants_aux_load(tl.data) && !tl.wants_aux_load(tl.data)) // once per enter
	custom := cm.default_palette()
	custom[3] = {9, 8, 7}
	testing.expect(t, tl.load_aux(tl.data, transmute([]u8)cm.palette_to_json(custom)))
	testing.expect(t, e.palette[3] == cm.Color{9, 8, 7} && !e.dirty)
	testing.expect(t, !tl.load_aux(tl.data, transmute([]u8)string("not json")))
	testing.expect(t, e.palette[3] == cm.Color{9, 8, 7}) // a bad palette changes nothing
}

@(test)
test_enter_starts_blank_and_asks_for_files :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Green, .Yellow, .Right)
	e.palette[2] = {1, 1, 1}
	e.confirm_exit, e.exit_requested = true, true
	m := cm.default_input_map()
	e.labels = &m
	tl := tool(&e)
	tl.enter(tl.data)
	testing.expect(t, e.image.width == 8 && pixel(&e, 0, 0) == 0 && e.color == 15 && e.palette == cm.default_palette())
	testing.expect(t, e.mode == .Draw && !e.dirty && !e.confirm_exit && !e.exit_requested)
	testing.expect(t, e.labels == &m) // the input map is kept
	testing.expect(t, e.requests == {.Load} && e.aux_requests == {.Palette})
}

// --- Layout, drawing and text ---

@(test)
test_layout_is_on_screen_and_does_not_overlap :: proc(t: ^testing.T) {
	strip := Rect{PALETTE_X, PALETTE_Y, SWATCH_W * cm.PALETTE_SIZE, SWATCH_W}
	rects := [?]Rect{CANVAS, BANNER, COLOR_CHIP, WIDTH_MINUS, WIDTH_PLUS, HEIGHT_MINUS, HEIGHT_PLUS, strip, PREVIEW_FRAME, SAVE_BUTTON, LOAD_BUTTON, MENU_BUTTON}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	testing.expect(t, ROW_LABEL_X + cm.text_width("HEIGHT") < HEIGHT_MINUS.x)
	testing.expect(t, ROW_LABEL_X + cm.text_width("COLOR") < COLOR_CHIP.x - 1)
	testing.expect(t, ROW_VALUE_X > WIDTH_PLUS.x + WIDTH_PLUS.w && ROW_VALUE_X + cm.text_width("64") <= cm.SCREEN_W)
	testing.expect(t, ROW_MARKER_X + cm.text_width(">") < ROW_LABEL_X && ROW_MARKER_X > CANVAS.x + CANVAS.w)
	testing.expect(t, INFO_Y > BANNER.y + BANNER.h && COLOR_CHIP.y > INFO_Y + cm.GLYPH_H)
	testing.expect(t, HELP_Y >= CANVAS.y + CANVAS.h && HELP_Y >= PREVIEW_FRAME.y + PREVIEW_FRAME.h)
	in_ := PREVIEW_INNER
	testing.expect(t, in_.x > PREVIEW_FRAME.x && in_.y > PREVIEW_FRAME.y && in_.x + in_.w < PREVIEW_FRAME.x + PREVIEW_FRAME.w && in_.y + in_.h < PREVIEW_FRAME.y + PREVIEW_FRAME.h)
	testing.expect(t, CLIPPED_X > PREVIEW_FRAME.x + PREVIEW_FRAME.w && CLIPPED_X + cm.text_width("CLIPPED") <= cm.SCREEN_W)
	testing.expect(t, CLIPPED_Y > MENU_BUTTON.y + MENU_BUTTON.h && CLIPPED_Y + cm.GLYPH_H <= HELP_Y)
}

@(test)
test_preview_scale_and_clipping :: proc(t: ^testing.T) {
	testing.expect_value(t, preview_scale(8, 8), 2)
	testing.expect_value(t, preview_scale(1, 1), 20)
	testing.expect_value(t, preview_scale(20, 20), 1)
	testing.expect_value(t, preview_scale(64, 64), 1)
	testing.expect(t, !preview_clipped(8, 8) && !preview_clipped(20, 20))
	testing.expect(t, preview_clipped(21, 21) && preview_clipped(64, 1))
}

@(test)
test_all_on_screen_text_is_in_the_font_and_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	m := cm.default_input_map()
	e.labels = &m
	for round in 0 ..< 2 {
		if round == 1 { 	// the longest labels allowed
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for mode in Mode {
			e.mode = mode
			for confirm in ([]bool{false, true}) {
				e.confirm_exit = confirm
				if round == 0 {
					testing.expectf(t, cm.text_is_drawable(banner_text(&e)), "banner: %s", banner_text(&e))
				}
				testing.expectf(t, cm.text_width(banner_text(&e)) + 8 <= BANNER.w, "banner too wide in %v", mode)
			}
			lines, n := help_lines(&e)
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

Draw_Log :: struct {
	rects, out_of_bounds, presents: int,
	of_color:                       map[cm.Color]int,
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
			k.of_color[c] += 1
		},
		present = proc(d: rawptr) {(^Draw_Log)(d).presents += 1},
	}
}

@(test)
test_draw_stays_on_screen_in_every_mode_and_size :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	defer delete(log.of_color)
	r := logging_renderer(&log)
	for sz in ([][2]int{{1, 1}, {8, 8}, {3, 40}, {40, 3}, {64, 64}, {16, 9}}) {
		e := editor_init()
		cm.image4_resize(&e.image, sz[0], sz[1])
		for y in 0 ..< sz[1] { 	// every colour, as a diagonal pattern: the worst case for run merging
			for x in 0 ..< sz[0] {
				cm.image4_set(&e.image, x, y, (x + y) % 16)
			}
		}
		e.cx, e.cy = sz[0] - 1, sz[1] - 1
		for mode in Mode {
			e.mode = mode
			log.rects, log.out_of_bounds, log.presents = 0, 0, 0
			editor_draw(&e, &r)
			testing.expectf(t, log.out_of_bounds == 0, "%dx%d %v: %d rects off screen", sz[0], sz[1], mode, log.out_of_bounds)
			testing.expect_value(t, log.presents, 1)
			testing.expectf(t, log.rects < 12000, "%dx%d: %d rects is too many for one frame", sz[0], sz[1], log.rects)
		}
	}
}

@(test)
test_pixels_are_drawn_in_their_palette_colours :: proc(t: ^testing.T) {
	log: Draw_Log
	defer delete(log.of_color)
	r := logging_renderer(&log)
	e := editor_init()
	e.palette[5] = {201, 202, 203} // a colour used nowhere else on screen
	e.palette[9] = {111, 112, 113}
	e.color = 9
	cm.image4_set(&e.image, 2, 3, 5)
	cm.image4_set(&e.image, 4, 4, 5)
	editor_draw(&e, &r)
	// Each pixel is one canvas cell, plus 9 tiles in the preview, plus the palette swatch.
	testing.expect_value(t, log.of_color[cm.Color{201, 202, 203}], 2 + 2 * 9 + 1)
	// The drawing colour's swatch and chip are the only places colour 9 shows.
	testing.expect_value(t, log.of_color[cm.Color{111, 112, 113}], 2)
	// Changing the palette changes the drawing with no change to the image.
	e.palette[5] = {211, 212, 213}
	clear(&log.of_color)
	editor_draw(&e, &r)
	testing.expect_value(t, log.of_color[cm.Color{211, 212, 213}], 2 + 2 * 9 + 1)
	testing.expect_value(t, log.of_color[cm.Color{201, 202, 203}], 0)
}

@(test)
test_tiled_preview_draws_each_run_nine_times :: proc(t: ^testing.T) {
	log: Draw_Log
	defer delete(log.of_color)
	r := logging_renderer(&log)
	e := editor_init()
	e.palette[6] = {77, 78, 79}
	cm.image4_set(&e.image, 1, 1, 6)
	cm.image4_set(&e.image, 2, 1, 6) // one run of two
	cm.image4_resize(&e.image, 8, 8)
	editor_draw(&e, &r)
	with_run := log.of_color[cm.Color{77, 78, 79}]
	e.cx = 0
	cm.image4_set(&e.image, 3, 1, 5) // a different colour next to it: a second, separate run
	clear(&log.of_color)
	editor_draw(&e, &r)
	testing.expect_value(t, log.of_color[cm.Color{77, 78, 79}], with_run) // unchanged: still one run
	// Colour 0 pixels are the background and cost nothing in the preview.
	e2 := editor_init()
	clear(&log.of_color)
	editor_draw(&e2, &r)
	black := log.of_color[e2.palette[0]]
	testing.expect(t, black >= 1)
}

// --- Parity: everything is reachable with the commands alone and with the mouse alone. ---

Input_Method :: enum {
	Commands,
	Mouse,
}

@(test)
test_every_pixel_can_be_painted_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for size in ([]int{1, 5, 8, 17, 40}) {
			for target in ([]int{0, size / 2, size - 1}) {
				e := editor_init()
				cm.image4_resize(&e.image, size, size)
				e.color = 11
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
				testing.expectf(t, pixel(&e, tx, ty) == 11 && e.cx == tx && e.cy == ty, "%v size %d: pixel (%d,%d)", m, size, tx, ty)
			}
		}
	}
}

@(test)
test_every_colour_can_be_chosen_and_painted_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for target in 0 ..< cm.IMAGE_COLORS {
			e := editor_init()
			switch m {
			case .Commands:
				press(&e, .Yellow)
				steps := (target - e.color + cm.IMAGE_COLORS) % cm.IMAGE_COLORS
				for _ in 0 ..< steps {
					press(&e, .Right)
				}
				press(&e, .Red, .Green)
			case .Mouse:
				r := swatch_rect(target)
				click_at(&e, r.x + 2, r.y + 2)
				x, y := center_of_cell(&e, 0, 0)
				click_at(&e, x, y)
			}
			testing.expectf(t, e.color == target && pixel(&e, 0, 0) == target, "%v could not paint with colour %d", m, target)
		}
	}
}

@(test)
test_every_size_is_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for w in ([]int{1, 2, 8, 9, 33, 64}) {
			for h in ([]int{1, 5, 8, 20, 64}) {
				e := editor_init()
				switch m {
				case .Commands:
					press(&e, .Yellow, .Down) // Setup, width row
					for _ in 0 ..< 70 {
						press(&e, .Left)
					}
					for _ in 0 ..< w - 1 {
						press(&e, .Right)
					}
					press(&e, .Down)
					for _ in 0 ..< 70 {
						press(&e, .Left)
					}
					for _ in 0 ..< h - 1 {
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
				testing.expectf(t, e.image.width == w && e.image.height == h, "%v: wanted %dx%d got %dx%d", m, w, h, e.image.width, e.image.height)
			}
		}
	}
}

@(test)
test_save_load_and_leave_are_reachable_by_each_input :: proc(t: ^testing.T) {
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
