package font_editor

import cm "../common"
import "core:mem"

Request :: enum {
	Save,
	Load,
}

// Red always means "back". Four modes:
//   Pick:  d-pad moves over the 16 x 16 character grid (left/right one character, up/down one row);
//          green edits the selected glyph (creating it if absent); yellow opens Setup; blue opens
//          File; red leaves for the main menu (twice if there are unsaved changes).
//   Edit:  the pixel canvas for one glyph. D-pad moves the cursor; green toggles the pixel; yellow
//          opens Setup; blue opens File; red returns to the grid.
//   Setup: up/down choose a row, left/right change it (this glyph's width, the font's height,
//          whether this glyph is present); green runs the action rows: Copy (remember this glyph),
//          Paste (make this character a copy of the remembered one) and Delete (remove this glyph
//          for good; green twice) and Flip horizontal / Flip vertical (mirror this glyph; again undoes
//          it). Blue opens File; red returns to where it was opened.
//   File:  green saves, yellow loads, red or blue cancel; every choice returns to where it was opened.
// The mouse works in all modes and switches mode itself (click a grid cell to select it and again
// to edit; paint on the canvas; - and + buttons; the YES/NO button; SAVE, LOAD, EDIT/GRID, MENU).
Mode :: enum {
	Pick,
	Edit,
	Setup,
	File,
}

Setup_Row :: enum {
	Width,
	Height,
	Present,
	Copy,
	Paste,
	Delete,
	Flip_Horizontal,
	Flip_Vertical,
}

// State for the font editor. About 1 MB because of the font: create it as a global or with new(),
// and initialise it in place with editor_init. Never copy or return one by value.
Editor :: struct {
	font:           cm.Pixel_Font,
	code:           int, // selected character, 0..255
	cx, cy:         int, // cursor in the selected glyph, always inside it
	mode:           Mode,
	back:           Mode, // Pick or Edit: where Setup and File return to
	row:            Setup_Row,
	dirty:          bool, // the font changed since the last save/load
	requests:       bit_set[Request],
	exit_requested: bool,
	confirm_exit:   bool, // unsaved changes: the next exit request is the confirmation
	paint:          Maybe(bool), // mouse drag in progress: the value being painted
	clipboard:      cm.Bitmap, // the last copied glyph (when has_clip)
	has_clip:       bool,
	clip_code:      int, // which character it was copied from, for display
	confirm_delete: bool, // Delete was run once: the next Delete is the confirmation
	labels:         ^cm.Input_Map,
}

// Starts blank: an 8 pixel high font with no glyphs.
editor_init :: proc(e: ^Editor) {
	labels := e.labels
	mem.zero_item(e)
	e.labels = labels
	cm.pixel_font_reset(&e.font)
}

// Called each time the tool becomes the active one: start blank (so unsaved edits do not survive
// leaving), then ask the frontend to load the saved font.
editor_enter :: proc(e: ^Editor) {
	editor_init(e)
	e.requests = {.Load}
}

editor_mark_saved :: proc(e: ^Editor) {
	e.dirty = false
}

glyph :: proc(e: ^Editor) -> ^cm.Bitmap {
	return &e.font.glyphs[e.code]
}

present :: proc(e: ^Editor) -> bool {
	return e.font.present[e.code]
}

clamp_cursor :: proc(e: ^Editor) {
	g := glyph(e)
	e.cx = clamp(e.cx, 0, g.width - 1)
	e.cy = clamp(e.cy, 0, g.height - 1)
}

// True while the left side shows the pixel canvas rather than the character grid: while editing,
// and in Setup/File when they were opened from editing (unless the glyph was just made absent).
showing_canvas :: proc(e: ^Editor) -> bool {
	return e.mode == .Edit || (e.mode != .Pick && e.back == .Edit && present(e))
}

@(private = "file")
set_code :: proc(e: ^Editor, code: int) {
	e.code = clamp(code, 0, cm.PIXEL_FONT_CHARS - 1)
	clamp_cursor(e)
}

// Selecting a glyph that is not there yet creates it (a blank one at its stored width).
@(private = "file")
begin_edit :: proc(e: ^Editor) {
	if cm.pixel_font_set_present(&e.font, e.code, true) {
		e.dirty = true
	}
	e.mode = .Edit
	e.cx, e.cy = 0, 0
	clamp_cursor(e)
}

// Setup and File remember where they were opened from, so Red goes back there.
@(private = "file")
open_side_mode :: proc(e: ^Editor, m: Mode) {
	if e.mode == .Pick || e.mode == .Edit {
		e.back = e.mode
	}
	e.mode = m
}

@(private = "file")
close_side_mode :: proc(e: ^Editor) {
	// A glyph made absent in Setup cannot be edited: fall back to the grid.
	e.mode = e.back == .Edit && present(e) ? .Edit : .Pick
}

@(private = "file")
change_setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
	switch row {
	case .Width:
		if cm.pixel_font_set_width(&e.font, e.code, glyph(e).width + delta) {
			e.dirty = true
		}
	case .Height:
		if cm.pixel_font_set_height(&e.font, e.font.height + delta) {
			e.dirty = true
		}
	case .Present:
		// Right means yes, left means no.
		if cm.pixel_font_set_present(&e.font, e.code, delta > 0) {
			e.dirty = true
		}
	case .Copy, .Paste, .Delete, .Flip_Horizontal, .Flip_Vertical:
		// Actions, not values: green runs them.
	}
	clamp_cursor(e)
}

// Remembers the selected glyph. Only glyphs that exist can be copied.
@(private = "file")
copy_selected :: proc(e: ^Editor) {
	if cm.pixel_font_copy_glyph(&e.font, e.code, &e.clipboard) {
		e.has_clip = true
		e.clip_code = e.code
	}
}

// Makes the selected character a copy of the remembered glyph (creating it if absent).
@(private = "file")
paste :: proc(e: ^Editor) {
	if e.has_clip && cm.pixel_font_paste_glyph(&e.font, e.code, &e.clipboard) {
		e.dirty = true
		clamp_cursor(e)
	}
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes. A
// character with no glyph has nothing to delete and is never armed.
@(private = "file")
delete_selected :: proc(e: ^Editor) {
	if !present(e) {
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.pixel_font_delete(&e.font, e.code)
	e.dirty = true
	clamp_cursor(e)
}

// Mirrors the selected glyph (only glyphs that exist). It only counts as changed if it moved something.
@(private = "file")
flip :: proc(e: ^Editor, horizontal: bool) {
	if !present(e) {
		return
	}
	changed := horizontal ? cm.bitmap_flip_horizontal(glyph(e)) : cm.bitmap_flip_vertical(glyph(e))
	if changed {
		e.dirty = true
	}
}

@(private = "file")
run_action_row :: proc(e: ^Editor) {
	#partial switch e.row {
	case .Flip_Horizontal:
		flip(e, true)
	case .Flip_Vertical:
		flip(e, false)
	case .Copy:
		copy_selected(e)
	case .Paste:
		paste(e)
	case .Delete:
		delete_selected(e)
	}
}

@(private = "file")
set_pixel :: proc(e: ^Editor, x, y: int, on: bool) {
	if cm.bitmap_set(glyph(e), x, y, on) {
		e.dirty = true
	}
}

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch v in ev {
	case cm.Command:
		editor_apply_action(e, v.action)
	case cm.Mouse_Move:
		if on, painting := e.paint.?; painting && e.mode == .Edit {
			g := glyph(e)
			if x, y, ok := cell_at(g.width, g.height, v.x, v.y); ok {
				e.cx, e.cy = x, y
				set_pixel(e, x, y, on)
			}
		}
	case cm.Mouse_Button_Event:
		if v.button == .Left {
			if v.down {
				click(e, v.x, v.y)
			} else {
				e.paint = nil
			}
		}
	case cm.Mouse_Wheel:
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	if a != .Red {
		e.confirm_exit = false // any other command cancels the "leave anyway?" prompt
	}
	if !(e.mode == .Setup && e.row == .Delete && a == .Green) {
		e.confirm_delete = false // so does anything but running Delete again
	}
	switch e.mode {
	case .Pick:
		#partial switch a {
		case .Up:
			set_code(e, e.code - cm.PIXEL_FONT_CHARS / 16)
		case .Down:
			set_code(e, e.code + cm.PIXEL_FONT_CHARS / 16)
		case .Left:
			set_code(e, e.code - 1)
		case .Right:
			set_code(e, e.code + 1)
		case .Green:
			begin_edit(e)
		case .Yellow:
			open_side_mode(e, .Setup)
		case .Blue:
			open_side_mode(e, .File)
		case .Red:
			request_exit(e)
		}
	case .Edit:
		g := glyph(e)
		#partial switch a {
		case .Up:
			e.cy = max(e.cy - 1, 0)
		case .Down:
			e.cy = min(e.cy + 1, g.height - 1)
		case .Left:
			e.cx = max(e.cx - 1, 0)
		case .Right:
			e.cx = min(e.cx + 1, g.width - 1)
		case .Green:
			cm.bitmap_toggle(g, e.cx, e.cy)
			e.dirty = true
		case .Yellow:
			open_side_mode(e, .Setup)
		case .Blue:
			open_side_mode(e, .File)
		case .Red:
			e.mode = .Pick
		}
	case .Setup:
		#partial switch a {
		case .Up:
			e.row = Setup_Row((int(e.row) + len(Setup_Row) - 1) % len(Setup_Row))
		case .Down:
			e.row = Setup_Row((int(e.row) + 1) % len(Setup_Row))
		case .Left:
			change_setting(e, e.row, -1)
		case .Right:
			change_setting(e, e.row, 1)
		case .Green:
			run_action_row(e)
		case .Blue:
			e.mode = .File
		case .Red:
			close_side_mode(e)
		}
	case .File:
		#partial switch a {
		case .Green:
			e.requests += {.Save}
			close_side_mode(e)
		case .Yellow:
			e.requests += {.Load}
			close_side_mode(e)
		case .Red, .Blue:
			close_side_mode(e)
		}
	}
}

// Leaving with unsaved changes needs a second request.
@(private = "file")
request_exit :: proc(e: ^Editor) {
	if e.dirty && !e.confirm_exit {
		e.confirm_exit = true
		return
	}
	e.confirm_exit = false
	e.exit_requested = true
}

// The window is closing. Clean: fine. Dirty: the first ask shows the "unsaved" prompt and says no;
// asking again while the prompt is still up says yes.
editor_allow_close :: proc(e: ^Editor) -> bool {
	if !e.dirty || e.confirm_exit {
		return true
	}
	e.confirm_exit = true
	return false
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(MENU_BUTTON, x, y) {
		e.confirm_exit = false
	}
	if !rect_contains(DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	// The same ± buttons work from any mode; they open Setup on the row they change.
	setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
		open_side_mode(e, .Setup)
		e.row = row
		change_setting(e, row, delta)
	}
	if showing_canvas(e) {
		g := glyph(e)
		if cx, cy, ok := cell_at(g.width, g.height, x, y); ok {
			e.mode = .Edit // painting from Setup or File resumes editing
			e.cx, e.cy = cx, cy
			on := cm.bitmap_toggle(g, cx, cy)
			e.dirty = true
			e.paint = on // dragging paints the value just set
			return
		}
	} else if code, ok := grid_cell_at(x, y); ok {
		if code == e.code && e.mode == .Pick {
			begin_edit(e) // clicking the selected character again edits it
		} else {
			set_code(e, code)
			e.mode = .Pick
		}
		return
	}
	switch {
	case rect_contains(WIDTH_MINUS, x, y):
		setting(e, .Width, -1)
	case rect_contains(WIDTH_PLUS, x, y):
		setting(e, .Width, 1)
	case rect_contains(HEIGHT_MINUS, x, y):
		setting(e, .Height, -1)
	case rect_contains(HEIGHT_PLUS, x, y):
		setting(e, .Height, 1)
	case rect_contains(PRESENT_BUTTON, x, y):
		setting(e, .Present, present(e) ? -1 : 1) // toggles
	case rect_contains(FLIP_H_BUTTON, x, y):
		open_side_mode(e, .Setup)
		e.row = .Flip_Horizontal
		flip(e, true)
	case rect_contains(FLIP_V_BUTTON, x, y):
		open_side_mode(e, .Setup)
		e.row = .Flip_Vertical
		flip(e, false)
	case rect_contains(COPY_BUTTON, x, y):
		open_side_mode(e, .Setup)
		e.row = .Copy
		copy_selected(e)
	case rect_contains(PASTE_BUTTON, x, y):
		open_side_mode(e, .Setup)
		e.row = .Paste
		paste(e)
	case rect_contains(DELETE_BUTTON, x, y):
		open_side_mode(e, .Setup)
		e.row = .Delete
		delete_selected(e) // a second click confirms
	case rect_contains(EDIT_BUTTON, x, y):
		if e.mode == .Edit {
			e.mode = .Pick
		} else if e.mode == .Pick {
			begin_edit(e)
		} else {
			// From Setup or File: go where it was opened from, or edit.
			if e.back == .Edit && present(e) {
				e.mode = .Edit
			} else {
				begin_edit(e)
			}
		}
	case rect_contains(SAVE_BUTTON, x, y):
		e.requests += {.Save}
	case rect_contains(LOAD_BUTTON, x, y):
		e.requests += {.Load}
	case rect_contains(MENU_BUTTON, x, y):
		request_exit(e)
	}
}
