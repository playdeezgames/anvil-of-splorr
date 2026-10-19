package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Which keyboard keys and gamepad buttons mean which command. Stored as input_map.json, which the
// user can edit by hand:
//
//   { "gamepad":  { "up": 12, "red": 0, ... },       standard-layout button index (see the Gamepad Tester)
//     "keyboard": { "up": "ArrowUp", "red": "KeyR" }, KeyboardEvent.code names, see KNOWN below
//     "labels":   { "green": "SPACE", ... }          what the tools call each command on screen
//   }
//
// A command left out keeps its default; null unbinds it (for a label, null means the command name). Keys starting with "_" are ignored
// (use them for notes). Loading is strict: unknown commands, bad values and two commands on one
// input are errors, and the caller falls back to the defaults.

KEY_NAME_CAP :: 24
LABEL_CAP :: 12 // longest label; keeps the editors' help lines on screen

Key_Name :: struct {
	buf: [KEY_NAME_CAP]u8,
	len: int, // 0 = unbound
}

NO_BUTTON :: -1

Input_Map :: struct {
	pad:    [Action]int, // standard-layout button index, or NO_BUTTON
	keys:   [Action]Key_Name,
	labels: [Action]Key_Name, // on-screen name of each command; empty means the default (the command name)
}

ACTION_NAMES := [Action]string {
	.Up     = "up",
	.Down   = "down",
	.Left   = "left",
	.Right  = "right",
	.Green  = "green",
	.Red    = "red",
	.Blue   = "blue",
	.Yellow = "yellow",
}

// What tools call each command on screen unless input_map.json says otherwise.
DEFAULT_LABELS := [Action]string {
	.Up     = "UP",
	.Down   = "DOWN",
	.Left   = "LEFT",
	.Right  = "RIGHT",
	.Green  = "GREEN",
	.Red    = "RED",
	.Blue   = "BLUE",
	.Yellow = "YELLOW",
}

// Every key name a binding may use. These are browser KeyboardEvent.code values (layout
// independent); the SDL2 frontend translates its scancodes to the same names.
LETTER_CODES := [26]string{"KeyA", "KeyB", "KeyC", "KeyD", "KeyE", "KeyF", "KeyG", "KeyH", "KeyI", "KeyJ", "KeyK", "KeyL", "KeyM", "KeyN", "KeyO", "KeyP", "KeyQ", "KeyR", "KeyS", "KeyT", "KeyU", "KeyV", "KeyW", "KeyX", "KeyY", "KeyZ"}
DIGIT_CODES := [10]string{"Digit0", "Digit1", "Digit2", "Digit3", "Digit4", "Digit5", "Digit6", "Digit7", "Digit8", "Digit9"}
NAMED_CODES := [?]string{"ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space", "Enter", "Tab", "Backspace", "Escape", "Comma", "Period", "Slash", "Semicolon", "Quote", "BracketLeft", "BracketRight", "Minus", "Equal", "Backquote", "Backslash"}

is_known_key_code :: proc(s: string) -> bool {
	for c in LETTER_CODES {
		if c == s {
			return true
		}
	}
	for c in DIGIT_CODES {
		if c == s {
			return true
		}
	}
	for c in NAMED_CODES {
		if c == s {
			return true
		}
	}
	return false
}

key_name :: proc(k: ^Key_Name) -> string {
	return string(k.buf[:k.len])
}

set_key_name :: proc(k: ^Key_Name, s: string) {
	k^ = {} // no stale bytes, so equal maps compare equal
	k.len = min(len(s), KEY_NAME_CAP)
	copy(k.buf[:], s[:k.len])
}

default_input_map :: proc() -> (m: Input_Map) {
	pad := [Action]int {
		.Up     = 12,
		.Down   = 13,
		.Left   = 14,
		.Right  = 15,
		.Red    = 0,
		.Green  = 1,
		.Blue   = 9,
		.Yellow = 8,
	}
	keys := [Action]string {
		.Up     = "ArrowUp",
		.Down   = "ArrowDown",
		.Left   = "ArrowLeft",
		.Right  = "ArrowRight",
		.Red    = "Escape",
		.Green  = "Space",
		.Blue   = "Enter",
		.Yellow = "Tab",
	}
	for a in Action {
		m.pad[a] = pad[a]
		set_key_name(&m.keys[a], keys[a])
		set_key_name(&m.labels[a], DEFAULT_LABELS[a])
	}
	return
}

// The text to show for a command. A nil map gives the defaults (handy in tests).
action_label :: proc(m: ^Input_Map, a: Action) -> string {
	if m == nil || m.labels[a].len == 0 {
		return DEFAULT_LABELS[a]
	}
	return key_name(&m.labels[a])
}

action_for_pad_button :: proc(m: ^Input_Map, index: int) -> (Action, bool) {
	for a in Action {
		if m.pad[a] == index {
			return a, true
		}
	}
	return {}, false
}

action_for_key :: proc(m: ^Input_Map, code: string) -> (Action, bool) {
	if code == "" {
		return {}, false
	}
	for a in Action {
		if key_name(&m.keys[a]) == code {
			return a, true
		}
	}
	return {}, false
}

NOTE :: "Gamepad values are standard-layout button indices (the Gamepad Tester shows them); keyboard values are KeyboardEvent.code names such as KeyR or ArrowUp. Use null to unbind a command; a command left out keeps its default. Labels are what the tools call each command on screen (max 12 characters), e.g. SPACE or A BUTTON."

input_map_to_json :: proc(map_in: Input_Map, allocator := context.temp_allocator) -> string {
	m := map_in
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n  \"_note\": \"%s\",\n  \"gamepad\": {{\n", NOTE)
	for a in Action {
		sep := a == max(Action) ? "" : ","
		if m.pad[a] == NO_BUTTON {
			fmt.sbprintf(&b, "    \"%s\": null%s\n", ACTION_NAMES[a], sep)
		} else {
			fmt.sbprintf(&b, "    \"%s\": %d%s\n", ACTION_NAMES[a], m.pad[a], sep)
		}
	}
	strings.write_string(&b, "  },\n  \"keyboard\": {\n")
	for a in Action {
		sep := a == max(Action) ? "" : ","
		if m.keys[a].len == 0 {
			fmt.sbprintf(&b, "    \"%s\": null%s\n", ACTION_NAMES[a], sep)
		} else {
			fmt.sbprintf(&b, "    \"%s\": \"%s\"%s\n", ACTION_NAMES[a], key_name(&m.keys[a]), sep)
		}
	}
	strings.write_string(&b, "  },\n  \"labels\": {\n")
	for a in Action {
		sep := a == max(Action) ? "" : ","
		fmt.sbprintf(&b, "    \"%s\": \"%s\"%s\n", ACTION_NAMES[a], action_label(&m, a), sep)
	}
	strings.write_string(&b, "  }\n}\n")
	return strings.to_string(b)
}

// err == "" means success. Error text lives on the temp allocator; use or copy it right away.
input_map_from_json :: proc(data: []u8) -> (m: Input_Map, err: string) {
	val, perr := json.parse(data, .JSON, true, context.temp_allocator)
	if perr != .None {
		return {}, "not valid JSON"
	}
	defer json.destroy_value(val, context.temp_allocator)
	root, is_obj := val.(json.Object)
	if !is_obj {
		return {}, "the top level must be an object"
	}

	m = default_input_map()
	for name, section in root {
		switch name {
		case "gamepad":
			obj, ok := section.(json.Object)
			if !ok {
				return {}, `"gamepad" must be an object`
			}
			if e := read_pad_section(&m, obj); e != "" {
				return {}, e
			}
		case "keyboard":
			obj, ok := section.(json.Object)
			if !ok {
				return {}, `"keyboard" must be an object`
			}
			if e := read_key_section(&m, obj); e != "" {
				return {}, e
			}
		case "labels":
			obj, ok := section.(json.Object)
			if !ok {
				return {}, `"labels" must be an object`
			}
			if e := read_label_section(&m, obj); e != "" {
				return {}, e
			}
		case:
			if !strings.has_prefix(name, "_") {
				return {}, fmt.tprintf(`unknown section "%s" (expected "gamepad", "keyboard" or "labels")`, name)
			}
		}
	}

	for a in Action {
		for b in Action {
			if a >= b {
				continue
			}
			if m.pad[a] != NO_BUTTON && m.pad[a] == m.pad[b] {
				return {}, fmt.tprintf(`gamepad button %d is bound to both "%s" and "%s"`, m.pad[a], ACTION_NAMES[a], ACTION_NAMES[b])
			}
			if m.keys[a].len > 0 && key_name(&m.keys[a]) == key_name(&m.keys[b]) {
				return {}, fmt.tprintf(`key %s is bound to both "%s" and "%s"`, key_name(&m.keys[a]), ACTION_NAMES[a], ACTION_NAMES[b])
			}
		}
	}
	return m, ""
}

@(private = "file")
action_from_name :: proc(name: string) -> (Action, bool) {
	for a in Action {
		if ACTION_NAMES[a] == name {
			return a, true
		}
	}
	return {}, false
}

@(private = "file")
read_pad_section :: proc(m: ^Input_Map, obj: json.Object) -> string {
	for name, v in obj {
		if strings.has_prefix(name, "_") {
			continue
		}
		a, ok := action_from_name(name)
		if !ok {
			return fmt.tprintf(`gamepad: unknown command "%s"`, name)
		}
		#partial switch x in v {
		case json.Null:
			m.pad[a] = NO_BUTTON
		case json.Integer:
			if x < 0 || x >= STANDARD_BUTTON_COUNT {
				return fmt.tprintf(`gamepad "%s": button %d is out of range (0 to %d)`, name, x, STANDARD_BUTTON_COUNT - 1)
			}
			m.pad[a] = int(x)
		case:
			return fmt.tprintf(`gamepad "%s": expected a button number or null`, name)
		}
	}
	return ""
}

@(private = "file")
read_key_section :: proc(m: ^Input_Map, obj: json.Object) -> string {
	for name, v in obj {
		if strings.has_prefix(name, "_") {
			continue
		}
		a, ok := action_from_name(name)
		if !ok {
			return fmt.tprintf(`keyboard: unknown command "%s"`, name)
		}
		#partial switch x in v {
		case json.Null:
			m.keys[a] = {}
		case json.String:
			if !is_known_key_code(x) {
				return fmt.tprintf(`keyboard "%s": unknown key "%s"`, name, x)
			}
			set_key_name(&m.keys[a], x)
		case:
			return fmt.tprintf(`keyboard "%s": expected a key name or null`, name)
		}
	}
	return ""
}

@(private = "file")
read_label_section :: proc(m: ^Input_Map, obj: json.Object) -> string {
	for name, v in obj {
		if strings.has_prefix(name, "_") {
			continue
		}
		a, ok := action_from_name(name)
		if !ok {
			return fmt.tprintf(`labels: unknown command "%s"`, name)
		}
		#partial switch x in v {
		case json.Null:
			m.labels[a] = {}
		case json.String:
			if len(x) > LABEL_CAP {
				return fmt.tprintf(`labels "%s": "%s" is longer than %d characters`, name, x, LABEL_CAP)
			}
			set_key_name(&m.labels[a], x)
		case:
			return fmt.tprintf(`labels "%s": expected text or null`, name)
		}
	}
	return ""
}
