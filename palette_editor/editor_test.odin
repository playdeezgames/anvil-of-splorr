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
