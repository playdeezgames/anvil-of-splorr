#+build !js
package common

import "core:strings"
import "core:testing"

@(test)
test_gamepad_report_explains_a_pad_that_does_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// A standard pad that opened: one line.
	lines := gamepad_report_lines(Pad_Report{seen = 1, opened = 1})
	testing.expect(t, len(lines) == 1 && strings.contains(lines[0], "SDL sees 1, opened 1"))
	// Nothing at all: no devices, so nothing more to say.
	lines = gamepad_report_lines(Pad_Report{})
	testing.expect(t, len(lines) == 1 && strings.contains(lines[0], "SDL sees 0, opened 0"))
	// Devices exist, SDL sees none, one cannot be read: the line names it and the fix.
	lines = gamepad_report_lines(Pad_Report{devices_exist = true, unreadable = "/dev/input/event16"})
	testing.expect(t, len(lines) == 2)
	testing.expect(t, strings.contains(lines[1], "/dev/input/event16") && strings.contains(lines[1], "\"input\" group") && strings.contains(lines[1], "udev"))
	// Devices exist and all are readable: say so instead of blaming permissions.
	lines = gamepad_report_lines(Pad_Report{devices_exist = true})
	testing.expect(t, len(lines) == 2 && strings.contains(lines[1], "readable") && !strings.contains(lines[1], "udev"))
	// A device with no standard mapping is named, once each.
	lines = gamepad_report_lines(Pad_Report{seen = 2, opened = 1, ignored = {"USB Gamepad", "Odd Stick"}})
	testing.expect(t, len(lines) == 3)
	testing.expect(t, strings.contains(lines[1], "\"USB Gamepad\"") && strings.contains(lines[1], "no standard controller mapping"))
	testing.expect(t, strings.contains(lines[2], "\"Odd Stick\""))
	// Unreadable files are only mentioned when SDL sees nothing.
	lines = gamepad_report_lines(Pad_Report{seen = 1, opened = 1, devices_exist = true, unreadable = "/dev/input/event3"})
	testing.expect_value(t, len(lines), 1)
}
