package common

import "core:fmt"

// What the native frontend tells the person at start-up about gamepads, so that a pad that does nothing
// is explained instead of silent. The frontend gathers the facts (SDL's view and the device files);
// this turns them into lines for stderr, and is tested without a pad.
//
// The usual causes: SDL sees no device at all because /dev/input/event* is readable only by the
// `input` group (join it, or add a udev rule), or SDL sees a device that has no standard controller
// mapping, which this suite ignores (only standard layouts produce commands).

Pad_Report :: struct {
	seen:          int, // joysticks SDL reports
	opened:        int, // of those, opened as standard controllers
	ignored:       []string, // names of devices ignored for want of a standard mapping
	devices_exist: bool, // /dev/input has js* or event* files
	unreadable:    string, // the first of those this user cannot open ("" if all can, or none exist)
}

// The lines to print (on the temp allocator), the first always saying what SDL sees.
gamepad_report_lines :: proc(r: Pad_Report) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	append(&out, fmt.tprintf("gamepads: SDL sees %d, opened %d as standard controllers", r.seen, r.opened))
	for name in r.ignored {
		append(&out, fmt.tprintf("gamepads: ignored \"%s\": it has no standard controller mapping (see GAMES.md)", name))
	}
	if r.seen == 0 && r.devices_exist {
		if r.unreadable != "" {
			append(&out, fmt.tprintf("gamepads: SDL sees none, but %s cannot be read by this user: join the \"input\" group or add a udev rule (see GAMES.md)", r.unreadable))
		} else {
			append(&out, "gamepads: SDL sees none although input devices exist and are readable: is a pad plugged in?")
		}
	}
	return out[:]
}
