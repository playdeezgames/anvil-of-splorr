#+build !js
package common

import "core:testing"

@(test)
test_held_keys_follow_down_and_up_and_ignore_repeats :: proc(t: ^testing.T) {
	m := default_input_map()
	k: Key_Tracker
	testing.expect(t, keys_held(&k, &m) == Held_Keys{})
	keys_down(&k, "ArrowLeft")
	keys_down(&k, "ArrowLeft") // an OS repeat is the same key
	testing.expect_value(t, k.count, 1)
	h := keys_held(&k, &m)
	testing.expect(t, h[.Left] && !h[.Right] && !h[.Up])
	keys_down(&k, "ArrowUp")
	h = keys_held(&k, &m)
	testing.expect(t, h[.Left] && h[.Up])
	keys_up(&k, "ArrowLeft")
	h = keys_held(&k, &m)
	testing.expect(t, !h[.Left] && h[.Up])
	keys_up(&k, "KeyQ") // never went down: ignored
	testing.expect_value(t, k.count, 1)
	keys_clear(&k)
	testing.expect(t, keys_held(&k, &m) == Held_Keys{})
}

@(test)
test_two_keys_for_one_command_hold_it_until_both_are_up :: proc(t: ^testing.T) {
	m := default_input_map()
	set_key_name(&m.keys[.Green], "Space")
	// "KeyW" is not bound by default; bind it by hand as a second key via the held lookup of Up.
	set_key_name(&m.keys[.Up], "KeyW")
	k: Key_Tracker
	keys_down(&k, "KeyW")
	keys_down(&k, "Space")
	h := keys_held(&k, &m)
	testing.expect(t, h[.Up] && h[.Green])
	keys_up(&k, "KeyW")
	h = keys_held(&k, &m)
	testing.expect(t, !h[.Up] && h[.Green])
	// Unbound keys are tracked but hold no command.
	keys_down(&k, "KeyZ")
	h = keys_held(&k, &m)
	testing.expect(t, h == Held_Keys{.Up = false, .Down = false, .Left = false, .Right = false, .Green = true, .Red = false, .Blue = false, .Yellow = false})
}

@(test)
test_the_tool_gets_the_held_commands_every_frame :: proc(t: ^testing.T) {
	m := default_input_map()
	k: Key_Tracker
	got: Held_Keys
	calls := 0
	Seen :: struct {
		got:   ^Held_Keys,
		calls: ^int,
	}
	seen := Seen{&got, &calls}
	tool := Tool {
		data = &seen,
		update_keys = proc(data: rawptr, held: ^Held_Keys) {
			s := (^Seen)(data)
			s.got^ = held^
			s.calls^ += 1
		},
	}
	keys_down(&k, "ArrowRight")
	tool_update_keys(&tool, &k, &m)
	testing.expect(t, got[.Right])
	keys_up(&k, "ArrowRight")
	tool_update_keys(&tool, &k, &m) // the release is delivered too
	testing.expect(t, !got[.Right])
	testing.expect_value(t, calls, 2)
	none := Tool{}
	tool_update_keys(&none, &k, &m) // no proc: nothing happens
}
