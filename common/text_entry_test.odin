#+build !js
package common

import "core:testing"

cmd :: proc(e: ^Text_Entry, actions: ..Action) -> Text_Entry_Result {
	res := e.result
	for a in actions {
		res = text_entry_handle(e, Command{action = a})
	}
	return res
}

click_cell :: proc(e: ^Text_Entry, col, row: int) -> Text_Entry_Result {
	rc := text_entry_cell_rect(col, row)
	x, y := rc.x + rc.w / 2, rc.y + rc.h / 2
	text_entry_handle(e, Mouse_Button_Event{button = .Left, x = x, y = y, down = true})
	return text_entry_handle(e, Mouse_Button_Event{button = .Left, x = x, y = y, down = false})
}

new_entry :: proc(initial := "", max_len := TEXT_ENTRY_MAX) -> Text_Entry {
	e: Text_Entry
	text_entry_begin(&e, "TEST", initial, max_len)
	return e
}

@(test)
test_the_grid_holds_every_printable_character_exactly_once :: proc(t: ^testing.T) {
	seen: [256]int
	fillers := 0
	for row in 0 ..< TEXT_ENTRY_CHAR_ROWS {
		testing.expect_value(t, len(TEXT_ENTRY_GRID[row]), TEXT_ENTRY_COLS)
		for col in 0 ..< TEXT_ENTRY_COLS {
			ch, ok := text_entry_char_at(col, row)
			if ok {
				seen[ch] += 1
			} else {
				fillers += 1
			}
		}
	}
	for c in 32 ..= 126 {
		testing.expectf(t, seen[c] == 1, "character %d (%c) appears %d times", c, rune(c), seen[c])
	}
	for c in 0 ..< 256 {
		if c < 32 || c > 126 {
			testing.expectf(t, seen[c] == 0, "unexpected character %d", c)
		}
	}
	testing.expect_value(t, fillers, 1) // exactly one unused cell
	_, ok := text_entry_char_at(TEXT_ENTRY_COLS - 1, TEXT_ENTRY_CHAR_ROWS - 1)
	testing.expect(t, !ok) // and it is the very last one
	_, ok = text_entry_char_at(-1, 0)
	testing.expect(t, !ok)
	_, ok = text_entry_char_at(0, TEXT_ENTRY_CHAR_ROWS) // the action row has no characters
	testing.expect(t, !ok)
}

@(test)
test_begin_sets_up_the_state_and_truncates :: proc(t: ^testing.T) {
	e := new_entry("HELLO", 8)
	testing.expect(t, text_entry_text(&e) == "HELLO" && e.max_len == 8 && e.result == .Editing)
	testing.expect(t, e.col == 0 && e.row == 0)
	e = new_entry("ABCDEFGHIJ", 4) // an initial text longer than the limit is cut
	testing.expect_value(t, text_entry_text(&e), "ABCD")
	e = new_entry("", 1000) // the limit is capped
	testing.expect_value(t, e.max_len, TEXT_ENTRY_MAX)
	e = new_entry("", 0) // and is at least one
	testing.expect_value(t, e.max_len, 1)
}

@(test)
test_every_character_can_be_typed_with_the_commands :: proc(t: ^testing.T) {
	for c in 32 ..= 126 {
		// Find the cell, then walk there from the top-left with the d-pad.
		col, row := -1, -1
		for r in 0 ..< TEXT_ENTRY_CHAR_ROWS {
			for k in 0 ..< TEXT_ENTRY_COLS {
				if ch, ok := text_entry_char_at(k, r); ok && int(ch) == c {
					col, row = k, r
				}
			}
		}
		e := new_entry()
		for _ in 0 ..< col {
			cmd(&e, .Right)
		}
		for _ in 0 ..< row {
			cmd(&e, .Down)
		}
		cmd(&e, .Green)
		testing.expectf(t, e.len == 1 && int(e.buf[0]) == c, "could not type character %d (%c) with the commands", c, rune(c))
	}
}

@(test)
test_every_character_can_be_typed_with_the_mouse :: proc(t: ^testing.T) {
	for row in 0 ..< TEXT_ENTRY_CHAR_ROWS {
		for col in 0 ..< TEXT_ENTRY_COLS {
			e := new_entry()
			click_cell(&e, col, row)
			if ch, ok := text_entry_char_at(col, row); ok {
				testing.expectf(t, e.len == 1 && e.buf[0] == ch, "click (%d,%d) typed the wrong thing", col, row)
			} else {
				testing.expectf(t, e.len == 0, "the filler cell typed something")
			}
			testing.expect(t, e.col == col && e.row == row) // the highlight followed the click
		}
	}
}

@(test)
test_typing_builds_text_in_order :: proc(t: ^testing.T) {
	e := new_entry()
	cmd(&e, .Green) // A
	cmd(&e, .Right, .Green) // B
	cmd(&e, .Right, .Right, .Green) // column 3: D
	testing.expect_value(t, text_entry_text(&e), "ABD")
	cmd(&e, .Down, .Green) // row 1, column 3: T
	testing.expect_value(t, text_entry_text(&e), "ABDT")
}

@(test)
test_navigation_wraps_and_the_action_row_steps_by_cell :: proc(t: ^testing.T) {
	e := new_entry()
	cmd(&e, .Left)
	testing.expect_value(t, e.col, TEXT_ENTRY_COLS - 1) // wrapped
	cmd(&e, .Right)
	testing.expect_value(t, e.col, 0)
	cmd(&e, .Up)
	testing.expect_value(t, e.row, TEXT_ENTRY_ROWS - 1) // wrapped up into the action row
	testing.expect_value(t, text_entry_action_at(e.col), Text_Entry_Action.Backspace)
	cmd(&e, .Right)
	testing.expect_value(t, text_entry_action_at(e.col), Text_Entry_Action.Clear)
	cmd(&e, .Right, .Right)
	testing.expect_value(t, text_entry_action_at(e.col), Text_Entry_Action.Cancel)
	cmd(&e, .Right)
	testing.expect_value(t, text_entry_action_at(e.col), Text_Entry_Action.Backspace) // wrapped across the actions
	cmd(&e, .Left)
	testing.expect_value(t, text_entry_action_at(e.col), Text_Entry_Action.Cancel)
	cmd(&e, .Down)
	testing.expect_value(t, e.row, 0) // wrapped down to the top
	// Going up from an action cell lands on a character above it.
	e = new_entry()
	cmd(&e, .Up, .Right, .Right) // Done
	cmd(&e, .Up)
	testing.expect_value(t, e.row, TEXT_ENTRY_CHAR_ROWS - 1)
	testing.expect(t, e.col >= 2 * ACTION_COLS && e.col < 3 * ACTION_COLS) // the columns Done spans
}

@(test)
test_action_cells :: proc(t: ^testing.T) {
	e := new_entry("ABC")
	cmd(&e, .Up) // the action row, Backspace
	cmd(&e, .Green)
	testing.expect_value(t, text_entry_text(&e), "AB")
	res := cmd(&e, .Right, .Green) // Clear
	testing.expect(t, e.len == 0 && res == .Editing)
	cmd(&e, .Green) // backspace on empty: nothing
	e = new_entry("XY")
	testing.expect_value(t, cmd(&e, .Up, .Right, .Right, .Green), Text_Entry_Result.Done)
	testing.expect_value(t, text_entry_text(&e), "XY") // done keeps the text
	e = new_entry("XY")
	testing.expect_value(t, cmd(&e, .Up, .Right, .Right, .Right, .Green), Text_Entry_Result.Cancelled)
}

@(test)
test_shortcuts_and_the_ignored_command :: proc(t: ^testing.T) {
	e := new_entry("HI")
	cmd(&e, .Yellow)
	testing.expect_value(t, text_entry_text(&e), "H") // yellow = backspace from anywhere
	cmd(&e, .Blue) // blue does nothing
	testing.expect(t, text_entry_text(&e) == "H" && e.result == .Editing && e.col == 0 && e.row == 0)
	testing.expect_value(t, cmd(&e, .Red), Text_Entry_Result.Cancelled) // red = cancel from anywhere
}

@(test)
test_the_length_limit :: proc(t: ^testing.T) {
	e := new_entry("", 3)
	for _ in 0 ..< 6 {
		cmd(&e, .Green) // type A each time
	}
	testing.expect_value(t, text_entry_text(&e), "AAA") // stops at the limit
	cmd(&e, .Yellow, .Green) // making room works again
	testing.expect_value(t, text_entry_text(&e), "AAA")
	cmd(&e, .Up, .Right, .Green, .Down, .Green) // Clear, then type from the grid: nothing wrong with the limit
	testing.expect(t, e.len <= 3)
	// The maximum the keypad can hold.
	full := new_entry("", TEXT_ENTRY_MAX)
	for _ in 0 ..< TEXT_ENTRY_MAX + 10 {
		cmd(&full, .Green)
	}
	testing.expect_value(t, full.len, TEXT_ENTRY_MAX)
}

@(test)
test_nothing_changes_after_the_result_is_decided :: proc(t: ^testing.T) {
	e := new_entry("AB")
	cmd(&e, .Red)
	testing.expect_value(t, cmd(&e, .Green, .Yellow, .Right), Text_Entry_Result.Cancelled)
	testing.expect_value(t, text_entry_text(&e), "AB") // frozen
	click_cell(&e, 5, 1)
	testing.expect_value(t, text_entry_text(&e), "AB")
	// A new begin starts afresh.
	text_entry_begin(&e, "AGAIN", "")
	testing.expect(t, e.result == .Editing && e.len == 0)
}

@(test)
test_mouse_hover_highlights_and_clicks_press :: proc(t: ^testing.T) {
	e := new_entry()
	rc := text_entry_cell_rect(7, 2)
	text_entry_handle(&e, Mouse_Move{rc.x + 3, rc.y + 3})
	testing.expect(t, e.col == 7 && e.row == 2 && e.len == 0) // hover alone types nothing
	text_entry_handle(&e, Mouse_Move{0, 0}) // outside the grid: the highlight stays
	testing.expect(t, e.col == 7 && e.row == 2)
	text_entry_handle(&e, Mouse_Button_Event{button = .Right, x = rc.x + 3, y = rc.y + 3, down = true}) // only the left button
	testing.expect_value(t, e.len, 0)
	text_entry_handle(&e, Mouse_Wheel{dy = 3})
	testing.expect_value(t, e.len, 0)
	// Each of the four wide action cells works from any of its columns.
	for a in Text_Entry_Action {
		for k in 0 ..< ACTION_COLS {
			e = new_entry("AB")
			res := click_cell(&e, int(a) * ACTION_COLS + k, TEXT_ENTRY_ROWS - 1)
			switch a {
			case .Backspace:
				testing.expect_value(t, text_entry_text(&e), "A")
			case .Clear:
				testing.expect_value(t, e.len, 0)
			case .Done:
				testing.expect_value(t, res, Text_Entry_Result.Done)
			case .Cancel:
				testing.expect_value(t, res, Text_Entry_Result.Cancelled)
			}
		}
	}
}

@(test)
test_cell_geometry :: proc(t: ^testing.T) {
	for row in 0 ..< TEXT_ENTRY_ROWS {
		for col in 0 ..< TEXT_ENTRY_COLS {
			rc := text_entry_cell_rect(col, row)
			for p in ([][2]int{{0, 0}, {rc.w - 1, rc.h - 1}, {rc.w / 2, rc.h / 2}}) {
				c2, r2, ok := text_entry_cell_at(rc.x + p.x, rc.y + p.y)
				testing.expectf(t, ok && r2 == row, "cell (%d,%d) point %v", col, row, p)
				if row < TEXT_ENTRY_ROWS - 1 {
					testing.expect(t, c2 == col)
				} else {
					testing.expect(t, text_entry_action_at(c2) == text_entry_action_at(col))
				}
			}
		}
	}
	_, _, ok := text_entry_cell_at(TE_X - 1, TE_GRID_Y)
	testing.expect(t, !ok)
	_, _, ok = text_entry_cell_at(TE_X + TEXT_ENTRY_COLS * TE_CELL_W, TE_GRID_Y)
	testing.expect(t, !ok)
	_, _, ok = text_entry_cell_at(TE_X, TE_GRID_Y + TEXT_ENTRY_ROWS * TE_CELL_H)
	testing.expect(t, !ok)
}

@(test)
test_layout_fits_the_screen :: proc(t: ^testing.T) {
	grid := Rect{TE_X, TE_GRID_Y, TEXT_ENTRY_COLS * TE_CELL_W, TEXT_ENTRY_ROWS * TE_CELL_H}
	testing.expect(t, grid.x >= 0 && grid.x + grid.w <= SCREEN_W && grid.y + grid.h <= TE_HELP_Y)
	testing.expect(t, TE_HELP_Y + 3 * LINE_ADVANCE <= SCREEN_H)
	testing.expect(t, TE_FIELD.y > TE_TITLE_Y + GLYPH_H && TE_FIELD.y + TE_FIELD.h <= TE_GRID_Y)
	testing.expect(t, TE_FIELD.x + TE_FIELD.w <= SCREEN_W)
	// The longest text fits its field, with room for the counter.
	longest := text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
	testing.expect(t, 4 + longest + text_width("32/32") + 12 <= TE_FIELD.w)
	// A wide action cell fits its longest label.
	for a in Text_Entry_Action {
		testing.expect(t, text_width(TEXT_ENTRY_ACTION_LABELS[a]) < ACTION_COLS * TE_CELL_W - 2)
	}
}

Keypad_Log :: struct {
	rects, out_of_bounds, presents: int,
	hilite_cells:                   int, // big yellow rects: the selected cell
}

keypad_renderer :: proc(l: ^Keypad_Log) -> Renderer {
	return Renderer {
		data = l,
		clear = proc(d: rawptr, c: Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: Color) {
			k := (^Keypad_Log)(d)
			k.rects += 1
			if x < 0 || y < 0 || x + w > SCREEN_W || y + h > SCREEN_H {
				k.out_of_bounds += 1
			}
			if c == TE_HILITE && w >= TE_CELL_W - 2 && h >= TE_CELL_H - 4 {
				k.hilite_cells += 1
			}
		},
		present = proc(d: rawptr) {(^Keypad_Log)(d).presents += 1},
	}
}

@(test)
test_the_keypad_draws_on_screen_and_highlights_one_cell :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Keypad_Log
	r := keypad_renderer(&log)
	e := new_entry("HELLO WORLD")
	m := default_input_map()
	for round in 0 ..< 2 {
		if round == 1 { 	// the longest labels allowed
			for a in Action {
				set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for row in 0 ..< TEXT_ENTRY_ROWS {
			for col in ([]int{0, 5, 15}) {
				e.col, e.row = col, row
				log = {}
				text_entry_draw(&e, &r, &m)
				testing.expectf(t, log.out_of_bounds == 0, "(%d,%d): %d rects off screen", col, row, log.out_of_bounds)
				testing.expect_value(t, log.presents, 1)
				testing.expectf(t, log.hilite_cells == 1, "(%d,%d): %d highlighted cells", col, row, log.hilite_cells)
			}
		}
	}
	// A full field has no insertion block, and a long text still fits.
	e = new_entry("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
	log = {}
	text_entry_draw(&e, &r, nil)
	testing.expect(t, log.out_of_bounds == 0)
}

@(test)
test_the_keypad_text_is_drawable_and_help_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for a in Text_Entry_Action {
		testing.expect(t, text_is_drawable(TEXT_ENTRY_ACTION_LABELS[a]))
	}
	for row in 0 ..< TEXT_ENTRY_CHAR_ROWS {
		testing.expect(t, text_is_drawable(TEXT_ENTRY_GRID[row][:TEXT_ENTRY_COLS - (row == TEXT_ENTRY_CHAR_ROWS - 1 ? 1 : 0)]))
	}
	m := default_input_map()
	for round in 0 ..< 2 {
		if round == 1 {
			for a in Action {
				set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for line in 0 ..< 3 {
			text := text_entry_help(line, &m)
			if round == 0 {
				testing.expectf(t, text_is_drawable(text), "help line %d: %s", line, text)
			}
			testing.expectf(t, TE_X + text_width(text) <= SCREEN_W - 8, "help line %d too wide: %s", line, text)
		}
	}
	testing.expect_value(t, text_entry_help(0, nil), "UP/DOWN/LEFT/RIGHT: SELECT")
}

@(test)
test_a_refused_done_resumes_typing_with_a_note :: proc(t: ^testing.T) {
	e := new_entry("TAKEN")
	testing.expect_value(t, cmd(&e, .Up, .Right, .Right, .Green), Text_Entry_Result.Done)
	text_entry_resume(&e, "NAME IN USE")
	testing.expect(t, e.result == .Editing && e.note == "NAME IN USE" && text_entry_text(&e) == "TAKEN")
	cmd(&e, .Left) // any input clears the note
	testing.expect_value(t, e.note, "")
	text_entry_resume(&e, "AGAIN")
	click_cell(&e, 0, 0)
	testing.expect_value(t, e.note, "")
	text_entry_resume(&e, "HOVER")
	text_entry_handle(&e, Mouse_Move{20, 60}) // moving the mouse alone keeps it
	testing.expect_value(t, e.note, "HOVER")
	// The note is drawn in red, inside the screen.
	defer free_all(context.temp_allocator)
	log: Keypad_Log
	r := keypad_renderer(&log)
	text_entry_draw(&e, &r, nil)
	testing.expect(t, log.out_of_bounds == 0 && log.presents == 1)
}
