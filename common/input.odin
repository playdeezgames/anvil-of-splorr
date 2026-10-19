package common

// Frontends translate native events into Input_Events. Keyboard keys and gamepad buttons never
// reach a tool directly: the Input_Map (input_map.odin, loaded from input_map.json) turns them
// into one of eight commands, so every frontend and tool sees identical bindings.

Action :: enum {
	Up,
	Down,
	Left,
	Right,
	Green,
	Red,
	Blue,
	Yellow,
}

// Step sizes the editor uses for fine and coarse value changes.
STEP_SMALL :: 1
STEP_BIG :: 16

// A command from the keyboard or a gamepad, sent on press (and on key repeat). `from_pad` lets a
// diagnostic tool tell the two apart; ordinary tools must not care.
Command :: struct {
	action:   Action,
	from_pad: bool,
}

Mouse_Button :: enum {
	Left,
	Right,
	Middle,
}

Mouse_Move :: struct {
	x, y: int,
}

Mouse_Button_Event :: struct {
	button: Mouse_Button,
	x, y:   int,
	down:   bool,
}

// dy > 0 means scrolled up/away from the user.
Mouse_Wheel :: struct {
	dy: int,
}

// Pointer coordinates are logical (SCREEN_W x SCREEN_H) pixels.
Input_Event :: union {
	Command,
	Mouse_Move,
	Mouse_Button_Event,
	Mouse_Wheel,
}
