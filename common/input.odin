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

// A key or pad button pressed while a tool is capturing a new binding (the controls editor). It is not
// an Input_Event: tools never see raw input unless they ask (Tool.wants_raw), and then the frontends
// hand the press to Tool.handle_raw *instead of* turning it into a command.
Raw_Input :: struct {
	from_pad: bool,
	key:      string, // keyboard: the KeyboardEvent.code name, or "" for a key outside the shared vocabulary
	button:   int, // pad: the standard-layout button index
}

// Pointer coordinates are logical (SCREEN_W x SCREEN_H) pixels.
Input_Event :: union {
	Command,
	Mouse_Move,
	Mouse_Button_Event,
	Mouse_Wheel,
}
