#+build !js
package common

import "core:testing"

@(test)
test_every_bound_pad_button_has_a_standard_index :: proc(t: ^testing.T) {
	seen: bit_set[Pad_Button]
	for i in 0 ..< STANDARD_BUTTON_COUNT {
		if b, ok := pad_button_for_index(i); ok {
			seen += {b}
		}
	}
	for b in Pad_Button {
		testing.expectf(t, b in seen, "no standard-mapping index gives %v", b)
	}
	_, ok := pad_button_for_index(6) // triggers are not bound
	testing.expect(t, !ok)
	_, ok = pad_button_for_index(100)
	testing.expect(t, !ok)
}

@(test)
test_pad_edges :: proc(t: ^testing.T) {
	prev, now: Pad_State
	prev.connected, prev.standard, prev.button_count = true, true, 17
	now = prev
	now.buttons[0].down = true // A
	now.buttons[6].down = true // LT: not bound, never an edge
	pressed, released := pad_edges(&prev, &now)
	testing.expect(t, pressed == {.A} && released == {})
	prev = now
	now.buttons[0].down = false
	pressed, released = pad_edges(&prev, &now)
	testing.expect(t, pressed == {} && released == {.A})

	// Non-standard or disconnected pads never produce presses.
	now.buttons[1].down = true
	now.standard = false
	pressed, _ = pad_edges(&prev, &now)
	testing.expect(t, pressed == {})
	now.standard, now.connected = true, false
	pressed, _ = pad_edges(&prev, &now)
	testing.expect(t, pressed == {})
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
