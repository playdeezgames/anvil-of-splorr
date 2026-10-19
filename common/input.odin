package common

// Frontends translate native events into Input_Events. Keyboard and gamepad events are mapped
// to Actions here, so every frontend gets identical bindings. Pointer events carry logical
// (SCREEN_W x SCREEN_H) coordinates and are interpreted by the tool against its own layout.

Action :: enum {
	Up,
	Down,
	Left,
	Right,
	Next_Channel,
	Prev_Channel,
	Select_R,
	Select_G,
	Select_B,
	Increase,
	Decrease,
	Increase_Big,
	Decrease_Big,
	Save,
	Load,
	Quit,
}

// Step sizes for Increase/Decrease and their _Big variants.
STEP_SMALL :: 1
STEP_BIG :: 16

Key :: enum {
	None,
	Left,
	Right,
	Up,
	Down,
	Tab,
	Page_Up,
	Page_Down,
	Plus, // '+' and '=' (same physical key on US layouts)
	Minus,
	R,
	G,
	B,
	S,
	L,
	Escape,
}

Pad_Button :: enum {
	Dpad_Up,
	Dpad_Down,
	Dpad_Left,
	Dpad_Right,
	A,
	B,
	X,
	Y,
	Left_Shoulder,
	Right_Shoulder,
	Start,
	Back,
	Guide,
}

Mouse_Button :: enum {
	Left,
	Right,
	Middle,
}

Key_Event :: struct {
	key:   Key,
	shift: bool,
	down:  bool, // key repeats should be sent as down events
}

Pad_Event :: struct {
	button: Pad_Button,
	down:   bool,
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

Input_Event :: union {
	Key_Event,
	Pad_Event,
	Mouse_Move,
	Mouse_Button_Event,
	Mouse_Wheel,
}

// Only key-down events map to actions.
key_to_action :: proc(e: Key_Event) -> (a: Action, ok: bool) {
	if !e.down {
		return {}, false
	}
	switch e.key {
	case .None:
		return {}, false
	case .Left:
		return .Left, true
	case .Right:
		return .Right, true
	case .Up:
		return .Up, true
	case .Down:
		return .Down, true
	case .Tab:
		return e.shift ? .Prev_Channel : .Next_Channel, true
	case .Page_Up:
		return .Increase_Big, true
	case .Page_Down:
		return .Decrease_Big, true
	case .Plus:
		return .Increase, true
	case .Minus:
		return .Decrease, true
	case .R:
		return .Select_R, true
	case .G:
		return .Select_G, true
	case .B:
		return .Select_B, true
	case .S:
		return .Save, true
	case .L:
		return .Load, true
	case .Escape:
		return .Quit, true
	}
	return {}, false
}

// Only button-down events map to actions.
pad_to_action :: proc(e: Pad_Event) -> (a: Action, ok: bool) {
	if !e.down {
		return {}, false
	}
	switch e.button {
	case .Dpad_Up:
		return .Up, true
	case .Dpad_Down:
		return .Down, true
	case .Dpad_Left:
		return .Left, true
	case .Dpad_Right:
		return .Right, true
	case .Left_Shoulder:
		return .Prev_Channel, true
	case .Right_Shoulder:
		return .Next_Channel, true
	case .A:
		return .Increase, true
	case .B:
		return .Decrease, true
	case .Y:
		return .Increase_Big, true
	case .X:
		return .Decrease_Big, true
	case .Start:
		return .Save, true
	case .Back:
		return .Load, true
	case .Guide:
		return .Quit, true
	}
	return {}, false
}
