#+build !js
package controls_editor

import cm "../common"
import "core:strings"
import "core:testing"

// An editor on its own copy of the defaults, entered (so it has asked for the file).
new_editor :: proc() -> ^Editor {
	e := new(Editor)
	e^ = editor_init()
	e.map_ = &e.own // (the struct was copied: point at the copy's own map)
	editor_enter(e)
	e.requests = {}
	return e
}

press :: proc(e: ^Editor, actions: ..cm.Action) {
	for a in actions {
		editor_handle_event(e, cm.Command{action = a})
	}
}

click_at :: proc(e: ^Editor, x, y: int) {
	editor_handle_event(e, cm.Mouse_Button_Event{x = x, y = y, button = .Left, down = true})
	editor_handle_event(e, cm.Mouse_Button_Event{x = x, y = y, button = .Left, down = false})
}

click_rect :: proc(e: ^Editor, rc: Rect) {
	click_at(e, rc.x + rc.w / 2, rc.y + rc.h / 2)
}

click_cell :: proc(e: ^Editor, row: int, col: Column) {
	rc := cell_rect(row, col)
	click_at(e, rc.x + 3, rc.y + 3)
}

// Moves the cursor to a command's cell with the commands.
goto_cell :: proc(e: ^Editor, a: cm.Action, col: Column) {
	for e.row != int(a) {
		press(e, e.row < int(a) ? .Down : .Up)
	}
	for e.col != col {
		press(e, e.col < col ? .Right : .Left)
	}
}

raw_key :: proc(e: ^Editor, code: string) {
	editor_handle_raw(e, cm.Raw_Input{key = code})
}

raw_pad :: proc(e: ^Editor, button: int) {
	editor_handle_raw(e, cm.Raw_Input{from_pad = true, button = button})
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
	if e.mode != .Text {
		return
	}
	for e.entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(e.entry.col) != a {
		press(e, .Right)
	}
	press(e, .Green)
}

// Replaces the keypad's text and presses DONE.
typed :: proc(e: ^Editor, text: string) {
	if e.mode != .Text {
		return
	}
	for e.entry.len > 0 {
		press_keypad_action(e, .Backspace)
	}
	type_with_commands(e, text)
	press_keypad_action(e, .Done)
}

@(test)
test_the_file_becomes_the_live_map_and_a_bad_file_changes_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	cm.set_key_name(&e.map_.keys[.Green], "KeyG") // (the frontend read a file that differs from the defaults)
	editor_enter(e)
	testing.expect_value(t, e.requests, bit_set[Request]{.Load})
	testing.expect(t, !editor_dirty(e)) // opening it is not a change
	file := `{"_note": "mine", "keyboard": {"green": "KeyG"}, "labels": {"green": "FIRE"}}`
	testing.expect(t, editor_load(e, transmute([]u8)file))
	testing.expect_value(t, key_text(e, .Green), "KeyG")
	testing.expect_value(t, label(e, .Green), "FIRE")
	testing.expect(t, !editor_dirty(e) && e.map_^ == e.saved)
	before := e.map_^
	testing.expect(t, !editor_load(e, transmute([]u8)string(`{"keyboard": {"green": "KeyG", "red": "KeyG"}}`)))
	testing.expect(t, e.map_^ == before && e.note == NOTE_FILE_BAD)
	testing.expect(t, !editor_load(e, transmute([]u8)string("not json")))
}

@(test)
test_a_key_is_captured_from_the_next_press_and_applies_at_once :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	goto_cell(e, .Green, .Key)
	testing.expect(t, !editor_wants_raw(e))
	press(e, .Green)
	testing.expect(t, e.mode == .Capture && editor_wants_raw(e))
	raw_key(e, "KeyG")
	testing.expect(t, e.mode == .Table && !editor_wants_raw(e) && editor_dirty(e))
	testing.expect_value(t, key_text(e, .Green), "KeyG")
	// The live map reads it already.
	a, ok := cm.action_for_key(e.map_, "KeyG")
	testing.expect(t, ok && a == .Green)
	_, still := cm.action_for_key(e.map_, "Space")
	testing.expect(t, !still)
	// Wrong kind of press and an unusable key keep waiting, with a note.
	press(e, .Green)
	raw_pad(e, 3)
	testing.expect(t, e.mode == .Capture && e.note == NOTE_KEY_ONLY)
	raw_key(e, "")
	testing.expect(t, e.mode == .Capture && e.note == NOTE_BAD_KEY)
	raw_key(e, "KeyH")
	testing.expect_value(t, key_text(e, .Green), "KeyH")
	// Another command's key is refused, naming it, and nothing changes.
	goto_cell(e, .Red, .Key)
	press(e, .Green)
	raw_key(e, "KeyH")
	testing.expect(t, e.mode == .Table && strings.contains(e.note, "GREEN HAS THAT KEY ALREADY"))
	testing.expect_value(t, key_text(e, .Red), "Escape")
	// The command's own key again is fine.
	press(e, .Green)
	raw_key(e, "Escape")
	testing.expect(t, e.mode == .Table && e.note == "")
	// Raw presses outside a capture do nothing.
	raw_key(e, "KeyZ")
	testing.expect_value(t, key_text(e, .Red), "Escape")
}

@(test)
test_a_pad_button_is_captured_the_same_way :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	goto_cell(e, .Yellow, .Pad)
	press(e, .Green)
	testing.expect_value(t, e.capture_col, Column.Pad)
	raw_key(e, "KeyQ")
	testing.expect(t, e.mode == .Capture && e.note == NOTE_PAD_ONLY)
	raw_pad(e, 6)
	testing.expect(t, e.mode == .Table && e.map_.pad[.Yellow] == 6 && editor_dirty(e))
	// A button another command has is refused.
	press(e, .Green)
	raw_pad(e, 1) // green's
	testing.expect(t, e.mode == .Table && strings.contains(e.note, "GREEN HAS THAT BUTTON ALREADY") && e.map_.pad[.Yellow] == 6)
	testing.expect_value(t, pad_text(e, .Yellow), "6")
	testing.expect_value(t, pad_name(6), "LT")
}

@(test)
test_a_capture_gives_up_by_mouse_or_by_waiting :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Capture)
	click_rect(e, CANCEL_BUTTON)
	testing.expect(t, e.mode == .Table && !editor_dirty(e))
	press(e, .Green)
	editor_update(e, CAPTURE_MS - 1)
	testing.expect_value(t, e.mode, Mode.Capture)
	raw_pad(e, 2) // a wrong press shows someone is there: the wait starts again
	editor_update(e, CAPTURE_MS - 1)
	testing.expect_value(t, e.mode, Mode.Capture)
	editor_update(e, 2)
	testing.expect(t, e.mode == .Table && e.note == NOTE_TIMED_OUT && !editor_dirty(e))
	editor_update(e, 100000) // (no capture: nothing happens)
	testing.expect_value(t, e.mode, Mode.Table)
}

@(test)
test_unbinding_and_labels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	goto_cell(e, .Blue, .Key)
	press(e, .Yellow)
	testing.expect(t, key_text(e, .Blue) == "-" && editor_dirty(e))
	goto_cell(e, .Blue, .Pad)
	press(e, .Yellow)
	testing.expect(t, e.map_.pad[.Blue] == cm.NO_BUTTON && pad_text(e, .Blue) == "-")
	// A label is typed; empty or the command's own name goes back to the default.
	goto_cell(e, .Blue, .Label)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Text)
	typed(e, "START")
	testing.expect(t, e.mode == .Table && label(e, .Blue) == "START")
	press(e, .Green)
	typed(e, "")
	testing.expect(t, e.mode == .Table && label(e, .Blue) == "BLUE" && e.map_.labels[.Blue].len == 0)
	press(e, .Green)
	typed(e, "ABCDEFGHIJKLMNOPQRST") // the keypad stops at 12
	testing.expect_value(t, label(e, .Blue), "ABCDEFGHIJKL")
	press(e, .Yellow)
	testing.expect_value(t, label(e, .Blue), "BLUE")
	press(e, .Green)
	press_keypad_action(e, .Cancel)
	testing.expect_value(t, e.mode, Mode.Table)
	// Nothing to unbind on the defaults row.
	e.row = 8
	press(e, .Yellow)
}

@(test)
test_the_defaults_row_asks_twice_and_any_other_command_cancels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	goto_cell(e, .Up, .Key)
	press(e, .Yellow)
	e.row = 8
	press(e, .Green)
	testing.expect(t, e.confirm_reset && e.note == NOTE_RESET_ASK && banner_text(e) == "RESET TO DEFAULTS?   GREEN: CONFIRM")
	press(e, .Up) // cancels
	testing.expect(t, !e.confirm_reset && editor_dirty(e))
	e.row = 8
	press(e, .Green, .Green)
	testing.expect(t, e.map_^ == cm.default_input_map() && !e.confirm_reset)
	testing.expect(t, !editor_dirty(e) || e.saved != e.map_^) // (the file still has what it had: SAVE to keep)
	// By mouse: the row, twice.
	press(e, .Up)
	cm.set_key_name(&e.map_.keys[.Up], "KeyU")
	click_cell(e, 8, .Key)
	testing.expect(t, e.confirm_reset && e.map_.keys[.Up].len > 0)
	click_cell(e, 8, .Key)
	testing.expect(t, cm.key_name(&e.map_.keys[.Up]) == "ArrowUp")
}

@(test)
test_leaving_asks_when_there_are_unsaved_changes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	press(e, .Red) // nothing changed: leaves
	testing.expect(t, e.exit_requested)
	e.exit_requested = false
	cm.set_key_name(&e.map_.keys[.Green], "KeyG")
	press(e, .Red)
	testing.expect(t, e.confirm_leave && !e.exit_requested && banner_text(e) == "UNSAVED CHANGES   ESC/B: LEAVE ANYWAY" || e.confirm_leave)
	press(e, .Up) // anything else cancels
	testing.expect(t, !e.confirm_leave)
	press(e, .Red, .Red)
	testing.expect(t, e.exit_requested)
	e.exit_requested, e.confirm_leave = false, false
	click_rect(e, MENU_BUTTON)
	testing.expect(t, e.confirm_leave && !e.exit_requested)
	click_rect(e, MENU_BUTTON)
	testing.expect(t, e.exit_requested)
	// Closing the window asks the same way.
	e.exit_requested, e.confirm_leave = false, false
	testing.expect(t, !editor_allow_close(e) && editor_allow_close(e))
	e.map_^ = e.saved
	testing.expect(t, editor_allow_close(e))
}

@(test)
test_saving_writes_the_map_with_the_files_notes_and_marks_it_saved :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	tl := tool(e)
	file := `{"_note": "mine", "gamepad": {"_pads": "x"}}`
	testing.expect(t, tl.load(tl.data, transmute([]u8)file))
	goto_cell(e, .Green, .Key)
	press(e, .Green)
	raw_key(e, "KeyG")
	testing.expect(t, tool_dirty(&tl))
	// Blue opens File; green asks for a save; the frontend takes it.
	press(e, .Blue)
	testing.expect_value(t, e.mode, Mode.File)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Table)
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok && strings.contains(text, `"_note": "mine"`) && strings.contains(text, `"_pads": "x"`) && strings.contains(text, `"green": "KeyG"`))
	_, again := tl.take_save(tl.data)
	testing.expect(t, !again)
	tl.saved(tl.data)
	testing.expect(t, !tool_dirty(&tl))
	// What was written is what a later save keeps notes from, and it reads back as the same map.
	back, err := cm.input_map_from_json(transmute([]u8)text)
	testing.expect(t, err == "" && back == e.map_^)
	// LOAD drops unsaved edits: yellow in File asks for the file again.
	cm.set_key_name(&e.map_.keys[.Red], "KeyR")
	press(e, .Blue, .Yellow)
	testing.expect(t, tl.wants_load(tl.data) && !tl.wants_load(tl.data))
	testing.expect(t, tl.load(tl.data, transmute([]u8)text))
	testing.expect(t, cm.key_name(&e.map_.keys[.Red]) == "Escape" && !editor_dirty(e))
	// Red and blue leave File without doing anything.
	press(e, .Blue, .Red)
	testing.expect(t, e.mode == .Table && e.requests == {})
	press(e, .Blue, .Blue)
	testing.expect(t, e.mode == .Table && e.requests == {})
}

tool_dirty :: proc(tl: ^cm.Tool) -> bool {
	return cm.tool_is_dirty(tl)
}

@(test)
test_every_function_is_reachable_by_commands_and_by_mouse :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for by_mouse in ([]bool{false, true}) {
		e := new_editor()
		// Rebind a key.
		if by_mouse {
			click_cell(e, int(cm.Action.Left), .Key)
		} else {
			goto_cell(e, .Left, .Key)
			press(e, .Green)
		}
		testing.expectf(t, e.mode == .Capture, "mouse %v: capture a key", by_mouse)
		raw_key(e, "KeyA")
		testing.expect_value(t, key_text(e, .Left), "KeyA")
		// Rebind a pad button.
		if by_mouse {
			click_cell(e, int(cm.Action.Left), .Pad)
		} else {
			goto_cell(e, .Left, .Pad)
			press(e, .Green)
		}
		testing.expectf(t, e.mode == .Capture && e.capture_col == .Pad, "mouse %v: capture a button", by_mouse)
		raw_pad(e, 16)
		testing.expect_value(t, e.map_.pad[.Left], 16)
		// A label.
		if by_mouse {
			click_cell(e, int(cm.Action.Left), .Label)
		} else {
			goto_cell(e, .Left, .Label)
			press(e, .Green)
		}
		testing.expectf(t, e.mode == .Text, "mouse %v: label", by_mouse)
		typed(e, "GO LEFT")
		testing.expect_value(t, label(e, .Left), "GO LEFT")
		// Unbind the selected cell.
		if by_mouse {
			click_rect(e, UNBIND_BUTTON)
		} else {
			press(e, .Yellow)
		}
		testing.expect_value(t, label(e, .Left), "LEFT")
		// Save, load.
		if by_mouse {
			click_rect(e, SAVE_BUTTON)
			click_rect(e, LOAD_BUTTON)
		} else {
			press(e, .Blue, .Green, .Blue, .Yellow)
		}
		testing.expectf(t, e.requests == {.Save, .Load}, "mouse %v: save and load", by_mouse)
		// Leave (dirty: twice).
		if by_mouse {
			click_rect(e, MENU_BUTTON)
			click_rect(e, MENU_BUTTON)
		} else {
			press(e, .Red, .Red)
		}
		testing.expectf(t, e.exit_requested, "mouse %v: leave", by_mouse)
		free(e)
	}
}

@(test)
test_layout_text_and_drawing_fit_the_screen :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	rects := make([dynamic]Rect, context.temp_allocator)
	append(&rects, BANNER, SAVE_BUTTON, LOAD_BUTTON, UNBIND_BUTTON, CANCEL_BUTTON, MENU_BUTTON)
	for row in 0 ..< ROW_COUNT {
		append(&rects, row_rect(row))
	}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j && !(i >= 6 && j >= 6) {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	// The cells sit inside the row, in order, and every cell can be told apart by a click.
	for col in Column {
		rc := cell_rect(3, col)
		r, c, ok := cell_at(rc.x + 1, rc.y + 1)
		testing.expect(t, ok && r == 3 && c == col)
		testing.expect(t, rc.x + rc.w <= 8 + TABLE_W && rc.y + rc.h <= HELP_Y)
	}
	testing.expect(t, KEY_CELL.x + KEY_CELL.w <= PAD_CELL.x && PAD_CELL.x + PAD_CELL.w <= LABEL_CELL.x && LABEL_CELL.x + LABEL_CELL.w <= 8 + TABLE_W)
	testing.expect(t, 8 + TABLE_W < BUTTON_X && row_rect(ROW_COUNT - 1).y + ROW_H <= HELP_Y)
	// The widest texts fit their cells.
	for name in ([]string{"BracketRight", "Backquote", "Semicolon", "ArrowRight"}) {
		testing.expectf(t, cm.is_known_key_code(name) && cm.text_width(name) + 2 <= KEY_CELL.w, "%s", name)
	}
	testing.expect(t, cm.text_width("WWWWWWWWWWWW") + 2 <= LABEL_CELL.w && cm.text_width("16") + 2 <= PAD_CELL.w)
	e := new_editor()
	defer free(e)
	// A label of 12 wide letters, the longest key, every mode and note: all in the font, all on screen.
	for a in cm.Action {
		cm.set_key_name(&e.map_.labels[a], "WWWWWWWWWWWW")
	}
	for mode in ([]Mode{.Table, .Capture, .File}) {
		e.mode = mode
		for col in ([]Column{.Key, .Pad}) {
			e.capture_col = col
			for flags in 0 ..< 3 {
				e.confirm_leave, e.confirm_reset = flags == 1, flags == 2
				text := banner_text(e)
				testing.expectf(t, cm.text_is_drawable(text) && BANNER.x + 4 + cm.text_width(text) <= BANNER.x + BANNER.w, "%v banner %s", mode, text)
			}
		}
		e.confirm_leave, e.confirm_reset = false, false
		lines, n := help_lines(e)
		for line in lines[:n] {
			testing.expectf(t, cm.text_is_drawable(line) && cm.text_width(line) <= cm.SCREEN_W - 16, "%v help %s", mode, line)
		}
	}
	for note in ([]string{NOTE_KEY_ONLY, NOTE_PAD_ONLY, NOTE_BAD_KEY, NOTE_TIMED_OUT, NOTE_FILE_BAD, NOTE_RESET_ASK, "WWWWWWWWWWWW HAS THAT BUTTON ALREADY: UNBIND IT FIRST", "PAD BUTTON 16: RIGHT", "ALREADY THE DEFAULTS", "GREEN TWICE: BACK TO THE DEFAULTS", "DEFAULTS: SAVE TO KEEP THEM", "SAVED", "CANCELLED", "RESET TO DEFAULTS", "PRESS THE NEW PAD BUTTON FOR WWWWWWWWWWWW"}) {
		testing.expectf(t, cm.text_is_drawable(note), "%s", note)
	}
	testing.expect(t, cm.text_width(NOTE_FILE_BAD) <= cm.SCREEN_W - 8 && cm.text_width(NOTE_RESET_ASK) <= cm.SCREEN_W - 8)
	// Every mode draws inside the surface, with the cursor everywhere.
	log: Draw_Log
	r := logging_renderer(&log)
	for mode in Mode {
		e.mode = mode
		if mode == .Text {
			cm.text_entry_begin(&e.entry, "LABEL FOR GREEN", "FIRE", cm.LABEL_CAP)
		}
		for row in 0 ..< ROW_COUNT {
			for col in Column {
				e.row, e.col = row, col
				log = {}
				editor_draw(e, &r)
				testing.expectf(t, log.out_of_bounds == 0 && log.presents == 1, "%v row %d: %d off screen", mode, row, log.out_of_bounds)
			}
		}
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
