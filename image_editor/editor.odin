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
//   Setup: up/down choose a row, left/right change it (drawing colour, width, height); green runs
//          the action rows: Flip horizontal / vertical, Rotate left / right / 180 (whole image;
//          the opposite action undoes them; a quarter turn swaps width and height), Frame / Fill
//          (draw a rectangle), Flood fill (the connected region under the cursor becomes the
//          drawing colour), Replace colour (every pixel of the colour under the cursor becomes the
//          drawing colour) and Clear (the whole image becomes the drawing colour); blue opens File;
//          red returns to Draw. The colour is a palette index 0..15 and wraps around.
//   Rect:  placing a rectangle: the cursor is its second corner (the first is where it started).
//          D-pad moves the cursor, green draws it in the drawing colour, red cancels.
//   File:  green saves, yellow loads, red or blue cancel; every choice returns to Draw.
// The mouse works in all modes (click/drag on the canvas paints, right click picks up the colour
// under the pointer, click a palette swatch to choose it, - and + buttons resize, FLIP, ROT, FRAME
// FILL, FLOOD, REPLACE and CLEAR buttons, SAVE, LOAD and MENU buttons) and switches mode itself.
// FRAME and FILL arm a tool: the next drag on the canvas, corner to corner, draws the rectangle.
// FLOOD and REPLACE arm a tool too: the next click on a pixel runs it from there. (Red or the
// button again disarms; CLEAR needs no pixel and acts at once.)
Mode :: enum {
	Draw,
	Setup,
	File,
	Rect,
}

Setup_Row :: enum {
	Color,
	Width,
	Height,
	Flip_Horizontal,
	Flip_Vertical,
	Rotate_Left,
	Rotate_Right,
	Rotate_180,
	Frame,
	Fill,
	Flood_Fill,
	Replace_Color,
	Clear,
}

// A tool armed with a mouse button that acts on the next click on a pixel.
Point_Tool :: enum {
	None,
	Flood_Fill,
	Replace_Color,
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
	shape:          cm.Shape, // the rectangle being placed (Rect mode) or armed with the mouse; None otherwise
	ax, ay:         int, // the rectangle's first corner
	rect_drag:      bool, // a mouse drag is placing the rectangle
	point_tool:     Point_Tool, // flood fill / replace colour armed with the mouse
	note:           string, // a one-line message about the last action ("" for none); cleared by the next input
	embedded:       bool, // hosted by the tileset editor: no files, red leaves without a prompt (see editor_begin_embedded)
	lock_size:      bool, // embedded in a tileset: width and height are the tileset's, and only a square tile can be turned a quarter
	labels:         ^cm.Input_Map,
}

// Shown (instead of the cursor readout) when flood fill, replace colour or clear changes nothing,
// which happens when the target is already the drawing colour.
NOTE_SAME_FILL :: "SAME COLOR: NOTHING TO FILL"
NOTE_SAME_REPLACE :: "SAME COLOR: NOTHING TO REPLACE"
NOTE_SAME_CLEAR :: "ALREADY ALL THAT COLOR"
NOTE_SIZE_LOCKED :: "THE TILESET SETS THE SIZE"
NOTE_NO_TURN :: "CANNOT TURN A NON-SQUARE TILE"

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

// Sets the editor up to edit a tile for the tileset editor, which owns the file, the palette and
// the list of images: copies the image and palette in, starts in Draw mode, and turns off File mode
// and the main-menu exit. Red (or the BACK button) sets exit_requested with no prompt. With
// `lock_size` the size cannot be changed and a non-square image cannot be turned a quarter.
// The host copies `image` back out when `dirty` and when the editor exits.
editor_begin_embedded :: proc(e: ^Editor, image: ^cm.Image4, palette: ^cm.Palette, lock_size := true) {
	labels := e.labels
	e^ = fresh()
	e.labels = labels
	e.image = image^
	e.palette = palette^
	e.embedded = true
	e.lock_size = lock_size
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
	if e.lock_size {
		if w != e.image.width || h != e.image.height {
			e.note = NOTE_SIZE_LOCKED
		}
		return
	}
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

// Whole-image transforms. The image only counts as changed if the transform moved something (a
// quarter turn of a non-square image always does: its size changes). The cursor is kept inside.
@(private = "file")
transform :: proc(e: ^Editor, row: Setup_Row) {
	changed := false
	if (row == .Rotate_Left || row == .Rotate_Right) && e.lock_size && e.image.width != e.image.height {
		e.note = NOTE_NO_TURN // a quarter turn would change the size
		return
	}
	#partial switch row {
	case .Flip_Horizontal:
		changed = cm.image4_flip_horizontal(&e.image)
	case .Flip_Vertical:
		changed = cm.image4_flip_vertical(&e.image)
	case .Rotate_Left:
		changed = cm.image4_rotate_left(&e.image)
	case .Rotate_Right:
		changed = cm.image4_rotate_right(&e.image)
	case .Rotate_180:
		changed = cm.image4_rotate_180(&e.image)
	case .Flood_Fill:
		changed = cm.image4_flood_fill(&e.image, e.cx, e.cy, e.color)
		if !changed {
			e.note = NOTE_SAME_FILL
		}
	case .Replace_Color:
		changed = cm.image4_replace_color(&e.image, int(cm.image4_get(&e.image, e.cx, e.cy)), e.color)
		if !changed {
			e.note = NOTE_SAME_REPLACE
		}
	case .Clear:
		changed = cm.image4_clear(&e.image, e.color)
		if !changed {
			e.note = NOTE_SAME_CLEAR
		}
	}
	if changed {
		e.dirty = true
		clamp_cursor(e)
	}
}

// Starts placing a rectangle whose first corner is the cursor.
@(private = "file")
begin_shape :: proc(e: ^Editor, shape: cm.Shape) {
	e.shape = shape
	e.ax, e.ay = e.cx, e.cy
	e.mode = .Rect
}

// Draws the rectangle from its first corner to the cursor in the drawing colour and finishes.
@(private = "file")
commit_shape :: proc(e: ^Editor) {
	if cm.image4_draw_shape(&e.image, e.shape, e.ax, e.ay, e.cx, e.cy, e.color) {
		e.dirty = true
	}
	cancel_shape(e)
}

// Abandons (or, after a commit, ends) rectangle placement and disarms the mouse tool.
@(private = "file")
cancel_shape :: proc(e: ^Editor) {
	e.shape = .None
	e.point_tool = .None
	e.rect_drag = false
	if e.mode == .Rect {
		e.mode = .Draw
	}
}

// Palette indices wrap around.
@(private = "file")
step_color :: proc(index, delta: int) -> int {
	return (index + delta + cm.IMAGE_COLORS) % cm.IMAGE_COLORS
}

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	// Any command or button press clears the message; moving the mouse or letting go does not (the
	// release of the click that produced it must not wipe it at once).
	#partial switch v in ev {
	case cm.Command:
		e.note = ""
	case cm.Mouse_Button_Event:
		if v.down {
			e.note = ""
		}
	}
	switch v in ev {
	case cm.Command:
		editor_apply_action(e, v.action)
	case cm.Mouse_Move:
		if e.rect_drag {
			if x, y, ok := cell_at(e.image.width, e.image.height, v.x, v.y); ok {
				e.cx, e.cy = x, y
			}
		} else if color, painting := e.paint.?; painting {
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
				if e.rect_drag { 	// letting go places the second corner
					commit_shape(e)
				}
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
			if !e.embedded {
				e.mode = .File
			}
		case .Red:
			if e.shape != .None || e.point_tool != .None {
				cancel_shape(e) // red first disarms a mouse-armed tool
			} else {
				request_exit(e)
			}
		}
	case .Rect:
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
			case .Flip_Horizontal, .Flip_Vertical, .Rotate_Left, .Rotate_Right, .Rotate_180:
				transform(e, e.row)
			case .Flood_Fill:
				before := e.dirty
				e.dirty = false
				transform(e, e.row)
				if e.dirty { 	// one fill, then back to drawing (when nothing changed the note says why)
					e.mode = .Draw
				}
				e.dirty ||= before
			case .Replace_Color, .Clear:
				transform(e, e.row) // acts at the cursor at once
			case .Frame:
				begin_shape(e, .Frame)
			case .Fill:
				begin_shape(e, .Fill)
			}
		case .Blue:
			if !e.embedded {
				e.mode = .File
			}
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
	case .Flip_Horizontal, .Flip_Vertical, .Rotate_Left, .Rotate_Right, .Rotate_180, .Frame, .Fill, .Flood_Fill, .Replace_Color, .Clear:
		// Actions, not values: green runs them.
	}
}

// Leaving with unsaved changes needs a second request.
@(private = "file")
request_exit :: proc(e: ^Editor) {
	if e.embedded {
		e.exit_requested = true // the tileset editor keeps the changes: nothing to confirm
		return
	}
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
// drawing colour. While a rectangle is being placed the mode is left alone, so picking a colour
// does not abandon it.
@(private = "file")
pick :: proc(e: ^Editor, x, y: int) {
	e.confirm_exit = false
	if cx, cy, ok := cell_at(e.image.width, e.image.height, x, y); ok {
		if e.shape == .None {
			e.cx, e.cy = cx, cy
		}
		e.color = int(cm.image4_get(&e.image, cx, cy))
	} else if i, ok := swatch_at(x, y); ok {
		e.color = i
	} else {
		return
	}
	if e.shape == .None {
		e.mode, e.row = .Setup, .Color
	}
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

// The FLOOD and REPLACE buttons: arm that click tool (or disarm it if it is already armed).
@(private = "file")
toggle_point_tool :: proc(e: ^Editor, tool: Point_Tool) {
	armed := e.point_tool == tool
	cancel_shape(e)
	if !armed {
		e.point_tool = tool
		e.mode = .Draw
	}
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(MENU_BUTTON, x, y) {
		e.confirm_exit = false
	}
	img := &e.image
	if cx, cy, ok := cell_at(img.width, img.height, x, y); ok {
		e.cx, e.cy = cx, cy
		switch {
		case e.point_tool != .None: // a click tool armed with a button: run it from this pixel
			row: Setup_Row = e.point_tool == .Flood_Fill ? .Flood_Fill : .Replace_Color
			e.point_tool = .None
			e.mode = .Draw
			transform(e, row)
		case e.mode == .Rect: // a rectangle started from the keyboard: this click is its second corner
			commit_shape(e)
		case e.shape != .None: // a tool armed with a button: start dragging out a rectangle
			e.ax, e.ay = cx, cy
			e.rect_drag = true
			e.mode = .Rect
		case:
			e.mode = .Draw
			paint_pixel(e, cx, cy, e.color)
			e.paint = e.color // dragging paints the same colour
		}
		return
	}
	// Choosing a colour or a tool keeps a rectangle in progress; every other button abandons it.
	_, on_swatch := swatch_at(x, y)
	is_tool_button := rect_contains(FRAME_BUTTON, x, y) || rect_contains(FILL_BUTTON, x, y) || rect_contains(FLOOD_BUTTON, x, y) || rect_contains(REPLACE_BUTTON, x, y)
	if !on_swatch && !is_tool_button {
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
		setting(e, .Width, img.width - 1, img.height)
	case rect_contains(WIDTH_PLUS, x, y):
		setting(e, .Width, img.width + 1, img.height)
	case rect_contains(HEIGHT_MINUS, x, y):
		setting(e, .Height, img.width, img.height - 1)
	case rect_contains(HEIGHT_PLUS, x, y):
		setting(e, .Height, img.width, img.height + 1)
	case on_swatch:
		i, _ := swatch_at(x, y)
		e.color = i
		if e.shape == .None {
			e.mode, e.row = .Setup, .Color
		}
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
	case rect_contains(FLOOD_BUTTON, x, y):
		toggle_point_tool(e, .Flood_Fill)
	case rect_contains(REPLACE_BUTTON, x, y):
		toggle_point_tool(e, .Replace_Color)
	case rect_contains(CLEAR_BUTTON, x, y):
		action(e, .Clear)
	case rect_contains(SAVE_BUTTON, x, y):
		if !e.embedded {
			e.requests += {.Save}
		}
	case rect_contains(LOAD_BUTTON, x, y):
		if !e.embedded {
			e.requests += {.Load}
		}
	case rect_contains(MENU_BUTTON, x, y):
		request_exit(e)
	}
}
