#+build !js
package gamepad_tester

import cm "../common"
import "core:testing"

standard_pad :: proc() -> cm.Pad_State {
	p: cm.Pad_State
	p.connected, p.standard = true, true
	p.button_count, p.axis_count = 17, 4
	cm.pad_set_name(&p, "Test Pad")
	return p
}

@(test)
test_last_pressed_tracks_press_edges :: proc(t: ^testing.T) {
	tester := tester_init()
	pads: cm.Pads
	pads[0] = standard_pad()
	tester_update_pads(&tester, &pads)
	testing.expect_value(t, tester.last[0], 0)

	pads[0].buttons[6] = {true, 0.8} // LT
	tester_update_pads(&tester, &pads)
	testing.expect_value(t, tester.last[0], 7)

	pads[0].buttons[2].down = true // X pressed while LT is still held
	tester_update_pads(&tester, &pads)
	testing.expect_value(t, tester.last[0], 3)

	pads[0].buttons[2].down = false // release does not change "last"
	tester_update_pads(&tester, &pads)
	testing.expect_value(t, tester.last[0], 3)

	pads[0].connected = false
	tester_update_pads(&tester, &pads)
	testing.expect_value(t, tester.last[0], 0)
}

@(test)
test_selection_follows_connected_pads :: proc(t: ^testing.T) {
	tester := tester_init()
	pads: cm.Pads
	pads[1], pads[3] = standard_pad(), standard_pad()
	tester_update_pads(&tester, &pads)
	testing.expect_value(t, tester.selected, 1) // first connected
	tester_handle_event(&tester, cm.Command{.Green}) // commands do not switch pads
	testing.expect_value(t, tester.selected, 1)
	tester_handle_event(&tester, cm.Mouse_Button_Event{button = .Left, down = true})
	testing.expect_value(t, tester.selected, 3)
	tester_handle_event(&tester, cm.Mouse_Button_Event{button = .Left, down = true})
	testing.expect_value(t, tester.selected, 1) // wraps
	pads[1].connected = false
	tester_update_pads(&tester, &pads)
	testing.expect_value(t, tester.selected, 3)
}

Count :: struct {
	rects, clears, presents, out_of_bounds: int,
}

@(test)
test_draw_all_layouts_stay_on_screen :: proc(t: ^testing.T) {
	count: Count
	r := cm.Renderer {
		data = &count,
		clear = proc(d: rawptr, c: cm.Color) {(^Count)(d).clears += 1},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			c := (^Count)(d)
			c.rects += 1
			if x < 0 || y < 0 || x + w > cm.SCREEN_W || y + h > cm.SCREEN_H {
				c.out_of_bounds += 1
			}
		},
		present = proc(d: rawptr) {(^Count)(d).presents += 1},
	}
	tester := tester_init()
	tester_draw(&tester, &r) // no pad
	testing.expect_value(t, count.presents, 1)

	// Standard pad with everything pressed and sticks at extremes, then a worst-case raw pad.
	pads: cm.Pads
	pads[0] = standard_pad()
	for i in 0 ..< 17 {
		pads[0].buttons[i] = {true, 1}
	}
	for i in 0 ..< 4 {
		pads[0].axes[i] = i % 2 == 0 ? 1 : -1
	}
	pads[1].connected = true
	pads[1].button_count, pads[1].axis_count = cm.MAX_PAD_BUTTONS, cm.MAX_PAD_AXES
	for i in 0 ..< cm.MAX_PAD_BUTTONS {
		pads[1].buttons[i] = {true, 1}
	}
	for i in 0 ..< cm.MAX_PAD_AXES {
		pads[1].axes[i] = -1
	}
	tester_update_pads(&tester, &pads)
	for sel in 0 ..< 2 {
		tester.selected = sel
		before := count.rects
		tester_draw(&tester, &r)
		testing.expectf(t, count.rects > before, "pad %d drew nothing", sel)
	}
	testing.expect_value(t, count.out_of_bounds, 0)
}
