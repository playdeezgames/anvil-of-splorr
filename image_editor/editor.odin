package image_editor

import cm "../common"

Request :: enum {
	Save,
	Load,
}

Aux_Request :: enum {
	Palette,
}

// Red always means "back". Three modes:
//   Draw:  d-pad moves the cursor; green paints the pixel under it with the drawing colour; yellow
//          opens Setup; blue opens File; red leaves for the main menu (twice if there are unsaved
//          changes).
//   Setup: up/down choose a setting (drawing colour, width, height), left/right change it; blue
//          opens File; red returns to Draw. The colour is a palette index 0..15 and wraps around.
//   File:  green saves, yellow loads, red or blue cancel; every choice returns to Draw.
// The mouse works in all modes (click/drag on the canvas paints, right click picks up the colour
// under the pointer, click a palette swatch to choose it, - and + buttons resize, SAVE, LOAD and
// MENU buttons) and switches mode itself.
Mode :: enum {
	Draw,
	Setup,
	File,
}

Setup_Row :: enum {
	Color,
	Width,
	Height,
}

// Pure tool state, driven by events, drawn with editor_draw; file IO is the frontend's job.
Editor :: struct {
	image:          cm.Image4,
	cx, cy:         int, // cursor, always inside the visible image
	mode:           Mode,
	row:            Setup_Row, // selected setting in Setup mode
	color:          int, // drawing colour: a palette index 0..15 (not part of the saved image)
	palette:        cm.Palette, // the palette editor's saved palette, or the default
	dirty:          bool, // the image changed since the last save/load (the colour choice does not count)
	requests:       bit_set[Request],
	aux_requests:   bit_set[Aux_Request],
	exit_requested: bool,
	confirm_exit:   bool, // unsaved changes: the next exit request is the confirmation
	paint:          Maybe(int), // mouse drag in progress: the colour being painted
	labels:         ^cm.Input_Map,
}

DEFAULT_SIZE :: 8
DEFAULT_COLOR :: 15 // white in the default palette

fresh :: proc() -> Editor {
	return Editor{image = cm.image4_make(DEFAULT_SIZE, DEFAULT_SIZE), palette = cm.default_palette(), color = DEFAULT_COLOR}
}

editor_init :: proc() -> Editor {
	return fresh()
}

// Called each time the tool becomes the active one: start blank (so unsaved edits do not survive
// leaving), then ask the frontend for the saved image and the palette.
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

editor_set_image :: proc(e: ^Editor, img: cm.Image4) {
	e.image = img
	e.dirty = false
	clamp_cursor(e)
}

editor_set_palette :: proc(e: ^Editor, p: cm.Palette) {
	e.palette = p
}

@(private = "file")
clamp_cursor :: proc(e: ^Editor) {
	e.cx = clamp(e.cx, 0, e.image.width - 1)
	e.cy = clamp(e.cy, 0, e.image.height - 1)
}

@(private = "file")
set_size :: proc(e: ^Editor, w, h: int) {
	if cm.image4_resize(&e.image, w, h) {
		e.dirty = true
		clamp_cursor(e)
	}
}

@(private = "file")
paint_pixel :: proc(e: ^Editor, x, y, color: int) {
	if cm.image4_set(&e.image, x, y, color) {
		e.dirty = true
	}
}

// Palette indices wrap around.
@(private = "file")
step_color :: proc(index, delta: int) -> int {
	return (index + delta + cm.IMAGE_COLORS) % cm.IMAGE_COLORS
}

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch v in ev {
	case cm.Command:
		editor_apply_action(e, v.action)
	case cm.Mouse_Move:
		if color, painting := e.paint.?; painting {
			if x, y, ok := cell_at(e.image.width, e.image.height, v.x, v.y); ok {
				e.cx, e.cy = x, y
				paint_pixel(e, x, y, color)
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
				pick(e, v.x, v.y)
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
			e.cy = min(e.cy + 1, e.image.height - 1)
		case .Left:
			e.cx = max(e.cx - 1, 0)
		case .Right:
			e.cx = min(e.cx + 1, e.image.width - 1)
		case .Green:
			paint_pixel(e, e.cx, e.cy, e.color)
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
	case .Color:
		e.color = step_color(e.color, delta)
	case .Width:
		set_size(e, e.image.width + delta, e.image.height)
	case .Height:
		set_size(e, e.image.width, e.image.height + delta)
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

// Right click: take the colour under the pointer (a canvas pixel or a palette swatch) as the
// drawing colour.
@(private = "file")
pick :: proc(e: ^Editor, x, y: int) {
	e.confirm_exit = false
	if cx, cy, ok := cell_at(e.image.width, e.image.height, x, y); ok {
		e.cx, e.cy = cx, cy
		e.color = int(cm.image4_get(&e.image, cx, cy))
		e.mode, e.row = .Setup, .Color
	} else if i, ok := swatch_at(x, y); ok {
		e.color = i
		e.mode, e.row = .Setup, .Color
	}
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(MENU_BUTTON, x, y) {
		e.confirm_exit = false
	}
	img := &e.image
	resize :: proc(e: ^Editor, row: Setup_Row, w, h: int) {
		e.mode, e.row = .Setup, row
		set_size(e, w, h)
	}
	if cx, cy, ok := cell_at(img.width, img.height, x, y); ok {
		e.mode = .Draw
		e.cx, e.cy = cx, cy
		paint_pixel(e, cx, cy, e.color)
		e.paint = e.color // dragging paints the same colour
	} else if rect_contains(WIDTH_MINUS, x, y) {
		resize(e, .Width, img.width - 1, img.height)
	} else if rect_contains(WIDTH_PLUS, x, y) {
		resize(e, .Width, img.width + 1, img.height)
	} else if rect_contains(HEIGHT_MINUS, x, y) {
		resize(e, .Height, img.width, img.height - 1)
	} else if rect_contains(HEIGHT_PLUS, x, y) {
		resize(e, .Height, img.width, img.height + 1)
	} else if i, ok := swatch_at(x, y); ok {
		e.mode, e.row = .Setup, .Color
		e.color = i
	} else if rect_contains(SAVE_BUTTON, x, y) {
		e.requests += {.Save}
	} else if rect_contains(LOAD_BUTTON, x, y) {
		e.requests += {.Load}
	} else if rect_contains(MENU_BUTTON, x, y) {
		request_exit(e)
	}
}
