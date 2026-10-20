package glyph_editor

import cm "../common"

Request :: enum {
	Save,
	Load,
}

// Red always means "back". Three modes:
//   Draw:  d-pad moves the cursor; green toggles the pixel under it; yellow opens Setup; blue opens
//          File; red leaves for the main menu (twice if there are unsaved changes).
//   Setup: up/down choose a row, left/right change it (width, height, foreground, background);
//          green runs the action rows: Invert (swap every set and clear pixel), Flip horizontal /
//          vertical, Rotate left / right / 180 (whole bitmap; the opposite action undoes them; a
//          quarter turn swaps width and height) and Frame / Fill (draw a rectangle); blue opens
//          File; red returns to Draw.
//   Rect:  placing a rectangle: the cursor is its second corner (the first is where it started).
//          D-pad moves the cursor, green draws it, red cancels. The rectangle sets its pixels to the
//          opposite of the pixel it started on: start on a clear pixel to draw, on a lit one to erase
//          (the preview squares are yellow for drawing, red for erasing). Foreground and background are palette colours used
//          by the tiled preview only; they are not part of the saved image.
//   File:  green saves, yellow loads, red or blue cancel; every choice returns to Draw.
// The mouse works in all modes (click/drag on the canvas paints, - and + buttons resize, left/right
// click on a palette swatch sets foreground/background, FLIP, ROT, FRAME, FILL and INVERT buttons,
// SAVE, LOAD and MENU buttons) and switches mode itself. FRAME and FILL arm a tool: the next drag on
// the canvas, corner to corner, draws the rectangle (red or the button again disarms).
Mode :: enum {
	Draw,
	Setup,
	File,
	Rect,
}

Setup_Row :: enum {
	Width,
	Height,
	Foreground,
	Background,
	Invert,
	Flip_Horizontal,
	Flip_Vertical,
	Rotate_Left,
	Rotate_Right,
	Rotate_180,
	Frame,
	Fill,
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
	shape:          cm.Shape, // the rectangle being placed (Rect mode) or armed with the mouse; None otherwise
	ax, ay:         int, // the rectangle's first corner
	shape_on:       bool, // what the rectangle sets its pixels to: the opposite of the first corner's pixel
	rect_drag:      bool, // a mouse drag is placing the rectangle
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

// Whole-bitmap transforms. The bitmap only counts as changed if the transform moved something (a
// quarter turn of a non-square bitmap always does: its size changes). The cursor is kept inside.
@(private = "file")
transform :: proc(e: ^Editor, row: Setup_Row) {
	changed := false
	#partial switch row {
	case .Invert:
		cm.bitmap_invert(&e.bitmap)
		changed = true
	case .Flip_Horizontal:
		changed = cm.bitmap_flip_horizontal(&e.bitmap)
	case .Flip_Vertical:
		changed = cm.bitmap_flip_vertical(&e.bitmap)
	case .Rotate_Left:
		changed = cm.bitmap_rotate_left(&e.bitmap)
	case .Rotate_Right:
		changed = cm.bitmap_rotate_right(&e.bitmap)
	case .Rotate_180:
		changed = cm.bitmap_rotate_180(&e.bitmap)
	}
	if changed {
		e.dirty = true
		clamp_cursor(e)
	}
}

// Starts placing a rectangle whose first corner is at (x, y).
@(private = "file")
begin_shape :: proc(e: ^Editor, shape: cm.Shape, x, y: int) {
	e.shape = shape
	e.ax, e.ay = x, y
	e.shape_on = !cm.bitmap_get(&e.bitmap, x, y)
}

// Draws the rectangle from its first corner to the cursor and finishes.
@(private = "file")
commit_shape :: proc(e: ^Editor) {
	if cm.bitmap_draw_shape(&e.bitmap, e.shape, e.ax, e.ay, e.cx, e.cy, e.shape_on) {
		e.dirty = true
	}
	cancel_shape(e)
}

// Abandons (or, after a commit, ends) rectangle placement and disarms the mouse tool.
@(private = "file")
cancel_shape :: proc(e: ^Editor) {
	e.shape = .None
	e.rect_drag = false
	if e.mode == .Rect {
		e.mode = .Draw
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
		if e.rect_drag {
			if x, y, ok := cell_at(e.bitmap.width, e.bitmap.height, v.x, v.y); ok {
				e.cx, e.cy = x, y
			}
		} else if on, painting := e.paint.?; painting {
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
				if e.rect_drag { 	// letting go places the second corner
					commit_shape(e)
				}
			}
		case .Right:
			if v.down {
				if i, ok := swatch_at(v.x, v.y); ok {
					e.confirm_exit = false
					e.bg = i
					if e.shape == .None {
						e.mode, e.row = .Setup, .Background
					}
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
			if e.shape != .None {
				cancel_shape(e) // red first disarms a mouse-armed rectangle tool
			} else {
				request_exit(e)
			}
		}
	case .Rect:
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
			commit_shape(e)
		case .Red:
			cancel_shape(e)
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
		case .Green:
			#partial switch e.row {
			case .Invert, .Flip_Horizontal, .Flip_Vertical, .Rotate_Left, .Rotate_Right, .Rotate_180:
				transform(e, e.row)
			case .Frame:
				begin_shape(e, .Frame, e.cx, e.cy)
				e.mode = .Rect
			case .Fill:
				begin_shape(e, .Fill, e.cx, e.cy)
				e.mode = .Rect
			}
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
	case .Invert, .Flip_Horizontal, .Flip_Vertical, .Rotate_Left, .Rotate_Right, .Rotate_180, .Frame, .Fill:
		// Actions, not values: green runs them.
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

// The FRAME and FILL buttons: arm that tool (or disarm it if it is already armed).
@(private = "file")
toggle_tool :: proc(e: ^Editor, shape: cm.Shape) {
	armed := e.shape == shape && !e.rect_drag
	cancel_shape(e)
	if !armed {
		e.shape = shape
		e.mode = .Draw
	}
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(MENU_BUTTON, x, y) {
		e.confirm_exit = false
	}
	b := &e.bitmap
	if cx, cy, ok := cell_at(b.width, b.height, x, y); ok {
		e.cx, e.cy = cx, cy
		switch {
		case e.mode == .Rect: // a rectangle started from the keyboard: this click is its second corner
			commit_shape(e)
		case e.shape != .None: // a tool armed with a button: start dragging out a rectangle
			begin_shape(e, e.shape, cx, cy)
			e.rect_drag = true
			e.mode = .Rect
		case:
			e.mode = .Draw
			on := cm.bitmap_toggle(b, cx, cy)
			e.dirty = true
			e.paint = on // dragging paints the value just set
		}
		return
	}
	// Choosing a colour or a tool keeps a rectangle in progress; every other button abandons it.
	_, on_swatch := swatch_at(x, y)
	if !on_swatch && !rect_contains(FRAME_BUTTON, x, y) && !rect_contains(FILL_BUTTON, x, y) {
		cancel_shape(e)
	}
	setting :: proc(e: ^Editor, row: Setup_Row, w, h: int) {
		e.mode, e.row = .Setup, row
		set_size(e, w, h)
	}
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		transform(e, row)
	}
	switch {
	case rect_contains(WIDTH_MINUS, x, y):
		setting(e, .Width, b.width - 1, b.height)
	case rect_contains(WIDTH_PLUS, x, y):
		setting(e, .Width, b.width + 1, b.height)
	case rect_contains(HEIGHT_MINUS, x, y):
		setting(e, .Height, b.width, b.height - 1)
	case rect_contains(HEIGHT_PLUS, x, y):
		setting(e, .Height, b.width, b.height + 1)
	case on_swatch:
		i, _ := swatch_at(x, y)
		e.fg = i
		if e.shape == .None {
			e.mode, e.row = .Setup, .Foreground
		}
	case rect_contains(INVERT_BUTTON, x, y):
		action(e, .Invert)
	case rect_contains(FLIP_H_BUTTON, x, y):
		action(e, .Flip_Horizontal)
	case rect_contains(FLIP_V_BUTTON, x, y):
		action(e, .Flip_Vertical)
	case rect_contains(ROT_L_BUTTON, x, y):
		action(e, .Rotate_Left)
	case rect_contains(ROT_R_BUTTON, x, y):
		action(e, .Rotate_Right)
	case rect_contains(ROT_180_BUTTON, x, y):
		action(e, .Rotate_180)
	case rect_contains(FRAME_BUTTON, x, y):
		toggle_tool(e, .Frame)
	case rect_contains(FILL_BUTTON, x, y):
		toggle_tool(e, .Fill)
	case rect_contains(SAVE_BUTTON, x, y):
		e.requests += {.Save}
	case rect_contains(LOAD_BUTTON, x, y):
		e.requests += {.Load}
	case rect_contains(MENU_BUTTON, x, y):
		request_exit(e)
	}
}
