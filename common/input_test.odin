#+build !js
package common

import "core:testing"

@(test)
test_key_mapping :: proc(t: ^testing.T) {
	a, ok := key_to_action({key = .Tab, down = true})
	testing.expect(t, ok && a == .Next_Channel)
	a, ok = key_to_action({key = .Tab, shift = true, down = true})
	testing.expect(t, ok && a == .Prev_Channel)
	_, ok = key_to_action({key = .Tab, down = false})
	testing.expect(t, !ok)
	_, ok = key_to_action({key = .None, down = true})
	testing.expect(t, !ok)
}

@(test)
test_every_action_reachable_from_keyboard_and_gamepad :: proc(t: ^testing.T) {
	from_key: bit_set[Action]
	for k in Key {
		if a, ok := key_to_action({key = k, down = true}); ok {
			from_key += {a}
		}
		if a, ok := key_to_action({key = k, shift = true, down = true}); ok {
			from_key += {a}
		}
	}
	from_pad: bit_set[Action]
	for b in Pad_Button {
		if a, ok := pad_to_action({button = b, down = true}); ok {
			from_pad += {a}
		}
	}
	for a in Action {
		testing.expectf(t, a in from_key, "action %v has no keyboard binding", a)
	}
	// Direct channel selection (R/G/B) is keyboard-only; the gamepad cycles channels instead.
	for a in Action {
		if a == .Select_R || a == .Select_G || a == .Select_B {
			continue
		}
		testing.expectf(t, a in from_pad, "action %v has no gamepad binding", a)
	}
}
