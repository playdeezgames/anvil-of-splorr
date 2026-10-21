package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Tags of a world: one world-wide list of up to 64 named tags ("solid", "water", "hostile" ...), each
// of which can be set or cleared on an entity. Terrains and character types (the "types") either
// have a tag or do not. Characters and map cells (the "instances") have three states per tag: they
// inherit it from their type (a character's character type, a cell's terrain), or they set it, or
// they clear it, whatever the type says. Tag 0 is "solid": it always exists and cannot be renamed
// or deleted, because game code looks for it by name.
//
// A tag is a bit index in a u64 mask; the masks live in the entities. Deleting a tag closes the gap
// in every mask (see world_delete_tag).

WORLD_MAX_TAGS :: 64
TAG_SOLID :: 0
TAG_SOLID_NAME :: "solid"

Tag_Mask :: u64

tag_bit :: proc(i: int) -> Tag_Mask {
	return Tag_Mask(1) << uint(i)
}

// An instance's own state for one tag.
Tag_State :: enum {
	Inherit, // whatever its type says
	Set,
	Cleared,
}

// The own tags of a map cell (most cells have none).
Cell_Tags :: struct {
	set, cleared: Tag_Mask,
}

tag_state :: proc(set, cleared: Tag_Mask, tag: int) -> Tag_State {
	if set & tag_bit(tag) != 0 {
		return .Set
	}
	if cleared & tag_bit(tag) != 0 {
		return .Cleared
	}
	return .Inherit
}

// Inherit -> Set -> Cleared -> Inherit.
@(private = "file")
cycled :: proc(set, cleared: Tag_Mask, tag: int) -> (Tag_Mask, Tag_Mask) {
	b := tag_bit(tag)
	switch tag_state(set, cleared, tag) {
	case .Inherit:
		return set | b, cleared
	case .Set:
		return set & ~b, cleared | b
	case .Cleared:
		return set, cleared & ~b
	}
	return set, cleared
}

world_find_tag :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.tag_count {
		if i != except && name_str(&w.tags[i]) == name {
			return i
		}
	}
	return -1
}

world_check_tag_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_tag(w, name, index) >= 0 ? .In_Use : .None
}

// The reserved tag ("solid") cannot be renamed or deleted.
tag_is_reserved :: proc(i: int) -> bool {
	return i == TAG_SOLID
}

@(private = "file")
tag_names :: proc(w: ^World) -> []string {
	out := make([]string, w.tag_count, context.temp_allocator)
	for i in 0 ..< w.tag_count {
		out[i] = name_str(&w.tags[i])
	}
	return out
}

// Adds a tag named after `base` (made unique). Returns its index, or -1 if the world has 64.
world_add_tag :: proc(w: ^World, base := "tag") -> int {
	if w.tag_count >= WORLD_MAX_TAGS {
		return -1
	}
	i := w.tag_count
	name_assign(&w.tags[i], unique_among(base, tag_names(w)))
	w.tag_count += 1
	return i
}

// Renames tag i. The reserved tag is refused (.In_Use: its name is taken for good).
world_rename_tag :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.tag_count {
		return .Empty
	}
	if tag_is_reserved(i) {
		return .In_Use
	}
	if p := world_check_tag_name(w, i, name); p != .None {
		return p
	}
	name_assign(&w.tags[i], name)
	return .None
}

// How many entities set or clear this tag explicitly: terrains, character types, characters and
// map cells.
world_tag_uses :: proc(w: ^World, tag: int) -> (n: int) {
	b := tag_bit(tag)
	for si in 0 ..< w.set_count {
		for ti in 0 ..< w.sets[si].count {
			if w.sets[si].terrains[ti].tags & b != 0 {
				n += 1
			}
		}
	}
	for i in 0 ..< w.char_type_count {
		if w.char_types[i].tags & b != 0 {
			n += 1
		}
	}
	for i in 0 ..< w.character_count {
		if (w.characters[i].tags_set | w.characters[i].tags_cleared) & b != 0 {
			n += 1
		}
	}
	for mi in 0 ..< w.map_count {
		m := &w.maps[mi]
		for y in 0 ..< m.height {
			for x in 0 ..< m.width {
				if (m.cell_tags[y][x].set | m.cell_tags[y][x].cleared) & b != 0 {
					n += 1
				}
			}
		}
	}
	return
}

// Closes the gap that deleting tag i leaves in a mask: higher tags move down one place.
@(private = "file")
close_gap :: proc(mask: Tag_Mask, i: int) -> Tag_Mask {
	low := tag_bit(i) - 1
	return (mask & low) | ((mask >> uint(i + 1)) << uint(i))
}

// Deletes tag i and clears it everywhere it was set or cleared. Returns how many entities had it
// explicitly (so the caller can say), and false (nothing done) for the reserved tag or a bad index.
world_delete_tag :: proc(w: ^World, i: int) -> (uses: int, ok: bool) {
	if i < 0 || i >= w.tag_count || tag_is_reserved(i) {
		return 0, false
	}
	uses = world_tag_uses(w, i)
	for si in 0 ..< w.set_count {
		for ti in 0 ..< w.sets[si].count {
			w.sets[si].terrains[ti].tags = close_gap(w.sets[si].terrains[ti].tags, i)
		}
	}
	for k in 0 ..< w.char_type_count {
		w.char_types[k].tags = close_gap(w.char_types[k].tags, i)
	}
	for k in 0 ..< w.character_count {
		w.characters[k].tags_set = close_gap(w.characters[k].tags_set, i)
		w.characters[k].tags_cleared = close_gap(w.characters[k].tags_cleared, i)
	}
	for mi in 0 ..< w.map_count {
		m := &w.maps[mi]
		for y in 0 ..< MAP_MAX {
			for x in 0 ..< MAP_MAX {
				m.cell_tags[y][x].set = close_gap(m.cell_tags[y][x].set, i)
				m.cell_tags[y][x].cleared = close_gap(m.cell_tags[y][x].cleared, i)
			}
		}
	}
	for k in i ..< w.tag_count - 1 {
		w.tags[k] = w.tags[k + 1]
	}
	w.tags[w.tag_count - 1] = {}
	w.tag_count -= 1
	return uses, true
}

// --- Reading and changing tags ------------------------------------------------------------------

// Whether a terrain of a set has the tag.
world_terrain_has_tag :: proc(w: ^World, si, ti, tag: int) -> bool {
	if si < 0 || si >= w.set_count || ti < 0 || ti >= w.sets[si].count || tag < 0 || tag >= WORLD_MAX_TAGS {
		return false
	}
	return w.sets[si].terrains[ti].tags & tag_bit(tag) != 0
}

// Sets or clears a tag on a terrain (a type: it has the tag or it does not).
world_toggle_terrain_tag :: proc(w: ^World, si, ti, tag: int) -> bool {
	if si < 0 || si >= w.set_count || ti < 0 || ti >= w.sets[si].count || tag < 0 || tag >= w.tag_count {
		return false
	}
	w.sets[si].terrains[ti].tags ~= tag_bit(tag)
	return true
}

world_toggle_char_type_tag :: proc(w: ^World, ct, tag: int) -> bool {
	if ct < 0 || ct >= w.char_type_count || tag < 0 || tag >= w.tag_count {
		return false
	}
	w.char_types[ct].tags ~= tag_bit(tag)
	return true
}

// Whether a character has the tag: its own setting if it has one, else its type's.
world_character_has_tag :: proc(w: ^World, ci, tag: int) -> bool {
	if ci < 0 || ci >= w.character_count || tag < 0 || tag >= WORLD_MAX_TAGS {
		return false
	}
	c := &w.characters[ci]
	switch tag_state(c.tags_set, c.tags_cleared, tag) {
	case .Set:
		return true
	case .Cleared:
		return false
	case .Inherit:
	}
	ti := world_find_char_type(w, name_str(&c.type))
	return ti >= 0 && w.char_types[ti].tags & tag_bit(tag) != 0
}

// Inherit -> set -> cleared -> inherit, for a character.
world_cycle_character_tag :: proc(w: ^World, ci, tag: int) -> bool {
	if ci < 0 || ci >= w.character_count || tag < 0 || tag >= w.tag_count {
		return false
	}
	c := &w.characters[ci]
	c.tags_set, c.tags_cleared = cycled(c.tags_set, c.tags_cleared, tag)
	return true
}

// Whether a map cell has the tag: its own setting, else its terrain's.
world_cell_has_tag :: proc(w: ^World, mi, x, y, tag: int) -> bool {
	if mi < 0 || mi >= w.map_count || tag < 0 || tag >= WORLD_MAX_TAGS {
		return false
	}
	m := &w.maps[mi]
	if x < 0 || y < 0 || x >= m.width || y >= m.height {
		return false
	}
	switch tag_state(m.cell_tags[y][x].set, m.cell_tags[y][x].cleared, tag) {
	case .Set:
		return true
	case .Cleared:
		return false
	case .Inherit:
	}
	si := world_find_set(w, name_str(&m.set))
	return si >= 0 && world_terrain_has_tag(w, si, int(m.cells[y][x]), tag)
}

world_cycle_cell_tag :: proc(w: ^World, mi, x, y, tag: int) -> bool {
	if mi < 0 || mi >= w.map_count || tag < 0 || tag >= w.tag_count {
		return false
	}
	m := &w.maps[mi]
	if x < 0 || y < 0 || x >= m.width || y >= m.height {
		return false
	}
	c := &m.cell_tags[y][x]
	c.set, c.cleared = cycled(c.set, c.cleared, tag)
	return true
}

// --- File format -------------------------------------------------------------------------------
//
//   "tags": [ "solid", "water" ]          the list; "solid" is always first
//   terrains and character types:   "tags": [ "solid" ]
//   characters:                     "tags": [ "water" ], "tags_cleared": [ "solid" ]
//   maps:                           "cell_tags": [ { "x": 1, "y": 2, "tags": [ "water" ], "tags_cleared": [ ] } ]
// Every name must be in the list; an instance cannot both set and clear a tag. All of it is optional
// when reading; the old terrain field "solid": true is read as the tag "solid".

write_tag_list :: proc(b: ^strings.Builder, w: ^World, mask: Tag_Mask) {
	strings.write_string(b, "[")
	first := true
	for i in 0 ..< w.tag_count {
		if mask & tag_bit(i) != 0 {
			fmt.sbprintf(b, "%s\"%s\"", first ? "" : ", ", escape_name(name_str(&w.tags[i])))
			first = false
		}
	}
	strings.write_string(b, "]")
}

// Reads a list of tag names into a mask. An absent key is an empty mask.
read_tag_mask :: proc(obj: json.Object, key: string, tmp: ^World, what: string) -> (mask: Tag_Mask, err: string) {
	v, present := obj[key]
	if !present {
		return 0, ""
	}
	list, is_list := v.(json.Array)
	if !is_list {
		return 0, fmt.tprintf(`%s: "%s" must be a list of tag names`, what, key)
	}
	for entry in list {
		name, ok := entry.(json.String)
		i := ok ? world_find_tag(tmp, name) : -1
		if i < 0 {
			return 0, fmt.tprintf(`%s: "%s" names a tag that is not in the "tags" list`, what, key)
		}
		mask |= tag_bit(i)
	}
	return
}

// The "tags" list of the file: names in order, "solid" first. Absent = just "solid".
read_tags :: proc(root: json.Object, tmp: ^World) -> (err: string) {
	v, present := root["tags"]
	if !present {
		return ""
	}
	list, is_list := v.(json.Array)
	if !is_list || len(list) < 1 || len(list) > WORLD_MAX_TAGS {
		return fmt.tprintf(`"tags" must be a list of 1 to %d names, starting with "%s"`, WORLD_MAX_TAGS, TAG_SOLID_NAME)
	}
	tmp.tag_count = 0
	for entry, i in list {
		name, ok := entry.(json.String)
		if !ok {
			return fmt.tprintf(`tag %d must be text`, i)
		}
		if i == TAG_SOLID && name != TAG_SOLID_NAME {
			return fmt.tprintf(`the first tag must be "%s"`, TAG_SOLID_NAME)
		}
		if p := world_check_tag_name(tmp, -1, name); p != .None {
			return fmt.tprintf(`tag %d: the name "%s" is %v`, i, name, name_problem_text(p))
		}
		name_assign(&tmp.tags[i], name)
		tmp.tag_count += 1
	}
	return ""
}

// The "cell_tags" of one map object, after its cells are known.
read_cell_tags :: proc(obj: json.Object, m: ^World_Map, tmp: ^World) -> (err: string) {
	v, present := obj["cell_tags"]
	if !present {
		return ""
	}
	list, is_list := v.(json.Array)
	if !is_list {
		return fmt.tprintf(`map "%s": "cell_tags" must be a list`, name_str(&m.name))
	}
	seen := make(map[[2]int]bool, context.temp_allocator)
	for item in list {
		e, ok := item.(json.Object)
		x, x_ok := e["x"].(json.Integer)
		y, y_ok := e["y"].(json.Integer)
		if !ok || !x_ok || !y_ok || x < 0 || y < 0 || int(x) >= m.width || int(y) >= m.height {
			return fmt.tprintf(`map "%s": a "cell_tags" entry needs "x" and "y" inside the map`, name_str(&m.name))
		}
		if seen[{int(x), int(y)}] {
			return fmt.tprintf(`map "%s": two "cell_tags" entries for the cell %d,%d`, name_str(&m.name), x, y)
		}
		seen[{int(x), int(y)}] = true
		what := fmt.tprintf(`map "%s" cell %d,%d`, name_str(&m.name), x, y)
		set, e1 := read_tag_mask(e, "tags", tmp, what)
		if e1 != "" {
			return e1
		}
		cleared, e2 := read_tag_mask(e, "tags_cleared", tmp, what)
		if e2 != "" {
			return e2
		}
		if set & cleared != 0 {
			return fmt.tprintf("%s: a tag is both set and cleared", what)
		}
		m.cell_tags[y][x] = {set, cleared}
	}
	return ""
}
