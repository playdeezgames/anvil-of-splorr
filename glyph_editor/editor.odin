package glyph_editor

import cm "../common"

Request :: enum {
	Save,
	Load,
}

// Red always means "back". Three modes:
//   Draw:  d-pad moves the cursor; green toggles the pixel under it; yellow opens Setup; blue opens
//          File; red leaves for the main menu (twice if there are unsaved changes).
//   Setup: up/down choose a setting (width, height, foreground, background), left/right change it;
//          blue opens File; red returns to Draw. Foreground and background are palette colours used
//          by the tiled preview only; they are not part of the saved image.
//   File:  green saves, yellow loads, red or blue cancel; every choice returns to Draw.
// The mouse works in all modes (click/drag on the canvas paints, - and + buttons resize, left/right
// click on a palette swatch sets foreground/background, SAVE, LOAD and MENU buttons) and switches
// mode itself.
Mode :: enum {
	Draw,
	Setup,
	File,
}

Setup_Row :: enum {
	Width,
	Height,
	Foreground,
	Background,
}

Aux_Request :: enum {
	Palette,
}

// Pure tool state, driven by events, drawn with editor_draw; file IO is the frontend's job.
Editor :: struct {
	bitmap:         cm.Bitmap,
	cx, cy:         int, // cursor, always inside the visible bitmap
	mode:           Mode,
	row:            Setup_Row, // selected setting in Setup mode
	fg, bg:         int, // palette indices used by the tiled preview
	palette:        cm.Palette, // the palette editor's saved palette, or the default
	dirty:          bool, // the bitmap changed since the last save/load (colours do not count)
	requests:       bit_set[Request],
	aux_requests:   bit_set[Aux_Request],
	exit_requested: bool,
	confirm_exit:   bool, // unsaved changes: the next exit request is the confirmation
	paint:          Maybe(bool), // mouse drag in progress: the value being painted
	labels:         ^cm.Input_Map,
}

DEFAULT_SIZE :: 8
DEFAULT_FG :: 15 // white in the default palette
DEFAULT_BG :: 0 // black in the default palette

fresh :: proc() -> Editor {
	return Editor {
		bitmap  = cm.bitmap_make(DEFAULT_SIZE, DEFAULT_SIZE),
		palette = cm.default_palette(),
		fg      = DEFAULT_FG,
		bg      = DEFAULT_BG,
	}
}

editor_init :: proc() -> Editor {
	return fresh()
}

// Called each time the tool becomes the active one: start blank (so unsaved edits do not survive
// leaving), then ask the frontend for the saved bitmap and the palette.
editor_enter :: proc(e: ^Editor) {
	labels := e.labels
	e^ = fresh()
	e.labels = labels
	e.requests = {.Load}
	e.aux_requests = {.Palette}
}

editor_mark_saved :: proc(e: ^Editor) {
	e.dirty = false
}

editor_set_bitmap :: proc(e: ^Editor, b: cm.Bitmap) {
	e.bitmap = b
	e.dirty = false
	clamp_cursor(e)
}

editor_set_palette :: proc(e: ^Editor, p: cm.Palette) {
	e.palette = p
}

@(private = "file")
clamp_cursor :: proc(e: ^Editor) {
	e.cx = clamp(e.cx, 0, e.bitmap.width - 1)
	e.cy = clamp(e.cy, 0, e.bitmap.height - 1)
}

@(private = "file")
set_size :: proc(e: ^Editor, w, h: int) {
	if cm.bitmap_resize(&e.bitmap, w, h) {
		e.dirty = true
		clamp_cursor(e)
	}
}

@(private = "file")
set_pixel :: proc(e: ^Editor, x, y: int, on: bool) {
	if cm.bitmap_set(&e.bitmap, x, y, on) {
		e.dirty = true
	}
}

// Palette indices wrap around.
@(private = "file")
step_color :: proc(index, delta: int) -> int {
	return (index + delta + cm.PALETTE_SIZE) % cm.PALETTE_SIZE
}

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch v in ev {
	case cm.Command:
		editor_apply_action(e, v.action)
	case cm.Mouse_Move:
		if on, painting := e.paint.?; painting {
			if x, y, ok := cell_at(e.bitmap.width, e.bitmap.height, v.x, v.y); ok {
				e.cx, e.cy = x, y
				set_pixel(e, x, y, on)
			}
		}
	case cm.Mouse_Button_Event:
		switch v.button {
		case .Left:
			if v.down {
				click(e, v.x, v.y)
			} else {
				e.paint = nil
			}
		case .Right:
			if v.down {
				if i, ok := swatch_at(v.x, v.y); ok {
					e.confirm_exit = false
					e.mode, e.row = .Setup, .Background
					e.bg = i
				}
			}
		case .Middle:
		}
	case cm.Mouse_Wheel:
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	if a != .Red {
		e.confirm_exit = false // any other command cancels the "leave anyway?" prompt
	}
	switch e.mode {
	case .Draw:
		#partial switch a {
		case .Up:
			e.cy = max(e.cy - 1, 0)
		case .Down:
			e.cy = min(e.cy + 1, e.bitmap.height - 1)
		case .Left:
			e.cx = max(e.cx - 1, 0)
		case .Right:
			e.cx = min(e.cx + 1, e.bitmap.width - 1)
		case .Green:
			cm.bitmap_toggle(&e.bitmap, e.cx, e.cy)
			e.dirty = true
		case .Yellow:
			e.mode = .Setup
		case .Blue:
			e.mode = .File
		case .Red:
			request_exit(e)
		}
	case .Setup:
		#partial switch a {
		case .Up:
			e.row = Setup_Row((int(e.row) + len(Setup_Row) - 1) % len(Setup_Row))
		case .Down:
			e.row = Setup_Row((int(e.row) + 1) % len(Setup_Row))
		case .Left:
			change_setting(e, -1)
		case .Right:
			change_setting(e, 1)
		case .Blue:
			e.mode = .File
		case .Red:
			e.mode = .Draw
		}
	case .File:
		#partial switch a {
		case .Green:
			e.requests += {.Save}
			e.mode = .Draw
		case .Yellow:
			e.requests += {.Load}
			e.mode = .Draw
		case .Red, .Blue:
			e.mode = .Draw
		}
	}
}

@(private = "file")
change_setting :: proc(e: ^Editor, delta: int) {
	switch e.row {
	case .Width:
		set_size(e, e.bitmap.width + delta, e.bitmap.height)
	case .Height:
		set_size(e, e.bitmap.width, e.bitmap.height + delta)
	case .Foreground:
		e.fg = step_color(e.fg, delta)
	case .Background:
		e.bg = step_color(e.bg, delta)
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
// asking again while the prompt is still up says yes. (Any other command cancels the prompt, so
// the user is warned again.)
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
	b := &e.bitmap
	resize :: proc(e: ^Editor, row: Setup_Row, w, h: int) {
		e.mode, e.row = .Setup, row
		set_size(e, w, h)
	}
	if cx, cy, ok := cell_at(b.width, b.height, x, y); ok {
		e.mode = .Draw
		e.cx, e.cy = cx, cy
		on := cm.bitmap_toggle(b, cx, cy)
		e.dirty = true
		e.paint = on // dragging paints the value just set
	} else if rect_contains(WIDTH_MINUS, x, y) {
		resize(e, .Width, b.width - 1, b.height)
	} else if rect_contains(WIDTH_PLUS, x, y) {
		resize(e, .Width, b.width + 1, b.height)
	} else if rect_contains(HEIGHT_MINUS, x, y) {
		resize(e, .Height, b.width, b.height - 1)
	} else if rect_contains(HEIGHT_PLUS, x, y) {
		resize(e, .Height, b.width, b.height + 1)
	} else if i, ok := swatch_at(x, y); ok {
		e.mode, e.row = .Setup, .Foreground
		e.fg = i
	} else if rect_contains(SAVE_BUTTON, x, y) {
		e.requests += {.Save}
	} else if rect_contains(LOAD_BUTTON, x, y) {
		e.requests += {.Load}
	} else if rect_contains(MENU_BUTTON, x, y) {
		request_exit(e)
	}
}
