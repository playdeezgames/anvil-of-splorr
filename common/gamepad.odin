package common

// Frontends snapshot each connected gamepad into a Pad_State every frame. Pads with the
// "standard" layout (the web Gamepad API's standard mapping, SDL's game controller API) use the
// fixed button/axis indices below; anything else is reported raw (indices as the device gives).

MAX_PADS :: 4
MAX_PAD_BUTTONS :: 36
MAX_PAD_AXES :: 8
STANDARD_BUTTON_COUNT :: 17
STANDARD_AXIS_COUNT :: 4
PAD_PRESS_THRESHOLD :: 0.5 // analog value at which a trigger counts as down

STANDARD_BUTTON_NAMES := [STANDARD_BUTTON_COUNT]string {
	"A", "B", "X", "Y", "LB", "RB", "LT", "RT", "BACK", "START", "LS", "RS", "UP", "DOWN", "LEFT", "RIGHT", "GUIDE",
}

STANDARD_AXIS_NAMES := [STANDARD_AXIS_COUNT]string{"LX", "LY", "RX", "RY"}

Pad_Button_State :: struct {
	down:  bool,
	value: f32, // 0..1; triggers are analog, other buttons are 0 or 1
}

Pad_State :: struct {
	connected:    bool,
	standard:     bool,
	name_len:     int,
	name_buf:     [64]u8,
	button_count: int,
	axis_count:   int,
	buttons:      [MAX_PAD_BUTTONS]Pad_Button_State,
	axes:         [MAX_PAD_AXES]f32, // -1..1, positive is right / down
}

Pads :: [MAX_PADS]Pad_State

pad_set_name :: proc(p: ^Pad_State, s: string) {
	p.name_len = min(len(s), len(p.name_buf))
	copy(p.name_buf[:], s[:p.name_len])
}

pad_name :: proc(p: ^Pad_State) -> string {
	return string(p.name_buf[:p.name_len])
}

// Standard-layout button index -> the button the editors bind commands to. Not every standard
// button is bound: triggers and stick clicks are deliberately absent.
pad_button_for_index :: proc(i: int) -> (Pad_Button, bool) {
	switch i {
	case 0:
		return .A, true
	case 1:
		return .B, true
	case 2:
		return .X, true
	case 3:
		return .Y, true
	case 4:
		return .Left_Shoulder, true
	case 5:
		return .Right_Shoulder, true
	case 8:
		return .Back, true
	case 9:
		return .Start, true
	case 12:
		return .Dpad_Up, true
	case 13:
		return .Dpad_Down, true
	case 14:
		return .Dpad_Left, true
	case 15:
		return .Dpad_Right, true
	case 16:
		return .Guide, true
	}
	return {}, false
}

pad_pressed_set :: proc(p: ^Pad_State) -> (set: bit_set[Pad_Button]) {
	if !p.connected || !p.standard {
		return
	}
	for i in 0 ..< min(p.button_count, STANDARD_BUTTON_COUNT) {
		if b, ok := pad_button_for_index(i); ok && p.buttons[i].down {
			set += {b}
		}
	}
	return
}

// Buttons that went down / up between two snapshots (bound buttons of standard pads only).
pad_edges :: proc(prev, now: ^Pad_State) -> (pressed, released: bit_set[Pad_Button]) {
	a, b := pad_pressed_set(prev), pad_pressed_set(now)
	return b - a, a - b
}
