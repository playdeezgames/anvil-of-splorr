#+build !js
package app

import cm "anvil:common"
import "core:testing"

Frame_Count :: struct {
	fills, presents: int,
}

// What a frontend does with the app each frame (draw through the present guard), with a fake screen:
// a game that never calls `renderer_present` (this app does not) must still get every frame presented.
@(test)
test_every_frame_of_the_app_is_presented_by_the_frontends_guard :: proc(t: ^testing.T) {
	tool := make_tool()
	screen: Frame_Count
	guard := cm.Present_Guard {
		inner = cm.Renderer {
			data = &screen,
			clear = proc(d: rawptr, c: cm.Color) {},
			fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {(^Frame_Count)(d).fills += 1},
			present = proc(d: rawptr) {(^Frame_Count)(d).presents += 1},
		},
	}
	r := cm.present_guard_renderer(&guard)
	for _ in 0 ..< 5 {
		cm.present_guard_begin(&guard)
		cm.tool_update(&tool, 16)
		tool.draw(tool.data, &r)
		cm.present_guard_end(&guard)
	}
	testing.expect_value(t, screen.presents, 5)
	testing.expect(t, screen.fills > 0, "the app draws something")
}
