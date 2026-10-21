package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Sounds: short tunes and effects, each a name and a text in the style of Microsoft BASIC's PLAY
// statement ("T120 O4 L8 C D E P8 G4."), played by one square-wave voice (see SOUND.md). A world holds
// up to WORLD_MAX_SOUNDS, with unique names of 1..32 printable ASCII characters; the text is up to
// SOUND_TEXT_MAX printable ASCII characters and may be empty (a silent sound) or not yet valid PLAY
// text, since checking it belongs to the parser (play_text.odin), not to the world. A sound may loop.

WORLD_MAX_SOUNDS :: 64
SOUND_TEXT_MAX :: 1024

Sound :: struct {
	name:     Name,
	text_len: int,
	text:     [SOUND_TEXT_MAX]u8,
	loop:     bool, // a game plays it again and again until told to stop
}

sound_text :: proc(s: ^Sound) -> string {
	return string(s.text[:s.text_len])
}

world_find_sound :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.sound_count {
		if i != except && name_str(&w.sounds[i].name) == name {
			return i
		}
	}
	return -1
}

world_check_sound_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_sound(w, name, index) >= 0 ? .In_Use : .None
}

// Only printable ASCII, at most SOUND_TEXT_MAX characters; the empty text is fine.
sound_text_problem :: proc(text: string) -> Name_Problem {
	if len(text) > SOUND_TEXT_MAX {
		return .Too_Long
	}
	for i in 0 ..< len(text) {
		if text[i] < 32 || text[i] > 126 {
			return .Bad_Character
		}
	}
	return .None
}

@(private = "file")
sound_names :: proc(w: ^World) -> []string {
	out := make([]string, w.sound_count, context.temp_allocator)
	for i in 0 ..< w.sound_count {
		out[i] = name_str(&w.sounds[i].name)
	}
	return out
}

// Adds an empty, non-looping sound named after `base` (made unique). Returns its index, or -1 if the
// world has 64.
world_add_sound :: proc(w: ^World, base := "sound") -> int {
	if w.sound_count >= WORLD_MAX_SOUNDS {
		return -1
	}
	i := w.sound_count
	w.sounds[i] = {}
	name_assign(&w.sounds[i].name, unique_among(base, sound_names(w)))
	w.sound_count += 1
	return i
}

// Copies sound i right after itself as "<name>_copy" (made unique). Returns the new index or -1 if
// the world has 64 or i is bad.
world_duplicate_sound :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.sound_count || w.sound_count >= WORLD_MAX_SOUNDS {
		return -1
	}
	at := i + 1
	for k := w.sound_count; k > at; k -= 1 {
		w.sounds[k] = w.sounds[k - 1]
	}
	w.sounds[at] = w.sounds[i]
	name_assign(&w.sounds[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.sounds[i].name)), sound_names(w)))
	w.sound_count += 1
	return at
}

world_delete_sound :: proc(w: ^World, i: int) -> bool {
	if i < 0 || i >= w.sound_count {
		return false
	}
	for k in i ..< w.sound_count - 1 {
		w.sounds[k] = w.sounds[k + 1]
	}
	w.sounds[w.sound_count - 1] = {}
	w.sound_count -= 1
	return true
}

world_rename_sound :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.sound_count {
		return .Empty
	}
	if p := world_check_sound_name(w, i, name); p != .None {
		return p
	}
	name_assign(&w.sounds[i].name, name)
	return .None
}

// Replaces a sound's text. Nothing changes unless the text is acceptable (see sound_text_problem).
world_set_sound_text :: proc(w: ^World, i: int, text: string) -> Name_Problem {
	if i < 0 || i >= w.sound_count {
		return .Empty
	}
	if p := sound_text_problem(text); p != .None {
		return p
	}
	s := &w.sounds[i]
	s.text = {}
	copy(s.text[:], text)
	s.text_len = len(text)
	return .None
}

world_set_sound_loop :: proc(w: ^World, i: int, loop: bool) -> bool {
	if i < 0 || i >= w.sound_count {
		return false
	}
	w.sounds[i].loop = loop
	return true
}

// --- File format -------------------------------------------------------------------------------
//
//   "sounds": [ { "name": "pickup", "text": "T200 O5 L16 C E G >C", "loop": false } ]
// "loop" is optional (false); "text" may be empty. Optional when reading: a world from before sounds
// has none.

write_sounds :: proc(b: ^strings.Builder, w: ^World) {
	strings.write_string(b, "  \"sounds\": [")
	for i in 0 ..< w.sound_count {
		s := &w.sounds[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(b, "    {{\"name\": \"%s\", \"text\": \"%s\", \"loop\": %v}}", escape_name(name_str(&s.name)), escape_name(sound_text(s)), s.loop)
	}
	strings.write_string(b, w.sound_count == 0 ? "],\n" : "\n  ],\n")
}

read_sounds :: proc(root: json.Object, tmp: ^World) -> (err: string) {
	v, present := root["sounds"]
	if !present {
		return ""
	}
	list, is_list := v.(json.Array)
	if !is_list {
		return `"sounds" must be a list`
	}
	if len(list) > WORLD_MAX_SOUNDS {
		return fmt.tprintf("%d sounds is more than the %d allowed", len(list), WORLD_MAX_SOUNDS)
	}
	for item, i in list {
		obj, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("sound %d must be an object", i)
		}
		name, name_ok := obj["name"].(json.String)
		if !name_ok {
			return fmt.tprintf(`sound %d: "name" must be text`, i)
		}
		if p := world_check_sound_name(tmp, -1, name); p != .None {
			return fmt.tprintf(`sound %d: the name "%s" is %v`, i, name, name_problem_text(p))
		}
		text := ""
		if tv, has_text := obj["text"]; has_text {
			t, t_ok := tv.(json.String)
			if !t_ok {
				return fmt.tprintf(`sound "%s": "text" must be text`, name)
			}
			text = t
		}
		loop := false
		if lv, has_loop := obj["loop"]; has_loop {
			l, l_ok := lv.(json.Boolean)
			if !l_ok {
				return fmt.tprintf(`sound "%s": "loop" must be true or false`, name)
			}
			loop = bool(l)
		}
		tmp.sound_count = i + 1
		tmp.sounds[i] = {}
		name_assign(&tmp.sounds[i].name, name)
		if problem := world_set_sound_text(tmp, i, text); problem != .None {
			return fmt.tprintf(`sound "%s": the text is %v (at most %d printable ASCII characters)`, name, name_problem_text(problem), SOUND_TEXT_MAX)
		}
		tmp.sounds[i].loop = loop
	}
	return ""
}
