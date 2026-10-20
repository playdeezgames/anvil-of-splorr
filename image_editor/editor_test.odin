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
	testing.expect_value(t, e.row, Setup_Row.Clear) // wrapped: one press from the top
	press(&e, .Up)
	testing.expect_value(t, e.row, Setup_Row.Replace_Color)
	press(&e, .Down, .Down)
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
	rects := [?]Rect{CANVAS, BANNER, COLOR_CHIP, WIDTH_MINUS, WIDTH_PLUS, HEIGHT_MINUS, HEIGHT_PLUS, strip, PREVIEW_FRAME, SAVE_BUTTON, LOAD_BUTTON, MENU_BUTTON, FLIP_H_BUTTON, FLIP_V_BUTTON, ROT_L_BUTTON, ROT_R_BUTTON, ROT_180_BUTTON, FRAME_BUTTON, FILL_BUTTON, FLOOD_BUTTON, REPLACE_BUTTON, CLEAR_BUTTON}
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
	testing.expect(t, FLIP_H_BUTTON.x > MENU_BUTTON.x + MENU_BUTTON.w && FRAME_BUTTON.x > ROT_180_BUTTON.x + ROT_180_BUTTON.w - 1)
	testing.expect(t, FRAME_BUTTON.x + FRAME_BUTTON.w <= cm.SCREEN_W && FILL_BUTTON.x + FILL_BUTTON.w <= cm.SCREEN_W)
	testing.expect(t, FLIP_H_BUTTON.x > PREVIEW_FRAME.x + PREVIEW_FRAME.w) // clear of the preview
	for pair in ([]struct {
			text: string,
			rc:   Rect,
		}{{"SAVE", SAVE_BUTTON}, {"LOAD", LOAD_BUTTON}, {"MENU", MENU_BUTTON}, {"FLIP H", FLIP_H_BUTTON}, {"FLIP V", FLIP_V_BUTTON}, {"ROT L", ROT_L_BUTTON}, {"ROT R", ROT_R_BUTTON}, {"ROT 180", ROT_180_BUTTON}, {"FRAME", FRAME_BUTTON}, {"FILL", FILL_BUTTON}, {"FLOOD", FLOOD_BUTTON}, {"REPLACE", REPLACE_BUTTON}, {"CLEAR", CLEAR_BUTTON}}) {
		testing.expectf(t, cm.text_width(pair.text) <= pair.rc.w - 2 && cm.GLYPH_H <= pair.rc.h, "label %s does not fit its button", pair.text)
	}
	testing.expect(t, CLIPPED_X + cm.text_width("CLIPPED") < FLIP_H_BUTTON.x) // the clipped flag clears the transform column
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

// --- Flips ---

// Opens Setup and moves down to a row.
goto_row :: proc(e: ^Editor, row: Setup_Row) {
	press(e, .Yellow)
	for e.row != row {
		press(e, .Down)
	}
}

// A small asymmetric picture: colours 1, 2, 3 across the top row, 4 at the bottom-left.
flip_fixture :: proc() -> Editor {
	e := editor_init()
	cm.image4_resize(&e.image, 3, 2)
	for c, x in ([]int{1, 2, 3}) {
		cm.image4_set(&e.image, x, 0, c)
	}
	cm.image4_set(&e.image, 0, 1, 4)
	return e
}

@(test)
test_flip_rows_flip_the_whole_image_with_green :: proc(t: ^testing.T) {
	e := flip_fixture()
	goto_row(&e, .Flip_Horizontal)
	press(&e, .Green)
	testing.expect(t, pixel(&e, 0, 0) == 3 && pixel(&e, 1, 0) == 2 && pixel(&e, 2, 0) == 1 && pixel(&e, 2, 1) == 4 && pixel(&e, 0, 1) == 0)
	testing.expect(t, e.dirty)
	press(&e, .Green) // flipping again undoes it
	testing.expect(t, pixel(&e, 0, 0) == 1 && pixel(&e, 2, 0) == 3 && pixel(&e, 0, 1) == 4 && pixel(&e, 2, 1) == 0)
	press(&e, .Down, .Green) // Flip vertical
	testing.expect_value(t, e.row, Setup_Row.Flip_Vertical)
	testing.expect(t, pixel(&e, 0, 1) == 1 && pixel(&e, 1, 1) == 2 && pixel(&e, 2, 1) == 3 && pixel(&e, 0, 0) == 4)
	testing.expect_value(t, e.mode, Mode.Setup) // stays in Setup, ready to flip again
	testing.expect(t, e.image.width == 3 && e.image.height == 2) // the size is unchanged
}

@(test)
test_flipping_changes_the_picture_not_the_drawing_state :: proc(t: ^testing.T) {
	e := flip_fixture()
	e.color = 9
	e.cx, e.cy = 2, 1
	goto_row(&e, .Flip_Horizontal)
	press(&e, .Green, .Down, .Green)
	testing.expect(t, e.color == 9 && e.cx == 2 && e.cy == 1) // cursor and colour stay put
	testing.expect_value(t, e.palette, cm.default_palette())
}

@(test)
test_green_on_other_setup_rows_does_not_flip :: proc(t: ^testing.T) {
	e := flip_fixture()
	before := e.image
	press(&e, .Yellow, .Green) // colour row
	press(&e, .Down, .Green) // width row
	press(&e, .Down, .Green) // height row
	testing.expect(t, e.image == before && !e.dirty)
}

@(test)
test_a_flip_that_changes_nothing_is_not_an_edit :: proc(t: ^testing.T) {
	e := editor_init() // blank: symmetric both ways
	goto_row(&e, .Flip_Horizontal)
	press(&e, .Green, .Down, .Green)
	testing.expect(t, !e.dirty)
	cm.image4_set(&e.image, 3, 3, 5) // not symmetric in an 8 x 8
	press(&e, .Green)
	testing.expect(t, e.dirty)
	editor_mark_saved(&e)
	e.image = cm.image4_make(1, 1) // a 1 x 1 image is its own mirror
	press(&e, .Green, .Up, .Green)
	testing.expect(t, !e.dirty)
}

@(test)
test_flip_buttons_flip_and_open_setup_on_their_row :: proc(t: ^testing.T) {
	e := flip_fixture()
	click_rect(&e, FLIP_H_BUTTON)
	testing.expect(t, e.mode == .Setup && e.row == .Flip_Horizontal && pixel(&e, 0, 0) == 3 && e.dirty)
	click_rect(&e, FLIP_H_BUTTON) // again: back to how it was
	testing.expect(t, pixel(&e, 0, 0) == 1 && pixel(&e, 2, 0) == 3)
	click_rect(&e, FLIP_V_BUTTON)
	testing.expect(t, e.row == .Flip_Vertical && pixel(&e, 0, 1) == 1 && pixel(&e, 0, 0) == 4)
	e.mode = .Draw
	click_rect(&e, FLIP_V_BUTTON) // from Draw mode too
	testing.expect(t, e.mode == .Setup && pixel(&e, 0, 0) == 1)
}

@(test)
test_a_flip_counts_as_an_unsaved_change_for_leaving :: proc(t: ^testing.T) {
	e := flip_fixture()
	click_rect(&e, FLIP_H_BUTTON)
	testing.expect(t, e.dirty)
	press(&e, .Red) // Setup -> Draw
	press(&e, .Red) // dirty: only asks
	testing.expect(t, !take_exit(&e) && e.confirm_exit)
	press(&e, .Red)
	testing.expect(t, take_exit(&e))
}

@(test)
test_flip_text_is_drawable_and_buttons_light_up :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	e.mode = .Setup
	lines, n := help_lines(&e)
	for line in lines[:n] {
		testing.expect(t, cm.text_is_drawable(line))
	}
	testing.expect_value(t, lines[2], "GREEN: RUN A TRANSFORM OR TOOL")
	lit := 0
	r := cm.Renderer {
		data = &lit,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			// The button's own background rect, in the highlight colour.
			if x == FLIP_H_BUTTON.x && y == FLIP_H_BUTTON.y && w == FLIP_H_BUTTON.w && c == HILITE {
				(^int)(d)^ += 1
			}
		},
		present = proc(d: rawptr) {},
	}
	e.row = .Color
	editor_draw(&e, &r)
	testing.expect_value(t, lit, 0)
	e.row = .Flip_Horizontal
	editor_draw(&e, &r)
	testing.expect_value(t, lit, 1) // lit while its Setup row is selected
	e.mode = .Draw
	lit = 0
	editor_draw(&e, &r)
	testing.expect_value(t, lit, 0) // and not outside Setup
}

@(test)
test_both_flips_are_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for horizontal in ([]bool{true, false}) {
			e := flip_fixture()
			switch m {
			case .Commands:
				goto_row(&e, horizontal ? .Flip_Horizontal : .Flip_Vertical)
				press(&e, .Green)
			case .Mouse:
				click_rect(&e, horizontal ? FLIP_H_BUTTON : FLIP_V_BUTTON)
			}
			moved := horizontal ? pixel(&e, 2, 0) == 1 : pixel(&e, 0, 1) == 1
			testing.expectf(t, moved, "%v could not flip horizontal=%v", m, horizontal)
		}
	}
}

// --- Rotation ---

@(test)
test_rotate_rows_turn_the_image :: proc(t: ^testing.T) {
	e := flip_fixture() // 3 x 2: row 0 = 1 2 3, row 1 = 4 . .
	goto_row(&e, .Rotate_Right)
	press(&e, .Green)
	testing.expect(t, e.image.width == 2 && e.image.height == 3 && e.dirty)
	// Clockwise: the top row becomes the right column, read top to bottom: 1 2 3.
	testing.expect(t, pixel(&e, 1, 0) == 1 && pixel(&e, 1, 1) == 2 && pixel(&e, 1, 2) == 3)
	testing.expect(t, pixel(&e, 0, 0) == 4 && pixel(&e, 0, 1) == 0)
	press(&e, .Up, .Green) // Rotate left undoes it
	testing.expect(t, e.image.width == 3 && e.image.height == 2)
	testing.expect(t, pixel(&e, 0, 0) == 1 && pixel(&e, 1, 0) == 2 && pixel(&e, 2, 0) == 3 && pixel(&e, 0, 1) == 4)
	// Left alone: the top row becomes the left column, read bottom to top: 1 2 3.
	press(&e, .Green)
	testing.expect(t, pixel(&e, 0, 2) == 1 && pixel(&e, 0, 1) == 2 && pixel(&e, 0, 0) == 3 && pixel(&e, 1, 2) == 4)
	press(&e, .Up, .Up) // back to the 180 row? (Rotate_Left -> Flip_Vertical -> Flip_Horizontal): see below
}

@(test)
test_rotate_180_keeps_the_size :: proc(t: ^testing.T) {
	e := flip_fixture()
	goto_row(&e, .Rotate_180)
	press(&e, .Green)
	testing.expect(t, e.image.width == 3 && e.image.height == 2)
	testing.expect(t, pixel(&e, 2, 1) == 1 && pixel(&e, 1, 1) == 2 && pixel(&e, 0, 1) == 3 && pixel(&e, 2, 0) == 4)
	press(&e, .Green)
	testing.expect(t, pixel(&e, 0, 0) == 1 && pixel(&e, 0, 1) == 4) // twice is nothing
}

@(test)
test_turning_a_blank_square_is_not_an_edit_but_a_non_square_is :: proc(t: ^testing.T) {
	e := editor_init() // blank 8 x 8
	for row in ([]Setup_Row{.Rotate_Left, .Rotate_Right, .Rotate_180}) {
		goto_row(&e, row)
		press(&e, .Green)
		testing.expect(t, !e.dirty)
	}
	e.image = cm.image4_make(3, 5) // blank, but a quarter turn changes its size
	goto_row(&e, .Rotate_Right)
	press(&e, .Green)
	testing.expect(t, e.dirty && e.image.width == 5 && e.image.height == 3)
}

@(test)
test_rotation_keeps_the_cursor_inside :: proc(t: ^testing.T) {
	e := editor_init()
	cm.image4_resize(&e.image, 8, 2)
	e.cx, e.cy = 7, 1
	goto_row(&e, .Rotate_Left)
	press(&e, .Green)
	testing.expect(t, e.image.width == 2 && e.image.height == 8)
	testing.expect(t, e.cx == 1 && e.cy == 1) // clamped into the new size
}

@(test)
test_rotate_buttons :: proc(t: ^testing.T) {
	e := flip_fixture()
	click_rect(&e, ROT_R_BUTTON)
	testing.expect(t, e.image.width == 2 && e.image.height == 3 && e.mode == .Setup && e.row == .Rotate_Right)
	click_rect(&e, ROT_L_BUTTON)
	testing.expect(t, e.image.width == 3 && pixel(&e, 0, 0) == 1 && e.row == .Rotate_Left)
	click_rect(&e, ROT_180_BUTTON)
	testing.expect(t, pixel(&e, 2, 1) == 1 && e.row == .Rotate_180)
}

// --- Rectangles ---

// An 8 x 8 image with the drawing colour set to 6.
rect_fixture :: proc() -> Editor {
	e := editor_init()
	e.color = 6
	return e
}

pixels_of_colour :: proc(e: ^Editor, c: int) -> (n: int) {
	for y in 0 ..< e.image.height {
		for x in 0 ..< e.image.width {
			if pixel(e, x, y) == c {
				n += 1
			}
		}
	}
	return
}

@(test)
test_frame_from_the_keyboard :: proc(t: ^testing.T) {
	e := rect_fixture()
	press(&e, .Right, .Down) // first corner (1,1)
	goto_row(&e, .Frame)
	press(&e, .Green)
	testing.expect(t, e.mode == .Rect && e.shape == .Frame && e.ax == 1 && e.ay == 1)
	testing.expect(t, !e.dirty) // placing changes nothing yet
	press(&e, .Right, .Right, .Right, .Down, .Down) // second corner (4,3)
	testing.expect(t, e.cx == 4 && e.cy == 3 && pixels_of_colour(&e, 6) == 0)
	press(&e, .Green)
	testing.expect(t, e.mode == .Draw && e.shape == .None && e.dirty)
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			border := x >= 1 && x <= 4 && y >= 1 && y <= 3 && (x == 1 || x == 4 || y == 1 || y == 3)
			testing.expectf(t, (pixel(&e, x, y) == 6) == border, "frame pixel (%d,%d)", x, y)
		}
	}
	testing.expect_value(t, pixels_of_colour(&e, 6), 10) // 4 x 3 outline
	testing.expect(t, e.cx == 4 && e.cy == 3) // the cursor stays at the far corner
}

@(test)
test_fill_from_the_keyboard_in_any_direction :: proc(t: ^testing.T) {
	e := rect_fixture()
	e.cx, e.cy = 5, 5
	goto_row(&e, .Fill)
	press(&e, .Green, .Left, .Left, .Left, .Up, .Up, .Green) // up and to the left of the first corner
	testing.expect_value(t, pixels_of_colour(&e, 6), 4 * 3)
	for y in 3 ..= 5 {
		for x in 2 ..= 5 {
			testing.expect_value(t, pixel(&e, x, y), 6)
		}
	}
}

@(test)
test_a_rectangle_uses_the_drawing_colour_and_overwrites :: proc(t: ^testing.T) {
	e := rect_fixture()
	cm.image4_set(&e.image, 1, 1, 9)
	cm.image4_set(&e.image, 2, 2, 9)
	e.color = 3
	goto_row(&e, .Fill)
	press(&e, .Green, .Right, .Right, .Down, .Down, .Green)
	testing.expect(t, pixel(&e, 1, 1) == 3 && pixel(&e, 2, 2) == 3 && pixel(&e, 0, 0) == 3)
	testing.expect_value(t, pixels_of_colour(&e, 3), 9)
	// Painting with colour 0 erases a region.
	e.color = 0
	press(&e, .Down, .Down, .Down) // cursor stays; go to the Fill row again
	e.mode = .Setup
	e.row = .Fill
	e.cx, e.cy = 0, 0
	press(&e, .Green, .Right, .Right, .Down, .Down, .Green)
	testing.expect_value(t, pixels_of_colour(&e, 3), 0)
}

@(test)
test_a_single_cell_rectangle :: proc(t: ^testing.T) {
	e := rect_fixture()
	e.cx, e.cy = 3, 3
	goto_row(&e, .Frame)
	press(&e, .Green, .Green) // second corner = the first
	testing.expect(t, pixels_of_colour(&e, 6) == 1 && pixel(&e, 3, 3) == 6)
}

@(test)
test_red_cancels_a_rectangle_and_nothing_is_drawn :: proc(t: ^testing.T) {
	e := rect_fixture()
	goto_row(&e, .Fill)
	press(&e, .Green, .Right, .Right, .Down, .Red)
	testing.expect(t, e.mode == .Draw && e.shape == .None && !e.dirty && pixels_of_colour(&e, 6) == 0)
	testing.expect(t, !take_exit(&e)) // that red only cancelled
	press(&e, .Red) // and now it leaves
	testing.expect(t, take_exit(&e))
}

@(test)
test_rect_mode_ignores_other_commands :: proc(t: ^testing.T) {
	e := rect_fixture()
	goto_row(&e, .Frame)
	press(&e, .Green, .Yellow, .Blue)
	testing.expect(t, e.mode == .Rect && e.shape == .Frame && e.requests == {})
}

@(test)
test_the_cursor_stays_inside_while_placing :: proc(t: ^testing.T) {
	e := rect_fixture()
	goto_row(&e, .Fill)
	press(&e, .Green)
	for _ in 0 ..< 20 {
		press(&e, .Right, .Down)
	}
	testing.expect(t, e.cx == 7 && e.cy == 7)
	for _ in 0 ..< 20 {
		press(&e, .Left, .Up)
	}
	press(&e, .Green)
	testing.expect_value(t, pixels_of_colour(&e, 6), 1) // from the corner back to itself
}

@(test)
test_mouse_arms_a_tool_then_a_drag_draws_the_rectangle :: proc(t: ^testing.T) {
	e := rect_fixture()
	click_rect(&e, FRAME_BUTTON)
	testing.expect(t, e.shape == .Frame && e.mode == .Draw && !e.rect_drag)
	x0, y0 := center_of_cell(&e, 1, 1)
	mouse(&e, x0, y0, true) // press: the first corner
	testing.expect(t, e.rect_drag && e.mode == .Rect && e.ax == 1 && e.ay == 1 && pixels_of_colour(&e, 6) == 0)
	x, y := center_of_cell(&e, 4, 2)
	editor_handle_event(&e, cm.Mouse_Move{x, y})
	testing.expect(t, e.cx == 4 && e.cy == 2)
	x, y = center_of_cell(&e, 5, 4) // dragging further: the last position counts
	editor_handle_event(&e, cm.Mouse_Move{x, y})
	mouse(&e, x, y, false) // release: draws
	testing.expect(t, !e.rect_drag && e.mode == .Draw && e.shape == .None && e.dirty)
	testing.expect_value(t, pixels_of_colour(&e, 6), 2 * 5 + 2 * (4 - 2)) // the outline of a 5 x 4 rectangle: 14
}

@(test)
test_mouse_fill_drag_and_the_tool_is_one_shot :: proc(t: ^testing.T) {
	e := rect_fixture()
	click_rect(&e, FILL_BUTTON)
	x0, y0 := center_of_cell(&e, 2, 2)
	mouse(&e, x0, y0, true)
	x, y := center_of_cell(&e, 4, 3)
	editor_handle_event(&e, cm.Mouse_Move{x, y})
	mouse(&e, x, y, false)
	testing.expect_value(t, pixels_of_colour(&e, 6), 3 * 2)
	// The tool is spent: the next click paints one pixel as usual.
	x, y = center_of_cell(&e, 7, 7)
	click_at(&e, x, y)
	testing.expect(t, pixel(&e, 7, 7) == 6 && pixels_of_colour(&e, 6) == 7 && e.shape == .None)
}

@(test)
test_clicking_the_tool_button_again_disarms_it :: proc(t: ^testing.T) {
	e := rect_fixture()
	click_rect(&e, FRAME_BUTTON)
	click_rect(&e, FRAME_BUTTON)
	testing.expect_value(t, e.shape, cm.Shape.None)
	click_rect(&e, FRAME_BUTTON)
	click_rect(&e, FILL_BUTTON) // switching tools
	testing.expect_value(t, e.shape, cm.Shape.Fill)
	press(&e, .Red) // red disarms a mouse-armed tool before it would leave
	testing.expect(t, e.shape == .None && !take_exit(&e))
	x, y := center_of_cell(&e, 3, 3) // and clicks paint again
	click_at(&e, x, y)
	testing.expect_value(t, pixel(&e, 3, 3), 6)
}

@(test)
test_a_click_places_the_second_corner_of_a_keyboard_rectangle :: proc(t: ^testing.T) {
	e := rect_fixture()
	e.cx, e.cy = 1, 1
	goto_row(&e, .Fill)
	press(&e, .Green)
	x, y := center_of_cell(&e, 3, 4)
	click_at(&e, x, y)
	testing.expect(t, e.mode == .Draw && e.shape == .None)
	testing.expect_value(t, pixels_of_colour(&e, 6), 3 * 4)
}

@(test)
test_other_buttons_abandon_a_rectangle_but_colour_choices_do_not :: proc(t: ^testing.T) {
	e := rect_fixture()
	goto_row(&e, .Frame)
	press(&e, .Green)
	r := swatch_rect(2)
	click_at(&e, r.x + 2, r.y + 2) // choosing a colour keeps going
	testing.expect(t, e.mode == .Rect && e.shape == .Frame && e.color == 2)
	right_click_at(&e, r.x + 2, r.y + 2) // so does picking one
	testing.expect(t, e.mode == .Rect && e.shape == .Frame)
	press(&e, .Green) // draws with the colour chosen meanwhile
	testing.expect(t, pixels_of_colour(&e, 2) == 1 && e.mode == .Draw)
	goto_row(&e, .Frame)
	press(&e, .Green)
	click_rect(&e, WIDTH_PLUS) // any other button abandons it
	testing.expect(t, e.shape == .None && e.mode == .Setup && !e.rect_drag)
	click_rect(&e, FRAME_BUTTON)
	click_rect(&e, SAVE_BUTTON)
	testing.expect(t, e.shape == .None && .Save in e.requests)
}

@(test)
test_rectangle_that_changes_nothing_is_not_an_edit :: proc(t: ^testing.T) {
	e := rect_fixture()
	goto_row(&e, .Fill)
	press(&e, .Green, .Right, .Green)
	testing.expect(t, e.dirty)
	editor_mark_saved(&e)
	press(&e, .Left, .Left) // cursor is already at the right end of the fill; move back to the corner
	e.mode, e.row = .Setup, .Fill
	e.cx, e.cy = 0, 0
	press(&e, .Green, .Right, .Green) // the same rectangle again, same colour
	testing.expect(t, !e.dirty)
}

@(test)
test_rectangle_text_is_drawable_and_fits :: proc(t: ^testing.T) {
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
}

@(test)
test_the_rectangle_preview_marks_exactly_the_shape :: proc(t: ^testing.T) {
	log: Draw_Log
	defer delete(log.of_color)
	r := logging_renderer(&log)
	e := rect_fixture()
	e.mode, e.shape = .Rect, .Frame
	e.ax, e.ay, e.cx, e.cy = 1, 1, 4, 3 // a 4 x 3 frame: 10 pixels
	editor_draw(&e, &r)
	frame_marks := log.of_color[HILITE]
	e.shape = .Fill // 12 pixels
	clear(&log.of_color)
	editor_draw(&e, &r)
	testing.expect_value(t, log.of_color[HILITE] - frame_marks, 2) // the fill has two more cells than the frame
	// No preview outside Rect mode.
	e.mode = .Draw
	e.shape = .None
	clear(&log.of_color)
	editor_draw(&e, &r)
	testing.expect(t, log.of_color[HILITE] < frame_marks)
}

@(test)
test_rect_and_rotate_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for shape in ([]cm.Shape{.Frame, .Fill}) {
			e := rect_fixture()
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
			want := shape == .Frame ? 8 : 9
			testing.expectf(t, pixels_of_colour(&e, 6) == want, "%v %v: %d pixels, want %d", m, shape, pixels_of_colour(&e, 6), want)
		}
		for row in ([]Setup_Row{.Rotate_Left, .Rotate_Right, .Rotate_180}) {
			e := flip_fixture()
			switch m {
			case .Commands:
				goto_row(&e, row)
				press(&e, .Green)
			case .Mouse:
				click_rect(&e, row == .Rotate_Left ? ROT_L_BUTTON : (row == .Rotate_Right ? ROT_R_BUTTON : ROT_180_BUTTON))
			}
			moved := row == .Rotate_180 ? pixel(&e, 2, 1) == 1 : (e.image.width == 2 && e.image.height == 3)
			testing.expectf(t, moved, "%v could not %v", m, row)
		}
	}
}

// --- Flood fill, replace colour, clear ---

// 4 x 3. Row 0: 1 1 2 2   Row 1: 1 3 3 2   Row 2: 1 1 3 1   (two separate regions of colour 1 are joined
// through the left column, the lone 1 at (3,2) is not connected to them.)
region_fixture :: proc() -> Editor {
	e := editor_init()
	cm.image4_resize(&e.image, 4, 3)
	rows := [3][4]int{{1, 1, 2, 2}, {1, 3, 3, 2}, {1, 1, 3, 1}}
	for y in 0 ..< 3 {
		for x in 0 ..< 4 {
			cm.image4_set(&e.image, x, y, rows[y][x])
		}
	}
	return e
}

@(test)
test_flood_fill_row_fills_the_connected_region :: proc(t: ^testing.T) {
	e := region_fixture()
	e.color = 9
	goto_row(&e, .Flood_Fill)
	press(&e, .Green) // from the cursor at (0,0): the 1s joined through the left column
	testing.expect(t, e.dirty && e.mode == .Draw) // back to drawing after a fill
	testing.expect(t, pixel(&e, 0, 0) == 9 && pixel(&e, 1, 0) == 9 && pixel(&e, 0, 1) == 9 && pixel(&e, 0, 2) == 9 && pixel(&e, 1, 2) == 9)
	testing.expect(t, pixel(&e, 3, 2) == 1) // the separate 1 is not connected
	testing.expect(t, pixel(&e, 2, 0) == 2 && pixel(&e, 1, 1) == 3) // other colours untouched
	editor_mark_saved(&e)
	press(&e, .Green) // nothing left to fill with the same colour: not an edit
	testing.expect(t, !e.dirty)
}

@(test)
test_flood_fill_starts_from_the_cursor :: proc(t: ^testing.T) {
	e := region_fixture()
	e.color = 8
	press(&e, .Right, .Right, .Down) // (2,1): colour 3, connected to (1,1) and (2,2)
	goto_row(&e, .Flood_Fill)
	press(&e, .Green)
	testing.expect(t, pixel(&e, 2, 1) == 8 && pixel(&e, 1, 1) == 8 && pixel(&e, 2, 2) == 8)
	testing.expect(t, pixel(&e, 0, 0) == 1 && pixel(&e, 3, 0) == 2)
}

@(test)
test_replace_color_row_changes_every_pixel_of_that_colour :: proc(t: ^testing.T) {
	e := region_fixture()
	e.color = 5
	goto_row(&e, .Replace_Color)
	press(&e, .Green) // the colour under the cursor (0,0) is 1: all of them, connected or not
	testing.expect(t, pixels_of_colour(&e, 1) == 0 && pixels_of_colour(&e, 5) == 6)
	testing.expect(t, pixel(&e, 3, 2) == 5) // including the lone one
	testing.expect(t, e.dirty && pixels_of_colour(&e, 2) == 3 && pixels_of_colour(&e, 3) == 3)
	editor_mark_saved(&e)
	press(&e, .Green) // there is no colour 5-under-cursor change left: cursor pixel is 5 and the colour is 5
	testing.expect(t, !e.dirty)
}

@(test)
test_clear_row_sets_the_whole_image :: proc(t: ^testing.T) {
	e := region_fixture()
	e.color = 12
	goto_row(&e, .Clear)
	press(&e, .Green)
	testing.expect_value(t, pixels_of_colour(&e, 12), 12)
	testing.expect(t, e.dirty && e.image.width == 4 && e.image.height == 3)
	editor_mark_saved(&e)
	press(&e, .Green)
	testing.expect(t, !e.dirty) // already all that colour
	e.color = 0 // clearing to colour 0 erases the picture
	press(&e, .Green)
	testing.expect_value(t, pixels_of_colour(&e, 0), 12)
}

@(test)
test_clear_button_acts_at_once :: proc(t: ^testing.T) {
	e := region_fixture()
	e.color = 4
	click_rect(&e, CLEAR_BUTTON)
	testing.expect(t, e.mode == .Setup && e.row == .Clear && pixels_of_colour(&e, 4) == 12 && e.dirty)
}

@(test)
test_flood_button_arms_a_one_shot_click_tool :: proc(t: ^testing.T) {
	e := region_fixture()
	e.color = 9
	click_rect(&e, FLOOD_BUTTON)
	testing.expect(t, e.point_tool == .Flood_Fill && e.mode == .Draw && !e.dirty)
	x, y := center_of_cell(&e, 2, 1) // the 3s
	click_at(&e, x, y)
	testing.expect(t, e.point_tool == .None && e.dirty)
	testing.expect(t, pixel(&e, 1, 1) == 9 && pixel(&e, 2, 1) == 9 && pixel(&e, 2, 2) == 9 && pixel(&e, 0, 0) == 1)
	// The tool is spent: the next click paints a single pixel.
	x, y = center_of_cell(&e, 0, 0)
	click_at(&e, x, y)
	testing.expect(t, pixel(&e, 0, 0) == 9 && pixel(&e, 0, 1) == 1)
}

@(test)
test_replace_button_replaces_the_clicked_colour :: proc(t: ^testing.T) {
	e := region_fixture()
	e.color = 7
	click_rect(&e, REPLACE_BUTTON)
	testing.expect(t, e.point_tool == .Replace_Color)
	x, y := center_of_cell(&e, 3, 0) // a colour 2 pixel
	click_at(&e, x, y)
	testing.expect(t, e.point_tool == .None && pixels_of_colour(&e, 2) == 0 && pixels_of_colour(&e, 7) == 3)
	testing.expect_value(t, e.cx, 3) // the click also moved the cursor there
}

@(test)
test_armed_tools_are_exclusive_toggle_and_red_disarms :: proc(t: ^testing.T) {
	e := region_fixture()
	click_rect(&e, FLOOD_BUTTON)
	click_rect(&e, REPLACE_BUTTON) // switching tools
	testing.expect(t, e.point_tool == .Replace_Color && e.shape == .None)
	click_rect(&e, FRAME_BUTTON) // a rectangle tool replaces a point tool
	testing.expect(t, e.shape == .Frame && e.point_tool == .None)
	click_rect(&e, FLOOD_BUTTON)
	testing.expect(t, e.shape == .None && e.point_tool == .Flood_Fill)
	click_rect(&e, FLOOD_BUTTON) // again: disarmed
	testing.expect_value(t, e.point_tool, Point_Tool.None)
	click_rect(&e, REPLACE_BUTTON)
	press(&e, .Red)
	testing.expect(t, e.point_tool == .None && !take_exit(&e)) // red disarmed instead of leaving
	x, y := center_of_cell(&e, 1, 1)
	click_at(&e, x, y) // clicks paint again
	testing.expect_value(t, pixel(&e, 1, 1), 15)
}

@(test)
test_other_buttons_cancel_an_armed_click_tool_but_a_colour_choice_does_not :: proc(t: ^testing.T) {
	e := region_fixture()
	click_rect(&e, FLOOD_BUTTON)
	r := swatch_rect(5)
	click_at(&e, r.x + 2, r.y + 2) // pick the colour to fill with
	testing.expect(t, e.point_tool == .Flood_Fill && e.color == 5)
	x, y := center_of_cell(&e, 0, 0)
	click_at(&e, x, y)
	testing.expect_value(t, pixel(&e, 0, 0), 5)
	testing.expect_value(t, pixels_of_colour(&e, 5), 5) // the connected region: five pixels
	click_rect(&e, REPLACE_BUTTON)
	click_rect(&e, WIDTH_PLUS) // anything else disarms
	testing.expect_value(t, e.point_tool, Point_Tool.None)
}

@(test)
test_a_click_tool_banner_and_text :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	e.point_tool = .Flood_Fill
	testing.expect_value(t, banner_text(&e), "CLICK TO FLOOD  RED: CANCEL")
	e.point_tool = .Replace_Color
	testing.expect_value(t, banner_text(&e), "CLICK TO REPLACE  RED: CANCEL")
	m := cm.default_input_map()
	for a in cm.Action {
		cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
	}
	e.labels = &m
	testing.expect(t, cm.text_width(banner_text(&e)) + 8 <= BANNER.w)
}

@(test)
test_flood_replace_and_clear_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		// Flood fill
		e := region_fixture()
		e.color = 9
		switch m {
		case .Commands:
			goto_row(&e, .Flood_Fill)
			press(&e, .Green)
		case .Mouse:
			click_rect(&e, FLOOD_BUTTON)
			x, y := center_of_cell(&e, 0, 0)
			click_at(&e, x, y)
		}
		testing.expectf(t, pixel(&e, 0, 0) == 9 && pixel(&e, 1, 2) == 9 && pixel(&e, 3, 2) == 1, "%v flood fill", m)
		// Replace colour
		e = region_fixture()
		e.color = 9
		switch m {
		case .Commands:
			goto_row(&e, .Replace_Color)
			press(&e, .Green)
		case .Mouse:
			click_rect(&e, REPLACE_BUTTON)
			x, y := center_of_cell(&e, 0, 0)
			click_at(&e, x, y)
		}
		testing.expectf(t, pixels_of_colour(&e, 1) == 0 && pixels_of_colour(&e, 9) == 6, "%v replace colour", m)
		// Clear
		e = region_fixture()
		e.color = 9
		switch m {
		case .Commands:
			goto_row(&e, .Clear)
			press(&e, .Green)
		case .Mouse:
			click_rect(&e, CLEAR_BUTTON)
		}
		testing.expectf(t, pixels_of_colour(&e, 9) == 12, "%v clear", m)
	}
}

// --- Flood fill works on every colour ---

@(test)
test_flood_fill_works_for_every_target_and_fill_colour :: proc(t: ^testing.T) {
	for target in 0 ..< 16 {
		for fill_color in 0 ..< 16 {
			if fill_color == target {
				continue
			}
			e := editor_init()
			cm.image4_resize(&e.image, 5, 4)
			// A blob of `target` in the middle on a background of the other colour that is not either of them.
			other := (target + 1) % 16
			if other == fill_color {
				other = (other + 1) % 16
			}
			cm.image4_clear(&e.image, other)
			for y in 1 ..= 2 {
				for x in 1 ..= 3 {
					cm.image4_set(&e.image, x, y, target)
				}
			}
			e.color = fill_color
			e.cx, e.cy = 2, 1
			goto_row(&e, .Flood_Fill)
			press(&e, .Green)
			ok := e.dirty && e.note == ""
			for y in 0 ..< 4 {
				for x in 0 ..< 5 {
					inside := x >= 1 && x <= 3 && y >= 1 && y <= 2
					want := inside ? fill_color : other
					if pixel(&e, x, y) != want {
						ok = false
					}
				}
			}
			testing.expectf(t, ok, "flood fill of colour %d with colour %d did not work (keyboard)", target, fill_color)

			// The same through the mouse tool.
			e2 := editor_init()
			cm.image4_resize(&e2.image, 5, 4)
			cm.image4_clear(&e2.image, other)
			for y in 1 ..= 2 {
				for x in 1 ..= 3 {
					cm.image4_set(&e2.image, x, y, target)
				}
			}
			e2.color = fill_color
			click_rect(&e2, FLOOD_BUTTON)
			x, y := center_of_cell(&e2, 3, 2)
			click_at(&e2, x, y)
			ok = pixel(&e2, 1, 1) == fill_color && pixel(&e2, 3, 2) == fill_color && pixel(&e2, 0, 0) == other && e2.note == ""
			testing.expectf(t, ok, "flood fill of colour %d with colour %d did not work (mouse)", target, fill_color)
		}
	}
}

@(test)
test_flood_fill_with_the_colour_already_there_says_so :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init() // the default drawing colour is white (15)
	cm.image4_set(&e.image, 2, 2, 15)
	cm.image4_set(&e.image, 3, 2, 15)
	e.cx, e.cy = 2, 2
	goto_row(&e, .Flood_Fill)
	press(&e, .Green) // fill a white region with white
	testing.expect_value(t, e.note, NOTE_SAME_FILL)
	testing.expect(t, !e.dirty)
	press(&e, .Up) // any input clears the message
	testing.expect_value(t, e.note, "")
	testing.expect_value(t, e.mode, Mode.Setup) // a fill that changed nothing stays put
	e.color = 3 // with another colour it fills
	e.row = .Flood_Fill
	press(&e, .Green)
	testing.expect(t, e.note == "" && pixel(&e, 2, 2) == 3 && pixel(&e, 3, 2) == 3 && e.dirty)
	testing.expect_value(t, e.mode, Mode.Draw)
	e.mode = .Setup
	// Replace and clear report the same situation.
	e.color = 3
	e.row = .Replace_Color
	press(&e, .Green)
	testing.expect_value(t, e.note, NOTE_SAME_REPLACE)
	e.row = .Clear
	e.color = 0
	press(&e, .Green) // clears to 0: that changes the two painted pixels
	testing.expect_value(t, e.note, "")
	press(&e, .Green) // and now it is already all 0
	testing.expect_value(t, e.note, NOTE_SAME_CLEAR)
	// The mouse tool reports it too; moving the mouse does not clear it, a click does.
	e.color = 0
	click_rect(&e, FLOOD_BUTTON)
	x, y := center_of_cell(&e, 0, 0)
	click_at(&e, x, y)
	testing.expect_value(t, e.note, NOTE_SAME_FILL)
	editor_handle_event(&e, cm.Mouse_Move{x + 1, y})
	testing.expect_value(t, e.note, NOTE_SAME_FILL)
	click_at(&e, x, y) // a click is input: the message goes (this click paints, so nothing re-sets it)
	testing.expect_value(t, e.note, "")
}

@(test)
test_the_notes_are_drawable_and_fit :: proc(t: ^testing.T) {
	for note in ([]string{NOTE_SAME_FILL, NOTE_SAME_REPLACE, NOTE_SAME_CLEAR}) {
		testing.expect(t, cm.text_is_drawable(note))
		testing.expect(t, cm.text_width(note) <= cm.SCREEN_W - INFO_X - 4)
	}
	log: Draw_Log
	defer delete(log.of_color)
	r := logging_renderer(&log)
	e := editor_init()
	e.note = NOTE_SAME_FILL
	editor_draw(&e, &r)
	testing.expect(t, log.of_color[WARN] > 0)
}

// --- Embedded in the tileset editor ---

embedded_fixture :: proc(w, h: int, lock := true) -> Editor {
	img := cm.image4_make(w, h)
	cm.image4_set(&img, 0, 0, 7)
	pal := cm.default_palette()
	pal[3] = {1, 2, 3}
	e := editor_init()
	editor_begin_embedded(&e, &img, &pal, lock)
	return e
}

@(test)
test_begin_embedded_copies_the_image_and_palette_and_starts_clean :: proc(t: ^testing.T) {
	e := embedded_fixture(4, 2)
	testing.expect(t, e.embedded && e.lock_size && e.mode == .Draw && !e.dirty)
	testing.expect(t, e.image.width == 4 && e.image.height == 2 && pixel(&e, 0, 0) == 7)
	testing.expect(t, e.palette[3] == cm.Color{1, 2, 3})
	testing.expect(t, e.color == DEFAULT_COLOR && e.cx == 0 && e.cy == 0 && e.requests == {} && !e.exit_requested)
	// Beginning again resets leftovers but keeps the labels.
	m := cm.default_input_map()
	e.labels = &m
	e.confirm_exit, e.note, e.shape = true, "X", .Fill
	img := cm.image4_make(2, 2)
	pal := cm.default_palette()
	editor_begin_embedded(&e, &img, &pal)
	testing.expect(t, !e.confirm_exit && e.note == "" && e.shape == .None && e.labels == &m && e.image.width == 2)
}

@(test)
test_embedded_red_leaves_at_once_even_with_changes :: proc(t: ^testing.T) {
	e := embedded_fixture(4, 4)
	press(&e, .Green) // paint: dirty
	testing.expect(t, e.dirty)
	press(&e, .Red)
	testing.expect(t, e.exit_requested && !e.confirm_exit) // no "leave anyway?" prompt
	// An armed tool is disarmed first, as everywhere.
	e = embedded_fixture(4, 4)
	click_rect(&e, FLOOD_BUTTON)
	press(&e, .Red)
	testing.expect(t, e.point_tool == .None && !e.exit_requested)
	press(&e, .Red)
	testing.expect(t, e.exit_requested)
	// The BACK (menu) button does the same.
	e = embedded_fixture(4, 4)
	e.dirty = true
	click_rect(&e, MENU_BUTTON)
	testing.expect(t, e.exit_requested && !e.confirm_exit)
}

@(test)
test_embedded_has_no_file_mode :: proc(t: ^testing.T) {
	e := embedded_fixture(4, 4)
	press(&e, .Blue)
	testing.expect_value(t, e.mode, Mode.Draw)
	press(&e, .Yellow, .Blue)
	testing.expect_value(t, e.mode, Mode.Setup) // blue does nothing in Setup either
	click_rect(&e, SAVE_BUTTON)
	click_rect(&e, LOAD_BUTTON)
	testing.expect(t, e.requests == {})
}

@(test)
test_embedded_size_is_locked :: proc(t: ^testing.T) {
	e := embedded_fixture(4, 3)
	goto_row(&e, .Width)
	press(&e, .Right, .Left, .Left)
	testing.expect(t, e.image.width == 4 && e.image.height == 3 && !e.dirty)
	testing.expect_value(t, e.note, NOTE_SIZE_LOCKED)
	press(&e, .Down, .Right) // height row
	testing.expect(t, e.image.height == 3 && e.note == NOTE_SIZE_LOCKED)
	click_rect(&e, WIDTH_PLUS)
	click_rect(&e, HEIGHT_MINUS)
	testing.expect(t, e.image.width == 4 && e.image.height == 3 && !e.dirty)
	// Unlocked (a standalone image) still resizes.
	e = embedded_fixture(4, 3, false)
	goto_row(&e, .Width)
	press(&e, .Right)
	testing.expect(t, e.image.width == 5 && e.dirty)
}

@(test)
test_embedded_quarter_turns_only_on_square_tiles :: proc(t: ^testing.T) {
	e := embedded_fixture(4, 3)
	goto_row(&e, .Rotate_Left)
	press(&e, .Green)
	testing.expect(t, e.image.width == 4 && e.image.height == 3 && !e.dirty && e.note == NOTE_NO_TURN && pixel(&e, 0, 0) == 7)
	click_rect(&e, ROT_R_BUTTON)
	testing.expect(t, e.image.width == 4 && e.note == NOTE_NO_TURN)
	// Half a turn and the flips keep the size, so they are allowed.
	click_rect(&e, ROT_180_BUTTON)
	testing.expect(t, e.dirty && pixel(&e, 3, 2) == 7 && e.note == "")
	click_rect(&e, FLIP_H_BUTTON)
	testing.expect(t, pixel(&e, 0, 2) == 7)
	// A square tile turns freely.
	sq := embedded_fixture(3, 3)
	click_rect(&sq, ROT_R_BUTTON)
	testing.expect(t, sq.dirty && sq.image.width == 3 && pixel(&sq, 2, 0) == 7 && sq.note == "")
	click_rect(&sq, ROT_L_BUTTON)
	testing.expect_value(t, pixel(&sq, 0, 0), 7)
}

@(test)
test_embedded_drawing_tools_still_work :: proc(t: ^testing.T) {
	e := embedded_fixture(5, 5)
	e.color = 9
	press(&e, .Right, .Green) // paint
	testing.expect(t, pixel(&e, 1, 0) == 9 && e.dirty)
	goto_row(&e, .Frame)
	e.cx, e.cy = 0, 1
	press(&e, .Green, .Right, .Right, .Down, .Green)
	testing.expect(t, pixel(&e, 0, 1) == 9 && pixel(&e, 2, 2) == 9 && pixel(&e, 1, 1) == 9)
	goto_row(&e, .Clear)
	press(&e, .Green)
	testing.expect_value(t, pixels_of_colour(&e, 9), 25)
}

@(test)
test_embedded_screen_hides_save_and_load_and_says_back :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	Seen :: struct {
		save, load, menu_rect: int,
	}
	seen: Seen
	r := cm.Renderer {
		data = &seen,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^Seen)(d)
			if x == SAVE_BUTTON.x && y == SAVE_BUTTON.y && w == SAVE_BUTTON.w {
				k.save += 1
			}
			if x == LOAD_BUTTON.x && y == LOAD_BUTTON.y && w == LOAD_BUTTON.w {
				k.load += 1
			}
			if x == MENU_BUTTON.x && y == MENU_BUTTON.y && w == MENU_BUTTON.w {
				k.menu_rect += 1
			}
		},
		present = proc(d: rawptr) {},
	}
	e := embedded_fixture(4, 4)
	cm.renderer_clear(&r, {})
	editor_draw(&e, &r)
	testing.expect(t, seen.save == 0 && seen.load == 0 && seen.menu_rect == 1) // only the BACK button is there
	standalone := editor_init()
	seen = {}
	editor_draw(&standalone, &r)
	testing.expect(t, seen.save == 1 && seen.load == 1 && seen.menu_rect == 1)
	// Help and banner text for the embedded editor fits and is drawable, with the longest labels too.
	m := cm.default_input_map()
	e.labels = &m
	for round in 0 ..< 2 {
		if round == 1 {
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for mode in ([]Mode{.Draw, .Setup, .Rect}) {
			e.mode = mode
			lines, n := help_lines(&e)
			for line in lines[:n] {
				if round == 0 {
					testing.expectf(t, cm.text_is_drawable(line), "help: %s", line)
				}
				testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
			}
		}
	}
	for note in ([]string{NOTE_SIZE_LOCKED, NOTE_NO_TURN}) {
		testing.expect(t, cm.text_is_drawable(note) && cm.text_width(note) <= cm.SCREEN_W - INFO_X - 4)
	}
}
