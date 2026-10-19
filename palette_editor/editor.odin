package palette_editor

import cm "../common"

GRID_COLS :: 4
GRID_ROWS :: 4
#assert(GRID_COLS * GRID_ROWS == cm.PALETTE_SIZE)

Request :: enum {
	Save,
	Load,
}

// Pure tool state. Frontends feed it events, call editor_draw, and service `requests` (file IO
// is platform specific) and `quit`.
Editor :: struct {
	palette:  cm.Palette,
	selected: int,
	channel:  cm.Channel,
	dirty:    bool, // palette changed since the last save/load
	requests: bit_set[Request],
	quit:     bool,
	can_quit: bool, // false on platforms with no way to exit (web); Quit is then ignored and not advertised
	mouse:    [2]int,
	drag:     Maybe(cm.Channel), // slider currently being dragged with the mouse
}

editor_init :: proc() -> Editor {
	return Editor{palette = cm.default_palette(), can_quit = true}
}

// Frontend calls these after servicing a Request.
editor_mark_saved :: proc(e: ^Editor) {
	e.dirty = false
}

editor_set_palette :: proc(e: ^Editor, p: cm.Palette) {
	e.palette = p
	e.dirty = false
}

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch v in ev {
	case cm.Key_Event:
		if a, ok := cm.key_to_action(v); ok {
			editor_apply_action(e, a)
		}
	case cm.Pad_Event:
		if a, ok := cm.pad_to_action(v); ok {
			editor_apply_action(e, a)
		}
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
		// Over a slider: that channel. Elsewhere: the current channel.
		ch := e.channel
		if hit, ok := slider_at(e.mouse.x, e.mouse.y); ok {
			ch = hit
			e.channel = hit
		}
		adjust(e, ch, v.dy * cm.STEP_SMALL)
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	col, row := e.selected % GRID_COLS, e.selected / GRID_COLS
	switch a {
	case .Up:
		row = (row + GRID_ROWS - 1) % GRID_ROWS
	case .Down:
		row = (row + 1) % GRID_ROWS
	case .Left:
		col = (col + GRID_COLS - 1) % GRID_COLS
	case .Right:
		col = (col + 1) % GRID_COLS
	case .Next_Channel:
		e.channel = cm.Channel((int(e.channel) + 1) % len(cm.Channel))
	case .Prev_Channel:
		e.channel = cm.Channel((int(e.channel) + len(cm.Channel) - 1) % len(cm.Channel))
	case .Select_R:
		e.channel = .R
	case .Select_G:
		e.channel = .G
	case .Select_B:
		e.channel = .B
	case .Increase:
		adjust(e, e.channel, cm.STEP_SMALL)
	case .Decrease:
		adjust(e, e.channel, -cm.STEP_SMALL)
	case .Increase_Big:
		adjust(e, e.channel, cm.STEP_BIG)
	case .Decrease_Big:
		adjust(e, e.channel, -cm.STEP_BIG)
	case .Save:
		e.requests += {.Save}
	case .Load:
		e.requests += {.Load}
	case .Quit:
		e.quit = e.can_quit
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
	if i, ok := swatch_at(x, y); ok {
		e.selected = i
	} else if ch, ok := slider_at(x, y); ok {
		e.channel = ch
		e.drag = ch
		set_from_slider_x(e, ch, x)
	} else if rect_contains(SAVE_BUTTON, x, y) {
		e.requests += {.Save}
	} else if rect_contains(LOAD_BUTTON, x, y) {
		e.requests += {.Load}
	}
}

@(private = "file")
set_from_slider_x :: proc(e: ^Editor, ch: cm.Channel, x: int) {
	r := slider_rect(ch)
	// Track is r.w pixels wide; first pixel is 0 and last is 255.
	px := clamp(x - r.x, 0, r.w - 1)
	set_value(e, ch, (px * 255 + (r.w - 1) / 2) / (r.w - 1))
}
