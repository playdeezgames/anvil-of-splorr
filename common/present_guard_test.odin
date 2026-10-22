#+build !js
package common

import "core:testing"

Fake_Screen :: struct {
	clears, fills, presents: int,
	last_fill:               [4]int,
	last_color:              Color,
}

fake_renderer :: proc(s: ^Fake_Screen) -> Renderer {
	return Renderer {
		data = s,
		clear = proc(d: rawptr, c: Color) {
			s := (^Fake_Screen)(d)
			s.clears += 1
			s.last_color = c
		},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: Color) {
			s := (^Fake_Screen)(d)
			s.fills += 1
			s.last_fill = {x, y, w, h}
			s.last_color = c
		},
		present = proc(d: rawptr) {(^Fake_Screen)(d).presents += 1},
	}
}

@(test)
test_a_frame_is_presented_exactly_once_whether_or_not_the_tool_presents :: proc(t: ^testing.T) {
	screen: Fake_Screen
	guard := Present_Guard {
		inner = fake_renderer(&screen),
	}
	r := present_guard_renderer(&guard)
	// A game that only draws.
	for frame in 1 ..= 3 {
		present_guard_begin(&guard)
		renderer_clear(&r, Color{1, 2, 3})
		renderer_fill_rect(&r, 4, 5, 6, 7, Color{8, 9, 10})
		testing.expect(t, present_guard_end(&guard))
		testing.expect_value(t, screen.presents, frame)
	}
	testing.expect(t, screen.clears == 3 && screen.fills == 3)
	testing.expect(t, screen.last_fill == [4]int{4, 5, 6, 7} && screen.last_color == Color{8, 9, 10}) // forwarded unchanged
	// An editor that presents itself at the end of draw: nothing more is done.
	screen = {}
	for frame in 1 ..= 3 {
		present_guard_begin(&guard)
		renderer_clear(&r, Color{})
		renderer_present(&r)
		testing.expect(t, !present_guard_end(&guard))
		testing.expect_value(t, screen.presents, frame)
	}
	// The count starts again each frame: a presenting frame does not excuse the next one.
	screen = {}
	present_guard_begin(&guard)
	renderer_present(&r)
	present_guard_end(&guard)
	present_guard_begin(&guard)
	testing.expect(t, present_guard_end(&guard)) // an empty frame is still presented
	testing.expect_value(t, screen.presents, 2)
}
