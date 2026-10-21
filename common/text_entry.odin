package common

import "core:fmt"

// An on-screen keypad for typing text with only the eight commands (or the mouse). It is a modal
// screen a tool shows while it needs a string: a text field, a grid of characters, and one row of
// four wide action cells. Move over the grid with the d-pad; green presses the highlighted cell.
//
//   characters   type that character (until the text is as long as allowed)
//   BKSP         delete the last character
//   CLEAR        delete everything
//   DONE         finish: the tool then reads the text with text_entry_text
//   CANCEL       abandon: the tool keeps whatever it had
//
// Shortcuts: yellow is backspace and red is cancel. Blue does nothing, so a stray press cannot
// finish or change anything. With the mouse, hovering highlights a cell and clicking presses it.
//
// Usage: text_entry_begin when the tool wants text; while it is active send every event to
// text_entry_handle and draw with text_entry_draw instead of the tool's own screen; stop when
// text_entry_handle returns Done or Cancelled.

TEXT_ENTRY_COLS :: 16
TEXT_ENTRY_CHAR_ROWS :: 6
TEXT_ENTRY_ROWS :: TEXT_ENTRY_CHAR_ROWS + 1 // the character rows, then the action row
TEXT_ENTRY_MAX :: 32 // the default longest text (names and values)
TEXT_ENTRY_CAPACITY :: 1024 // the most a tool may ask for with `max_len` (the sounds' PLAY text)

Text_Entry_Result :: enum {
	Editing,
	Done,
	Cancelled,
}

Text_Entry_Action :: enum {
	Backspace,
	Clear,
	Done,
	Cancel,
}

Text_Entry :: struct {
	prompt:  string, // shown above the field; keep it alive (a string literal is fine)
	note:    string, // an optional message in red beside the prompt (e.g. "NAME IN USE"); keep it alive too
	buf:     [TEXT_ENTRY_CAPACITY]u8,
	len:     int,
	max_len: int,
	col:     int, // highlighted cell, 0..TEXT_ENTRY_COLS-1
	row:     int, // 0..TEXT_ENTRY_ROWS-1 (the last row is the action row)
	result:  Text_Entry_Result,
}

// The character rows: every printable ASCII character exactly once, arranged by kind (capitals,
// lower case, digits, punctuation). The very last cell is an unused filler; pressing it does nothing.
TEXT_ENTRY_GRID := [TEXT_ENTRY_CHAR_ROWS]string {
	"ABCDEFGHIJKLMNOP",
	"QRSTUVWXYZ.,-_'!",
	"abcdefghijklmnop",
	"qrstuvwxyz?:;()+",
	"0123456789=/*#@$",
	" \"%&<>[\\]^`{|}~\x00",
}

TEXT_ENTRY_ACTION_LABELS := [Text_Entry_Action]string {
	.Backspace = "BKSP",
	.Clear     = "CLEAR",
	.Done      = "DONE",
	.Cancel    = "CANCEL",
}

ACTION_COLS :: TEXT_ENTRY_COLS / len(Text_Entry_Action) // each action cell is this many columns wide

// Layout in logical pixels.
TE_X :: 8
TE_CELL_W :: 19
TE_CELL_H :: 14
TE_TITLE_Y :: 8
TE_FIELD :: Rect{8, 20, 304, 18}
TE_GRID_Y :: 44
TE_HELP_Y :: 146

text_entry_begin :: proc(e: ^Text_Entry, prompt: string, initial: string, max_len := TEXT_ENTRY_MAX) {
	e^ = {}
	e.prompt = prompt
	e.max_len = clamp(max_len, 1, TEXT_ENTRY_MAX)
	e.len = min(len(initial), e.max_len)
	copy(e.buf[:], initial[:e.len])
	e.result = .Editing
}

// The same for a long text (up to TEXT_ENTRY_CAPACITY characters): the field then shows the end of
// the text, led by "...". Names and values keep using text_entry_begin, which stops at 32.
text_entry_begin_long :: proc(e: ^Text_Entry, prompt: string, initial: string, max_len := TEXT_ENTRY_CAPACITY) {
	e^ = {}
	e.prompt = prompt
	e.max_len = clamp(max_len, 1, TEXT_ENTRY_CAPACITY)
	e.len = min(len(initial), e.max_len)
	copy(e.buf[:], initial[:e.len])
	e.result = .Editing
}

// The text typed so far; valid until the next change.
text_entry_text :: proc(e: ^Text_Entry) -> string {
	return string(e.buf[:e.len])
}

// The character at a grid cell, or ok = false for the filler cell and the action row.
text_entry_char_at :: proc(col, row: int) -> (ch: u8, ok: bool) {
	if row < 0 || row >= TEXT_ENTRY_CHAR_ROWS || col < 0 || col >= TEXT_ENTRY_COLS {
		return 0, false
	}
	c := TEXT_ENTRY_GRID[row][col]
	return c, c != 0
}

// Which action cell a column of the action row belongs to.
text_entry_action_at :: proc(col: int) -> Text_Entry_Action {
	return Text_Entry_Action(clamp(col / ACTION_COLS, 0, len(Text_Entry_Action) - 1))
}

// The rect of the cell (or, in the action row, of the whole wide action cell) at col, row.
text_entry_cell_rect :: proc(col, row: int) -> Rect {
	if row == TEXT_ENTRY_ROWS - 1 {
		first := int(text_entry_action_at(col)) * ACTION_COLS
		return Rect{TE_X + first * TE_CELL_W, TE_GRID_Y + row * TE_CELL_H, ACTION_COLS * TE_CELL_W, TE_CELL_H}
	}
	return Rect{TE_X + col * TE_CELL_W, TE_GRID_Y + row * TE_CELL_H, TE_CELL_W, TE_CELL_H}
}

// The cell under a logical position, if any.
text_entry_cell_at :: proc(px, py: int) -> (col, row: int, ok: bool) {
	x, y := px - TE_X, py - TE_GRID_Y
	if x < 0 || y < 0 {
		return 0, 0, false
	}
	col, row = x / TE_CELL_W, y / TE_CELL_H
	return col, row, col < TEXT_ENTRY_COLS && row < TEXT_ENTRY_ROWS
}

@(private = "file")
press_action :: proc(e: ^Text_Entry, a: Text_Entry_Action) {
	switch a {
	case .Backspace:
		e.len = max(e.len - 1, 0)
	case .Clear:
		e.len = 0
	case .Done:
		e.result = .Done
	case .Cancel:
		e.result = .Cancelled
	}
}

@(private = "file")
press_cell :: proc(e: ^Text_Entry) {
	if e.row == TEXT_ENTRY_ROWS - 1 {
		press_action(e, text_entry_action_at(e.col))
	} else if ch, ok := text_entry_char_at(e.col, e.row); ok && e.len < e.max_len {
		e.buf[e.len] = ch
		e.len += 1
	}
}

// Moves the highlight. Horizontal movement wraps; in the action row it steps from one action cell
// to the next. Vertical movement wraps and keeps the column (so the actions line up under the
// characters above them).
@(private = "file")
move :: proc(e: ^Text_Entry, a: Action) {
	#partial switch a {
	case .Left, .Right:
		step := a == .Right ? 1 : -1
		if e.row == TEXT_ENTRY_ROWS - 1 {
			n := (int(text_entry_action_at(e.col)) + step + len(Text_Entry_Action)) % len(Text_Entry_Action)
			e.col = n * ACTION_COLS
		} else {
			e.col = (e.col + step + TEXT_ENTRY_COLS) % TEXT_ENTRY_COLS
		}
	case .Up:
		e.row = (e.row + TEXT_ENTRY_ROWS - 1) % TEXT_ENTRY_ROWS
	case .Down:
		e.row = (e.row + 1) % TEXT_ENTRY_ROWS
	}
}

// After a Done the tool did not accept (say the name is taken): go back to typing, keeping the text,
// and show `note` beside the prompt until the next press.
text_entry_resume :: proc(e: ^Text_Entry, note: string) {
	e.result = .Editing
	e.note = note
}

// Feeds one input event to the keypad and says whether typing is still going on.
text_entry_handle :: proc(e: ^Text_Entry, ev: Input_Event) -> Text_Entry_Result {
	if e.result != .Editing {
		return e.result
	}
	#partial switch v in ev {
	case Command:
		e.note = ""
	case Mouse_Button_Event:
		if v.down {
			e.note = ""
		}
	}
	switch v in ev {
	case Command:
		switch v.action {
		case .Up, .Down, .Left, .Right:
			move(e, v.action)
		case .Green:
			press_cell(e)
		case .Yellow:
			press_action(e, .Backspace)
		case .Red:
			press_action(e, .Cancel)
		case .Blue:
		}
	case Mouse_Move:
		if col, row, ok := text_entry_cell_at(v.x, v.y); ok {
			e.col, e.row = col, row
		}
	case Mouse_Button_Event:
		if v.button == .Left && v.down {
			if col, row, ok := text_entry_cell_at(v.x, v.y); ok {
				e.col, e.row = col, row
				press_cell(e)
			}
		}
	case Mouse_Wheel:
	}
	return e.result
}

TE_BG :: Color{28, 28, 36}
TE_PANEL :: Color{64, 64, 76}
TE_TEXT :: Color{200, 200, 210}
TE_DIM :: Color{120, 120, 134}
TE_HILITE :: Color{255, 220, 80}
TE_WARN :: Color{235, 100, 90}

// Draws the whole keypad screen. `labels` supplies the on-screen names of the commands for the
// help text (nil for the defaults).
text_entry_draw :: proc(e: ^Text_Entry, r: ^Renderer, labels: ^Input_Map) {
	renderer_clear(r, TE_BG)
	draw_text(r, TE_X, TE_TITLE_Y, e.prompt, TE_HILITE)
	if e.note != "" {
		draw_text(r, TE_X + text_width(e.prompt) + 12, TE_TITLE_Y, e.note, TE_WARN)
	}

	// The field: the text so far and a block where the next character will go.
	renderer_fill_rect(r, TE_FIELD.x, TE_FIELD.y, TE_FIELD.w, TE_FIELD.h, TE_PANEL)
	renderer_fill_rect(r, TE_FIELD.x + 1, TE_FIELD.y + 1, TE_FIELD.w - 2, TE_FIELD.h - 2, TE_BG)
	count := fmt_count(e)
	// A long text shows its end (where the next character goes), led by "...".
	text := text_entry_visible(text_entry_text(e), TE_FIELD.w - 8 - text_width(count) - 6 - 3)
	ty := TE_FIELD.y + (TE_FIELD.h - GLYPH_H) / 2
	draw_text(r, TE_FIELD.x + 4, ty, text, TE_TEXT)
	cursor_x := TE_FIELD.x + 4 + text_width(text)
	if e.len < e.max_len {
		renderer_fill_rect(r, cursor_x, ty, 3, GLYPH_H - 1, TE_HILITE)
	}
	draw_text(r, TE_FIELD.x + TE_FIELD.w - 4 - text_width(count), ty, count, TE_DIM)

	// The grid.
	for row in 0 ..< TEXT_ENTRY_CHAR_ROWS {
		for col in 0 ..< TEXT_ENTRY_COLS {
			rc := text_entry_cell_rect(col, row)
			selected := e.col == col && e.row == row
			renderer_fill_rect(r, rc.x, rc.y, rc.w - 1, rc.h - 1, selected ? TE_HILITE : TE_PANEL)
			ch, has := text_entry_char_at(col, row)
			if !has {
				continue // the filler cell stays blank
			}
			color := selected ? TE_BG : TE_TEXT
			if ch == ' ' { 	// a space has no shape: show a small bar so the cell reads as "space"
				renderer_fill_rect(r, rc.x + 5, rc.y + rc.h - 5, rc.w - 11, 1, color)
			} else {
				one := [1]u8{ch}
				draw_text(r, rc.x + (rc.w - 1 - text_width(string(one[:]))) / 2, rc.y + (rc.h - GLYPH_H) / 2, string(one[:]), color)
			}
		}
	}
	for a in Text_Entry_Action {
		rc := text_entry_cell_rect(int(a) * ACTION_COLS, TEXT_ENTRY_ROWS - 1)
		selected := e.row == TEXT_ENTRY_ROWS - 1 && text_entry_action_at(e.col) == a
		renderer_fill_rect(r, rc.x, rc.y + 2, rc.w - 1, rc.h - 3, selected ? TE_HILITE : TE_PANEL)
		name := TEXT_ENTRY_ACTION_LABELS[a]
		draw_text(r, rc.x + (rc.w - 1 - text_width(name)) / 2, rc.y + 2 + (rc.h - 3 - GLYPH_H) / 2, name, selected ? TE_BG : TE_TEXT)
	}

	// Help.
	draw_text(r, TE_X, TE_HELP_Y, text_entry_help(0, labels), TE_TEXT)
	draw_text(r, TE_X, TE_HELP_Y + LINE_ADVANCE, text_entry_help(1, labels), TE_TEXT)
	draw_text(r, TE_X, TE_HELP_Y + 2 * LINE_ADVANCE, text_entry_help(2, labels), TE_TEXT)
	renderer_present(r)
}

// The part of `text` to show in `width` pixels: all of it if it fits, else "..." and the end of it.
text_entry_visible :: proc(text: string, width: int) -> string {
	if text_width(text) <= width {
		return text
	}
	dots := text_width("...")
	used := dots
	start := len(text)
	for start > 0 {
		one := text[start - 1:start]
		w := text_width(one)
		if used + w > width {
			break
		}
		used += w
		start -= 1
	}
	return fmt.tprintf("...%s", text[start:])
}

// The three help lines, built with the user's labels (on the temp allocator).
text_entry_help :: proc(line: int, labels: ^Input_Map) -> string {
	l :: action_label
	switch line {
	case 0:
		return fmt.tprintf("%s/%s/%s/%s: SELECT", l(labels, .Up), l(labels, .Down), l(labels, .Left), l(labels, .Right))
	case 1:
		return fmt.tprintf("%s: PRESS THE CELL  %s: BACKSPACE", l(labels, .Green), l(labels, .Yellow))
	case 2:
		return fmt.tprintf("%s: CANCEL   MOUSE: CLICK A CELL", l(labels, .Red))
	}
	return ""
}

@(private = "file")
fmt_count :: proc(e: ^Text_Entry) -> string {
	return fmt.tprintf("%d/%d", e.len, e.max_len)
}
