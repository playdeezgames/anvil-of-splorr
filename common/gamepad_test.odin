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
