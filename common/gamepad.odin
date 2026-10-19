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

// Bitmask of standard-layout buttons that are down (empty for disconnected / non-standard pads).
Button_Set :: bit_set[0 ..< STANDARD_BUTTON_COUNT;u32]

pad_down_set :: proc(p: ^Pad_State) -> (set: Button_Set) {
	if !p.connected || !p.standard {
		return
	}
	for i in 0 ..< min(p.button_count, STANDARD_BUTTON_COUNT) {
		if p.buttons[i].down {
			set += {i}
		}
	}
	return
}

// Standard buttons that went down / up between two snapshots.
pad_edges :: proc(prev, now: ^Pad_State) -> (pressed, released: Button_Set) {
	a, b := pad_down_set(prev), pad_down_set(now)
	return b - a, a - b
}
