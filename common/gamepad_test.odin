#+build !js
package common

import "core:testing"

@(test)
test_pad_edges :: proc(t: ^testing.T) {
	prev, now: Pad_State
	prev.connected, prev.standard, prev.button_count = true, true, 17
	now = prev
	now.buttons[0].down = true
	now.buttons[6].down = true
	pressed, released := pad_edges(&prev, &now)
	testing.expect(t, pressed == {0, 6} && released == {})
	prev = now
	now.buttons[0].down = false
	pressed, released = pad_edges(&prev, &now)
	testing.expect(t, pressed == {} && released == {0})

	// Non-standard or disconnected pads never produce presses.
	now.buttons[1].down = true
	now.standard = false
	pressed, _ = pad_edges(&prev, &now)
	testing.expect(t, pressed == {})
	now.standard, now.connected = true, false
	pressed, _ = pad_edges(&prev, &now)
	testing.expect(t, pressed == {})
}

Recorded :: struct {
	actions: [dynamic]Action,
}

@(test)
test_update_pads_sends_only_bound_buttons :: proc(t: ^testing.T) {
	rec: Recorded
	defer delete(rec.actions)
	tool := Tool {
		data = &rec,
		handle_event = proc(data: rawptr, ev: Input_Event) {
			if c, ok := ev.(Command); ok {
				append(&(^Recorded)(data).actions, c.action)
			}
		},
	}
	m := default_input_map()
	prev, now: Pads
	now[0].connected, now[0].standard, now[0].button_count = true, true, 17
	prev = now
	now[0].buttons[1].down = true // green
	now[0].buttons[6].down = true // trigger: unbound
	now[0].buttons[15].down = true // right
	tool_update_pads(&tool, &prev, &now, &m)
	testing.expect_value(t, len(rec.actions), 2)
	testing.expect(t, rec.actions[0] == .Green && rec.actions[1] == .Right)

	tool_update_pads(&tool, &prev, &now, &m) // held: no new presses
	testing.expect_value(t, len(rec.actions), 2)

	m.pad[.Yellow] = 6 // rebinding takes effect
	now[0].buttons[6].down = false
	tool_update_pads(&tool, &prev, &now, &m)
	now[0].buttons[6].down = true
	tool_update_pads(&tool, &prev, &now, &m)
	testing.expect_value(t, len(rec.actions), 3)
	testing.expect(t, rec.actions[2] == .Yellow)
}

@(test)
test_pad_name_truncates :: proc(t: ^testing.T) {
	p: Pad_State
	pad_set_name(&p, "Pad")
	testing.expect_value(t, pad_name(&p), "Pad")
	long: [100]u8
	for &c in long {
		c = 'x'
	}
	pad_set_name(&p, string(long[:]))
	testing.expect_value(t, len(pad_name(&p)), 64)
}

@(test)
test_a_capturing_tool_gets_pad_presses_raw_instead_of_commands :: proc(t: ^testing.T) {
	Probe :: struct {
		capturing: bool,
		commands:  int,
		raws:      [dynamic]int,
	}
	probe: Probe
	defer delete(probe.raws)
	tool := Tool {
		data = &probe,
		handle_event = proc(data: rawptr, ev: Input_Event) {
			if _, ok := ev.(Command); ok {
				(^Probe)(data).commands += 1
			}
		},
		wants_raw = proc(data: rawptr) -> bool {return (^Probe)(data).capturing},
		handle_raw = proc(data: rawptr, raw: Raw_Input) {
			if raw.from_pad {
				append(&(^Probe)(data).raws, raw.button)
			}
		},
	}
	m := default_input_map()
	prev, now: Pads
	now[0].connected, now[0].standard, now[0].button_count = true, true, 17
	prev = now
	probe.capturing = true
	now[0].buttons[1].down = true // bound to green
	now[0].buttons[6].down = true // bound to nothing
	tool_update_pads(&tool, &prev, &now, &m)
	testing.expect_value(t, probe.commands, 0)
	testing.expect_value(t, len(probe.raws), 2)
	testing.expect(t, probe.raws[0] == 1 && probe.raws[1] == 6)
	// Not capturing: commands again, nothing raw; and keys go through tool_raw only when asked.
	probe.capturing = false
	now[0].buttons[15].down = true
	tool_update_pads(&tool, &prev, &now, &m)
	testing.expect(t, probe.commands == 1 && len(probe.raws) == 2)
	testing.expect(t, !tool_raw(&tool, Raw_Input{key = "KeyA"}) && !tool_wants_raw(&tool))
	probe.capturing = true
	testing.expect(t, tool_raw(&tool, Raw_Input{key = "KeyA"}) && tool_wants_raw(&tool))
	plain := Tool{}
	testing.expect(t, !tool_raw(&plain, Raw_Input{key = "KeyA"}))
}
