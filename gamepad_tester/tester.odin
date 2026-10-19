package gamepad_tester

import cm "../common"

// Shows every value of the connected gamepads as the frontends report them, so the user can
// pick which inputs to bind. Standard-layout pads are labelled; others show raw indices.

Tester :: struct {
	pads:     cm.Pads,
	selected: int, // pad slot being displayed
	last:     [cm.MAX_PADS]int, // 1 + index of the most recently pressed button per pad; 0 = none
	exit_requested: bool,
	labels:   ^cm.Input_Map, // for the on-screen name of the red command
}

tester_init :: proc() -> Tester {
	return Tester{}
}

tester_update_pads :: proc(t: ^Tester, pads: ^cm.Pads) {
	for i in 0 ..< cm.MAX_PADS {
		now := &pads[i]
		if !now.connected {
			t.last[i] = 0
			continue
		}
		was := &t.pads[i]
		for b in 0 ..< min(now.button_count, cm.MAX_PAD_BUTTONS) {
			if now.buttons[b].down && !(was.connected && was.buttons[b].down) {
				t.last[i] = b + 1
			}
		}
	}
	t.pads = pads^
	if !t.pads[t.selected].connected {
		t.selected = first_connected(t)
	}
}

first_connected :: proc(t: ^Tester) -> int {
	for i in 0 ..< cm.MAX_PADS {
		if t.pads[i].connected {
			return i
		}
	}
	return 0
}

connected_count :: proc(t: ^Tester) -> (n: int) {
	for i in 0 ..< cm.MAX_PADS {
		if t.pads[i].connected {
			n += 1
		}
	}
	return
}

select_next :: proc(t: ^Tester) {
	for step in 1 ..= cm.MAX_PADS {
		i := (t.selected + step) % cm.MAX_PADS
		if t.pads[i].connected {
			t.selected = i
			return
		}
	}
}

// A click switches between connected pads, or leaves via the MENU button. Pad commands are
// ignored on purpose: pressing a pad's bound buttons while testing must neither switch pads nor
// leave. The keyboard's red command (and the mouse) leave instead.
tester_handle_event :: proc(t: ^Tester, ev: cm.Input_Event) {
	#partial switch v in ev {
	case cm.Command:
		if v.action == .Red && !v.from_pad {
			t.exit_requested = true
		}
	case cm.Mouse_Button_Event:
		if v.down && v.button == .Left {
			if rect_contains(MENU_BUTTON, v.x, v.y) {
				t.exit_requested = true
			} else {
				select_next(t)
			}
		}
	}
}

// Rect in logical pixels.
MENU_BUTTON :: [4]int{278, 168, 36, 10} // x, y, w, h

rect_contains :: proc(r: [4]int, x, y: int) -> bool {
	return x >= r[0] && y >= r[1] && x < r[0] + r[2] && y < r[1] + r[3]
}

tool :: proc(t: ^Tester) -> cm.Tool {
	return cm.Tool {
		title = "Gamepad Tester",
		data = t,
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {tester_handle_event((^Tester)(data), ev)},
		update_pads = proc(data: rawptr, pads: ^cm.Pads) {tester_update_pads((^Tester)(data), pads)},
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {(^Tester)(data).labels = m},
		enter = proc(data: rawptr) {(^Tester)(data).exit_requested = false},
		take_exit = proc(data: rawptr) -> bool {
			t := (^Tester)(data)
			defer t.exit_requested = false
			return t.exit_requested
		},
		draw = proc(data: rawptr, r: ^cm.Renderer) {tester_draw((^Tester)(data), r)},
	}
}
