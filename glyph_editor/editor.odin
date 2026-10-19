package glyph_editor

import cm "../common"

Request :: enum {
	Save,
	Load,
}

// Red always means "back". Three modes:
//   Draw: d-pad moves the cursor; green toggles the pixel under it; yellow opens Size; blue opens
//         File; red leaves for the main menu (twice if there are unsaved changes).
//   Size: left/right change the width by 1, up/down the height by 1; blue opens File; red returns to Draw.
//   File: green saves, yellow loads, red or blue cancel; every choice returns to Draw.
// The mouse works in all modes (click/drag on the canvas paints, + and - buttons resize, SAVE, LOAD
// and MENU buttons) and switches mode itself.
Mode :: enum {
	Draw,
	Size,
	File,
}

// Pure tool state, driven by events, drawn with editor_draw; file IO is the frontend's job.
Editor :: struct {
	bitmap:         cm.Bitmap,
	cx, cy:         int, // cursor, always inside the visible bitmap
	mode:           Mode,
	dirty:          bool, // changed since the last save/load
	requests:       bit_set[Request],
	exit_requested: bool,
	confirm_exit:   bool, // unsaved changes: the next exit request is the confirmation
	paint:          Maybe(bool), // mouse drag in progress: the value being painted
	labels:         ^cm.Input_Map,
}

DEFAULT_SIZE :: 8

editor_init :: proc() -> Editor {
	return Editor{bitmap = cm.bitmap_make(DEFAULT_SIZE, DEFAULT_SIZE)}
}

// Called each time the tool becomes the active one: start from a blank bitmap (so unsaved edits do
// not survive leaving) and ask the frontend to load the saved file over it.
editor_enter :: proc(e: ^Editor) {
	e^ = Editor {
		bitmap   = cm.bitmap_make(DEFAULT_SIZE, DEFAULT_SIZE),
		labels   = e.labels,
		requests = {.Load},
	}
}

editor_mark_saved :: proc(e: ^Editor) {
	e.dirty = false
}

editor_set_bitmap :: proc(e: ^Editor, b: cm.Bitmap) {
	e.bitmap = b
	e.dirty = false
	clamp_cursor(e)
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
			e.mode = .Size
		case .Blue:
			e.mode = .File
		case .Red:
			request_exit(e)
		}
	case .Size:
		#partial switch a {
		case .Left:
			set_size(e, e.bitmap.width - 1, e.bitmap.height)
		case .Right:
			set_size(e, e.bitmap.width + 1, e.bitmap.height)
		case .Up:
			set_size(e, e.bitmap.width, e.bitmap.height + 1)
		case .Down:
			set_size(e, e.bitmap.width, e.bitmap.height - 1)
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

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(MENU_BUTTON, x, y) {
		e.confirm_exit = false
	}
	b := &e.bitmap
	if cx, cy, ok := cell_at(b.width, b.height, x, y); ok {
		e.mode = .Draw
		e.cx, e.cy = cx, cy
		on := cm.bitmap_toggle(b, cx, cy)
		e.dirty = true
		e.paint = on // dragging paints the value just set
	} else if rect_contains(WIDTH_MINUS, x, y) {
		e.mode = .Size
		set_size(e, b.width - 1, b.height)
	} else if rect_contains(WIDTH_PLUS, x, y) {
		e.mode = .Size
		set_size(e, b.width + 1, b.height)
	} else if rect_contains(HEIGHT_MINUS, x, y) {
		e.mode = .Size
		set_size(e, b.width, b.height - 1)
	} else if rect_contains(HEIGHT_PLUS, x, y) {
		e.mode = .Size
		set_size(e, b.width, b.height + 1)
	} else if rect_contains(SAVE_BUTTON, x, y) {
		e.requests += {.Save}
	} else if rect_contains(LOAD_BUTTON, x, y) {
		e.requests += {.Load}
	} else if rect_contains(MENU_BUTTON, x, y) {
		request_exit(e)
	}
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
