package gamepad_tester

import cm "../common"

// Shows every value of the connected gamepads as the frontends report them, so the user can
// pick which inputs to bind. Standard-layout pads are labelled; others show raw indices.

Tester :: struct {
	pads:     cm.Pads,
	selected: int, // pad slot being displayed
	last:     [cm.MAX_PADS]int, // 1 + index of the most recently pressed button per pad; 0 = none
	quit:     bool,
	can_quit: bool,
}

tester_init :: proc() -> Tester {
	return Tester{can_quit = true}
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

tester_handle_event :: proc(t: ^Tester, ev: cm.Input_Event) {
	#partial switch v in ev {
	case cm.Key_Event:
		if v.down {
			#partial switch v.key {
			case .Tab:
				select_next(t)
			case .Escape:
				t.quit = t.can_quit
			}
		}
	case cm.Mouse_Button_Event:
		if v.down && v.button == .Left {
			select_next(t)
		}
	}
}

tool :: proc(t: ^Tester) -> cm.Tool {
	return cm.Tool {
		title = "Gamepad Tester",
		data = t,
		configure = proc(data: rawptr, info: cm.Platform_Info) {(^Tester)(data).can_quit = info.can_quit},
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {tester_handle_event((^Tester)(data), ev)},
		update_pads = proc(data: rawptr, pads: ^cm.Pads) {tester_update_pads((^Tester)(data), pads)},
		draw = proc(data: rawptr, r: ^cm.Renderer) {tester_draw((^Tester)(data), r)},
		wants_quit = proc(data: rawptr) -> bool {return (^Tester)(data).quit},
	}
}
