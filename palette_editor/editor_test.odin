#+build !js
package palette_editor

import cm "../common"
import "core:testing"

key :: proc(k: cm.Key, shift := false) -> cm.Input_Event {
	return cm.Key_Event{key = k, shift = shift, down = true}
}

click_at :: proc(e: ^Editor, x, y: int) {
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = true})
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = false})
}

@(test)
test_selection_wraps :: proc(t: ^testing.T) {
	e := editor_init()
	editor_handle_event(&e, key(.Left))
	testing.expect_value(t, e.selected, 3)
	editor_handle_event(&e, key(.Right))
	testing.expect_value(t, e.selected, 0)
	editor_handle_event(&e, key(.Up))
	testing.expect_value(t, e.selected, 12)
	editor_handle_event(&e, key(.Down))
	testing.expect_value(t, e.selected, 0)
	editor_handle_event(&e, cm.Pad_Event{button = .Dpad_Right, down = true})
	testing.expect_value(t, e.selected, 1)
}

@(test)
test_channel_selection :: proc(t: ^testing.T) {
	e := editor_init()
	editor_handle_event(&e, key(.Tab))
	testing.expect_value(t, e.channel, cm.Channel.G)
	editor_handle_event(&e, key(.Tab, shift = true))
	editor_handle_event(&e, key(.Tab, shift = true))
	testing.expect_value(t, e.channel, cm.Channel.B)
	editor_handle_event(&e, key(.R))
	testing.expect_value(t, e.channel, cm.Channel.R)
}

@(test)
test_value_edit_saturates_and_sets_dirty :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 0 // black
	editor_handle_event(&e, key(.Minus))
	testing.expect_value(t, e.palette[0].r, 0)
	testing.expect(t, !e.dirty) // nothing changed
	editor_handle_event(&e, key(.Page_Up))
	testing.expect_value(t, e.palette[0].r, 16)
	testing.expect(t, e.dirty)
	for _ in 0 ..< 30 {
		editor_handle_event(&e, key(.Page_Up))
	}
	testing.expect_value(t, e.palette[0].r, 255)
}

@(test)
test_requests_and_quit :: proc(t: ^testing.T) {
	e := editor_init()
	editor_handle_event(&e, key(.S))
	editor_handle_event(&e, cm.Pad_Event{button = .Back, down = true})
	testing.expect(t, .Save in e.requests && .Load in e.requests)
	testing.expect(t, !e.quit)
	editor_handle_event(&e, key(.Escape))
	testing.expect(t, e.quit)

	e = editor_init()
	e.can_quit = false
	editor_handle_event(&e, key(.Escape))
	testing.expect(t, !e.quit)
}

@(test)
test_mouse_selects_swatch_and_buttons :: proc(t: ^testing.T) {
	e := editor_init()
	r := swatch_rect(6)
	click_at(&e, r.x + 3, r.y + 3)
	testing.expect_value(t, e.selected, 6)
	click_at(&e, SAVE_BUTTON.x + 1, SAVE_BUTTON.y + 1)
	testing.expect(t, .Save in e.requests)
	click_at(&e, LOAD_BUTTON.x + 1, LOAD_BUTTON.y + 1)
	testing.expect(t, .Load in e.requests)
	// The gap between swatches is not a hit.
	_, ok := swatch_at(GRID_X + CELL + 1, GRID_Y)
	testing.expect(t, !ok)
}

@(test)
test_slider_click_and_drag :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 0
	rg := slider_rect(.G)
	click_at(&e, rg.x + rg.w - 1, rg.y + 2)
	testing.expect_value(t, e.channel, cm.Channel.G)
	testing.expect_value(t, e.palette[0].g, 255)
	click_at(&e, rg.x, rg.y + 2)
	testing.expect_value(t, e.palette[0].g, 0)
	testing.expect(t, e.dirty)

	// Drag past both ends clamps.
	editor_handle_event(&e, cm.Mouse_Button_Event{button = .Left, x = rg.x + 10, y = rg.y, down = true})
	editor_handle_event(&e, cm.Mouse_Move{rg.x + 500, 0})
	testing.expect_value(t, e.palette[0].g, 255)
	editor_handle_event(&e, cm.Mouse_Move{rg.x - 500, 170})
	testing.expect_value(t, e.palette[0].g, 0)
	editor_handle_event(&e, cm.Mouse_Button_Event{button = .Left, x = 0, y = 0, down = false})
	editor_handle_event(&e, cm.Mouse_Move{rg.x + 60, 0})
	testing.expect_value(t, e.palette[0].g, 0) // no longer dragging
}

@(test)
test_wheel :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 8 // (85,85,85)
	// Away from sliders: current channel (R).
	editor_handle_event(&e, cm.Mouse_Move{0, 0})
	editor_handle_event(&e, cm.Mouse_Wheel{dy = 3})
	testing.expect_value(t, e.palette[8].r, 88)
	// Over the B slider: that channel, and it becomes current.
	rb := slider_rect(.B)
	editor_handle_event(&e, cm.Mouse_Move{rb.x + 5, rb.y + 5})
	editor_handle_event(&e, cm.Mouse_Wheel{dy = -2})
	testing.expect_value(t, e.palette[8].b, 83)
	testing.expect_value(t, e.channel, cm.Channel.B)
}

Fill_Log :: struct {
	colors:   [dynamic]cm.Color,
	presents: int,
	cleared:  int,
}

@(test)
test_draw_shows_selected_color :: proc(t: ^testing.T) {
	log: Fill_Log
	defer delete(log.colors)
	r := cm.Renderer {
		data = &log,
		clear = proc(d: rawptr, c: cm.Color) {(^Fill_Log)(d).cleared += 1},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			append(&(^Fill_Log)(d).colors, c)
		},
		present = proc(d: rawptr) {(^Fill_Log)(d).presents += 1},
	}
	e := editor_init()
	e.palette[5] = {12, 34, 56}
	e.selected = 5
	editor_draw(&e, &r)
	testing.expect_value(t, log.cleared, 1)
	testing.expect_value(t, log.presents, 1)
	found := 0
	for c in log.colors {
		if c == (cm.Color{12, 34, 56}) {
			found += 1
		}
	}
	testing.expect(t, found >= 2) // swatch + preview
}

@(test)
test_layout_fits_screen :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, r: Rect) {
		testing.expect(t, r.x >= 0 && r.y >= 0 && r.x + r.w <= cm.SCREEN_W && r.y + r.h <= cm.SCREEN_H)
	}
	for i in 0 ..< cm.PALETTE_SIZE {
		check(t, swatch_rect(i))
	}
	for ch in cm.Channel {
		check(t, slider_rect(ch))
	}
	check(t, PREVIEW)
	check(t, SAVE_BUTTON)
	check(t, LOAD_BUTTON)
}

// --- Parity: every function must be reachable with each input method alone. ---

Input_Method :: enum {
	Keyboard,
	Mouse,
	Gamepad,
}

// Select swatch `target` from swatch 0 using only the given method.
select_swatch_via :: proc(e: ^Editor, m: Input_Method, target: int) {
	switch m {
	case .Keyboard:
		for _ in 0 ..< target % GRID_COLS {
			editor_handle_event(e, key(.Right))
		}
		for _ in 0 ..< target / GRID_COLS {
			editor_handle_event(e, key(.Down))
		}
	case .Gamepad:
		for _ in 0 ..< target % GRID_COLS {
			editor_handle_event(e, cm.Pad_Event{.Dpad_Right, true})
		}
		for _ in 0 ..< target / GRID_COLS {
			editor_handle_event(e, cm.Pad_Event{.Dpad_Down, true})
		}
	case .Mouse:
		r := swatch_rect(target)
		click_at(e, r.x + r.w / 2, r.y + r.h / 2)
	}
}

@(test)
test_every_swatch_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for target in 0 ..< cm.PALETTE_SIZE {
			e := editor_init()
			select_swatch_via(&e, m, target)
			testing.expectf(t, e.selected == target, "%v could not select swatch %d (got %d)", m, target, e.selected)
		}
	}
}

// Make the current channel reach `target` using only the given method, starting from 0.
set_value_via :: proc(e: ^Editor, m: Input_Method, target: int) {
	switch m {
	case .Keyboard:
		for _ in 0 ..< target / cm.STEP_BIG {
			editor_handle_event(e, key(.Page_Up))
		}
		for _ in 0 ..< target % cm.STEP_BIG {
			editor_handle_event(e, key(.Plus))
		}
	case .Gamepad:
		for _ in 0 ..< target / cm.STEP_BIG {
			editor_handle_event(e, cm.Pad_Event{.Y, true})
		}
		for _ in 0 ..< target % cm.STEP_BIG {
			editor_handle_event(e, cm.Pad_Event{.A, true})
		}
	case .Mouse:
		// Click the slider at the closest pixel, then trim with the wheel.
		rc := slider_rect(e.channel)
		px := (target * (rc.w - 1) + 127) / 255
		click_at(e, rc.x + px, rc.y + 2)
		diff := target - int(e.palette[e.selected][e.channel])
		editor_handle_event(e, cm.Mouse_Wheel{diff})
	}
}

@(test)
test_every_value_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for ch in cm.Channel {
			for target in 0 ..= 255 {
				e := editor_init()
				e.palette[0] = {} // black, so keyboard/pad start from 0
				e.channel = ch
				set_value_via(&e, m, target)
				got := int(e.palette[0][ch])
				if got != target {
					testing.expectf(t, false, "%v could not set %v to %d (got %d)", m, ch, target, got)
					return
				}
			}
		}
	}
}

@(test)
test_slider_mapping_is_monotonic_with_exact_ends :: proc(t: ^testing.T) {
	e := editor_init()
	e.palette[0] = {}
	rc := slider_rect(.R)
	prev := -1
	for dx in 0 ..< rc.w {
		click_at(&e, rc.x + dx, rc.y + 2)
		v := int(e.palette[0].r)
		testing.expectf(t, v >= prev, "slider not monotonic at %d: %d < %d", dx, v, prev)
		if dx == 0 {
			testing.expect_value(t, v, 0)
		}
		prev = v
	}
	testing.expect_value(t, prev, 255)
}

@(test)
test_channels_reachable_by_each_input :: proc(t: ^testing.T) {
	// Keyboard: direct keys. Gamepad: shoulders cycle. Mouse: click the slider.
	e := editor_init()
	editor_handle_event(&e, key(.B))
	testing.expect_value(t, e.channel, cm.Channel.B)
	editor_handle_event(&e, key(.G))
	testing.expect_value(t, e.channel, cm.Channel.G)
	editor_handle_event(&e, key(.R))
	testing.expect_value(t, e.channel, cm.Channel.R)

	editor_handle_event(&e, cm.Pad_Event{.Right_Shoulder, true})
	editor_handle_event(&e, cm.Pad_Event{.Right_Shoulder, true})
	testing.expect_value(t, e.channel, cm.Channel.B)
	editor_handle_event(&e, cm.Pad_Event{.Left_Shoulder, true})
	testing.expect_value(t, e.channel, cm.Channel.G)

	for ch in cm.Channel {
		r := slider_rect(ch)
		click_at(&e, r.x + 5, r.y + 2)
		testing.expect_value(t, e.channel, ch)
	}
}

@(test)
test_save_and_load_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for req in Request {
			e := editor_init()
			switch m {
			case .Keyboard:
				editor_handle_event(&e, key(req == .Save ? .S : .L))
			case .Gamepad:
				editor_handle_event(&e, cm.Pad_Event{req == .Save ? .Start : .Back, true})
			case .Mouse:
				b := req == .Save ? SAVE_BUTTON : LOAD_BUTTON
				click_at(&e, b.x + b.w / 2, b.y + b.h / 2)
			}
			testing.expectf(t, req in e.requests, "%v could not request %v", m, req)
		}
	}
}
