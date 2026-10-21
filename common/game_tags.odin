package common

import "core:encoding/json"
import "core:fmt"

// The tags a game needs a world to have, read from a hand-edited `game_tags.json` next to the
// game. The world editor checks a world against it (missing / unused / present) and can create the
// missing tags; a game checks the same list at start-up.
//
//   { "tags": [
//       { "name": "thing", "note": "what the player can pick up" },
//       { "name": "spawn", "note": "cells where the thing may appear" },
//       "solid" ] }
//
// A tag is an object with a "name" (and an optional one-line "note", up to GAME_TAG_NOTE_MAX
// printable ASCII characters) or just its name as text. Names follow the usual tag rules and must
// all be different; "solid" may be listed (every world has it). At most WORLD_MAX_TAGS tags.

GAME_TAG_NOTE_MAX :: 80

Game_Tag :: struct {
	name:     Name,
	note_len: int,
	note:     [GAME_TAG_NOTE_MAX]u8,
}

Game_Tags :: struct {
	count: int,
	tags:  [WORLD_MAX_TAGS]Game_Tag,
}

game_tag_note :: proc(g: ^Game_Tags, i: int) -> string {
	if i < 0 || i >= g.count {
		return ""
	}
	return string(g.tags[i].note[:g.tags[i].note_len])
}

game_tag_name :: proc(g: ^Game_Tags, i: int) -> string {
	if i < 0 || i >= g.count {
		return ""
	}
	return name_str(&g.tags[i].name)
}

// The index of a required tag by name.
game_tag_find :: proc(g: ^Game_Tags, name: string) -> int {
	for i in 0 ..< g.count {
		if name_str(&g.tags[i].name) == name {
			return i
		}
	}
	return -1
}

// Replaces dst only if the whole file is valid. err == "" means success. Error text is on the temp
// allocator: use it or copy it right away.
game_tags_from_json :: proc(data: []u8, dst: ^Game_Tags) -> (err: string) {
	val, perr := json.parse(data, .JSON, true, context.temp_allocator)
	if perr != .None {
		return "not valid JSON"
	}
	defer json.destroy_value(val, context.temp_allocator)
	root, is_obj := val.(json.Object)
	if !is_obj {
		return "the top level must be an object"
	}
	list, is_list := root["tags"].(json.Array)
	if !is_list {
		return `needs a "tags" list`
	}
	if len(list) > WORLD_MAX_TAGS {
		return fmt.tprintf("%d tags is more than the %d a world can have", len(list), WORLD_MAX_TAGS)
	}
	tmp := new(Game_Tags, context.temp_allocator)
	for item, i in list {
		name, note: string
		#partial switch v in item {
		case json.String:
			name = v
		case json.Object:
			n, name_ok := v["name"].(json.String)
			if !name_ok {
				return fmt.tprintf(`tag %d needs a "name"`, i)
			}
			name = n
			if raw, has := v["note"]; has {
				text, note_ok := raw.(json.String)
				if !note_ok {
					return fmt.tprintf(`tag "%s": "note" must be text`, name)
				}
				note = text
			}
		case:
			return fmt.tprintf("tag %d must be a name or an object", i)
		}
		if p := name_text_problem(name); p != .None {
			return fmt.tprintf(`tag %d: the name "%s" is %v`, i, name, name_problem_text(p))
		}
		if game_tag_find(tmp, name) >= 0 {
			return fmt.tprintf(`the tag "%s" is listed more than once`, name)
		}
		if len(note) > GAME_TAG_NOTE_MAX {
			return fmt.tprintf(`tag "%s": the note is longer than %d characters`, name, GAME_TAG_NOTE_MAX)
		}
		for k in 0 ..< len(note) {
			if note[k] < 32 || note[k] > 126 {
				return fmt.tprintf(`tag "%s": the note has a character other than printable ASCII`, name)
			}
		}
		name_assign(&tmp.tags[i].name, name)
		copy(tmp.tags[i].note[:], note)
		tmp.tags[i].note_len = len(note)
		tmp.count += 1
	}
	dst^ = tmp^
	return ""
}

Tag_Status :: enum {
	Missing, // required, but the world has no such tag
	Unused, // the world has it, but nothing sets or clears it
	Present, // the world has it and something uses it
}

// The status of required tag i in a world.
game_tag_status :: proc(w: ^World, g: ^Game_Tags, i: int) -> Tag_Status {
	ti := world_find_tag(w, game_tag_name(g, i))
	switch {
	case ti < 0:
		return .Missing
	case world_tag_uses(w, ti) == 0:
		return .Unused
	}
	return .Present
}

// Whether a world tag (by name) is one the game requires, and its index in the list (-1 if not).
world_tag_required :: proc(g: ^Game_Tags, w: ^World, tag: int) -> int {
	if tag < 0 || tag >= w.tag_count {
		return -1
	}
	return game_tag_find(g, name_str(&w.tags[tag]))
}

// The required tags the world lacks, in the file's order. On the temp allocator.
game_tags_missing :: proc(w: ^World, g: ^Game_Tags) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for i in 0 ..< g.count {
		if world_find_tag(w, game_tag_name(g, i)) < 0 {
			append(&out, game_tag_name(g, i))
		}
	}
	return out[:]
}

// Adds every missing required tag to the world, in the file's order. Returns how many were added and
// how many could not be (the world holds at most WORLD_MAX_TAGS).
world_create_missing_tags :: proc(w: ^World, g: ^Game_Tags) -> (created, no_room: int) {
	for name in game_tags_missing(w, g) {
		if w.tag_count >= WORLD_MAX_TAGS {
			no_room += 1
			continue
		}
		name_assign(&w.tags[w.tag_count], name)
		w.tag_count += 1
		created += 1
	}
	return
}
