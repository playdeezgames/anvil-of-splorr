package palette_editor

import cm "../common"

GRID_COLS :: 4
GRID_ROWS :: 4
#assert(GRID_COLS * GRID_ROWS == cm.PALETTE_SIZE)

Request :: enum {
	Save,
	Load,
}

// Four modes give the eight commands enough meaning. Red always means "back":
//   Browse: d-pad moves between swatches; green edits the selected one; yellow copies it and
//           enters Paste; blue opens File; red leaves for the main menu (twice if there are
//           unsaved changes).
//   Edit:   left/right change the value by 1, up/down by 16; green cycles R/G/B; blue opens File;
//           red returns to Browse.
//   Paste:  d-pad moves; green pastes the copied colour into the selected swatch (repeat for
//           several); yellow copies the selected one instead; blue opens File; red returns to Browse.
//   File:   green saves, yellow loads, red or blue cancel; every choice returns to Browse.
// The mouse works in all of them (COPY, PASTE, SAVE, LOAD and MENU buttons) and switches mode itself.
Mode :: enum {
	Browse,
	Edit,
	Paste,
	File,
}

// Pure tool state. Frontends feed it events, call editor_draw, and service `requests` (file IO
// is platform specific).
Editor :: struct {
	palette:  cm.Palette,
	selected: int,
	channel:  cm.Channel,
	dirty:    bool, // palette changed since the last save/load
	requests: bit_set[Request],
	mode:     Mode,
	clipboard: Maybe(cm.Color), // last copied colour
	embedded: bool, // hosted by the world editor: no files, red leaves at once (see editor_begin_embedded)
	exit_requested: bool, // the tool wants to return to the main menu (see take_exit in tool.odin)
	confirm_exit:   bool, // unsaved changes: the next exit request is the confirmation
	labels:   ^cm.Input_Map, // source of on-screen command names; nil means the defaults
	mouse:    [2]int,
	drag:     Maybe(cm.Channel), // slider currently being dragged with the mouse
}

editor_init :: proc() -> Editor {
	return Editor{palette = cm.default_palette()}
}

// Frontend calls these after servicing a Request.
editor_mark_saved :: proc(e: ^Editor) {
	e.dirty = false
}

// Called each time the tool becomes the active one: start from the default palette (so unsaved
// edits do not survive leaving) and ask the frontend to load the saved file over it.
editor_enter :: proc(e: ^Editor) {
	e^ = Editor {
		palette  = cm.default_palette(),
		labels   = e.labels,
		requests = {.Load},
	}
}

// Sets the editor up to edit a palette for the world editor, which owns the file: copies the
// palette in, starts in Browse mode, turns off File mode, and makes red (or MENU, labelled BACK)
// set exit_requested with no prompt. The host copies `palette` back out when `dirty` and on exit.
editor_begin_embedded :: proc(e: ^Editor, palette: ^cm.Palette) {
	e^ = Editor {
		palette  = palette^,
		labels   = e.labels,
		embedded = true,
	}
}

editor_set_palette :: proc(e: ^Editor, p: cm.Palette) {
	e.palette = p
	e.dirty = false
}

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch v in ev {
	case cm.Command:
		editor_apply_action(e, v.action)
	case cm.Mouse_Move:
		e.mouse = {v.x, v.y}
		if ch, dragging := e.drag.?; dragging {
			set_from_slider_x(e, ch, v.x)
		}
	case cm.Mouse_Button_Event:
		e.mouse = {v.x, v.y}
		if v.button == .Left {
			if v.down {
				click(e, v.x, v.y)
			} else {
				e.drag = nil
			}
		}
	case cm.Mouse_Wheel:
		e.confirm_exit = false
		// Over a slider: that channel. Elsewhere: the current channel.
		ch := e.channel
		if hit, ok := slider_at(e.mouse.x, e.mouse.y); ok {
			ch = hit
			e.channel = hit
			e.mode = .Edit
		}
		adjust(e, ch, v.dy * cm.STEP_SMALL)
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	if a != .Red {
		e.confirm_exit = false // any other command cancels the "leave anyway?" prompt
	}
	switch e.mode {
	case .Browse:
		#partial switch a {
		case .Up, .Down, .Left, .Right:
			move_selection(e, a)
		case .Green:
			e.mode = .Edit
		case .Yellow:
			copy_selected(e)
		case .Blue:
			if !e.embedded {
				e.mode = .File
			}
		case .Red:
			request_exit(e)
		}
	case .Edit:
		#partial switch a {
		case .Left:
			adjust(e, e.channel, -cm.STEP_SMALL)
		case .Right:
			adjust(e, e.channel, cm.STEP_SMALL)
		case .Up:
			adjust(e, e.channel, cm.STEP_BIG)
		case .Down:
			adjust(e, e.channel, -cm.STEP_BIG)
		case .Green:
			e.channel = cm.Channel((int(e.channel) + 1) % len(cm.Channel))
		case .Blue:
			if !e.embedded {
				e.mode = .File
			}
		case .Red:
			e.mode = .Browse
		}
	case .Paste:
		#partial switch a {
		case .Up, .Down, .Left, .Right:
			move_selection(e, a)
		case .Green:
			paste(e)
		case .Yellow:
			copy_selected(e)
		case .Blue:
			if !e.embedded {
				e.mode = .File
			}
		case .Red:
			e.mode = .Browse
		}
	case .File:
		#partial switch a {
		case .Green:
			e.requests += {.Save}
			e.mode = .Browse
		case .Yellow:
			e.requests += {.Load}
			e.mode = .Browse
		case .Red, .Blue:
			e.mode = .Browse
		}
	}
}

// Leaving with unsaved changes needs a second request.
@(private = "file")
request_exit :: proc(e: ^Editor) {
	if e.embedded {
		e.exit_requested = true // the world editor keeps the changes: nothing to confirm
		return
	}
	if e.dirty && !e.confirm_exit {
		e.confirm_exit = true
		return
	}
	e.confirm_exit = false
	e.exit_requested = true
}

// Remembers the selected colour and enters Paste mode so it can be stamped onto other swatches.
@(private = "file")
copy_selected :: proc(e: ^Editor) {
	e.clipboard = e.palette[e.selected]
	e.mode = .Paste
}

@(private = "file")
paste :: proc(e: ^Editor) {
	c, has := e.clipboard.?
	if !has || e.palette[e.selected] == c {
		return
	}
	e.palette[e.selected] = c
	e.dirty = true
}

@(private = "file")
move_selection :: proc(e: ^Editor, a: cm.Action) {
	col, row := e.selected % GRID_COLS, e.selected / GRID_COLS
	#partial switch a {
	case .Up:
		row = (row + GRID_ROWS - 1) % GRID_ROWS
	case .Down:
		row = (row + 1) % GRID_ROWS
	case .Left:
		col = (col + GRID_COLS - 1) % GRID_COLS
	case .Right:
		col = (col + 1) % GRID_COLS
	}
	e.selected = row * GRID_COLS + col
}

@(private = "file")
adjust :: proc(e: ^Editor, ch: cm.Channel, delta: int) {
	before := e.palette[e.selected][ch]
	cm.palette_adjust_channel(&e.palette, e.selected, ch, delta)
	if e.palette[e.selected][ch] != before {
		e.dirty = true
	}
}

@(private = "file")
set_value :: proc(e: ^Editor, ch: cm.Channel, value: int) {
	before := e.palette[e.selected][ch]
	cm.palette_set_channel(&e.palette, e.selected, ch, value)
	if e.palette[e.selected][ch] != before {
		e.dirty = true
	}
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(MENU_BUTTON, x, y) {
		e.confirm_exit = false
	}
	if i, ok := swatch_at(x, y); ok {
		e.selected = i
		if e.mode != .Paste {
			e.mode = .Browse
		}
	} else if ch, ok := slider_at(x, y); ok {
		e.channel = ch
		e.mode = .Edit
		e.drag = ch
		set_from_slider_x(e, ch, x)
	} else if rect_contains(SAVE_BUTTON, x, y) {
		if !e.embedded {
			e.requests += {.Save}
		}
	} else if rect_contains(LOAD_BUTTON, x, y) {
		if !e.embedded {
			e.requests += {.Load}
		}
	} else if rect_contains(COPY_BUTTON, x, y) {
		copy_selected(e)
	} else if rect_contains(PASTE_BUTTON, x, y) {
		paste(e)
	} else if rect_contains(MENU_BUTTON, x, y) {
		request_exit(e)
	}
}

@(private = "file")
set_from_slider_x :: proc(e: ^Editor, ch: cm.Channel, x: int) {
	r := slider_rect(ch)
	// Track is r.w pixels wide; first pixel is 0 and last is 255.
	px := clamp(x - r.x, 0, r.w - 1)
	set_value(e, ch, (px * 255 + (r.w - 1) / 2) / (r.w - 1))
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
