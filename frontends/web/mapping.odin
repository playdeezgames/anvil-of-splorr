package main

import cm "../../common"

// Browser KeyboardEvent.code -> common key. Codes are layout independent.
key_for_code :: proc(code: string) -> cm.Key {
	switch code {
	case "ArrowLeft":
		return .Left
	case "ArrowRight":
		return .Right
	case "ArrowUp":
		return .Up
	case "ArrowDown":
		return .Down
	case "Tab":
		return .Tab
	case "PageUp":
		return .Page_Up
	case "PageDown":
		return .Page_Down
	case "Equal", "NumpadAdd":
		return .Plus
	case "Minus", "NumpadSubtract":
		return .Minus
	case "KeyR":
		return .R
	case "KeyG":
		return .G
	case "KeyB":
		return .B
	case "KeyS":
		return .S
	case "KeyL":
		return .L
	case "Escape":
		return .Escape
	}
	return .None
}

// Index into Gamepad.buttons for pads whose mapping is "standard".
pad_button_for_index :: proc(i: int) -> (cm.Pad_Button, bool) {
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
