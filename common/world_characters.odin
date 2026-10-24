package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Characters of a world. A character type (name + the sprite it draws) describes what every
// instance shares; a character is an instance: a uuid, a name and its type. All characters live in
// one table of the world; a map cell, and the world's player, refer to a character by its uuid.
// A character stands in at most one cell of the whole world, or on no map at all.

Uuid :: [16]u8

UUID_NONE :: Uuid{}

uuid_is_none :: proc(u: Uuid) -> bool {
	return u == UUID_NONE
}

// "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17": lower case hex, 8-4-4-4-12.
uuid_to_string :: proc(u: Uuid) -> string {
	return fmt.tprintf(
		"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
		u[0],
		u[1],
		u[2],
		u[3],
		u[4],
		u[5],
		u[6],
		u[7],
		u[8],
		u[9],
		u[10],
		u[11],
		u[12],
		u[13],
		u[14],
		u[15],
	)
}

// The first 8 hex digits, which is what the editors show.
uuid_short :: proc(u: Uuid) -> string {
	return fmt.tprintf("%02x%02x%02x%02x", u[0], u[1], u[2], u[3])
}

// Strict: exactly the form uuid_to_string writes (upper case digits are accepted too).
uuid_from_string :: proc(s: string) -> (u: Uuid, ok: bool) {
	if len(s) != 36 {
		return {}, false
	}
	n := 0
	for i in 0 ..< 36 {
		c := s[i]
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return {}, false
			}
			continue
		}
		v: u8
		switch {
		case c >= '0' && c <= '9':
			v = c - '0'
		case c >= 'a' && c <= 'f':
			v = c - 'a' + 10
		case c >= 'A' && c <= 'F':
			v = c - 'A' + 10
		case:
			return {}, false
		}
		if n % 2 == 0 {
			u[n / 2] = v << 4
		} else {
			u[n / 2] |= v
		}
		n += 1
	}
	return u, true
}

// Seeds the uuid generator (the frontends use the clock; tests use a fixed number).
world_seed_uuids :: proc(w: ^World, seed: u64) {
	w.uuid_state = seed
}

@(private = "file")
next_u64 :: proc(w: ^World) -> u64 { 	// splitmix64
	w.uuid_state += 0x9E3779B97F4A7C15
	z := w.uuid_state
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

// A random version 4 uuid that no character of the world has.
world_new_uuid :: proc(w: ^World) -> Uuid {
	for {
		a, b := next_u64(w), next_u64(w)
		u: Uuid
		for i in 0 ..< 8 {
			u[i] = u8(a >> uint(8 * i))
			u[8 + i] = u8(b >> uint(8 * i))
		}
		u[6] = u[6] & 0x0F | 0x40 // version 4
		u[8] = u[8] & 0x3F | 0x80 // variant
		if world_find_character(w, u) < 0 && world_find_feature(w, u) < 0 && world_find_inventory(w, u) < 0 && world_find_trigger(w, u) < 0 {
			return u
		}
	}
}

// --- Character types ---------------------------------------------------------------------------

Character_Type :: struct {
	name:       Name,
	sprite_set: Name, // empty = not set
	sprite:     Name, // the sprite's name within that set; empty = not set
	tags:       Tag_Mask, // the tags every character of this type has (unless its own settings say otherwise)
	props:      Prop_Set, // the numeric properties every character of the type has, with their defaults
}

Character :: struct {
	uuid: Uuid,
	name: Name, // a label: not unique
	type: Name, // the character type, by name
	tags_set, tags_cleared: Tag_Mask, // its own tag settings; a tag in neither is inherited from the type
	inventory: Uuid, // the inventory it carries, or none (world_items.odin)
	overrides: Prop_Overrides, // its own values of its type's properties (the others are the defaults)
}

world_find_char_type :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.char_type_count {
		if i != except && name_str(&w.char_types[i].name) == name {
			return i
		}
	}
	return -1
}

world_check_char_type_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_char_type(w, name, index) >= 0 ? .In_Use : .None
}

@(private = "file")
char_type_names :: proc(w: ^World) -> []string {
	out := make([]string, w.char_type_count, context.temp_allocator)
	for i in 0 ..< w.char_type_count {
		out[i] = name_str(&w.char_types[i].name)
	}
	return out
}

// The sprite a character type draws, or nil while it is not set (or points at nothing).
world_char_type_sprite :: proc(w: ^World, ct: ^Character_Type) -> ^Sprite {
	si := world_find_sprite_set(w, name_str(&ct.sprite_set))
	if si < 0 {
		return nil
	}
	i := sprite_set_find(&w.sprite_sets[si], name_str(&ct.sprite))
	return i >= 0 ? &w.sprite_sets[si].sprites[i] : nil
}

// Points a type at the first sprite of the first sprite set that has one; not set if none.
world_char_type_point_at_first :: proc(w: ^World, ct: ^Character_Type) {
	ct.sprite_set, ct.sprite = {}, {}
	for si in 0 ..< w.sprite_set_count {
		if w.sprite_sets[si].count > 0 {
			ct.sprite_set = w.sprite_sets[si].name
			ct.sprite = w.sprite_sets[si].sprites[0].name
			return
		}
	}
}

// Adds a character type ("character_type") drawing the first sprite. Returns its index or -1 if full.
world_add_char_type :: proc(w: ^World, base := "character_type") -> int {
	if w.char_type_count >= WORLD_MAX_CHARACTER_TYPES {
		return -1
	}
	i := w.char_type_count
	w.char_types[i] = {}
	name_assign(&w.char_types[i].name, unique_among(base, char_type_names(w)))
	world_char_type_point_at_first(w, &w.char_types[i])
	w.char_type_count += 1
	return i
}

// Copies type i right after itself as "<name>_copy". Returns the new index or -1 if full.
world_duplicate_char_type :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.char_type_count || w.char_type_count >= WORLD_MAX_CHARACTER_TYPES {
		return -1
	}
	at := i + 1
	for k := w.char_type_count; k > at; k -= 1 {
		w.char_types[k] = w.char_types[k - 1]
	}
	w.char_types[at] = w.char_types[i]
	name_assign(&w.char_types[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.char_types[i].name)), char_type_names(w)))
	w.char_type_count += 1
	return at
}

// How many characters have this type.
world_char_type_uses :: proc(w: ^World, name: string) -> (n: int) {
	for i in 0 ..< w.character_count {
		if name_str(&w.characters[i].type) == name {
			n += 1
		}
	}
	return
}

// Deletes type i unless a character has it. Returns the number of characters in the way (0 = done).
world_delete_char_type :: proc(w: ^World, i: int) -> (uses: int) {
	if i < 0 || i >= w.char_type_count {
		return 0
	}
	if uses = world_char_type_uses(w, name_str(&w.char_types[i].name)); uses > 0 {
		return
	}
	for k in i ..< w.char_type_count - 1 {
		w.char_types[k] = w.char_types[k + 1]
	}
	w.char_types[w.char_type_count - 1] = {}
	w.char_type_count -= 1
	return 0
}

// Renames type i; every character of that type follows.
world_rename_char_type :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.char_type_count {
		return .Empty
	}
	if p := world_check_char_type_name(w, i, name); p != .None {
		return p
	}
	old := strings.clone(name_str(&w.char_types[i].name), context.temp_allocator)
	for c in 0 ..< w.character_count {
		if name_str(&w.characters[c].type) == old {
			name_assign(&w.characters[c].type, name)
		}
	}
	name_assign(&w.char_types[i].name, name)
	return .None
}

// --- Sprites used by character types ------------------------------------------------------------

world_sprite_set_char_type_uses :: proc(w: ^World, set: string) -> (n: int) {
	for i in 0 ..< w.char_type_count {
		if name_str(&w.char_types[i].sprite_set) == set {
			n += 1
		}
	}
	return
}

world_sprite_char_type_uses :: proc(w: ^World, set, sprite: string) -> (n: int) {
	for i in 0 ..< w.char_type_count {
		ct := &w.char_types[i]
		if name_str(&ct.sprite_set) == set && name_str(&ct.sprite) == sprite {
			n += 1
		}
	}
	return
}

// A sprite set was renamed: the types drawing its sprites follow.
char_types_follow_sprite_set :: proc(w: ^World, old, new: string) {
	for i in 0 ..< w.char_type_count {
		if name_str(&w.char_types[i].sprite_set) == old {
			name_assign(&w.char_types[i].sprite_set, new)
		}
	}
}

// A sprite was renamed: the types drawing it follow.
char_types_follow_sprite :: proc(w: ^World, set, old, new: string) {
	for i in 0 ..< w.char_type_count {
		ct := &w.char_types[i]
		if name_str(&ct.sprite_set) == set && name_str(&ct.sprite) == old {
			name_assign(&ct.sprite, new)
		}
	}
}

// --- Characters --------------------------------------------------------------------------------

world_find_character :: proc(w: ^World, u: Uuid) -> int {
	if uuid_is_none(u) {
		return -1
	}
	for i in 0 ..< w.character_count {
		if w.characters[i].uuid == u {
			return i
		}
	}
	return -1
}

// Adds a character of type `type_index` named "character", standing nowhere. Returns its index,
// -1 if the world has 1024 characters, or -2 if the type does not exist.
world_add_character :: proc(w: ^World, type_index: int, base := "character") -> int {
	if type_index < 0 || type_index >= w.char_type_count {
		return -2
	}
	if w.character_count >= WORLD_MAX_CHARACTERS {
		return -1
	}
	i := w.character_count
	w.characters[i] = {
		uuid = world_new_uuid(w),
		type = w.char_types[type_index].name,
	}
	name_assign(&w.characters[i].name, base)
	w.character_count += 1
	return i
}

// Copies character i as "<name>_copy": a new uuid, standing nowhere. Returns its index or -1 if full.
world_duplicate_character :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.character_count || w.character_count >= WORLD_MAX_CHARACTERS {
		return -1
	}
	n := w.character_count
	w.characters[n] = w.characters[i]
	w.characters[n].uuid = world_new_uuid(w)
	w.characters[n].inventory = UUID_NONE // an inventory has one owner: the copy carries nothing
	name_assign(&w.characters[n].name, fmt.tprintf("%s_copy", name_str(&w.characters[i].name)))
	w.character_count += 1
	return n
}

// Takes the character off its map, makes the player nobody if it was the player, and removes it
// from the table.
world_delete_character :: proc(w: ^World, i: int) -> bool {
	if i < 0 || i >= w.character_count {
		return false
	}
	u := w.characters[i].uuid
	world_unplace_character(w, u)
	world_delete_inventory(w, w.characters[i].inventory) // what it carried goes with it
	if w.player == u {
		w.player = UUID_NONE
	}
	for k in i ..< w.character_count - 1 {
		w.characters[k] = w.characters[k + 1]
	}
	w.characters[w.character_count - 1] = {}
	w.character_count -= 1
	return true
}

// Only the text rules apply: a character's name is a label.
world_rename_character :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.character_count {
		return .Empty
	}
	if p := name_text_problem(name); p != .None {
		return p
	}
	name_assign(&w.characters[i].name, name)
	return .None
}

world_set_character_type :: proc(w: ^World, i, type_index: int) -> bool {
	if i < 0 || i >= w.character_count || type_index < 0 || type_index >= w.char_type_count {
		return false
	}
	if w.characters[i].type != w.char_types[type_index].name {
		w.characters[i].overrides = {} // the values belonged to the old type's properties
	}
	w.characters[i].type = w.char_types[type_index].name
	return true
}

// The player is a character of the table, or nobody (UUID_NONE).
world_set_player :: proc(w: ^World, u: Uuid) -> bool {
	if !uuid_is_none(u) && world_find_character(w, u) < 0 {
		return false
	}
	w.player = u
	return true
}

// --- Standing on maps --------------------------------------------------------------------------

Place_Result :: enum {
	Placed,
	Taken, // another character is in that cell
	Outside, // not a cell of the map
	Unknown, // no such map, character or feature
	Feature_There, // (placing a character) a feature stands in that cell: features always block
	Character_There, // (placing a feature) a character stands in that cell
}

// The table index of the character standing in a cell, or -1.
world_character_at :: proc(w: ^World, mi, x, y: int) -> int {
	if mi < 0 || mi >= w.map_count {
		return -1
	}
	m := &w.maps[mi]
	if x < 0 || y < 0 || x >= m.width || y >= m.height {
		return -1
	}
	return world_find_character(w, m.characters[y][x])
}

// Where a character stands, if it stands anywhere.
world_character_location :: proc(w: ^World, u: Uuid) -> (mi, x, y: int, ok: bool) {
	if uuid_is_none(u) {
		return 0, 0, 0, false
	}
	for m in 0 ..< w.map_count {
		mp := &w.maps[m]
		for cy in 0 ..< mp.height {
			for cx in 0 ..< mp.width {
				if mp.characters[cy][cx] == u {
					return m, cx, cy, true
				}
			}
		}
	}
	return 0, 0, 0, false
}

// Puts a character in a cell, taking it from wherever it stood. Refused if another character is
// there (the same character already there is fine).
world_place_character :: proc(w: ^World, mi, x, y: int, u: Uuid) -> Place_Result {
	if mi < 0 || mi >= w.map_count || world_find_character(w, u) < 0 {
		return .Unknown
	}
	m := &w.maps[mi]
	if x < 0 || y < 0 || x >= m.width || y >= m.height {
		return .Outside
	}
	if m.characters[y][x] == u {
		return .Placed
	}
	if !uuid_is_none(m.characters[y][x]) {
		return .Taken
	}
	if !uuid_is_none(m.features[y][x]) {
		return .Feature_There
	}
	world_unplace_character(w, u)
	m.characters[y][x] = u
	return .Placed
}

// Takes a character off the map it stands on. Returns true if it stood somewhere.
world_unplace_character :: proc(w: ^World, u: Uuid) -> bool {
	if mi, x, y, ok := world_character_location(w, u); ok {
		w.maps[mi].characters[y][x] = UUID_NONE
		return true
	}
	return false
}

// How many characters and features stand in the part of map mi that a new size would cut off.
world_map_shrink_blocked :: proc(w: ^World, mi, width, height: int) -> (n: int) {
	if mi < 0 || mi >= w.map_count {
		return 0
	}
	m := &w.maps[mi]
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if (x >= width || y >= height) && !uuid_is_none(m.characters[y][x]) {
				n += 1
			}
		}
	}
	return n + world_map_feature_shrink_blocked(w, mi, width, height) + world_map_inventory_shrink_blocked(w, mi, width, height) + world_map_trigger_shrink_blocked(w, mi, width, height)
}

// How many characters stand on map mi.
world_map_character_count :: proc(w: ^World, mi: int) -> (n: int) {
	if mi < 0 || mi >= w.map_count {
		return 0
	}
	m := &w.maps[mi]
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if !uuid_is_none(m.characters[y][x]) {
				n += 1
			}
		}
	}
	return
}

// --- File format -------------------------------------------------------------------------------
//
//   "character_types": [ { "name": "slime", "sprite_set": "creatures", "sprite": "slime" } ],
//   "characters": [ { "uuid": "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17", "name": "Goo", "type": "slime" } ],
//   "player": "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17",         (or null)
// and inside each map:  "characters": [ { "x": 2, "y": 1, "character": "3f2a9c1e-..." } ]
// Every reference must exist; a uuid may appear on one cell of one map at most; a cell holds at
// most one character. All of it is optional when reading (a world from before characters).

write_characters :: proc(b: ^strings.Builder, w: ^World) {
	strings.write_string(b, "  \"character_types\": [")
	for i in 0 ..< w.char_type_count {
		ct := &w.char_types[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(
			b,
			"    {{\"name\": \"%s\", \"sprite_set\": \"%s\", \"sprite\": \"%s\", \"tags\": ",
			escape_name(name_str(&ct.name)),
			escape_name(name_str(&ct.sprite_set)),
			escape_name(name_str(&ct.sprite)),
		)
		write_tag_list(b, w, ct.tags)
		if ct.props.count > 0 {
			strings.write_string(b, ", \"props\": ")
			write_prop_set(b, &ct.props)
		}
		strings.write_string(b, "}")
	}
	strings.write_string(b, w.char_type_count == 0 ? "],\n" : "\n  ],\n")
	strings.write_string(b, "  \"characters\": [")
	for i in 0 ..< w.character_count {
		c := &w.characters[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(b, "    {{\"uuid\": \"%s\", \"name\": \"%s\", \"type\": \"%s\", \"tags\": ", uuid_to_string(c.uuid), escape_name(name_str(&c.name)), escape_name(name_str(&c.type)))
		write_tag_list(b, w, c.tags_set)
		strings.write_string(b, ", \"tags_cleared\": ")
		write_tag_list(b, w, c.tags_cleared)
		if ti := world_find_char_type(w, name_str(&c.type)); ti >= 0 && c.overrides.mask != 0 {
			strings.write_string(b, ", \"props\": ")
			write_prop_overrides(b, &w.char_types[ti].props, &c.overrides)
		}
		strings.write_string(b, "}")
	}
	strings.write_string(b, w.character_count == 0 ? "],\n" : "\n  ],\n")
	if uuid_is_none(w.player) {
		strings.write_string(b, "  \"player\": null\n")
	} else {
		fmt.sbprintf(b, "  \"player\": \"%s\"\n", uuid_to_string(w.player))
	}
}

read_characters :: proc(root: json.Object, tmp: ^World) -> (err: string) {
	// Character types.
	if list, present := root["character_types"]; present {
		types, is_list := list.(json.Array)
		if !is_list {
			return `"character_types" must be a list`
		}
		if len(types) > WORLD_MAX_CHARACTER_TYPES {
			return fmt.tprintf("%d character types is more than the %d allowed", len(types), WORLD_MAX_CHARACTER_TYPES)
		}
		for item, i in types {
			obj, ok := item.(json.Object)
			if !ok {
				return fmt.tprintf("character type %d must be an object", i)
			}
			name, name_ok := obj["name"].(json.String)
			if !name_ok {
				return fmt.tprintf(`character type %d: "name" must be text`, i)
			}
			if p := world_check_char_type_name(tmp, -1, name); p != .None {
				return fmt.tprintf(`character type %d: the name "%s" is %v`, i, name, name_problem_text(p))
			}
			set, set_ok := obj["sprite_set"].(json.String)
			sprite, sprite_ok := obj["sprite"].(json.String)
			if !set_ok || !sprite_ok {
				return fmt.tprintf(`character type "%s": "sprite_set" and "sprite" must be text ("" for not set)`, name)
			}
			if (len(set) == 0) != (len(sprite) == 0) {
				return fmt.tprintf(`character type "%s": "sprite_set" and "sprite" must both be set or both be ""`, name)
			}
			ct := &tmp.char_types[i]
			name_assign(&ct.name, name)
			if len(set) > 0 {
				si := world_find_sprite_set(tmp, set)
				if si < 0 {
					return fmt.tprintf(`character type "%s": there is no sprite set "%s"`, name, set)
				}
				if sprite_set_find(&tmp.sprite_sets[si], sprite) < 0 {
					return fmt.tprintf(`character type "%s": sprite set "%s" has no sprite "%s"`, name, set, sprite)
				}
				name_assign(&ct.sprite_set, set)
				name_assign(&ct.sprite, sprite)
			}
			mask, mask_err := read_tag_mask(obj, "tags", tmp, fmt.tprintf(`character type "%s"`, name))
			if mask_err != "" {
				return mask_err
			}
			ct.tags = mask
			if msg := read_prop_set(obj, &ct.props, fmt.tprintf(`character type "%s"`, name)); msg != "" {
				return msg
			}
			tmp.char_type_count += 1
		}
	}
	// Characters.
	if list, present := root["characters"]; present {
		chars, is_list := list.(json.Array)
		if !is_list {
			return `"characters" must be a list`
		}
		if len(chars) > WORLD_MAX_CHARACTERS {
			return fmt.tprintf("%d characters is more than the %d allowed", len(chars), WORLD_MAX_CHARACTERS)
		}
		for item, i in chars {
			obj, ok := item.(json.Object)
			if !ok {
				return fmt.tprintf("character %d must be an object", i)
			}
			text, text_ok := obj["uuid"].(json.String)
			u, uuid_ok := uuid_from_string(text)
			if !text_ok || !uuid_ok || uuid_is_none(u) {
				return fmt.tprintf(`character %d: "uuid" must look like 3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17`, i)
			}
			if world_find_character(tmp, u) >= 0 {
				return fmt.tprintf(`character %d: the uuid %s is used more than once`, i, text)
			}
			name, name_ok := obj["name"].(json.String)
			if !name_ok || name_text_problem(name) != .None {
				return fmt.tprintf(`character %d: "name" must be 1 to %d printable ASCII characters`, i, NAME_MAX)
			}
			type_name, type_ok := obj["type"].(json.String)
			if !type_ok || world_find_char_type(tmp, type_name) < 0 {
				return fmt.tprintf(`character %d ("%s"): "type" must name a character type`, i, name)
			}
			what := fmt.tprintf(`character %d ("%s")`, i, name)
			set_mask, set_err := read_tag_mask(obj, "tags", tmp, what)
			if set_err != "" {
				return set_err
			}
			cleared_mask, cleared_err := read_tag_mask(obj, "tags_cleared", tmp, what)
			if cleared_err != "" {
				return cleared_err
			}
			if set_mask & cleared_mask != 0 {
				return fmt.tprintf("%s: a tag is both set and cleared", what)
			}
			tmp.characters[i].uuid = u
			tmp.characters[i].tags_set, tmp.characters[i].tags_cleared = set_mask, cleared_mask
			ti := world_find_char_type(tmp, type_name)
			if msg := read_prop_overrides(obj, &tmp.char_types[ti].props, &tmp.characters[i].overrides, what); msg != "" {
				return msg
			}
			name_assign(&tmp.characters[i].name, name)
			name_assign(&tmp.characters[i].type, type_name)
			tmp.character_count += 1
		}
	}
	// Who stands where.
	placed_somewhere := make(map[Uuid]bool, context.temp_allocator)
	if list, present := root["maps"]; present {
		maps, _ := list.(json.Array)
		for item, mi in maps {
			obj, _ := item.(json.Object)
			stands, has := obj["characters"]
			if !has {
				continue
			}
			arr, arr_ok := stands.(json.Array)
			if !arr_ok {
				return fmt.tprintf(`map %d: "characters" must be a list`, mi)
			}
			m := &tmp.maps[mi]
			for entry, k in arr {
				e, e_ok := entry.(json.Object)
				if !e_ok {
					return fmt.tprintf(`map "%s": character entry %d must be an object`, name_str(&m.name), k)
				}
				x, x_ok := e["x"].(json.Integer)
				y, y_ok := e["y"].(json.Integer)
				text, text_ok := e["character"].(json.String)
				u, uuid_ok := uuid_from_string(text)
				if !x_ok || !y_ok || !text_ok || !uuid_ok {
					return fmt.tprintf(`map "%s": character entry %d needs "x", "y" and a "character" uuid`, name_str(&m.name), k)
				}
				if x < 0 || y < 0 || int(x) >= m.width || int(y) >= m.height {
					return fmt.tprintf(`map "%s": character entry %d is outside the map`, name_str(&m.name), k)
				}
				if world_find_character(tmp, u) < 0 {
					return fmt.tprintf(`map "%s": character entry %d names the unknown character %s`, name_str(&m.name), k, text)
				}
				if !uuid_is_none(m.characters[y][x]) {
					return fmt.tprintf(`map "%s": two characters in the cell %d,%d`, name_str(&m.name), x, y)
				}
				if placed_somewhere[u] { 	// (a lookup, not a scan of every cell: a big world has many)
					return fmt.tprintf(`map "%s": character %s stands in more than one cell`, name_str(&m.name), text)
				}
				placed_somewhere[u] = true
				m.characters[y][x] = u
			}
		}
	}
	// The player.
	switch p in root["player"] {
	case json.String:
		u, ok := uuid_from_string(p)
		if !ok || world_find_character(tmp, u) < 0 {
			return `"player" must be the uuid of a character, or null`
		}
		tmp.player = u
	case json.Null:
	case json.Integer, json.Float, json.Boolean, json.Array, json.Object:
		return `"player" must be the uuid of a character, or null`
	case:
	}
	return ""
}
