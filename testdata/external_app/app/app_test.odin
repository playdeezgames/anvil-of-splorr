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

// A game's autosave: a press asks for a silent save, the frontend takes it once, and a fresh app that
// loads the text has the same count back. A broken file is refused and changes nothing.
@(test)
test_the_app_autosaves_and_loads_its_progress :: proc(t: ^testing.T) {
	tool := make_tool()
	testing.expect_value(t, cm.tool_file_name(&tool), "external.json")
	testing.expect(t, tool.wants_load(tool.data), "asks to load at start")
	testing.expect(t, !tool.wants_load(tool.data), "but only once")
	_, _, ok := cm.tool_take_save(&tool)
	testing.expect(t, !ok, "nothing to save yet")
	tool.handle_event(tool.data, cm.Command{action = .Yellow})
	tool.handle_event(tool.data, cm.Command{action = .Yellow})
	text, silent, ok2 := cm.tool_take_save(&tool)
	testing.expect(t, ok2 && silent, "the press asks for a silent save")
	testing.expect_value(t, text, "{\"presses\": 2}")
	_, _, again := cm.tool_take_save(&tool)
	testing.expect(t, !again, "one request, one save")

	bytes := transmute([]u8)text
	fresh := make_tool()
	testing.expect(t, fresh.load(fresh.data, bytes), "the saved text loads")
	testing.expect_value(t, demo.presses, 2)
	testing.expect(t, !fresh.load(fresh.data, transmute([]u8)string("nonsense")), "a broken file is refused")
	testing.expect_value(t, demo.presses, 2)
}
