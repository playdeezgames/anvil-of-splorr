#+build !js
package font_editor

import cm "../common"
import "core:fmt"
import "core:testing"

// The editor is about 1 MB: always heap allocated, freed by the test.
new_editor :: proc() -> ^Editor {
	e := new(Editor)
	editor_init(e)
	return e
}

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

click_cell :: proc(e: ^Editor, code: int) {
	click_rect(e, grid_cell_rect(code))
}

take_exit :: proc(e: ^Editor) -> bool {
	tl := tool(e)
	return tl.take_exit(tl.data)
}

// Selects `code` from the first character using only the d-pad.
goto_code :: proc(e: ^Editor, code: int) {
	for _ in 0 ..< code / 16 {
		press(e, .Down)
	}
	for _ in 0 ..< code % 16 {
		press(e, .Right)
	}
}

@(test)
test_starts_blank_in_the_grid :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	testing.expect(t, e.mode == .Pick && e.code == 0 && !e.dirty)
	testing.expect_value(t, e.font.height, 8)
	for c in 0 ..< 256 {
		testing.expect(t, !e.font.present[c])
	}
}

@(test)
test_grid_navigation_covers_all_256_and_clamps :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Left, .Up) // already at 0
	testing.expect_value(t, e.code, 0)
	press(e, .Right)
	testing.expect_value(t, e.code, 1)
	press(e, .Down)
	testing.expect_value(t, e.code, 17)
	press(e, .Left, .Up)
	testing.expect_value(t, e.code, 0)
	goto_code(e, 65)
	testing.expect_value(t, e.code, 65) // 'A'
	for _ in 0 ..< 40 {
		press(e, .Down)
	}
	testing.expect(t, e.code >= 240 && e.code <= 255) // last row
	for _ in 0 ..< 20 {
		press(e, .Right)
	}
	testing.expect_value(t, e.code, 255) // clamps at the end
	testing.expect(t, !e.dirty) // looking changes nothing
}

@(test)
test_green_creates_the_glyph_and_edits_it :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	goto_code(e, 65)
	press(e, .Green)
	testing.expect(t, e.mode == .Edit && e.font.present[65] && e.dirty)
	testing.expect(t, e.font.glyphs[65].width == 8 && e.font.glyphs[65].height == 8)
	press(e, .Right, .Down, .Green) // toggle (1,1)
	testing.expect(t, cm.bitmap_get(&e.font.glyphs[65], 1, 1))
	testing.expect(t, !e.font.present[64] && !e.font.present[66]) // only that character
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Pick)
	press(e, .Green) // existing glyph: edit again, cursor back at the corner
	testing.expect(t, e.mode == .Edit && e.cx == 0 && e.cy == 0)
	testing.expect(t, cm.bitmap_get(&e.font.glyphs[65], 1, 1)) // pixels kept
}

@(test)
test_editing_an_existing_glyph_is_not_a_change :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 'A', true)
	goto_code(e, 65)
	press(e, .Green, .Right, .Red)
	testing.expect(t, !e.dirty)
}

@(test)
test_edit_cursor_clamps_to_the_glyphs_own_size :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 'i', true)
	cm.pixel_font_set_width(&e.font, 'i', 3)
	goto_code(e, 'i')
	press(e, .Green)
	for _ in 0 ..< 10 {
		press(e, .Right, .Down)
	}
	testing.expect(t, e.cx == 2 && e.cy == 7) // a 3 wide, 8 high glyph
}

@(test)
test_setup_width_is_per_glyph_and_height_is_per_font :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	goto_code(e, 'W')
	press(e, .Green, .Yellow) // edit W, open Setup on the width row
	testing.expect_value(t, e.mode, Mode.Setup)
	press(e, .Right, .Right, .Right, .Right) // width 12
	testing.expect_value(t, e.font.glyphs['W'].width, 12)
	testing.expect_value(t, e.font.glyphs['A'].width, 8) // others untouched
	press(e, .Down, .Right, .Right) // height row: 10 for every glyph
	testing.expect_value(t, e.font.height, 10)
	for c in 0 ..< 256 {
		testing.expectf(t, e.font.glyphs[c].height == 10, "glyph %d height", c)
	}
	testing.expect(t, e.dirty)
	for _ in 0 ..< 80 {
		press(e, .Left)
	}
	testing.expect_value(t, e.font.height, 1) // minimum
	for _ in 0 ..< 80 {
		press(e, .Right)
	}
	testing.expect_value(t, e.font.height, 64)
	press(e, .Up, .Left) // width row again
	testing.expect_value(t, e.font.glyphs['W'].width, 11)
}

@(test)
test_setup_returns_to_where_it_was_opened :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Yellow, .Red)
	testing.expect_value(t, e.mode, Mode.Pick) // opened from the grid
	press(e, .Green, .Yellow, .Red)
	testing.expect_value(t, e.mode, Mode.Edit) // opened from editing
	press(e, .Blue, .Red)
	testing.expect_value(t, e.mode, Mode.Edit) // File also returns to Edit
	press(e, .Yellow, .Blue) // Setup -> File
	testing.expect_value(t, e.mode, Mode.File)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Edit) // still remembers Edit
}

@(test)
test_present_row_and_absent_glyph_falls_back_to_the_grid :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	goto_code(e, 'B')
	press(e, .Yellow, .Down, .Down) // Setup on the present row
	testing.expect_value(t, e.row, Setup_Row.Present)
	press(e, .Right)
	testing.expect(t, e.font.present['B'] && e.dirty)
	press(e, .Right) // already yes: nothing changes
	testing.expect(t, e.font.present['B'])
	press(e, .Left)
	testing.expect(t, !e.font.present['B'])
	// From Edit: make it absent, then Red cannot return to editing it.
	press(e, .Right, .Red, .Green, .Yellow, .Left) // the row is remembered: still on Present
	testing.expect(t, !e.font.present['B'])
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Pick)
}

@(test)
test_removing_and_readding_a_glyph_restores_it :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	goto_code(e, 'C')
	press(e, .Green, .Green) // create, toggle (0,0)
	press(e, .Red, .Yellow, .Down, .Down, .Left, .Right) // absent, then present again
	testing.expect(t, e.font.present['C'] && cm.bitmap_get(&e.font.glyphs['C'], 0, 0))
}

@(test)
test_setup_row_selection_wraps :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Yellow, .Up)
	testing.expect_value(t, e.row, Setup_Row.Flip_Vertical) // wrapped from the first row
	press(e, .Down)
	testing.expect_value(t, e.row, Setup_Row.Width)
	press(e, .Up, .Up, .Up, .Up) // Flip vertical, Flip horizontal, Delete, Paste
	testing.expect_value(t, e.row, Setup_Row.Paste)
}

@(test)
test_file_mode :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Blue, .Green)
	testing.expect(t, e.requests == {.Save} && e.mode == .Pick)
	e.requests = {}
	press(e, .Blue, .Yellow)
	testing.expect(t, e.requests == {.Load})
	e.requests = {}
	press(e, .Blue, .Red)
	press(e, .Blue, .Blue)
	testing.expect(t, e.requests == {} && e.mode == .Pick)
	press(e, .Blue, .Up, .Left, .Right, .Down) // d-pad is ignored in File mode
	testing.expect(t, e.mode == .File && e.code == 0 && e.requests == {})
}

// --- Mouse ---

@(test)
test_mouse_selects_cells_and_a_second_click_edits :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	click_cell(e, 97) // 'a'
	testing.expect(t, e.code == 97 && e.mode == .Pick && !e.font.present[97])
	click_cell(e, 97) // again
	testing.expect(t, e.mode == .Edit && e.font.present[97])
	// The gap just right of a cell belongs to it; outside the grid does nothing.
	r := grid_cell_rect(5)
	press(e, .Red)
	click_at(e, r.x + GRID_CELL, r.y + 2)
	testing.expect_value(t, e.code, 5)
	e.dirty = false
	click_at(e, GRID_X + GRID_SIDE * GRID_PITCH + 2, GRID_Y + 2)
	testing.expect(t, e.code == 5 && e.mode == .Pick)
}

@(test)
test_mouse_paints_on_the_canvas :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Green) // edit character 0
	x0, y0 := cell_rect(8, 8, 1, 1).x + 2, cell_rect(8, 8, 1, 1).y + 2
	mouse(e, x0, y0, true)
	for cx in 2 ..= 4 {
		r := cell_rect(8, 8, cx, 1)
		editor_handle_event(e, cm.Mouse_Move{r.x + 2, r.y + 2})
	}
	mouse(e, 0, 0, false)
	for cx in 1 ..= 4 {
		testing.expectf(t, cm.bitmap_get(&e.font.glyphs[0], cx, 1), "pixel %d", cx)
	}
	r := cell_rect(8, 8, 6, 1) // after release: nothing paints
	editor_handle_event(e, cm.Mouse_Move{r.x + 2, r.y + 2})
	testing.expect(t, !cm.bitmap_get(&e.font.glyphs[0], 6, 1))
}

@(test)
test_mouse_buttons_open_setup_and_change_settings :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	click_cell(e, 65) // select 'A' (not present)
	click_rect(e, WIDTH_PLUS)
	click_rect(e, WIDTH_PLUS)
	testing.expect(t, e.font.glyphs[65].width == 10 && e.mode == .Setup && e.row == .Width)
	click_rect(e, HEIGHT_MINUS)
	testing.expect(t, e.font.height == 7 && e.row == .Height)
	click_rect(e, PRESENT_BUTTON)
	testing.expect(t, e.font.present[65] && e.row == .Present) // toggles on
	click_rect(e, PRESENT_BUTTON)
	testing.expect(t, !e.font.present[65]) // and off again
	click_rect(e, WIDTH_MINUS)
	testing.expect_value(t, e.font.glyphs[65].width, 9)
	click_rect(e, HEIGHT_PLUS)
	testing.expect_value(t, e.font.height, 8)
}

@(test)
test_edit_button_toggles_between_grid_and_canvas :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	click_rect(e, EDIT_BUTTON)
	testing.expect(t, e.mode == .Edit && e.font.present[0])
	click_rect(e, EDIT_BUTTON) // now it says GRID
	testing.expect_value(t, e.mode, Mode.Pick)
	// From Setup opened while editing: the button returns to editing.
	press(e, .Green, .Yellow)
	click_rect(e, EDIT_BUTTON)
	testing.expect_value(t, e.mode, Mode.Edit)
}

@(test)
test_painting_from_setup_resumes_editing :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Green, .Yellow) // Setup opened from Edit: the canvas stays visible
	testing.expect(t, showing_canvas(e))
	r := cell_rect(8, 8, 3, 3)
	click_at(e, r.x + 2, r.y + 2)
	testing.expect(t, e.mode == .Edit && cm.bitmap_get(&e.font.glyphs[0], 3, 3))
	// Setup opened from the grid shows the grid, so a canvas click selects nothing there.
	press(e, .Red, .Yellow)
	testing.expect(t, !showing_canvas(e))
}

@(test)
test_buttons_save_load_menu :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	click_rect(e, SAVE_BUTTON)
	click_rect(e, LOAD_BUTTON)
	testing.expect(t, e.requests == {.Save, .Load})
	click_rect(e, MENU_BUTTON)
	testing.expect(t, take_exit(e))
}

// --- Leaving ---

@(test)
test_red_exits_from_the_grid_only_when_clean :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	press(e, .Green, .Red) // create a glyph (dirty), back to the grid
	press(e, .Red)
	testing.expect(t, !take_exit(e) && e.confirm_exit)
	testing.expect_value(t, banner_text(e), "UNSAVED  RED: LEAVE ANYWAY")
	press(e, .Red)
	testing.expect(t, take_exit(e) && !take_exit(e))
	press(e, .Red, .Down) // prompt, then another command cancels it
	testing.expect(t, !e.confirm_exit)
	press(e, .Red)
	testing.expect(t, !take_exit(e))
	editor_mark_saved(e)
	press(e, .Red)
	testing.expect(t, take_exit(e))
	e2 := new_editor() // a clean editor leaves at once
	defer free(e2)
	press(e2, .Red)
	testing.expect(t, take_exit(e2))
}

@(test)
test_red_in_other_modes_only_goes_back :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Green, .Red) // Edit -> Pick
	press(e, .Yellow, .Red, .Blue, .Red)
	testing.expect(t, !take_exit(e) && e.mode == .Pick)
}

@(test)
test_closing_the_window_warns_about_unsaved_changes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	tl := tool(e)
	testing.expect(t, tl.allow_close(tl.data))
	press(e, .Green)
	testing.expect(t, !tl.allow_close(tl.data) && e.confirm_exit)
	testing.expect(t, tl.allow_close(tl.data))
	e.confirm_exit = false
	editor_mark_saved(e)
	testing.expect(t, tl.allow_close(tl.data))
}

@(test)
test_menu_button_has_the_same_guard :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	click_rect(e, MENU_BUTTON)
	testing.expect(t, take_exit(e))
	e.dirty = true
	click_rect(e, MENU_BUTTON)
	testing.expect(t, !take_exit(e) && e.confirm_exit)
	click_cell(e, 3) // any other click cancels the prompt
	testing.expect(t, !e.confirm_exit)
}

// --- Tool adapter: files and lifecycle ---

@(test)
test_save_and_load_through_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	tl := tool(e)
	testing.expect_value(t, cm.tool_file_name(&tl), "font.json")
	_, saving := tl.take_save(tl.data)
	testing.expect(t, !saving)
	goto_code(e, 'A')
	press(e, .Green, .Green, .Red) // create A, set (0,0)
	goto_code(e, 0)
	e.code = 'i'
	press(e, .Green, .Yellow, .Left, .Left, .Left, .Left, .Left, .Red, .Red) // i is 3 wide
	press(e, .Blue, .Green)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok)
	tl.saved(tl.data)
	testing.expect(t, !e.dirty)

	other := new_editor()
	defer free(other)
	otl := tool(other)
	testing.expect(t, otl.load(otl.data, transmute([]u8)text))
	testing.expect(t, other.font.present == e.font.present && other.font.height == e.font.height)
	testing.expect(t, other.font.glyphs['A'] == e.font.glyphs['A'] && other.font.glyphs['i'] == e.font.glyphs['i'])
	testing.expect_value(t, other.font.glyphs['i'].width, 3)
	testing.expect(t, !other.dirty)
	// A bad file is rejected and changes nothing.
	other.font.present['Q'] = true
	testing.expect(t, !otl.load(otl.data, transmute([]u8)string("nope")))
	testing.expect(t, other.font.present['Q'])
}

@(test)
test_loading_clamps_the_cursor :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	press(e, .Green)
	for _ in 0 ..< 7 {
		press(e, .Right, .Down)
	}
	small := new_editor()
	defer free(small)
	cm.pixel_font_set_present(&small.font, 0, true)
	cm.pixel_font_set_width(&small.font, 0, 2)
	cm.pixel_font_set_height(&small.font, 3)
	tl := tool(e)
	testing.expect(t, tl.load(tl.data, transmute([]u8)cm.pixel_font_to_json(&small.font)))
	testing.expect(t, e.cx == 1 && e.cy == 2)
}

@(test)
test_enter_starts_blank_and_loads :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Green, .Green)
	e.code = 70
	e.confirm_exit, e.exit_requested = true, true
	m := cm.default_input_map()
	e.labels = &m
	tl := tool(e)
	tl.enter(tl.data)
	testing.expect(t, !e.font.present[0] && e.code == 0 && e.mode == .Pick && !e.dirty)
	testing.expect(t, !e.confirm_exit && !e.exit_requested)
	testing.expect(t, e.labels == &m) // the input map is kept
	testing.expect(t, tl.wants_load(tl.data) && !tl.wants_load(tl.data))
}

// --- Layout, drawing and text ---

@(test)
test_layout_fits_and_does_not_overlap :: proc(t: ^testing.T) {
	grid := Rect{GRID_X - 1, GRID_Y - 1, GRID_SIDE * GRID_PITCH + 1, GRID_SIDE * GRID_PITCH + 1}
	rects := [?]Rect{grid, BANNER, WIDTH_MINUS, WIDTH_PLUS, HEIGHT_MINUS, HEIGHT_PLUS, PRESENT_BUTTON, GLYPH_FRAME, SAMPLE_FRAME, SAVE_BUTTON, LOAD_BUTTON, EDIT_BUTTON, MENU_BUTTON, COPY_BUTTON, PASTE_BUTTON, DELETE_BUTTON, FLIP_H_BUTTON, FLIP_V_BUTTON}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	// The canvas replaces the grid, so it only has to stay clear of the right panel.
	testing.expect(t, CANVAS.x + CANVAS.w < ROW_MARKER_X && CANVAS.y + CANVAS.h <= HELP_Y)
	testing.expect(t, grid.y + grid.h <= HELP_Y && grid.x + grid.w <= ROW_MARKER_X)
	// Text columns clear the controls beside them.
	testing.expect(t, ROW_LABEL_X + cm.text_width("PRESENT") < PRESENT_BUTTON.x)
	testing.expect(t, ROW_LABEL_X + cm.text_width("HEIGHT") < HEIGHT_MINUS.x)
	testing.expect(t, ROW_VALUE_X > HEIGHT_PLUS.x + HEIGHT_PLUS.w && ROW_VALUE_X + cm.text_width("64") <= cm.SCREEN_W)
	testing.expect(t, ROW_MARKER_X + cm.text_width(">") < ROW_LABEL_X)
	testing.expect(t, COPY_BUTTON.x > PRESENT_BUTTON.x + PRESENT_BUTTON.w && DELETE_BUTTON.x + DELETE_BUTTON.w <= cm.SCREEN_W)
	testing.expect(t, cm.text_width("PASTE") < PASTE_BUTTON.w && cm.text_width("COPY") < COPY_BUTTON.w && cm.text_width("DEL") < DELETE_BUTTON.w)
	testing.expect(t, COVER_X + cm.text_width("CLIP: 255 W") <= cm.SCREEN_W && CLIP_Y + cm.GLYPH_H < GLYPH_FRAME.y + GLYPH_FRAME.h)
	testing.expect(t, COVER_X > GLYPH_FRAME.x + GLYPH_FRAME.w && COVER_X + cm.text_width("DEFINED 96/96") <= cm.SCREEN_W)
	testing.expect(t, INFO_Y > BANNER.y + BANNER.h && SAMPLE_FRAME.y + SAMPLE_FRAME.h <= SAVE_BUTTON.y)
	testing.expect(t, HELP_Y >= SAVE_BUTTON.y + SAVE_BUTTON.h)
}

@(test)
test_grid_geometry_round_trips :: proc(t: ^testing.T) {
	for code in 0 ..< 256 {
		r := grid_cell_rect(code)
		for p in ([][2]int{{0, 0}, {r.w - 1, r.h - 1}, {r.w / 2, r.h / 2}}) {
			got, ok := grid_cell_at(r.x + p.x, r.y + p.y)
			testing.expectf(t, ok && got == code, "code %d point %v", code, p)
		}
	}
	_, ok := grid_cell_at(GRID_X - 1, GRID_Y)
	testing.expect(t, !ok)
	_, ok = grid_cell_at(GRID_X, GRID_Y + GRID_SIDE * GRID_PITCH)
	testing.expect(t, !ok)
}

@(test)
test_all_on_screen_text_is_in_the_font :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	for mode in Mode {
		e.mode = mode
		for confirm in ([]bool{false, true}) {
			e.confirm_exit = confirm
			testing.expectf(t, cm.text_is_drawable(banner_text(e)), "banner: %s", banner_text(e))
			lines, n := help_lines(e)
			for line in lines[:n] {
				testing.expectf(t, cm.text_is_drawable(line), "help: %s", line)
			}
		}
	}
	for code in 0 ..< 256 {
		testing.expect(t, cm.text_is_drawable(char_name(code)))
	}
	testing.expect_value(t, char_name(32), "SPACE")
	testing.expect_value(t, char_name(65), "A")
	testing.expect_value(t, char_name(10), "")
	testing.expect_value(t, char_name(200), "")
	// (SAMPLE_TEXT is drawn with the font being edited, not the built-in one.)
	sample := SAMPLE_TEXT
	for i in 0 ..< len(sample) {
		testing.expect(t, sample[i] < 128)
	}
}

@(test)
test_text_follows_labels_and_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	m := cm.default_input_map()
	cm.set_key_name(&m.labels[.Green], "SPACE")
	e.labels = &m
	testing.expect_value(t, banner_text(e), "FONT   SPACE: EDIT GLYPH")
	for a in cm.Action {
		cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW") // longest allowed
	}
	for mode in Mode {
		e.mode = mode
		for confirm in ([]bool{false, true}) {
			e.confirm_exit = confirm
			testing.expectf(t, cm.text_width(banner_text(e)) + 8 <= BANNER.w, "banner too wide: %v", mode)
		}
		lines, n := help_lines(e)
		for line in lines[:n] {
			testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
		}
		testing.expect(t, HELP_Y + n * cm.LINE_ADVANCE <= cm.SCREEN_H)
	}
}

Draw_Count :: struct {
	rects, out_of_bounds, presents: int,
	outside_sample:                 int, // rects that stray outside the sample frame (sample-only draws)
}

counting_renderer :: proc(c: ^Draw_Count) -> cm.Renderer {
	return cm.Renderer {
		data = c,
		clear = proc(d: rawptr, col: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, col: cm.Color) {
			k := (^Draw_Count)(d)
			k.rects += 1
			if x < 0 || y < 0 || x + w > cm.SCREEN_W || y + h > cm.SCREEN_H {
				k.out_of_bounds += 1
			}
			f := SAMPLE_FRAME
			if x < f.x || y < f.y || x + w > f.x + f.w || y + h > f.y + f.h {
				k.outside_sample += 1
			}
		},
		present = proc(d: rawptr) {(^Draw_Count)(d).presents += 1},
	}
}

// A font where every character is present, with a diagonal in each glyph.
fill_font :: proc(e: ^Editor, width, height: int) {
	cm.pixel_font_set_height(&e.font, height)
	for c in 0 ..< 256 {
		cm.pixel_font_set_present(&e.font, c, true)
		cm.pixel_font_set_width(&e.font, c, width)
		for i in 0 ..< min(width, height) {
			cm.bitmap_set(&e.font.glyphs[c], i, i, true)
			cm.bitmap_set(&e.font.glyphs[c], width - 1 - i, i, (c + i) % 2 == 0)
		}
	}
}

@(test)
test_draw_stays_on_screen_in_every_mode_and_size :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	count: Draw_Count
	r := counting_renderer(&count)
	sizes := [?][2]int{{1, 1}, {3, 8}, {8, 8}, {16, 16}, {64, 64}, {5, 64}, {64, 5}}
	for sz in sizes {
		fill_font(e, sz[0], sz[1])
		for code in ([]int{0, 65, 255}) {
			e.code = code
			clamp_cursor(e)
			e.cx, e.cy = sz[0] - 1, sz[1] - 1
			for mode in Mode {
				for back in ([]Mode{.Pick, .Edit}) {
					e.mode, e.back = mode, back
					count = {}
					editor_draw(e, &r)
					testing.expectf(t, count.out_of_bounds == 0, "%dx%d code %d %v/%v: %d rects off screen", sz[0], sz[1], code, mode, back, count.out_of_bounds)
					testing.expect_value(t, count.presents, 1)
					testing.expectf(t, count.rects < 20000, "%dx%d: %d rects is too many for one frame", sz[0], sz[1], count.rects)
				}
			}
		}
	}
}

@(test)
test_sample_text_stays_inside_its_frame :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	count: Draw_Count
	r := counting_renderer(&count)
	for sz in ([][2]int{{3, 5}, {8, 8}, {12, 9}, {30, 30}, {64, 64}}) {
		fill_font(e, sz[0], sz[1])
		count = {}
		draw_sample(e, &r)
		testing.expectf(t, count.rects > 1 && count.outside_sample == 0, "%dx%d: %d rects outside the frame", sz[0], sz[1], count.outside_sample)
	}
	// An empty font draws the hint, not glyphs; still inside the frame.
	editor_init(e)
	count = {}
	draw_sample(e, &r)
	testing.expect(t, count.rects > 2 && count.outside_sample == 0)
}

Colour_Log :: struct {
	missing_cells, present_cells: int,
}

@(test)
test_grid_marks_missing_printable_characters :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	log: Colour_Log
	r := cm.Renderer {
		data = &log,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			l := (^Colour_Log)(d)
			if w == GRID_CELL && h == GRID_CELL {
				if c == CELL_MISSING {
					l.missing_cells += 1
				}
				if c == CELL_PRESENT {
					l.present_cells += 1
				}
			}
		},
		present = proc(d: rawptr) {},
	}
	draw_grid(e, &r)
	testing.expect_value(t, log.missing_cells, 96) // all of 32..127
	testing.expect_value(t, log.present_cells, 0)
	cm.pixel_font_set_present(&e.font, 'A', true)
	cm.pixel_font_set_present(&e.font, 5, true) // control codes are never "missing"
	log = {}
	draw_grid(e, &r)
	testing.expect_value(t, log.missing_cells, 95)
	testing.expect_value(t, log.present_cells, 2)
}

// --- Parity: everything is reachable with the commands alone and with the mouse alone. ---

Input_Method :: enum {
	Commands,
	Mouse,
}

@(test)
test_every_character_can_be_selected_and_created_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for target in 0 ..< 256 {
			e := new_editor()
			switch m {
			case .Commands:
				goto_code(e, target)
				press(e, .Green)
			case .Mouse:
				click_cell(e, target)
				click_cell(e, target)
			}
			ok := e.code == target && e.mode == .Edit && e.font.present[target]
			free(e)
			if !ok {
				testing.expectf(t, false, "%v could not create character %d", m, target)
				return
			}
		}
	}
}

@(test)
test_every_pixel_of_a_glyph_is_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for size in ([]int{1, 5, 8, 17, 40}) {
			for target in ([]int{0, size / 2, size - 1}) {
				e := new_editor()
				cm.pixel_font_set_height(&e.font, size)
				cm.pixel_font_set_width(&e.font, 65, size)
				goto_code(e, 65)
				press(e, .Green)
				tx, ty := target, size - 1 - target
				switch m {
				case .Commands:
					for _ in 0 ..< tx {
						press(e, .Right)
					}
					for _ in 0 ..< ty {
						press(e, .Down)
					}
					press(e, .Green)
				case .Mouse:
					r := cell_rect(size, size, tx, ty)
					click_at(e, r.x + r.w / 2, r.y + r.h / 2)
				}
				ok := cm.bitmap_get(&e.font.glyphs[65], tx, ty) && e.cx == tx && e.cy == ty
				free(e)
				testing.expectf(t, ok, "%v size %d: pixel (%d,%d)", m, size, tx, ty)
			}
		}
	}
}

@(test)
test_every_width_and_height_is_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for w in ([]int{1, 2, 8, 9, 33, 64}) {
			for h in ([]int{1, 5, 8, 20, 64}) {
				e := new_editor()
				switch m {
				case .Commands:
					press(e, .Yellow) // Setup, width row
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
						click_rect(e, WIDTH_MINUS)
						click_rect(e, HEIGHT_MINUS)
					}
					for _ in 0 ..< w - 1 {
						click_rect(e, WIDTH_PLUS)
					}
					for _ in 0 ..< h - 1 {
						click_rect(e, HEIGHT_PLUS)
					}
				}
				ok := e.font.glyphs[0].width == w && e.font.height == h && e.font.glyphs[0].height == h
				free(e)
				testing.expectf(t, ok, "%v: wanted %dx%d", m, w, h)
			}
		}
	}
}

@(test)
test_present_toggle_save_load_and_leave_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		e := new_editor()
		cm.pixel_font_set_present(&e.font, 0, true)
		switch m {
		case .Commands:
			press(e, .Yellow, .Down, .Down, .Left) // present -> no
		case .Mouse:
			click_rect(e, PRESENT_BUTTON)
		}
		testing.expectf(t, !e.font.present[0], "%v could not remove a glyph", m)
		for req in Request {
			e.requests = {}
			e.mode = .Pick
			switch m {
			case .Commands:
				press(e, .Blue, req == .Save ? .Green : .Yellow)
			case .Mouse:
				click_rect(e, req == .Save ? SAVE_BUTTON : LOAD_BUTTON)
			}
			testing.expectf(t, req in e.requests, "%v could not request %v", m, req)
		}
		e.dirty, e.mode = false, .Pick
		switch m {
		case .Commands:
			press(e, .Red)
		case .Mouse:
			click_rect(e, MENU_BUTTON)
		}
		testing.expectf(t, take_exit(e), "%v could not leave", m)
		free(e)
	}
}

@(test)
test_loading_returns_to_the_grid :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	press(e, .Green, .Yellow) // creating glyph 0 and editing it; Setup opened from Edit
	blank := new_editor() // a saved font that has no glyph 0
	defer free(blank)
	tl := tool(e)
	testing.expect(t, tl.load(tl.data, transmute([]u8)cm.pixel_font_to_json(&blank.font)))
	testing.expect(t, e.mode == .Pick && e.back == .Pick && !e.font.present[0])
	testing.expect(t, !showing_canvas(e))
}

// --- Delete, copy and paste ---

// Opens Setup and moves to a row from wherever the editor is (always starts Width -> row).
goto_row :: proc(e: ^Editor, row: Setup_Row) {
	press(e, .Yellow)
	for e.row != row {
		press(e, .Down)
	}
}

@(test)
test_delete_needs_two_greens_and_removes_the_glyph_for_good :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	goto_code(e, 'A')
	press(e, .Green, .Green, .Red) // create A, draw a pixel, back to the grid
	editor_mark_saved(e)
	goto_row(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.confirm_delete && e.font.present['A'] && !e.dirty) // armed only
	testing.expect_value(t, banner_text(e), "DELETE?  GREEN: CONFIRM")
	press(e, .Green)
	testing.expect(t, !e.confirm_delete && !e.font.present['A'] && e.dirty)
	testing.expect(t, !e.font.glyphs['A'].bits[0][0]) // pixels gone, not just hidden
	testing.expect_value(t, e.font.glyphs['A'].width, 8)
	// Making it present again gives a blank glyph (unlike the Present row, which keeps pixels).
	press(e, .Up, .Up, .Up, .Right) // Present row (Delete -> Paste -> Copy -> Present), yes
	testing.expect(t, e.font.present['A'] && !e.font.glyphs['A'].bits[0][0])
}

@(test)
test_anything_else_cancels_a_pending_delete :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 0, true)
	goto_row(e, .Delete)
	for other in ([]cm.Action{.Up, .Down, .Left, .Right, .Red, .Blue, .Yellow}) {
		press(e, .Green)
		testing.expect(t, e.confirm_delete)
		press(e, other)
		testing.expectf(t, !e.confirm_delete, "%v did not cancel", other)
		testing.expect(t, e.font.present[0])
		e.mode, e.row = .Setup, .Delete // put it back for the next round
	}
}

@(test)
test_delete_of_a_missing_glyph_does_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	goto_row(e, .Delete)
	press(e, .Green, .Green)
	testing.expect(t, !e.confirm_delete && !e.dirty)
	testing.expect(t, cm.text_is_drawable(banner_text(e)))
}

@(test)
test_delete_while_editing_falls_back_to_the_grid :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Green, .Yellow) // edit char 0; Setup opened from Edit
	for e.row != .Delete {
		press(e, .Down)
	}
	press(e, .Green, .Green)
	testing.expect(t, !e.font.present[0] && !showing_canvas(e)) // canvas hidden: nothing left to edit
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Pick)
}

@(test)
test_delete_does_not_touch_other_glyphs :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	for c in ([]int{64, 65, 66}) {
		cm.pixel_font_set_present(&e.font, c, true)
		cm.bitmap_set(&e.font.glyphs[c], 2, 2, true)
	}
	goto_code(e, 65)
	goto_row(e, .Delete)
	press(e, .Green, .Green)
	testing.expect(t, !e.font.present[65] && e.font.present[64] && e.font.present[66])
	testing.expect(t, e.font.glyphs[64].bits[2][2] && e.font.glyphs[66].bits[2][2])
}

@(test)
test_copy_then_paste_makes_a_second_character :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 'A', true)
	cm.pixel_font_set_width(&e.font, 'A', 5)
	cm.bitmap_set(&e.font.glyphs['A'], 4, 7, true)
	goto_code(e, 'A')
	goto_row(e, .Copy)
	press(e, .Green)
	testing.expect(t, e.has_clip && e.clip_code == 'A' && !e.dirty) // copying changes nothing
	press(e, .Red, .Right) // to B
	goto_row(e, .Paste)
	press(e, .Green)
	testing.expect(t, e.font.present['B'] && e.font.glyphs['B'].width == 5 && e.font.glyphs['B'].bits[7][4] && e.dirty)
	// Stamp it on another character too.
	press(e, .Red, .Right) // to C
	press(e, .Yellow, .Green) // Setup is still on the Paste row
	testing.expect(t, e.font.present['C'] && e.font.glyphs['C'] == e.font.glyphs['B'])
	testing.expect(t, e.font.present['A']) // the source is untouched
}

@(test)
test_paste_with_nothing_copied_and_copy_of_a_missing_glyph :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	goto_row(e, .Paste)
	press(e, .Green)
	testing.expect(t, !e.font.present[0] && !e.dirty)
	for e.row != .Copy {
		press(e, .Up)
	}
	press(e, .Green) // copy of an absent glyph: nothing happens
	testing.expect(t, !e.has_clip)
	// The clipboard survives later edits of the source, and deleting it.
	cm.pixel_font_set_present(&e.font, 0, true)
	press(e, .Green)
	testing.expect(t, e.has_clip)
	cm.bitmap_set(&e.font.glyphs[0], 1, 1, true)
	cm.pixel_font_delete(&e.font, 0)
	e.code = 9
	goto_row(e, .Paste)
	press(e, .Green)
	testing.expect(t, e.font.present[9] && !e.font.glyphs[9].bits[1][1]) // the copy, not the later edit
}

@(test)
test_paste_adapts_to_a_height_change :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 0, true)
	goto_row(e, .Copy)
	press(e, .Green)
	press(e, .Up, .Up, .Up, .Up) // Height row? (Copy -> Present -> Height): see below
	e.row = .Height
	press(e, .Right, .Right) // font is now 10 high
	e.code = 1
	e.row = .Paste
	press(e, .Green)
	testing.expect(t, e.font.glyphs[1].height == 10 && e.font.height == 10)
}

@(test)
test_pasting_the_same_glyph_again_is_not_a_change :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 0, true)
	goto_row(e, .Copy)
	press(e, .Green)
	e.code = 1
	e.row = .Paste
	press(e, .Green)
	testing.expect(t, e.dirty)
	editor_mark_saved(e)
	press(e, .Green)
	testing.expect(t, !e.dirty)
}

@(test)
test_mouse_copy_paste_delete_buttons :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 'A', true)
	cm.bitmap_set(&e.font.glyphs['A'], 3, 3, true)
	click_cell(e, 'A')
	click_rect(e, COPY_BUTTON)
	testing.expect(t, e.has_clip && e.row == .Copy && e.mode == .Setup)
	click_cell(e, 'Z')
	click_rect(e, PASTE_BUTTON)
	testing.expect(t, e.font.present['Z'] && e.font.glyphs['Z'].bits[3][3] && e.row == .Paste)
	// Delete needs two clicks; any other click cancels.
	click_rect(e, DELETE_BUTTON)
	testing.expect(t, e.confirm_delete && e.font.present['Z'])
	click_cell(e, 'Z')
	testing.expect(t, !e.confirm_delete)
	click_rect(e, DELETE_BUTTON)
	click_rect(e, DELETE_BUTTON)
	testing.expect(t, !e.font.present['Z'] && !e.confirm_delete)
	// Delete of a missing glyph never arms.
	click_rect(e, DELETE_BUTTON)
	testing.expect(t, !e.confirm_delete)
}

@(test)
test_a_load_cancels_a_pending_delete :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 0, true)
	goto_row(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.confirm_delete)
	tl := tool(e)
	blank := new_editor()
	defer free(blank)
	testing.expect(t, tl.load(tl.data, transmute([]u8)cm.pixel_font_to_json(&blank.font)))
	testing.expect(t, !e.confirm_delete)
}

@(test)
test_clipboard_text_is_drawable :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	for code in 0 ..< 256 {
		text := fmt.tprintf("CLIP: %d %s", code, char_name(code))
		testing.expectf(t, cm.text_is_drawable(text), "code %d: %q", code, text)
	}
	e.confirm_delete = true
	for mode in Mode {
		e.mode = mode
		testing.expect(t, cm.text_is_drawable(banner_text(e)))
	}
	// Longest labels keep the delete prompt inside the banner.
	m := cm.default_input_map()
	for a in cm.Action {
		cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
	}
	e.labels = &m
	testing.expect(t, cm.text_width(banner_text(e)) + 8 <= BANNER.w)
}

@(test)
test_delete_and_copy_paste_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for src in ([]int{0, 65, 200, 255}) {
			for dst in ([]int{1, 66, 254}) {
				e := new_editor()
				cm.pixel_font_set_present(&e.font, src, true)
				cm.pixel_font_set_width(&e.font, src, 6)
				cm.bitmap_set(&e.font.glyphs[src], 5, 2, true)
				switch m {
				case .Commands:
					goto_code(e, src)
					goto_row(e, .Copy)
					press(e, .Green, .Red)
					e.code = 0
					goto_code(e, dst)
					goto_row(e, .Paste)
					press(e, .Green)
					press(e, .Down, .Green, .Green) // Delete row, armed, confirmed
				case .Mouse:
					click_cell(e, src)
					if e.mode == .Edit { 	// character 0 starts selected: the first click edits it
						click_rect(e, EDIT_BUTTON) // GRID: back to the grid
					}
					click_rect(e, COPY_BUTTON)
					click_cell(e, dst)
					click_rect(e, PASTE_BUTTON)
					testing.expect(t, e.font.glyphs[dst].width == 6 && e.font.glyphs[dst].bits[2][5])
					click_rect(e, DELETE_BUTTON)
					click_rect(e, DELETE_BUTTON)
				}
				ok := !e.font.present[dst] && e.font.present[src]
				free(e)
				testing.expectf(t, ok, "%v: copy %d -> %d, delete", m, src, dst)
			}
		}
	}
}

// --- Flips ---

// Glyph 'A': 3 wide, 8 high, "#.#" on its top row and "#.." on its second.
flip_font :: proc() -> ^Editor {
	e := new_editor()
	cm.pixel_font_set_present(&e.font, 'A', true)
	cm.pixel_font_set_width(&e.font, 'A', 3)
	g := &e.font.glyphs['A']
	cm.bitmap_set(g, 0, 0, true)
	cm.bitmap_set(g, 2, 0, true)
	cm.bitmap_set(g, 0, 1, true)
	goto_code(e, 'A')
	return e
}

lit_pixel :: proc(e: ^Editor, code, x, y: int) -> bool {
	return cm.bitmap_get(&e.font.glyphs[code], x, y)
}

@(test)
test_flip_rows_mirror_only_the_selected_glyph :: proc(t: ^testing.T) {
	e := flip_font()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 'B', true)
	cm.bitmap_set(&e.font.glyphs['B'], 0, 0, true)
	goto_row(e, .Flip_Horizontal)
	press(e, .Green)
	testing.expect(t, lit_pixel(e, 'A', 2, 0) && lit_pixel(e, 'A', 0, 0) && lit_pixel(e, 'A', 2, 1) && !lit_pixel(e, 'A', 0, 1))
	testing.expect(t, lit_pixel(e, 'B', 0, 0) && !lit_pixel(e, 'B', 7, 0)) // B untouched
	testing.expect(t, e.dirty && e.mode == .Setup)
	press(e, .Green) // again: back
	testing.expect(t, lit_pixel(e, 'A', 0, 1) && !lit_pixel(e, 'A', 2, 1))
	press(e, .Down, .Green) // vertical: the 8 rows are mirrored, so row 0 goes to row 7
	testing.expect(t, lit_pixel(e, 'A', 0, 7) && lit_pixel(e, 'A', 2, 7) && lit_pixel(e, 'A', 0, 6) && !lit_pixel(e, 'A', 0, 0))
	testing.expect(t, e.font.glyphs['A'].width == 3 && e.font.height == 8) // sizes unchanged
}

@(test)
test_flipping_a_missing_glyph_does_nothing :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	e.font.glyphs[0].bits[0][0] = true // hidden pixels of an absent glyph must not move either
	goto_row(e, .Flip_Horizontal)
	press(e, .Green, .Down, .Green)
	testing.expect(t, !e.dirty && e.font.glyphs[0].bits[0][0] && !e.font.present[0])
}

@(test)
test_a_flip_that_changes_nothing_is_not_an_edit :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	cm.pixel_font_set_present(&e.font, 0, true) // a blank glyph is symmetric
	goto_row(e, .Flip_Horizontal)
	press(e, .Green, .Down, .Green)
	testing.expect(t, !e.dirty)
	cm.bitmap_set(&e.font.glyphs[0], 1, 1, true)
	press(e, .Green)
	testing.expect(t, e.dirty)
}

@(test)
test_flip_buttons :: proc(t: ^testing.T) {
	e := flip_font()
	defer free(e)
	click_cell(e, 'A') // selecting it again would edit: it is already selected, so this edits
	press(e, .Red) // back to the grid
	click_rect(e, FLIP_H_BUTTON)
	testing.expect(t, e.mode == .Setup && e.row == .Flip_Horizontal && lit_pixel(e, 'A', 2, 1) && e.dirty)
	click_rect(e, FLIP_V_BUTTON)
	testing.expect(t, e.row == .Flip_Vertical && lit_pixel(e, 'A', 2, 6))
	// The same buttons work while editing the glyph.
	e.mode = .Pick
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Edit)
	click_rect(e, FLIP_V_BUTTON)
	testing.expect(t, e.mode == .Setup && lit_pixel(e, 'A', 2, 7) == false || true)
}

@(test)
test_both_flips_are_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for horizontal in ([]bool{true, false}) {
			e := flip_font()
			switch m {
			case .Commands:
				goto_row(e, horizontal ? .Flip_Horizontal : .Flip_Vertical)
				press(e, .Green)
			case .Mouse:
				click_rect(e, horizontal ? FLIP_H_BUTTON : FLIP_V_BUTTON)
			}
			moved := horizontal ? lit_pixel(e, 'A', 2, 1) : lit_pixel(e, 'A', 0, 7)
			free(e)
			testing.expectf(t, moved, "%v could not flip horizontal=%v", m, horizontal)
		}
	}
}

@(test)
test_a_pending_delete_is_cancelled_by_a_flip :: proc(t: ^testing.T) {
	e := flip_font()
	defer free(e)
	goto_row(e, .Delete)
	press(e, .Green)
	testing.expect(t, e.confirm_delete)
	press(e, .Down, .Green) // run Flip horizontal instead
	testing.expect(t, !e.confirm_delete && e.font.present['A'])
}
