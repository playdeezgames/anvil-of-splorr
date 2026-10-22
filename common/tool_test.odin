#+build !js
package common

import "core:math"
import "core:testing"

Clock :: struct {
	total, last: f64,
	calls:       int,
}

// A fake frontend loop: the elapsed times it measured, handed to the tool the way both frontends do.
@(test)
test_a_tool_is_told_the_elapsed_time_each_frame_clamped :: proc(t: ^testing.T) {
	clock: Clock
	tool := Tool {
		data = &clock,
		update = proc(data: rawptr, dt_ms: f64) {
			c := (^Clock)(data)
			c.total += dt_ms
			c.last = dt_ms
			c.calls += 1
		},
	}
	// 60 Hz, 144 Hz, a hidden tab (3 seconds), a clock stepping back, and not-a-number.
	elapsed := []f64{16.667, 6.944, 3000, -5, math.nan_f64(), 0, 99.5, 100, 100.5}
	given := []f64{16.667, 6.944, MAX_FRAME_MS, 0, 0, 0, 99.5, 100, MAX_FRAME_MS}
	for e, i in elapsed {
		got := tool_update(&tool, e)
		testing.expectf(t, got == given[i] && clock.last == given[i], "frame %d: %v gave %v", i, e, got)
	}
	testing.expect_value(t, clock.calls, len(elapsed))
	// Fractions add up: 1000 frames of 1000/144 ms are about a second, not 1000 * 6 or 1000 * 7 ms.
	clock = {}
	for _ in 0 ..< 1000 {
		tool_update(&tool, 1000.0 / 144)
	}
	testing.expect(t, math.abs(clock.total - 6944.4) < 1.0)
}

@(test)
test_a_tool_without_a_clock_is_unaffected :: proc(t: ^testing.T) {
	editor := Tool{} // the editors leave update nil
	testing.expect_value(t, tool_update(&editor, 33), 33.0)
	testing.expect_value(t, tool_update(&editor, 500), MAX_FRAME_MS)
}

// A requested save comes before an autosave, each is reported once with its kind, and a tool with only
// an autosave hook still has a file.
@(test)
test_tool_take_save_reports_the_kind_of_save :: proc(t: ^testing.T) {
	Saves :: struct {
		loud, quiet: bool,
	}
	s := Saves{true, true}
	tool := Tool {
		data = &s,
		take_save = proc(data: rawptr) -> (string, bool) {
			d := (^Saves)(data)
			was := d.loud
			d.loud = false
			return "loud", was
		},
		take_autosave = proc(data: rawptr) -> (string, bool) {
			d := (^Saves)(data)
			was := d.quiet
			d.quiet = false
			return "quiet", was
		},
		wants_load = proc(data: rawptr) -> bool {return false},
		load = proc(data: rawptr, bytes: []u8) -> bool {return true},
		default_file = "x.json",
	}
	text, silent, ok := tool_take_save(&tool)
	testing.expect(t, ok && !silent && text == "loud", "the requested save first")
	text, silent, ok = tool_take_save(&tool)
	testing.expect(t, ok && silent && text == "quiet", "then the autosave")
	_, _, ok = tool_take_save(&tool)
	testing.expect(t, !ok, "then nothing")

	only := Tool {
		data = &s,
		take_autosave = tool.take_autosave,
		wants_load = tool.wants_load,
		load = tool.load,
		default_file = "y.json",
	}
	testing.expect_value(t, tool_file_name(&only), "y.json")
}
