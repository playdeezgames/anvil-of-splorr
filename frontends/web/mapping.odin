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
