package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Features (see FEATURES.md): things that stand in a map cell and never move: a tree, a door, a sign.
// Like characters they come in two parts. A feature type (name, the sprite it draws, tags) says what
// every feature of the type shares; a feature is an instance: a uuid, a name (a label), its type and
// its own tag settings. All features live in one table of the world; a map cell holds a feature's
// uuid or nothing, so a cell has at most one feature. A feature stands in at most one cell of the
// whole world, or on no map. A feature always blocks: a cell cannot hold both a feature and a
// character (placing either refuses, and the world file may not have both).

WORLD_MAX_FEATURE_TYPES :: 64
WORLD_MAX_FEATURES :: 2048

Feature_Type :: struct {
	name:       Name,
	sprite_set: Name, // empty = not set
	sprite:     Name, // the sprite's name within that set; empty = not set
	tags:       Tag_Mask, // the tags every feature of this type has (unless its own settings say otherwise)
	props:      Prop_Set, // the numeric properties every feature of the type has, with their defaults
}

Feature :: struct {
	uuid: Uuid,
	name: Name, // a label: not unique
	type: Name, // the feature type, by name
	tags_set, tags_cleared: Tag_Mask, // its own tag settings; a tag in neither is inherited from the type
	inventory: Uuid, // the inventory it holds, or none (world_items.odin)
	overrides: Prop_Overrides, // its own values of its type's properties (the others are the defaults)
}

// --- Feature types -----------------------------------------------------------------------------

world_find_feature_type :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.feature_type_count {
		if i != except && name_str(&w.feature_types[i].name) == name {
			return i
		}
	}
	return -1
}

world_check_feature_type_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_feature_type(w, name, index) >= 0 ? .In_Use : .None
}

@(private = "file")
feature_type_names :: proc(w: ^World) -> []string {
	out := make([]string, w.feature_type_count, context.temp_allocator)
	for i in 0 ..< w.feature_type_count {
		out[i] = name_str(&w.feature_types[i].name)
	}
	return out
}

// The sprite a feature type draws, or nil while it is not set (or points at nothing).
world_feature_type_sprite :: proc(w: ^World, ft: ^Feature_Type) -> ^Sprite {
	si := world_find_sprite_set(w, name_str(&ft.sprite_set))
	if si < 0 {
		return nil
	}
	i := sprite_set_find(&w.sprite_sets[si], name_str(&ft.sprite))
	return i >= 0 ? &w.sprite_sets[si].sprites[i] : nil
}

// Points a type at the first sprite of the first sprite set that has one; not set if none.
world_feature_type_point_at_first :: proc(w: ^World, ft: ^Feature_Type) {
	ft.sprite_set, ft.sprite = {}, {}
	for si in 0 ..< w.sprite_set_count {
		if w.sprite_sets[si].count > 0 {
			ft.sprite_set = w.sprite_sets[si].name
			ft.sprite = w.sprite_sets[si].sprites[0].name
			return
		}
	}
}

// Adds a feature type ("feature_type") drawing the first sprite. Returns its index or -1 if full.
world_add_feature_type :: proc(w: ^World, base := "feature_type") -> int {
	if w.feature_type_count >= WORLD_MAX_FEATURE_TYPES {
		return -1
	}
	i := w.feature_type_count
	w.feature_types[i] = {}
	name_assign(&w.feature_types[i].name, unique_among(base, feature_type_names(w)))
	world_feature_type_point_at_first(w, &w.feature_types[i])
	w.feature_type_count += 1
	return i
}

// Copies type i right after itself as "<name>_copy". Returns the new index or -1 if full.
world_duplicate_feature_type :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.feature_type_count || w.feature_type_count >= WORLD_MAX_FEATURE_TYPES {
		return -1
	}
	at := i + 1
	for k := w.feature_type_count; k > at; k -= 1 {
		w.feature_types[k] = w.feature_types[k - 1]
	}
	w.feature_types[at] = w.feature_types[i]
	name_assign(&w.feature_types[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.feature_types[i].name)), feature_type_names(w)))
	w.feature_type_count += 1
	return at
}

// How many features have this type.
world_feature_type_uses :: proc(w: ^World, name: string) -> (n: int) {
	for i in 0 ..< w.feature_count {
		if name_str(&w.features[i].type) == name {
			n += 1
		}
	}
	return
}

// Deletes type i unless a feature has it. Returns the number of features in the way (0 = done).
world_delete_feature_type :: proc(w: ^World, i: int) -> (uses: int) {
	if i < 0 || i >= w.feature_type_count {
		return 0
	}
	if uses = world_feature_type_uses(w, name_str(&w.feature_types[i].name)); uses > 0 {
		return
	}
	for k in i ..< w.feature_type_count - 1 {
		w.feature_types[k] = w.feature_types[k + 1]
	}
	w.feature_types[w.feature_type_count - 1] = {}
	w.feature_type_count -= 1
	return 0
}

// Renames type i; every feature of that type follows.
world_rename_feature_type :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.feature_type_count {
		return .Empty
	}
	if p := world_check_feature_type_name(w, i, name); p != .None {
		return p
	}
	old := strings.clone(name_str(&w.feature_types[i].name), context.temp_allocator)
	for c in 0 ..< w.feature_count {
		if name_str(&w.features[c].type) == old {
			name_assign(&w.features[c].type, name)
		}
	}
	name_assign(&w.feature_types[i].name, name)
	return .None
}

// --- Sprites used by feature types ---------------------------------------------------------------

world_sprite_set_feature_type_uses :: proc(w: ^World, set: string) -> (n: int) {
	for i in 0 ..< w.feature_type_count {
		if name_str(&w.feature_types[i].sprite_set) == set {
			n += 1
		}
	}
	return
}

world_sprite_feature_type_uses :: proc(w: ^World, set, sprite: string) -> (n: int) {
	for i in 0 ..< w.feature_type_count {
		ft := &w.feature_types[i]
		if name_str(&ft.sprite_set) == set && name_str(&ft.sprite) == sprite {
			n += 1
		}
	}
	return
}

// A sprite set was renamed: the types drawing its sprites follow.
feature_types_follow_sprite_set :: proc(w: ^World, old, new: string) {
	for i in 0 ..< w.feature_type_count {
		if name_str(&w.feature_types[i].sprite_set) == old {
			name_assign(&w.feature_types[i].sprite_set, new)
		}
	}
}

// A sprite was renamed: the types drawing it follow.
feature_types_follow_sprite :: proc(w: ^World, set, old, new: string) {
	for i in 0 ..< w.feature_type_count {
		ft := &w.feature_types[i]
		if name_str(&ft.sprite_set) == set && name_str(&ft.sprite) == old {
			name_assign(&ft.sprite, new)
		}
	}
}

// --- Features ----------------------------------------------------------------------------------

world_find_feature :: proc(w: ^World, u: Uuid) -> int {
	if uuid_is_none(u) {
		return -1
	}
	for i in 0 ..< w.feature_count {
		if w.features[i].uuid == u {
			return i
		}
	}
	return -1
}

// Adds a feature of type `type_index` named "feature", standing nowhere. Returns its index, -1 if the
// world has 2048 features, or -2 if the type does not exist.
world_add_feature :: proc(w: ^World, type_index: int, base := "feature") -> int {
	if type_index < 0 || type_index >= w.feature_type_count {
		return -2
	}
	if w.feature_count >= WORLD_MAX_FEATURES {
		return -1
	}
	i := w.feature_count
	w.features[i] = {
		uuid = world_new_uuid(w),
		type = w.feature_types[type_index].name,
	}
	name_assign(&w.features[i].name, base)
	w.feature_count += 1
	return i
}

// Copies feature i as "<name>_copy": a new uuid, standing nowhere. Returns its index or -1 if full.
world_duplicate_feature :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.feature_count || w.feature_count >= WORLD_MAX_FEATURES {
		return -1
	}
	n := w.feature_count
	w.features[n] = w.features[i]
	w.features[n].uuid = world_new_uuid(w)
	w.features[n].inventory = UUID_NONE // an inventory has one owner: the copy holds nothing
	name_assign(&w.features[n].name, fmt.tprintf("%s_copy", name_str(&w.features[i].name)))
	w.feature_count += 1
	return n
}

// Takes the feature off its map and removes it from the table.
world_delete_feature :: proc(w: ^World, i: int) -> bool {
	if i < 0 || i >= w.feature_count {
		return false
	}
	world_unplace_feature(w, w.features[i].uuid)
	world_delete_inventory(w, w.features[i].inventory) // what it held goes with it
	for k in i ..< w.feature_count - 1 {
		w.features[k] = w.features[k + 1]
	}
	w.features[w.feature_count - 1] = {}
	w.feature_count -= 1
	return true
}

// Only the text rules apply: a feature's name is a label.
world_rename_feature :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.feature_count {
		return .Empty
	}
	if p := name_text_problem(name); p != .None {
		return p
	}
	name_assign(&w.features[i].name, name)
	return .None
}

world_set_feature_type :: proc(w: ^World, i, type_index: int) -> bool {
	if i < 0 || i >= w.feature_count || type_index < 0 || type_index >= w.feature_type_count {
		return false
	}
	if w.features[i].type != w.feature_types[type_index].name {
		w.features[i].overrides = {} // the values belonged to the old type's properties
	}
	w.features[i].type = w.feature_types[type_index].name
	return true
}

// --- Standing on maps --------------------------------------------------------------------------

// The table index of the feature standing in a cell, or -1.
world_feature_at :: proc(w: ^World, mi, x, y: int) -> int {
	if mi < 0 || mi >= w.map_count {
		return -1
	}
	m := &w.maps[mi]
	if x < 0 || y < 0 || x >= m.width || y >= m.height {
		return -1
	}
	return world_find_feature(w, m.features[y][x])
}

// Where a feature stands, if it stands anywhere.
world_feature_location :: proc(w: ^World, u: Uuid) -> (mi, x, y: int, ok: bool) {
	if uuid_is_none(u) {
		return 0, 0, 0, false
	}
	for m in 0 ..< w.map_count {
		mp := &w.maps[m]
		for cy in 0 ..< mp.height {
			for cx in 0 ..< mp.width {
				if mp.features[cy][cx] == u {
					return m, cx, cy, true
				}
			}
		}
	}
	return 0, 0, 0, false
}

// Puts a feature in a cell, taking it from wherever it stood. Refused if another feature is there
// (Taken) or a character is (Character_There); the same feature already there is fine.
world_place_feature :: proc(w: ^World, mi, x, y: int, u: Uuid) -> Place_Result {
	if mi < 0 || mi >= w.map_count || world_find_feature(w, u) < 0 {
		return .Unknown
	}
	m := &w.maps[mi]
	if x < 0 || y < 0 || x >= m.width || y >= m.height {
		return .Outside
	}
	if m.features[y][x] == u {
		return .Placed
	}
	if !uuid_is_none(m.features[y][x]) {
		return .Taken
	}
	if !uuid_is_none(m.characters[y][x]) {
		return .Character_There
	}
	world_unplace_feature(w, u)
	m.features[y][x] = u
	return .Placed
}

// Takes a feature off the map it stands on. Returns true if it stood somewhere.
world_unplace_feature :: proc(w: ^World, u: Uuid) -> bool {
	if mi, x, y, ok := world_feature_location(w, u); ok {
		w.maps[mi].features[y][x] = UUID_NONE
		return true
	}
	return false
}

// How many features stand in the part of map mi that a new size would cut off.
world_map_feature_shrink_blocked :: proc(w: ^World, mi, width, height: int) -> (n: int) {
	if mi < 0 || mi >= w.map_count {
		return 0
	}
	m := &w.maps[mi]
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if (x >= width || y >= height) && !uuid_is_none(m.features[y][x]) {
				n += 1
			}
		}
	}
	return
}

// How many features stand on map mi.
world_map_feature_count :: proc(w: ^World, mi: int) -> (n: int) {
	if mi < 0 || mi >= w.map_count {
		return 0
	}
	m := &w.maps[mi]
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if !uuid_is_none(m.features[y][x]) {
				n += 1
			}
		}
	}
	return
}

// --- File format -------------------------------------------------------------------------------
//
//   "feature_types": [ { "name": "tree", "sprite_set": "scenery", "sprite": "tree", "tags": [ "solid" ] } ],
//   "features": [ { "uuid": "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17", "name": "Old oak", "type": "tree",
//                   "tags": [], "tags_cleared": [] } ],
// and inside each map:  "features": [ { "x": 2, "y": 1, "feature": "3f2a9c1e-..." } ]
// Every reference must exist; a uuid may appear on one cell of one map at most; a cell holds at most
// one feature, and never a feature and a character together. All of it is optional when reading (a
// world from before features).

write_features :: proc(b: ^strings.Builder, w: ^World) {
	strings.write_string(b, "  \"feature_types\": [")
	for i in 0 ..< w.feature_type_count {
		ft := &w.feature_types[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(
			b,
			"    {{\"name\": \"%s\", \"sprite_set\": \"%s\", \"sprite\": \"%s\", \"tags\": ",
			escape_name(name_str(&ft.name)),
			escape_name(name_str(&ft.sprite_set)),
			escape_name(name_str(&ft.sprite)),
		)
		write_tag_list(b, w, ft.tags)
		if ft.props.count > 0 {
			strings.write_string(b, ", \"props\": ")
			write_prop_set(b, &ft.props)
		}
		strings.write_string(b, "}")
	}
	strings.write_string(b, w.feature_type_count == 0 ? "],\n" : "\n  ],\n")
	strings.write_string(b, "  \"features\": [")
	for i in 0 ..< w.feature_count {
		f := &w.features[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(b, "    {{\"uuid\": \"%s\", \"name\": \"%s\", \"type\": \"%s\", \"tags\": ", uuid_to_string(f.uuid), escape_name(name_str(&f.name)), escape_name(name_str(&f.type)))
		write_tag_list(b, w, f.tags_set)
		strings.write_string(b, ", \"tags_cleared\": ")
		write_tag_list(b, w, f.tags_cleared)
		if ti := world_find_feature_type(w, name_str(&f.type)); ti >= 0 && f.overrides.mask != 0 {
			strings.write_string(b, ", \"props\": ")
			write_prop_overrides(b, &w.feature_types[ti].props, &f.overrides)
		}
		strings.write_string(b, "}")
	}
	strings.write_string(b, w.feature_count == 0 ? "],\n" : "\n  ],\n")
}

// What a map writes for its features (a list, inside the map object).
write_map_features :: proc(b: ^strings.Builder, m: ^World_Map) {
	first := true
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if !uuid_is_none(m.features[y][x]) {
				fmt.sbprintf(b, "%s{{\"x\": %d, \"y\": %d, \"feature\": \"%s\"}}", first ? "" : ", ", x, y, uuid_to_string(m.features[y][x]))
				first = false
			}
		}
	}
}

// Reads the feature types, the features and where they stand. Run after the characters (a feature may
// not share a cell with one).
read_features :: proc(root: json.Object, tmp: ^World) -> (err: string) {
	if list, present := root["feature_types"]; present {
		types, is_list := list.(json.Array)
		if !is_list {
			return `"feature_types" must be a list`
		}
		if len(types) > WORLD_MAX_FEATURE_TYPES {
			return fmt.tprintf("%d feature types is more than the %d allowed", len(types), WORLD_MAX_FEATURE_TYPES)
		}
		for item, i in types {
			obj, ok := item.(json.Object)
			if !ok {
				return fmt.tprintf("feature type %d must be an object", i)
			}
			name, name_ok := obj["name"].(json.String)
			if !name_ok {
				return fmt.tprintf(`feature type %d: "name" must be text`, i)
			}
			if p := world_check_feature_type_name(tmp, -1, name); p != .None {
				return fmt.tprintf(`feature type %d: the name "%s" is %v`, i, name, name_problem_text(p))
			}
			set, set_ok := obj["sprite_set"].(json.String)
			sprite, sprite_ok := obj["sprite"].(json.String)
			if !set_ok || !sprite_ok {
				return fmt.tprintf(`feature type "%s": "sprite_set" and "sprite" must be text ("" for not set)`, name)
			}
			if (len(set) == 0) != (len(sprite) == 0) {
				return fmt.tprintf(`feature type "%s": "sprite_set" and "sprite" must both be set or both be ""`, name)
			}
			ft := &tmp.feature_types[i]
			name_assign(&ft.name, name)
			if len(set) > 0 {
				si := world_find_sprite_set(tmp, set)
				if si < 0 {
					return fmt.tprintf(`feature type "%s": there is no sprite set "%s"`, name, set)
				}
				if sprite_set_find(&tmp.sprite_sets[si], sprite) < 0 {
					return fmt.tprintf(`feature type "%s": sprite set "%s" has no sprite "%s"`, name, set, sprite)
				}
				name_assign(&ft.sprite_set, set)
				name_assign(&ft.sprite, sprite)
			}
			mask, mask_err := read_tag_mask(obj, "tags", tmp, fmt.tprintf(`feature type "%s"`, name))
			if mask_err != "" {
				return mask_err
			}
			ft.tags = mask
			if msg := read_prop_set(obj, &ft.props, fmt.tprintf(`feature type "%s"`, name)); msg != "" {
				return msg
			}
			tmp.feature_type_count += 1
		}
	}
	if list, present := root["features"]; present {
		items, is_list := list.(json.Array)
		if !is_list {
			return `"features" must be a list`
		}
		if len(items) > WORLD_MAX_FEATURES {
			return fmt.tprintf("%d features is more than the %d allowed", len(items), WORLD_MAX_FEATURES)
		}
		seen := make(map[Uuid]bool, context.temp_allocator)
		for item, i in items {
			obj, ok := item.(json.Object)
			if !ok {
				return fmt.tprintf("feature %d must be an object", i)
			}
			text, text_ok := obj["uuid"].(json.String)
			u, uuid_ok := uuid_from_string(text)
			if !text_ok || !uuid_ok || uuid_is_none(u) {
				return fmt.tprintf(`feature %d: "uuid" must look like 3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17`, i)
			}
			if seen[u] || world_find_character(tmp, u) >= 0 {
				return fmt.tprintf(`feature %d: the uuid %s is used more than once`, i, text)
			}
			seen[u] = true
			name, name_ok := obj["name"].(json.String)
			if !name_ok || name_text_problem(name) != .None {
				return fmt.tprintf(`feature %d: "name" must be 1 to %d printable ASCII characters`, i, NAME_MAX)
			}
			type_name, type_ok := obj["type"].(json.String)
			if !type_ok || world_find_feature_type(tmp, type_name) < 0 {
				return fmt.tprintf(`feature %d ("%s"): "type" must name a feature type`, i, name)
			}
			what := fmt.tprintf(`feature %d ("%s")`, i, name)
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
			tmp.features[i].uuid = u
			tmp.features[i].tags_set, tmp.features[i].tags_cleared = set_mask, cleared_mask
			if msg := read_prop_overrides(obj, &tmp.feature_types[world_find_feature_type(tmp, type_name)].props, &tmp.features[i].overrides, what); msg != "" {
				return msg
			}
			name_assign(&tmp.features[i].name, name)
			name_assign(&tmp.features[i].type, type_name)
			tmp.feature_count += 1
		}
	}
	// Where they stand.
	placed_somewhere := make(map[Uuid]bool, context.temp_allocator)
	if list, present := root["maps"]; present {
		maps, _ := list.(json.Array)
		for item, mi in maps {
			obj, _ := item.(json.Object)
			stands, has := obj["features"]
			if !has {
				continue
			}
			arr, arr_ok := stands.(json.Array)
			if !arr_ok {
				return fmt.tprintf(`map %d: "features" must be a list`, mi)
			}
			m := &tmp.maps[mi]
			for entry, k in arr {
				e, e_ok := entry.(json.Object)
				if !e_ok {
					return fmt.tprintf(`map "%s": feature entry %d must be an object`, name_str(&m.name), k)
				}
				x, x_ok := e["x"].(json.Integer)
				y, y_ok := e["y"].(json.Integer)
				text, text_ok := e["feature"].(json.String)
				u, uuid_ok := uuid_from_string(text)
				if !x_ok || !y_ok || !text_ok || !uuid_ok {
					return fmt.tprintf(`map "%s": feature entry %d needs "x", "y" and a "feature" uuid`, name_str(&m.name), k)
				}
				if x < 0 || y < 0 || int(x) >= m.width || int(y) >= m.height {
					return fmt.tprintf(`map "%s": feature entry %d is outside the map`, name_str(&m.name), k)
				}
				if world_find_feature(tmp, u) < 0 {
					return fmt.tprintf(`map "%s": feature entry %d names the unknown feature %s`, name_str(&m.name), k, text)
				}
				if !uuid_is_none(m.features[y][x]) {
					return fmt.tprintf(`map "%s": two features in the cell %d,%d`, name_str(&m.name), x, y)
				}
				if !uuid_is_none(m.characters[y][x]) {
					return fmt.tprintf(`map "%s": a feature and a character in the cell %d,%d`, name_str(&m.name), x, y)
				}
				if placed_somewhere[u] {
					return fmt.tprintf(`map "%s": feature %s stands in more than one cell`, name_str(&m.name), text)
				}
				placed_somewhere[u] = true
				m.features[y][x] = u
			}
		}
	}
	return ""
}
