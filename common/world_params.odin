package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Game parameters: named values a game reads from the world instead of hard-coding, such as the
// length of a round or the points a pickup gives. Each is a whole number (32-bit) or a short text
// (up to PARAM_TEXT_MAX printable ASCII characters). A world holds up to WORLD_MAX_PARAMS, with
// unique names of 1..32 printable ASCII characters. They are edited from the PARAMS row of the
// world editor; a game reads them by name with a default for the ones the world lacks.

WORLD_MAX_PARAMS :: 64
PARAM_TEXT_MAX :: NAME_MAX // 32, the most the keypad can type
PARAM_NUMBER_MIN :: -2147483648
PARAM_NUMBER_MAX :: 2147483647

Param_Kind :: enum {
	Number,
	Text,
}

Param :: struct {
	name:   Name,
	kind:   Param_Kind,
	number: int, // used when kind is Number (PARAM_NUMBER_MIN..PARAM_NUMBER_MAX)
	text:   Name, // used when kind is Text
}

world_find_param :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.param_count {
		if i != except && name_str(&w.params[i].name) == name {
			return i
		}
	}
	return -1
}

world_check_param_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_param(w, name, index) >= 0 ? .In_Use : .None
}

@(private = "file")
param_names :: proc(w: ^World) -> []string {
	out := make([]string, w.param_count, context.temp_allocator)
	for i in 0 ..< w.param_count {
		out[i] = name_str(&w.params[i].name)
	}
	return out
}

// Adds a parameter named after `base` (made unique), a number worth 0. Returns its index, or -1 if
// the world has 64.
world_add_param :: proc(w: ^World, base := "param") -> int {
	if w.param_count >= WORLD_MAX_PARAMS {
		return -1
	}
	i := w.param_count
	w.params[i] = {}
	name_assign(&w.params[i].name, unique_among(base, param_names(w)))
	w.param_count += 1
	return i
}

// Copies parameter i right after itself as "<name>_copy" (made unique). Returns the new index or -1
// if the world has 64 or i is bad.
world_duplicate_param :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.param_count || w.param_count >= WORLD_MAX_PARAMS {
		return -1
	}
	at := i + 1
	for k := w.param_count; k > at; k -= 1 {
		w.params[k] = w.params[k - 1]
	}
	w.params[at] = w.params[i]
	name_assign(&w.params[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.params[i].name)), param_names(w)))
	w.param_count += 1
	return at
}

world_delete_param :: proc(w: ^World, i: int) -> bool {
	if i < 0 || i >= w.param_count {
		return false
	}
	for k in i ..< w.param_count - 1 {
		w.params[k] = w.params[k + 1]
	}
	w.params[w.param_count - 1] = {}
	w.param_count -= 1
	return true
}

world_rename_param :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.param_count {
		return .Empty
	}
	if p := world_check_param_name(w, i, name); p != .None {
		return p
	}
	name_assign(&w.params[i].name, name)
	return .None
}

// Sets a number (clamped to 32 bits) and makes the parameter a number. Returns false for a bad index.
world_set_param_number :: proc(w: ^World, i, value: int) -> bool {
	if i < 0 || i >= w.param_count {
		return false
	}
	w.params[i].kind = .Number
	w.params[i].number = clamp(value, PARAM_NUMBER_MIN, PARAM_NUMBER_MAX)
	return true
}

// Sets a text and makes the parameter a text. The empty text is fine; too long or non-ASCII is not
// (nothing changes then).
world_set_param_text :: proc(w: ^World, i: int, text: string) -> Name_Problem {
	if i < 0 || i >= w.param_count {
		return .Empty
	}
	if len(text) > PARAM_TEXT_MAX {
		return .Too_Long
	}
	for k in 0 ..< len(text) {
		if text[k] < 32 || text[k] > 126 {
			return .Bad_Character
		}
	}
	w.params[i].kind = .Text
	name_assign(&w.params[i].text, text)
	return .None
}

// Switches a parameter between number and text; the other value is kept for switching back.
world_toggle_param_kind :: proc(w: ^World, i: int) -> bool {
	if i < 0 || i >= w.param_count {
		return false
	}
	w.params[i].kind = w.params[i].kind == .Number ? .Text : .Number
	return true
}

// The value as text: "60", or the text itself.
param_value_text :: proc(p: ^Param) -> string {
	if p.kind == .Number {
		return fmt.tprintf("%d", p.number)
	}
	return name_str(&p.text)
}

// A number by name, or `default` if the world has no such parameter or it is a text.
world_param_number :: proc(w: ^World, name: string, default: int) -> int {
	i := world_find_param(w, name)
	if i < 0 || w.params[i].kind != .Number {
		return default
	}
	return w.params[i].number
}

// A text by name, or `default` if the world has no such parameter or it is a number.
world_param_text :: proc(w: ^World, name: string, default: string) -> string {
	i := world_find_param(w, name)
	if i < 0 || w.params[i].kind != .Text {
		return default
	}
	return name_str(&w.params[i].text)
}

// --- File format -------------------------------------------------------------------------------
//
//   "params": [ { "name": "round_seconds", "number": 60 }, { "name": "title", "text": "Go Get It" } ]
// Each entry has a name and exactly one of "number" (a whole number within 32 bits) and "text" (up to
// PARAM_TEXT_MAX printable ASCII characters). Optional when reading: a world from before parameters
// has none.

write_params :: proc(b: ^strings.Builder, w: ^World) {
	strings.write_string(b, "  \"params\": [")
	for i in 0 ..< w.param_count {
		p := &w.params[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		if p.kind == .Number {
			fmt.sbprintf(b, "    {{\"name\": \"%s\", \"number\": %d}}", escape_name(name_str(&p.name)), p.number)
		} else {
			fmt.sbprintf(b, "    {{\"name\": \"%s\", \"text\": \"%s\"}}", escape_name(name_str(&p.name)), escape_name(name_str(&p.text)))
		}
	}
	strings.write_string(b, w.param_count == 0 ? "],\n" : "\n  ],\n")
}

read_params :: proc(root: json.Object, tmp: ^World) -> (err: string) {
	v, present := root["params"]
	if !present {
		return ""
	}
	list, is_list := v.(json.Array)
	if !is_list {
		return `"params" must be a list`
	}
	if len(list) > WORLD_MAX_PARAMS {
		return fmt.tprintf("%d parameters is more than the %d allowed", len(list), WORLD_MAX_PARAMS)
	}
	for item, i in list {
		obj, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("parameter %d must be an object", i)
		}
		name, name_ok := obj["name"].(json.String)
		if !name_ok {
			return fmt.tprintf(`parameter %d: "name" must be text`, i)
		}
		if p := world_check_param_name(tmp, -1, name); p != .None {
			return fmt.tprintf(`parameter %d: the name "%s" is %v`, i, name, name_problem_text(p))
		}
		number, has_number := obj["number"]
		text, has_text := obj["text"]
		if has_number == has_text {
			return fmt.tprintf(`parameter "%s" needs exactly one of "number" and "text"`, name)
		}
		p := &tmp.params[i]
		name_assign(&p.name, name)
		if has_number {
			n, n_ok := number.(json.Integer)
			if !n_ok || n < PARAM_NUMBER_MIN || n > PARAM_NUMBER_MAX {
				return fmt.tprintf(`parameter "%s": "number" must be a whole number from %d to %d`, name, PARAM_NUMBER_MIN, PARAM_NUMBER_MAX)
			}
			p.kind, p.number = .Number, int(n)
		} else {
			s, s_ok := text.(json.String)
			if !s_ok {
				return fmt.tprintf(`parameter "%s": "text" must be text`, name)
			}
			tmp.param_count = i + 1
			if problem := world_set_param_text(tmp, i, s); problem != .None {
				return fmt.tprintf(`parameter "%s": the text is %v (at most %d printable ASCII characters)`, name, name_problem_text(problem), PARAM_TEXT_MAX)
			}
		}
		tmp.param_count = i + 1
	}
	return ""
}
