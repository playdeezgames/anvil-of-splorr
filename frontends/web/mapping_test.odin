#+build !js
package main

import cm "../../common"
import "core:testing"

@(test)
test_key_codes :: proc(t: ^testing.T) {
	testing.expect_value(t, key_for_code("ArrowLeft"), cm.Key.Left)
	testing.expect_value(t, key_for_code("NumpadAdd"), cm.Key.Plus)
	testing.expect_value(t, key_for_code("Equal"), cm.Key.Plus)
	testing.expect_value(t, key_for_code("F13"), cm.Key.None)
	testing.expect_value(t, key_for_code(""), cm.Key.None)
}

@(test)
test_every_key_has_a_code :: proc(t: ^testing.T) {
	codes := [?]string {
		"ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Tab", "PageUp", "PageDown", "Equal",
		"Minus", "KeyR", "KeyG", "KeyB", "KeyS", "KeyL", "Escape",
	}
	seen: bit_set[cm.Key]
	for c in codes {
		seen += {key_for_code(c)}
	}
	for k in cm.Key {
		if k != .None {
			testing.expectf(t, k in seen, "no browser code maps to %v", k)
		}
	}
}
