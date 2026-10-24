package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Triggers (design in coxswain task #64 of project `anvil`): things that sit in a map cell, or on a
// feature, and never block; they are what a game hears about when a character enters a cell, or tries to
// and is refused (a trap, a pressure plate, a locked door's lock). Like features and characters they come
// in two parts. A trigger type (name, the sprite it draws, tags, numeric properties) says what every
// trigger of the type shares; a trigger is an instance: a uuid, a name (a label), its type, its own tag
// settings, its own property values (only where they differ from the type's defaults) and where it is.
//
// A trigger is in one of three places: nowhere, a map cell (the map by name, x, y), or on a feature
// (the feature's uuid; it then has no cell of its own and goes wherever the feature goes). Any number of
// triggers may share a cell or a feature. The Anvil only notifies (anvil_runtime): what a trigger does is
// the game's business.

WORLD_MAX_TRIGGER_TYPES :: 64
WORLD_MAX_TRIGGERS :: 2048

Trigger_Type :: struct {
	name:       Name,
	sprite_set: Name, // empty = not set
	sprite:     Name, // the sprite's name within that set; empty = not set
	tags:       Tag_Mask, // the tags every trigger of this type has (unless its own settings say otherwise)
	props:      Prop_Set, // the numeric properties every trigger of the type has, with their defaults
}

Trigger_Place :: enum {
	None, // nowhere
	Cell, // in the cell (map, x, y)
	Feature, // on the feature `feature`
}

Trigger :: struct {
	uuid:                  Uuid,
	name:                  Name, // a label: not unique
	type:                  Name, // the trigger type, by name
	tags_set, tags_cleared: Tag_Mask, // its own tag settings; a tag in neither is inherited from the type
	overrides:             Prop_Overrides, // its own values of its type's properties
	place:                 Trigger_Place,
	map_name:              Name, // Cell: the map, by name
	x, y:                  int, // Cell: the cell
	feature:               Uuid, // Feature: the feature
}

// --- Trigger types -----------------------------------------------------------------------------

world_find_trigger_type :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.trigger_type_count {
		if i != except && name_str(&w.trigger_types[i].name) == name {
			return i
		}
	}
	return -1
}

world_check_trigger_type_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_trigger_type(w, name, index) >= 0 ? .In_Use : .None
}

@(private = "file")
trigger_type_names :: proc(w: ^World) -> []string {
	out := make([]string, w.trigger_type_count, context.temp_allocator)
	for i in 0 ..< w.trigger_type_count {
		out[i] = name_str(&w.trigger_types[i].name)
	}
	return out
}

// The sprite a trigger type draws, or nil while it is not set (or points at nothing).
world_trigger_type_sprite :: proc(w: ^World, tt: ^Trigger_Type) -> ^Sprite {
	si := world_find_sprite_set(w, name_str(&tt.sprite_set))
	if si < 0 {
		return nil
	}
	i := sprite_set_find(&w.sprite_sets[si], name_str(&tt.sprite))
	return i >= 0 ? &w.sprite_sets[si].sprites[i] : nil
}

// Points a type at the first sprite of the first sprite set that has one; not set if none.
world_trigger_type_point_at_first :: proc(w: ^World, tt: ^Trigger_Type) {
	tt.sprite_set, tt.sprite = {}, {}
	for si in 0 ..< w.sprite_set_count {
		if w.sprite_sets[si].count > 0 {
			tt.sprite_set = w.sprite_sets[si].name
			tt.sprite = w.sprite_sets[si].sprites[0].name
			return
		}
	}
}

// Adds a trigger type ("trigger_type") drawing the first sprite. Returns its index or -1 if full.
world_add_trigger_type :: proc(w: ^World, base := "trigger_type") -> int {
	if w.trigger_type_count >= WORLD_MAX_TRIGGER_TYPES {
		return -1
	}
	i := w.trigger_type_count
	w.trigger_types[i] = {}
	name_assign(&w.trigger_types[i].name, unique_among(base, trigger_type_names(w)))
	world_trigger_type_point_at_first(w, &w.trigger_types[i])
	w.trigger_type_count += 1
	return i
}

// Copies type i right after itself as "<name>_copy". Returns the new index or -1 if full.
world_duplicate_trigger_type :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.trigger_type_count || w.trigger_type_count >= WORLD_MAX_TRIGGER_TYPES {
		return -1
	}
	at := i + 1
	for k := w.trigger_type_count; k > at; k -= 1 {
		w.trigger_types[k] = w.trigger_types[k - 1]
	}
	w.trigger_types[at] = w.trigger_types[i]
	name_assign(&w.trigger_types[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.trigger_types[i].name)), trigger_type_names(w)))
	w.trigger_type_count += 1
	return at
}

// How many triggers have this type.
world_trigger_type_uses :: proc(w: ^World, name: string) -> (n: int) {
	for i in 0 ..< w.trigger_count {
		if name_str(&w.triggers[i].type) == name {
			n += 1
		}
	}
	return
}

// Deletes type i unless a trigger has it. Returns the number of triggers in the way (0 = done).
world_delete_trigger_type :: proc(w: ^World, i: int) -> (uses: int) {
	if i < 0 || i >= w.trigger_type_count {
		return 0
	}
	if uses = world_trigger_type_uses(w, name_str(&w.trigger_types[i].name)); uses > 0 {
		return
	}
	for k in i ..< w.trigger_type_count - 1 {
		w.trigger_types[k] = w.trigger_types[k + 1]
	}
	w.trigger_types[w.trigger_type_count - 1] = {}
	w.trigger_type_count -= 1
	return 0
}

// Renames type i; every trigger of that type follows.
world_rename_trigger_type :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.trigger_type_count {
		return .Empty
	}
	if p := world_check_trigger_type_name(w, i, name); p != .None {
		return p
	}
	old := strings.clone(name_str(&w.trigger_types[i].name), context.temp_allocator)
	for c in 0 ..< w.trigger_count {
		if name_str(&w.triggers[c].type) == old {
			name_assign(&w.triggers[c].type, name)
		}
	}
	name_assign(&w.trigger_types[i].name, name)
	return .None
}

world_toggle_trigger_type_tag :: proc(w: ^World, tt, tag: int) -> bool {
	if tt < 0 || tt >= w.trigger_type_count || tag < 0 || tag >= w.tag_count {
		return false
	}
	w.trigger_types[tt].tags ~= tag_bit(tag)
	return true
}

// Adds a property to trigger type i (a unique name made from `base`, default `value`). Returns its
// index or -1 if the type has 16.
world_trigger_type_add_prop :: proc(w: ^World, i: int, base := "property", value: i32 = 0) -> int {
	if i < 0 || i >= w.trigger_type_count {
		return -1
	}
	return prop_set_add(&w.trigger_types[i].props, base, value)
}

// Deletes property p of trigger type i; its triggers lose their value of it and the ones above shift down.
world_trigger_type_delete_prop :: proc(w: ^World, i, p: int) -> bool {
	if i < 0 || i >= w.trigger_type_count || !prop_set_delete(&w.trigger_types[i].props, p) {
		return false
	}
	name := name_str(&w.trigger_types[i].name)
	for t in 0 ..< w.trigger_count {
		if name_str(&w.triggers[t].type) == name {
			prop_overrides_remove(&w.triggers[t].overrides, p)
		}
	}
	return true
}

// --- Sprites used by trigger types ---------------------------------------------------------------

world_sprite_set_trigger_type_uses :: proc(w: ^World, set: string) -> (n: int) {
	for i in 0 ..< w.trigger_type_count {
		if name_str(&w.trigger_types[i].sprite_set) == set {
			n += 1
		}
	}
	return
}

world_sprite_trigger_type_uses :: proc(w: ^World, set, sprite: string) -> (n: int) {
	for i in 0 ..< w.trigger_type_count {
		tt := &w.trigger_types[i]
		if name_str(&tt.sprite_set) == set && name_str(&tt.sprite) == sprite {
			n += 1
		}
	}
	return
}

// A sprite set was renamed: the types drawing its sprites follow.
trigger_types_follow_sprite_set :: proc(w: ^World, old, new: string) {
	for i in 0 ..< w.trigger_type_count {
		if name_str(&w.trigger_types[i].sprite_set) == old {
			name_assign(&w.trigger_types[i].sprite_set, new)
		}
	}
}

// A sprite was renamed: the types drawing it follow.
trigger_types_follow_sprite :: proc(w: ^World, set, old, new: string) {
	for i in 0 ..< w.trigger_type_count {
		tt := &w.trigger_types[i]
		if name_str(&tt.sprite_set) == set && name_str(&tt.sprite) == old {
			name_assign(&tt.sprite, new)
		}
	}
}

// --- Triggers ----------------------------------------------------------------------------------

world_find_trigger :: proc(w: ^World, u: Uuid) -> int {
	if uuid_is_none(u) {
		return -1
	}
	for i in 0 ..< w.trigger_count {
		if w.triggers[i].uuid == u {
			return i
		}
	}
	return -1
}

// Adds a trigger of type `type_index` named "trigger", in no place. Returns its index, -1 if the world
// has 2048 triggers, or -2 if the type does not exist.
world_add_trigger :: proc(w: ^World, type_index: int, base := "trigger") -> int {
	if type_index < 0 || type_index >= w.trigger_type_count {
		return -2
	}
	if w.trigger_count >= WORLD_MAX_TRIGGERS {
		return -1
	}
	i := w.trigger_count
	w.triggers[i] = {
		uuid = world_new_uuid(w),
		type = w.trigger_types[type_index].name,
	}
	name_assign(&w.triggers[i].name, base)
	w.trigger_count += 1
	return i
}

// Copies trigger i as "<name>_copy": a new uuid, in no place. Returns its index or -1 if full.
world_duplicate_trigger :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.trigger_count || w.trigger_count >= WORLD_MAX_TRIGGERS {
		return -1
	}
	n := w.trigger_count
	w.triggers[n] = w.triggers[i]
	w.triggers[n].uuid = world_new_uuid(w)
	w.triggers[n].place = .None
	w.triggers[n].map_name, w.triggers[n].x, w.triggers[n].y, w.triggers[n].feature = {}, 0, 0, UUID_NONE
	name_assign(&w.triggers[n].name, fmt.tprintf("%s_copy", name_str(&w.triggers[i].name)))
	w.trigger_count += 1
	return n
}

world_delete_trigger :: proc(w: ^World, i: int) -> bool {
	if i < 0 || i >= w.trigger_count {
		return false
	}
	for k in i ..< w.trigger_count - 1 {
		w.triggers[k] = w.triggers[k + 1]
	}
	w.triggers[w.trigger_count - 1] = {}
	w.trigger_count -= 1
	return true
}

// Only the text rules apply: a trigger's name is a label.
world_rename_trigger :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.trigger_count {
		return .Empty
	}
	if p := name_text_problem(name); p != .None {
		return p
	}
	name_assign(&w.triggers[i].name, name)
	return .None
}

// Gives a trigger another type; its own property values belonged to the old type's properties and go.
world_set_trigger_type :: proc(w: ^World, i, type_index: int) -> bool {
	if i < 0 || i >= w.trigger_count || type_index < 0 || type_index >= w.trigger_type_count {
		return false
	}
	if w.triggers[i].type != w.trigger_types[type_index].name {
		w.triggers[i].overrides = {}
	}
	w.triggers[i].type = w.trigger_types[type_index].name
	return true
}

// Whether a trigger has the tag: its own setting if it has one, else its type's.
world_trigger_has_tag :: proc(w: ^World, ti, tag: int) -> bool {
	if ti < 0 || ti >= w.trigger_count || tag < 0 || tag >= WORLD_MAX_TAGS {
		return false
	}
	t := &w.triggers[ti]
	switch tag_state(t.tags_set, t.tags_cleared, tag) {
	case .Set:
		return true
	case .Cleared:
		return false
	case .Inherit:
	}
	tt := world_find_trigger_type(w, name_str(&t.type))
	return tt >= 0 && w.trigger_types[tt].tags & tag_bit(tag) != 0
}

// Inherit -> set -> cleared -> inherit, for a trigger.
world_cycle_trigger_tag :: proc(w: ^World, ti, tag: int) -> bool {
	if ti < 0 || ti >= w.trigger_count || tag < 0 || tag >= w.tag_count {
		return false
	}
	t := &w.triggers[ti]
	t.tags_set, t.tags_cleared = cycled(t.tags_set, t.tags_cleared, tag)
	return true
}

@(private = "file")
trigger_type_of :: proc(w: ^World, ti: int) -> int {
	if ti < 0 || ti >= w.trigger_count {
		return -1
	}
	return world_find_trigger_type(w, name_str(&w.triggers[ti].type))
}

// The value of property p for trigger ti: its own, else its type's default (0 if there is none).
world_trigger_value :: proc(w: ^World, ti, p: int) -> i32 {
	tt := trigger_type_of(w, ti)
	if tt < 0 {
		return 0
	}
	return prop_value(&w.trigger_types[tt].props, &w.triggers[ti].overrides, p)
}

// Sets property p of trigger ti (a value equal to the default drops the override).
world_trigger_set_value :: proc(w: ^World, ti, p: int, value: i32) -> bool {
	tt := trigger_type_of(w, ti)
	return tt >= 0 && prop_override_set(&w.trigger_types[tt].props, &w.triggers[ti].overrides, p, value)
}

// --- Where triggers are --------------------------------------------------------------------------

Trigger_Place_Result :: enum {
	Placed,
	Outside, // the cell is not on the map
	Unknown, // no such trigger, map or feature
}

// Puts a trigger in a cell (of any map), taking it from wherever it was (a cell or a feature).
world_place_trigger :: proc(w: ^World, u: Uuid, mi, x, y: int) -> Trigger_Place_Result {
	ti := world_find_trigger(w, u)
	if ti < 0 || mi < 0 || mi >= w.map_count {
		return .Unknown
	}
	m := &w.maps[mi]
	if x < 0 || y < 0 || x >= m.width || y >= m.height {
		return .Outside
	}
	t := &w.triggers[ti]
	t.place, t.map_name, t.x, t.y, t.feature = .Cell, m.name, x, y, UUID_NONE
	return .Placed
}

// Puts a trigger on a feature (it then follows the feature), taking it from its cell if it was in one.
// False if the trigger or the feature does not exist.
world_attach_trigger :: proc(w: ^World, u, feature: Uuid) -> bool {
	ti := world_find_trigger(w, u)
	if ti < 0 || world_find_feature(w, feature) < 0 {
		return false
	}
	t := &w.triggers[ti]
	t.place, t.map_name, t.x, t.y, t.feature = .Feature, {}, 0, 0, feature
	return true
}

// Takes a trigger out of its cell or off its feature. Returns true if it had a place.
world_unplace_trigger :: proc(w: ^World, u: Uuid) -> bool {
	ti := world_find_trigger(w, u)
	if ti < 0 || w.triggers[ti].place == .None {
		return false
	}
	t := &w.triggers[ti]
	t.place, t.map_name, t.x, t.y, t.feature = .None, {}, 0, 0, UUID_NONE
	return true
}

// The cell a trigger sits in (not for one on a feature or nowhere).
world_trigger_cell :: proc(w: ^World, ti: int) -> (mi, x, y: int, ok: bool) {
	if ti < 0 || ti >= w.trigger_count || w.triggers[ti].place != .Cell {
		return 0, 0, 0, false
	}
	t := &w.triggers[ti]
	mi = world_find_map(w, name_str(&t.map_name))
	return mi, t.x, t.y, mi >= 0
}

// The triggers in a cell, in table order. On the temp allocator unless another is given.
world_triggers_in_cell :: proc(w: ^World, mi, x, y: int, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	if mi < 0 || mi >= w.map_count {
		return out[:]
	}
	map_name := name_str(&w.maps[mi].name)
	for i in 0 ..< w.trigger_count {
		t := &w.triggers[i]
		if t.place == .Cell && t.x == x && t.y == y && name_str(&t.map_name) == map_name {
			append(&out, i)
		}
	}
	return out[:]
}

// The triggers on a feature (by uuid), in table order.
world_triggers_on_feature :: proc(w: ^World, feature: Uuid, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	if uuid_is_none(feature) {
		return out[:]
	}
	for i in 0 ..< w.trigger_count {
		if w.triggers[i].place == .Feature && w.triggers[i].feature == feature {
			append(&out, i)
		}
	}
	return out[:]
}

// How many triggers sit in cells of map mi.
world_map_trigger_count :: proc(w: ^World, mi: int) -> (n: int) {
	if mi < 0 || mi >= w.map_count {
		return 0
	}
	map_name := name_str(&w.maps[mi].name)
	for i in 0 ..< w.trigger_count {
		if w.triggers[i].place == .Cell && name_str(&w.triggers[i].map_name) == map_name {
			n += 1
		}
	}
	return
}

// How many triggers sit in the part of map mi that a new size would cut off.
world_map_trigger_shrink_blocked :: proc(w: ^World, mi, width, height: int) -> (n: int) {
	if mi < 0 || mi >= w.map_count {
		return 0
	}
	map_name := name_str(&w.maps[mi].name)
	for i in 0 ..< w.trigger_count {
		t := &w.triggers[i]
		if t.place == .Cell && name_str(&t.map_name) == map_name && (t.x >= width || t.y >= height) {
			n += 1
		}
	}
	return
}

// Takes every trigger out of the cells of map mi (before the map goes); they stay in the table.
world_map_unplace_triggers :: proc(w: ^World, mi: int) {
	if mi < 0 || mi >= w.map_count {
		return
	}
	map_name := name_str(&w.maps[mi].name)
	for i in 0 ..< w.trigger_count {
		t := &w.triggers[i]
		if t.place == .Cell && name_str(&t.map_name) == map_name {
			t.place, t.map_name, t.x, t.y = .None, {}, 0, 0
		}
	}
}

// A map was renamed: its triggers follow.
triggers_follow_map :: proc(w: ^World, old, new: string) {
	for i in 0 ..< w.trigger_count {
		t := &w.triggers[i]
		if t.place == .Cell && name_str(&t.map_name) == old {
			name_assign(&t.map_name, new)
		}
	}
}

// A feature is going: its triggers stay in the table, on nothing.
triggers_leave_feature :: proc(w: ^World, feature: Uuid) {
	for i in 0 ..< w.trigger_count {
		if w.triggers[i].place == .Feature && w.triggers[i].feature == feature {
			w.triggers[i].place, w.triggers[i].feature = .None, UUID_NONE
		}
	}
}

// --- Turning a map carries its triggers -----------------------------------------------------------
//
// The cell operations of common/world_map.odin know nothing of the world; these wrappers do them and move
// the map's triggers with their cells. They return true if anything changed (cells or triggers).

Map_Turn :: enum {
	Flip_Horizontal,
	Flip_Vertical,
	Rotate_Left,
	Rotate_Right,
	Rotate_180,
}

world_map_turn :: proc(w: ^World, mi: int, turn: Map_Turn) -> (changed: bool) {
	if mi < 0 || mi >= w.map_count {
		return false
	}
	m := &w.maps[mi]
	n := m.width
	if (turn == .Rotate_Left || turn == .Rotate_Right) && m.width != m.height {
		return false // a quarter turn would change the map's size: not offered
	}
	switch turn {
	case .Flip_Horizontal:
		changed = map_flip_horizontal(m)
	case .Flip_Vertical:
		changed = map_flip_vertical(m)
	case .Rotate_Left:
		changed = map_rotate_left(m)
	case .Rotate_Right:
		changed = map_rotate_right(m)
	case .Rotate_180:
		changed = map_rotate_180(m)
	}
	map_name := name_str(&m.name)
	for i in 0 ..< w.trigger_count {
		t := &w.triggers[i]
		if t.place != .Cell || name_str(&t.map_name) != map_name {
			continue
		}
		x, y := t.x, t.y
		switch turn {
		case .Flip_Horizontal:
			x = m.width - 1 - t.x
		case .Flip_Vertical:
			y = m.height - 1 - t.y
		case .Rotate_Right: // clockwise: the top row becomes the right column
			x, y = n - 1 - t.y, t.x
		case .Rotate_Left:
			x, y = t.y, n - 1 - t.x
		case .Rotate_180:
			x, y = m.width - 1 - t.x, m.height - 1 - t.y
		}
		if x != t.x || y != t.y {
			t.x, t.y = x, y
			changed = true
		}
	}
	return
}

// --- File format -------------------------------------------------------------------------------
//
//   "trigger_types": [ { "name": "spikes", "sprite_set": "things", "sprite": "spikes", "tags": [ "trap" ],
//                        "props": [ { "name": "damage", "value": 5 } ] } ],
//   "triggers": [ { "uuid": "3f2a9c1e-...", "name": "Hall trap", "type": "spikes", "tags": [], "tags_cleared": [],
//                   "props": { "damage": 8 }, "map": "dungeon", "x": 4, "y": 2 },
//                 { "uuid": "...", "name": "Door lock", "type": "lock", "tags": [], "tags_cleared": [],
//                   "feature": "7d0e..." } ]
// A trigger with no "map" and no "feature" is in no place; "map" (with "x" and "y") and "feature" never
// come together. Every reference must exist. All of it is optional when reading (a world from before
// triggers).

write_triggers :: proc(b: ^strings.Builder, w: ^World) {
	strings.write_string(b, "  \"trigger_types\": [")
	for i in 0 ..< w.trigger_type_count {
		tt := &w.trigger_types[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(
			b,
			"    {{\"name\": \"%s\", \"sprite_set\": \"%s\", \"sprite\": \"%s\", \"tags\": ",
			escape_name(name_str(&tt.name)),
			escape_name(name_str(&tt.sprite_set)),
			escape_name(name_str(&tt.sprite)),
		)
		write_tag_list(b, w, tt.tags)
		if tt.props.count > 0 {
			strings.write_string(b, ", \"props\": ")
			write_prop_set(b, &tt.props)
		}
		strings.write_string(b, "}")
	}
	strings.write_string(b, w.trigger_type_count == 0 ? "],\n" : "\n  ],\n")
	strings.write_string(b, "  \"triggers\": [")
	for i in 0 ..< w.trigger_count {
		t := &w.triggers[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(b, "    {{\"uuid\": \"%s\", \"name\": \"%s\", \"type\": \"%s\", \"tags\": ", uuid_to_string(t.uuid), escape_name(name_str(&t.name)), escape_name(name_str(&t.type)))
		write_tag_list(b, w, t.tags_set)
		strings.write_string(b, ", \"tags_cleared\": ")
		write_tag_list(b, w, t.tags_cleared)
		if tt := world_find_trigger_type(w, name_str(&t.type)); tt >= 0 && t.overrides.mask != 0 {
			strings.write_string(b, ", \"props\": ")
			write_prop_overrides(b, &w.trigger_types[tt].props, &t.overrides)
		}
		switch t.place {
		case .None:
		case .Cell:
			fmt.sbprintf(b, ", \"map\": \"%s\", \"x\": %d, \"y\": %d", escape_name(name_str(&t.map_name)), t.x, t.y)
		case .Feature:
			fmt.sbprintf(b, ", \"feature\": \"%s\"", uuid_to_string(t.feature))
		}
		strings.write_string(b, "}")
	}
	strings.write_string(b, w.trigger_count == 0 ? "],\n" : "\n  ],\n")
}

// Reads the trigger types and the triggers. Run after the features and the inventories (a trigger may be
// on a feature, and its uuid may not be any of theirs).
read_triggers :: proc(root: json.Object, tmp: ^World) -> (err: string) {
	if list, present := root["trigger_types"]; present {
		types, is_list := list.(json.Array)
		if !is_list {
			return `"trigger_types" must be a list`
		}
		if len(types) > WORLD_MAX_TRIGGER_TYPES {
			return fmt.tprintf("%d trigger types is more than the %d allowed", len(types), WORLD_MAX_TRIGGER_TYPES)
		}
		for item, i in types {
			obj, ok := item.(json.Object)
			if !ok {
				return fmt.tprintf("trigger type %d must be an object", i)
			}
			name, name_ok := obj["name"].(json.String)
			if !name_ok {
				return fmt.tprintf(`trigger type %d: "name" must be text`, i)
			}
			if p := world_check_trigger_type_name(tmp, -1, name); p != .None {
				return fmt.tprintf(`trigger type %d: the name "%s" is %v`, i, name, name_problem_text(p))
			}
			set, set_ok := obj["sprite_set"].(json.String)
			sprite, sprite_ok := obj["sprite"].(json.String)
			if !set_ok || !sprite_ok {
				return fmt.tprintf(`trigger type "%s": "sprite_set" and "sprite" must be text ("" for not set)`, name)
			}
			if (len(set) == 0) != (len(sprite) == 0) {
				return fmt.tprintf(`trigger type "%s": "sprite_set" and "sprite" must both be set or both be ""`, name)
			}
			tt := &tmp.trigger_types[i]
			name_assign(&tt.name, name)
			if len(set) > 0 {
				si := world_find_sprite_set(tmp, set)
				if si < 0 {
					return fmt.tprintf(`trigger type "%s": there is no sprite set "%s"`, name, set)
				}
				if sprite_set_find(&tmp.sprite_sets[si], sprite) < 0 {
					return fmt.tprintf(`trigger type "%s": sprite set "%s" has no sprite "%s"`, name, set, sprite)
				}
				name_assign(&tt.sprite_set, set)
				name_assign(&tt.sprite, sprite)
			}
			mask, mask_err := read_tag_mask(obj, "tags", tmp, fmt.tprintf(`trigger type "%s"`, name))
			if mask_err != "" {
				return mask_err
			}
			tt.tags = mask
			if msg := read_prop_set(obj, &tt.props, fmt.tprintf(`trigger type "%s"`, name)); msg != "" {
				return msg
			}
			tmp.trigger_type_count += 1
		}
	}
	list, present := root["triggers"]
	if !present {
		return ""
	}
	items, is_list := list.(json.Array)
	if !is_list {
		return `"triggers" must be a list`
	}
	if len(items) > WORLD_MAX_TRIGGERS {
		return fmt.tprintf("%d triggers is more than the %d allowed", len(items), WORLD_MAX_TRIGGERS)
	}
	seen := make(map[Uuid]bool, context.temp_allocator)
	for item, i in items {
		obj, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("trigger %d must be an object", i)
		}
		text, text_ok := obj["uuid"].(json.String)
		u, uuid_ok := uuid_from_string(text)
		if !text_ok || !uuid_ok || uuid_is_none(u) {
			return fmt.tprintf(`trigger %d: "uuid" must look like 3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17`, i)
		}
		if seen[u] || world_find_character(tmp, u) >= 0 || world_find_feature(tmp, u) >= 0 || world_find_inventory(tmp, u) >= 0 {
			return fmt.tprintf(`trigger %d: the uuid %s is used more than once`, i, text)
		}
		seen[u] = true
		name, name_ok := obj["name"].(json.String)
		if !name_ok || name_text_problem(name) != .None {
			return fmt.tprintf(`trigger %d: "name" must be 1 to %d printable ASCII characters`, i, NAME_MAX)
		}
		type_name, type_ok := obj["type"].(json.String)
		tt := type_ok ? world_find_trigger_type(tmp, type_name) : -1
		if tt < 0 {
			return fmt.tprintf(`trigger %d ("%s"): "type" must name a trigger type`, i, name)
		}
		what := fmt.tprintf(`trigger %d ("%s")`, i, name)
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
		t := &tmp.triggers[i]
		t^ = {}
		t.uuid = u
		t.tags_set, t.tags_cleared = set_mask, cleared_mask
		name_assign(&t.name, name)
		name_assign(&t.type, type_name)
		if msg := read_prop_overrides(obj, &tmp.trigger_types[tt].props, &t.overrides, what); msg != "" {
			return msg
		}
		// Where it is.
		map_text, has_map := obj["map"]
		feature_text, has_feature := obj["feature"]
		switch {
		case has_map && has_feature:
			return fmt.tprintf(`%s: "map" and "feature" cannot both be given`, what)
		case has_map:
			map_name, map_ok := map_text.(json.String)
			x, x_ok := obj["x"].(json.Integer)
			y, y_ok := obj["y"].(json.Integer)
			if !map_ok || !x_ok || !y_ok {
				return fmt.tprintf(`%s: a trigger in a cell needs "map", "x" and "y"`, what)
			}
			mi := world_find_map(tmp, map_name)
			if mi < 0 {
				return fmt.tprintf(`%s: there is no map "%s"`, what, map_name)
			}
			if x < 0 || y < 0 || int(x) >= tmp.maps[mi].width || int(y) >= tmp.maps[mi].height {
				return fmt.tprintf(`%s: the cell is outside map "%s"`, what, map_name)
			}
			t.place, t.x, t.y = .Cell, int(x), int(y)
			name_assign(&t.map_name, map_name)
		case has_feature:
			ftext, f_ok := feature_text.(json.String)
			fu, fu_ok := uuid_from_string(ftext)
			if !f_ok || !fu_ok || world_find_feature(tmp, fu) < 0 {
				return fmt.tprintf(`%s: "feature" must be the uuid of a feature`, what)
			}
			t.place, t.feature = .Feature, fu
		}
		tmp.trigger_count += 1
	}
	return ""
}
