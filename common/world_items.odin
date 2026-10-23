package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Items and inventories (design in coxswain task #1 of project anvil).
//
// An item type (name, sprite, tags, max stack, numeric properties) says what every item of the type
// shares. Items only exist inside inventories, as entries: {type, count, overrides}. An entry has no
// identity of its own: a stack of one is a unique item (a sword with its own durability), a bigger stack
// is a counted one (gold). A type's max_stack says which: 1 = never stacks. Overrides change some of the
// type's property defaults for that entry only; entries merge only when their type and every property
// value are equal, and never beyond max_stack.
//
// An inventory is its own thing: a uuid plus its entries, which live in one world-wide pool (the entries
// of one inventory keep their order, first entry first). It has exactly one owner, and the owner holds
// the uuid: a character (Character.inventory), a feature (Feature.inventory) or a map cell
// (World_Map.inventories). An inventory never lingers empty: when its last entry goes, it is removed and
// its owner has none. Inventories never block anything and take no part in the one-per-cell rule.

WORLD_MAX_ITEM_TYPES :: 128
WORLD_MAX_INVENTORIES :: 1024
WORLD_MAX_ENTRIES :: 8192 // in the whole world, over all inventories
INVENTORY_MAX_ENTRIES :: 256 // in one inventory
ITEM_MAX_STACK :: 1_000_000_000

Item_Type :: struct {
	name:       Name,
	sprite_set: Name, // empty = not set
	sprite:     Name, // the sprite's name within that set; empty = not set
	tags:       Tag_Mask, // the tags every item of this type has
	max_stack:  int, // 1..ITEM_MAX_STACK; 1 = never stacks
	props:      Prop_Set, // the properties every item of the type has, with their defaults
}

Entry :: struct {
	inventory: Uuid, // the inventory it is in
	type:      Name, // the item type, by name
	count:     int, // 1..the type's max_stack
	overrides: Prop_Overrides, // the property values that differ from the type's defaults
}

Inventory :: struct {
	uuid: Uuid,
}

Owner_Kind :: enum {
	Cell,
	Character,
	Feature,
}

// Who holds an inventory. A cell is a map and a position; a character or a feature is its uuid.
Inventory_Owner :: struct {
	kind:         Owner_Kind,
	map_index:    int,
	x, y:         int,
	uuid:         Uuid,
}

owner_cell :: proc(map_index, x, y: int) -> Inventory_Owner {
	return {kind = .Cell, map_index = map_index, x = x, y = y}
}

owner_character :: proc(u: Uuid) -> Inventory_Owner {
	return {kind = .Character, uuid = u}
}

owner_feature :: proc(u: Uuid) -> Inventory_Owner {
	return {kind = .Feature, uuid = u}
}

// --- Item types --------------------------------------------------------------------------------

world_find_item_type :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.item_type_count {
		if i != except && name_str(&w.item_types[i].name) == name {
			return i
		}
	}
	return -1
}

world_check_item_type_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_item_type(w, name, index) >= 0 ? .In_Use : .None
}

@(private = "file")
item_type_names :: proc(w: ^World) -> []string {
	out := make([]string, w.item_type_count, context.temp_allocator)
	for i in 0 ..< w.item_type_count {
		out[i] = name_str(&w.item_types[i].name)
	}
	return out
}

// The sprite an item type draws, or nil while it is not set (or points at nothing).
world_item_type_sprite :: proc(w: ^World, it: ^Item_Type) -> ^Sprite {
	si := world_find_sprite_set(w, name_str(&it.sprite_set))
	if si < 0 {
		return nil
	}
	i := sprite_set_find(&w.sprite_sets[si], name_str(&it.sprite))
	return i >= 0 ? &w.sprite_sets[si].sprites[i] : nil
}

// Points a type at the first sprite of the first sprite set that has one; not set if none.
world_item_type_point_at_first :: proc(w: ^World, it: ^Item_Type) {
	it.sprite_set, it.sprite = {}, {}
	for si in 0 ..< w.sprite_set_count {
		if w.sprite_sets[si].count > 0 {
			it.sprite_set = w.sprite_sets[si].name
			it.sprite = w.sprite_sets[si].sprites[0].name
			return
		}
	}
}

// Adds an item type ("item_type") that never stacks, drawing the first sprite. Returns its index or -1 if full.
world_add_item_type :: proc(w: ^World, base := "item_type") -> int {
	if w.item_type_count >= WORLD_MAX_ITEM_TYPES {
		return -1
	}
	i := w.item_type_count
	w.item_types[i] = {}
	w.item_types[i].max_stack = 1
	name_assign(&w.item_types[i].name, unique_among(base, item_type_names(w)))
	world_item_type_point_at_first(w, &w.item_types[i])
	w.item_type_count += 1
	return i
}

// Copies type i right after itself as "<name>_copy". Returns the new index or -1 if full.
world_duplicate_item_type :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.item_type_count || w.item_type_count >= WORLD_MAX_ITEM_TYPES {
		return -1
	}
	at := i + 1
	for k := w.item_type_count; k > at; k -= 1 {
		w.item_types[k] = w.item_types[k - 1]
	}
	w.item_types[at] = w.item_types[i]
	name_assign(&w.item_types[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.item_types[i].name)), item_type_names(w)))
	w.item_type_count += 1
	return at
}

// How many inventory entries have this type.
world_item_type_uses :: proc(w: ^World, name: string) -> (n: int) {
	for i in 0 ..< w.entry_count {
		if name_str(&w.entries[i].type) == name {
			n += 1
		}
	}
	return
}

// Deletes type i unless an entry has it. Returns the number of entries in the way (0 = done).
world_delete_item_type :: proc(w: ^World, i: int) -> (uses: int) {
	if i < 0 || i >= w.item_type_count {
		return 0
	}
	if uses = world_item_type_uses(w, name_str(&w.item_types[i].name)); uses > 0 {
		return
	}
	for k in i ..< w.item_type_count - 1 {
		w.item_types[k] = w.item_types[k + 1]
	}
	w.item_types[w.item_type_count - 1] = {}
	w.item_type_count -= 1
	return 0
}

// Renames type i; every entry of that type follows.
world_rename_item_type :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.item_type_count {
		return .Empty
	}
	if p := world_check_item_type_name(w, i, name); p != .None {
		return p
	}
	old := strings.clone(name_str(&w.item_types[i].name), context.temp_allocator)
	for e in 0 ..< w.entry_count {
		if name_str(&w.entries[e].type) == old {
			name_assign(&w.entries[e].type, name)
		}
	}
	name_assign(&w.item_types[i].name, name)
	return .None
}

// Sets how many items fit in one stack (clamped to 1..ITEM_MAX_STACK). Refused (returns the number of
// entries that are already bigger; 0 = done) while an entry of the type holds more than the new size.
world_set_item_type_max_stack :: proc(w: ^World, i: int, max_stack: int) -> (too_big: int) {
	if i < 0 || i >= w.item_type_count {
		return 0
	}
	n := clamp(max_stack, 1, ITEM_MAX_STACK)
	name := name_str(&w.item_types[i].name)
	for e in 0 ..< w.entry_count {
		if name_str(&w.entries[e].type) == name && w.entries[e].count > n {
			too_big += 1
		}
	}
	if too_big == 0 {
		w.item_types[i].max_stack = n
	}
	return
}

// Adds a property to type i (a unique name made from `base`, default `value`). Returns its index or -1 if full.
world_item_type_add_prop :: proc(w: ^World, i: int, base := "property", value: i32 = 0) -> int {
	if i < 0 || i >= w.item_type_count {
		return -1
	}
	return prop_set_add(&w.item_types[i].props, base, value)
}

// Deletes property p of type i; the entries of the type lose their override of it and the ones above shift down.
world_item_type_delete_prop :: proc(w: ^World, i, p: int) -> bool {
	if i < 0 || i >= w.item_type_count || !prop_set_delete(&w.item_types[i].props, p) {
		return false
	}
	name := name_str(&w.item_types[i].name)
	for e in 0 ..< w.entry_count {
		if name_str(&w.entries[e].type) == name {
			prop_overrides_remove(&w.entries[e].overrides, p)
		}
	}
	return true
}

// --- Sprites used by item types ----------------------------------------------------------------

world_sprite_set_item_type_uses :: proc(w: ^World, set: string) -> (n: int) {
	for i in 0 ..< w.item_type_count {
		if name_str(&w.item_types[i].sprite_set) == set {
			n += 1
		}
	}
	return
}

world_sprite_item_type_uses :: proc(w: ^World, set, sprite: string) -> (n: int) {
	for i in 0 ..< w.item_type_count {
		it := &w.item_types[i]
		if name_str(&it.sprite_set) == set && name_str(&it.sprite) == sprite {
			n += 1
		}
	}
	return
}

// A sprite set was renamed: the types drawing its sprites follow.
item_types_follow_sprite_set :: proc(w: ^World, old, new: string) {
	for i in 0 ..< w.item_type_count {
		if name_str(&w.item_types[i].sprite_set) == old {
			name_assign(&w.item_types[i].sprite_set, new)
		}
	}
}

// A sprite was renamed: the types drawing it follow.
item_types_follow_sprite :: proc(w: ^World, set, old, new: string) {
	for i in 0 ..< w.item_type_count {
		it := &w.item_types[i]
		if name_str(&it.sprite_set) == set && name_str(&it.sprite) == old {
			name_assign(&it.sprite, new)
		}
	}
}

// --- Entries -----------------------------------------------------------------------------------

// The effective value of property p of an entry (its own, else its type's default); 0 if the entry's
// type or the property does not exist.
world_entry_value :: proc(w: ^World, e: ^Entry, p: int) -> i32 {
	ti := world_find_item_type(w, name_str(&e.type))
	if ti < 0 {
		return 0
	}
	return prop_value(&w.item_types[ti].props, &e.overrides, p)
}

// Sets property p of an entry (a value equal to the type's default clears the override). Entries are
// found with world_owner_entry.
world_entry_set_value :: proc(w: ^World, e: ^Entry, p: int, value: i32) -> bool {
	ti := world_find_item_type(w, name_str(&e.type))
	if ti < 0 {
		return false
	}
	return prop_override_set(&w.item_types[ti].props, &e.overrides, p, value)
}

// True if two entries could be one stack: the same type and the same value for every property.
world_entries_mergeable :: proc(w: ^World, a, b: ^Entry) -> bool {
	if a.type != b.type {
		return false
	}
	ti := world_find_item_type(w, name_str(&a.type))
	return ti >= 0 && prop_values_equal(&w.item_types[ti].props, &a.overrides, &b.overrides)
}

// --- Inventories -------------------------------------------------------------------------------

world_find_inventory :: proc(w: ^World, u: Uuid) -> int {
	if uuid_is_none(u) {
		return -1
	}
	for i in 0 ..< w.inventory_count {
		if w.inventories[i].uuid == u {
			return i
		}
	}
	return -1
}

// How many entries inventory u has.
world_inventory_entry_count :: proc(w: ^World, u: Uuid) -> (n: int) {
	if uuid_is_none(u) {
		return 0
	}
	for i in 0 ..< w.entry_count {
		if w.entries[i].inventory == u {
			n += 1
		}
	}
	return
}

// The pool index of entry n (0 = first) of inventory u, or -1.
world_inventory_entry_index :: proc(w: ^World, u: Uuid, n: int) -> int {
	if uuid_is_none(u) || n < 0 {
		return -1
	}
	k := 0
	for i in 0 ..< w.entry_count {
		if w.entries[i].inventory == u {
			if k == n {
				return i
			}
			k += 1
		}
	}
	return -1
}

@(private = "file")
pool_remove :: proc(w: ^World, i: int) {
	for k in i ..< w.entry_count - 1 {
		w.entries[k] = w.entries[k + 1]
	}
	w.entries[w.entry_count - 1] = {}
	w.entry_count -= 1
}

// --- Who holds an inventory --------------------------------------------------------------------

// The uuid of the inventory the owner holds, or none (also for an owner that does not exist).
world_owner_inventory :: proc(w: ^World, o: Inventory_Owner) -> Uuid {
	switch o.kind {
	case .Cell:
		if o.map_index < 0 || o.map_index >= w.map_count {
			return UUID_NONE
		}
		m := &w.maps[o.map_index]
		if o.x < 0 || o.y < 0 || o.x >= m.width || o.y >= m.height {
			return UUID_NONE
		}
		return m.inventories[o.y][o.x]
	case .Character:
		if i := world_find_character(w, o.uuid); i >= 0 {
			return w.characters[i].inventory
		}
	case .Feature:
		if i := world_find_feature(w, o.uuid); i >= 0 {
			return w.features[i].inventory
		}
	}
	return UUID_NONE
}

// True if the owner exists (a cell inside a map, a character or feature of the table).
world_owner_exists :: proc(w: ^World, o: Inventory_Owner) -> bool {
	switch o.kind {
	case .Cell:
		if o.map_index < 0 || o.map_index >= w.map_count {
			return false
		}
		m := &w.maps[o.map_index]
		return o.x >= 0 && o.y >= 0 && o.x < m.width && o.y < m.height
	case .Character:
		return world_find_character(w, o.uuid) >= 0
	case .Feature:
		return world_find_feature(w, o.uuid) >= 0
	}
	return false
}

@(private = "file")
owner_set_inventory :: proc(w: ^World, o: Inventory_Owner, u: Uuid) {
	switch o.kind {
	case .Cell:
		w.maps[o.map_index].inventories[o.y][o.x] = u
	case .Character:
		w.characters[world_find_character(w, o.uuid)].inventory = u
	case .Feature:
		w.features[world_find_feature(w, o.uuid)].inventory = u
	}
}

// Who holds inventory u (the first owner found; there is only ever one), if anyone.
world_inventory_owner :: proc(w: ^World, u: Uuid) -> (o: Inventory_Owner, ok: bool) {
	if uuid_is_none(u) {
		return {}, false
	}
	for i in 0 ..< w.character_count {
		if w.characters[i].inventory == u {
			return owner_character(w.characters[i].uuid), true
		}
	}
	for i in 0 ..< w.feature_count {
		if w.features[i].inventory == u {
			return owner_feature(w.features[i].uuid), true
		}
	}
	for mi in 0 ..< w.map_count {
		m := &w.maps[mi]
		for y in 0 ..< m.height {
			for x in 0 ..< m.width {
				if m.inventories[y][x] == u {
					return owner_cell(mi, x, y), true
				}
			}
		}
	}
	return {}, false
}

// Removes inventory u with all its entries and tells its owner it has none.
world_delete_inventory :: proc(w: ^World, u: Uuid) -> bool {
	ii := world_find_inventory(w, u)
	if ii < 0 {
		return false
	}
	if o, ok := world_inventory_owner(w, u); ok {
		owner_set_inventory(w, o, UUID_NONE)
	}
	for e := w.entry_count - 1; e >= 0; e -= 1 {
		if w.entries[e].inventory == u {
			pool_remove(w, e)
		}
	}
	for k in ii ..< w.inventory_count - 1 {
		w.inventories[k] = w.inventories[k + 1]
	}
	w.inventories[w.inventory_count - 1] = {}
	w.inventory_count -= 1
	return true
}

// Empty inventories do not linger: removes u if it has no entries left. Returns true if it did.
world_inventory_tidy :: proc(w: ^World, u: Uuid) -> bool {
	if world_find_inventory(w, u) >= 0 && world_inventory_entry_count(w, u) == 0 {
		return world_delete_inventory(w, u)
	}
	return false
}

// Removes the inventory the owner holds, if any, with all it contains.
world_owner_clear_inventory :: proc(w: ^World, o: Inventory_Owner) -> bool {
	return world_delete_inventory(w, world_owner_inventory(w, o))
}

// Entry n (0 = first) of the owner's inventory, or nil.
world_owner_entry :: proc(w: ^World, o: Inventory_Owner, n: int) -> ^Entry {
	if i := world_inventory_entry_index(w, world_owner_inventory(w, o), n); i >= 0 {
		return &w.entries[i]
	}
	return nil
}

world_owner_entry_count :: proc(w: ^World, o: Inventory_Owner) -> int {
	return world_inventory_entry_count(w, world_owner_inventory(w, o))
}

Add_Result :: enum {
	Added, // everything was added
	Partly, // some was added; the rest did not fit (limits)
	None_Fit, // nothing was added (limits); nothing changed
	No_Owner, // the owner does not exist
	Unknown_Type, // no such item type
	Bad_Count, // the count must be at least 1
}

// Puts `count` items of type `type_index` (with these overrides) into the owner's inventory, which is
// made if the owner has none. Items fill up stacks that match (same type and values) before new
// entries are made, and a stack never exceeds the type's max_stack. Returns how many did not fit
// (entry limits, the world's pool and its inventory table).
world_owner_add :: proc(w: ^World, o: Inventory_Owner, type_index, count: int, overrides := Prop_Overrides{}) -> (left: int, result: Add_Result) {
	if !world_owner_exists(w, o) {
		return count, .No_Owner
	}
	if type_index < 0 || type_index >= w.item_type_count {
		return count, .Unknown_Type
	}
	if count < 1 {
		return count, .Bad_Count
	}
	it := &w.item_types[type_index]
	// Keep only overrides that matter (same numbers, same overrides).
	want := Entry{type = it.name}
	for p in 0 ..< it.props.count {
		if overrides.mask & (1 << uint(p)) != 0 {
			prop_override_set(&it.props, &want.overrides, p, overrides.values[p])
		}
	}
	u := world_owner_inventory(w, o)
	made := false
	if uuid_is_none(u) {
		if w.inventory_count >= WORLD_MAX_INVENTORIES {
			return count, .None_Fit
		}
		u = world_new_uuid(w)
		w.inventories[w.inventory_count] = {u}
		w.inventory_count += 1
		owner_set_inventory(w, o, u)
		made = true
	}
	left = count
	in_inventory := world_inventory_entry_count(w, u)
	for e in 0 ..< w.entry_count {
		if left == 0 {
			break
		}
		if w.entries[e].inventory == u && world_entries_mergeable(w, &w.entries[e], &want) {
			room := it.max_stack - w.entries[e].count
			if room > 0 {
				put := min(room, left)
				w.entries[e].count += put
				left -= put
			}
		}
	}
	for left > 0 && in_inventory < INVENTORY_MAX_ENTRIES && w.entry_count < WORLD_MAX_ENTRIES {
		put := min(it.max_stack, left)
		w.entries[w.entry_count] = want
		w.entries[w.entry_count].inventory = u
		w.entries[w.entry_count].count = put
		w.entry_count += 1
		in_inventory += 1
		left -= put
	}
	if made {
		world_inventory_tidy(w, u) // nothing fit: do not leave an empty one
	}
	switch {
	case left == 0:
		return 0, .Added
	case left == count:
		return left, .None_Fit
	}
	return left, .Partly
}

// Takes up to `count` items from entry n of the owner's inventory (the entry goes when its count
// reaches 0, and an inventory with nothing left goes with it). Returns how many were taken.
world_owner_remove :: proc(w: ^World, o: Inventory_Owner, n, count: int) -> (taken: int) {
	u := world_owner_inventory(w, o)
	i := world_inventory_entry_index(w, u, n)
	if i < 0 || count < 1 {
		return 0
	}
	taken = min(count, w.entries[i].count)
	w.entries[i].count -= taken
	if w.entries[i].count == 0 {
		pool_remove(w, i)
		world_inventory_tidy(w, u)
	}
	return
}

// --- Standing on maps --------------------------------------------------------------------------

// How many map cells hold an inventory in the part of map mi that a new size would cut off.
world_map_inventory_shrink_blocked :: proc(w: ^World, mi, width, height: int) -> (n: int) {
	if mi < 0 || mi >= w.map_count {
		return 0
	}
	m := &w.maps[mi]
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if (x >= width || y >= height) && !uuid_is_none(m.inventories[y][x]) {
				n += 1
			}
		}
	}
	return
}

// How many cells of map mi hold an inventory.
world_map_inventory_count :: proc(w: ^World, mi: int) -> (n: int) {
	if mi < 0 || mi >= w.map_count {
		return 0
	}
	m := &w.maps[mi]
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if !uuid_is_none(m.inventories[y][x]) {
				n += 1
			}
		}
	}
	return
}

// Deletes every inventory held by a cell of map mi (before the map goes).
world_map_clear_inventories :: proc(w: ^World, mi: int) {
	if mi < 0 || mi >= w.map_count {
		return
	}
	m := &w.maps[mi]
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			world_delete_inventory(w, m.inventories[y][x])
		}
	}
}

// --- File format -------------------------------------------------------------------------------
//
//   "item_types": [ { "name": "sword", "sprite_set": "things", "sprite": "sword", "tags": [ "weapon" ],
//                     "max_stack": 1, "props": [ { "name": "damage", "value": 5 },
//                                                { "name": "durability", "value": 100 } ] } ],
//   "inventories": [ { "uuid": "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17",
//                      "owner": { "kind": "character", "uuid": "..." },
//                      "entries": [ { "type": "sword", "count": 1, "props": { "durability": 40 } },
//                                   { "type": "gold", "count": 250 } ] } ]
// An owner is { "kind": "character" | "feature", "uuid": "..." } or
// { "kind": "cell", "map": "town", "x": 2, "y": 1 }. Every reference must exist; an inventory has
// 1..256 entries (an empty one is an error) and exactly one owner, and an owner holds one inventory.
// All of it is optional when reading (a world from before items). Entries are written in order.

write_items :: proc(b: ^strings.Builder, w: ^World) {
	strings.write_string(b, "  \"item_types\": [")
	for i in 0 ..< w.item_type_count {
		it := &w.item_types[i]
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(
			b,
			"    {{\"name\": \"%s\", \"sprite_set\": \"%s\", \"sprite\": \"%s\", \"max_stack\": %d, \"tags\": ",
			escape_name(name_str(&it.name)),
			escape_name(name_str(&it.sprite_set)),
			escape_name(name_str(&it.sprite)),
			it.max_stack,
		)
		write_tag_list(b, w, it.tags)
		strings.write_string(b, ", \"props\": ")
		write_prop_set(b, &it.props)
		strings.write_string(b, "}")
	}
	strings.write_string(b, w.item_type_count == 0 ? "],\n" : "\n  ],\n")
	strings.write_string(b, "  \"inventories\": [")
	for i in 0 ..< w.inventory_count {
		u := w.inventories[i].uuid
		strings.write_string(b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(b, "    {{\"uuid\": \"%s\", \"owner\": ", uuid_to_string(u))
		if o, ok := world_inventory_owner(w, u); ok {
			switch o.kind {
			case .Cell:
				fmt.sbprintf(b, "{{\"kind\": \"cell\", \"map\": \"%s\", \"x\": %d, \"y\": %d}}", escape_name(name_str(&w.maps[o.map_index].name)), o.x, o.y)
			case .Character:
				fmt.sbprintf(b, "{{\"kind\": \"character\", \"uuid\": \"%s\"}}", uuid_to_string(o.uuid))
			case .Feature:
				fmt.sbprintf(b, "{{\"kind\": \"feature\", \"uuid\": \"%s\"}}", uuid_to_string(o.uuid))
			}
		} else {
			strings.write_string(b, "null") // cannot happen through the procs here; a reader refuses it
		}
		strings.write_string(b, ", \"entries\": [")
		first := true
		for e in 0 ..< w.entry_count {
			en := &w.entries[e]
			if en.inventory != u {
				continue
			}
			fmt.sbprintf(b, "%s{{\"type\": \"%s\", \"count\": %d", first ? "" : ", ", escape_name(name_str(&en.type)), en.count)
			if ti := world_find_item_type(w, name_str(&en.type)); ti >= 0 && en.overrides.mask != 0 {
				strings.write_string(b, ", \"props\": ")
				write_prop_overrides(b, &w.item_types[ti].props, &en.overrides)
			}
			strings.write_string(b, "}")
			first = false
		}
		strings.write_string(b, "]}")
	}
	strings.write_string(b, w.inventory_count == 0 ? "],\n" : "\n  ],\n")
}

// Reads the item types and the inventories. Run after the characters and the features (owners).
read_items :: proc(root: json.Object, tmp: ^World) -> (err: string) {
	if list, present := root["item_types"]; present {
		types, is_list := list.(json.Array)
		if !is_list {
			return `"item_types" must be a list`
		}
		if len(types) > WORLD_MAX_ITEM_TYPES {
			return fmt.tprintf("%d item types is more than the %d allowed", len(types), WORLD_MAX_ITEM_TYPES)
		}
		for item, i in types {
			obj, ok := item.(json.Object)
			if !ok {
				return fmt.tprintf("item type %d must be an object", i)
			}
			name, name_ok := obj["name"].(json.String)
			if !name_ok {
				return fmt.tprintf(`item type %d: "name" must be text`, i)
			}
			if p := world_check_item_type_name(tmp, -1, name); p != .None {
				return fmt.tprintf(`item type %d: the name "%s" is %v`, i, name, name_problem_text(p))
			}
			set, set_ok := obj["sprite_set"].(json.String)
			sprite, sprite_ok := obj["sprite"].(json.String)
			if !set_ok || !sprite_ok {
				return fmt.tprintf(`item type "%s": "sprite_set" and "sprite" must be text ("" for not set)`, name)
			}
			if (len(set) == 0) != (len(sprite) == 0) {
				return fmt.tprintf(`item type "%s": "sprite_set" and "sprite" must both be set or both be ""`, name)
			}
			it := &tmp.item_types[i]
			name_assign(&it.name, name)
			if len(set) > 0 {
				si := world_find_sprite_set(tmp, set)
				if si < 0 {
					return fmt.tprintf(`item type "%s": there is no sprite set "%s"`, name, set)
				}
				if sprite_set_find(&tmp.sprite_sets[si], sprite) < 0 {
					return fmt.tprintf(`item type "%s": sprite set "%s" has no sprite "%s"`, name, set, sprite)
				}
				name_assign(&it.sprite_set, set)
				name_assign(&it.sprite, sprite)
			}
			it.max_stack = 1
			if v, has := obj["max_stack"]; has {
				n, n_ok := v.(json.Integer)
				if !n_ok || n < 1 || n > ITEM_MAX_STACK {
					return fmt.tprintf(`item type "%s": "max_stack" must be a whole number from 1 to %d`, name, ITEM_MAX_STACK)
				}
				it.max_stack = int(n)
			}
			mask, mask_err := read_tag_mask(obj, "tags", tmp, fmt.tprintf(`item type "%s"`, name))
			if mask_err != "" {
				return mask_err
			}
			it.tags = mask
			if msg := read_prop_set(obj, &it.props, fmt.tprintf(`item type "%s"`, name)); msg != "" {
				return msg
			}
			tmp.item_type_count += 1
		}
	}
	list, present := root["inventories"]
	if !present {
		return ""
	}
	items, is_list := list.(json.Array)
	if !is_list {
		return `"inventories" must be a list`
	}
	if len(items) > WORLD_MAX_INVENTORIES {
		return fmt.tprintf("%d inventories is more than the %d allowed", len(items), WORLD_MAX_INVENTORIES)
	}
	seen := make(map[Uuid]bool, context.temp_allocator)
	for item, i in items {
		obj, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("inventory %d must be an object", i)
		}
		text, text_ok := obj["uuid"].(json.String)
		u, uuid_ok := uuid_from_string(text)
		if !text_ok || !uuid_ok || uuid_is_none(u) {
			return fmt.tprintf(`inventory %d: "uuid" must look like 3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17`, i)
		}
		if seen[u] || world_find_character(tmp, u) >= 0 || world_find_feature(tmp, u) >= 0 {
			return fmt.tprintf(`inventory %d: the uuid %s is used more than once`, i, text)
		}
		seen[u] = true
		what := fmt.tprintf("inventory %d", i)
		o, owner_msg := read_inventory_owner(obj, tmp, what)
		if owner_msg != "" {
			return owner_msg
		}
		if !uuid_is_none(world_owner_inventory(tmp, o)) {
			return fmt.tprintf("%s: its owner already holds another inventory", what)
		}
		entries, entries_ok := obj["entries"].(json.Array)
		if !entries_ok {
			return fmt.tprintf(`%s: "entries" must be a list`, what)
		}
		if len(entries) == 0 {
			return fmt.tprintf("%s: an inventory with no entries must not be in the file", what)
		}
		if len(entries) > INVENTORY_MAX_ENTRIES {
			return fmt.tprintf("%s: %d entries is more than the %d allowed", what, len(entries), INVENTORY_MAX_ENTRIES)
		}
		if tmp.entry_count + len(entries) > WORLD_MAX_ENTRIES {
			return fmt.tprintf("more than %d entries in all", WORLD_MAX_ENTRIES)
		}
		for entry, k in entries {
			e, e_ok := entry.(json.Object)
			if !e_ok {
				return fmt.tprintf("%s: entry %d must be an object", what, k)
			}
			type_name, type_ok := e["type"].(json.String)
			ti := type_ok ? world_find_item_type(tmp, type_name) : -1
			if ti < 0 {
				return fmt.tprintf(`%s: entry %d: "type" must name an item type`, what, k)
			}
			n, n_ok := e["count"].(json.Integer)
			if !n_ok || n < 1 || int(n) > tmp.item_types[ti].max_stack {
				return fmt.tprintf(`%s: entry %d: "count" must be a whole number from 1 to the type's max_stack (%d)`, what, k, tmp.item_types[ti].max_stack)
			}
			en := &tmp.entries[tmp.entry_count]
			en^ = {
				inventory = u,
				count     = int(n),
			}
			name_assign(&en.type, type_name)
			if msg := read_prop_overrides(e, &tmp.item_types[ti].props, &en.overrides, fmt.tprintf("%s: entry %d", what, k)); msg != "" {
				return msg
			}
			tmp.entry_count += 1
		}
		tmp.inventories[tmp.inventory_count] = {u}
		tmp.inventory_count += 1
		owner_set_inventory(tmp, o, u)
	}
	return ""
}

@(private = "file")
read_inventory_owner :: proc(obj: json.Object, tmp: ^World, what: string) -> (o: Inventory_Owner, err: string) {
	own, own_ok := obj["owner"].(json.Object)
	if !own_ok {
		return {}, fmt.tprintf(`%s: "owner" must be an object`, what)
	}
	kind, kind_ok := own["kind"].(json.String)
	if !kind_ok {
		return {}, fmt.tprintf(`%s: the owner needs a "kind" of "character", "feature" or "cell"`, what)
	}
	switch kind {
	case "character", "feature":
		text, text_ok := own["uuid"].(json.String)
		u, uuid_ok := uuid_from_string(text)
		if !text_ok || !uuid_ok {
			return {}, fmt.tprintf(`%s: the owner needs a "uuid"`, what)
		}
		if kind == "character" {
			if world_find_character(tmp, u) < 0 {
				return {}, fmt.tprintf("%s: the owner names the unknown character %s", what, text)
			}
			return owner_character(u), ""
		}
		if world_find_feature(tmp, u) < 0 {
			return {}, fmt.tprintf("%s: the owner names the unknown feature %s", what, text)
		}
		return owner_feature(u), ""
	case "cell":
		map_name, map_ok := own["map"].(json.String)
		x, x_ok := own["x"].(json.Integer)
		y, y_ok := own["y"].(json.Integer)
		if !map_ok || !x_ok || !y_ok {
			return {}, fmt.tprintf(`%s: a cell owner needs "map", "x" and "y"`, what)
		}
		mi := world_find_map(tmp, map_name)
		if mi < 0 {
			return {}, fmt.tprintf(`%s: the owner names the unknown map "%s"`, what, map_name)
		}
		m := &tmp.maps[mi]
		if x < 0 || y < 0 || int(x) >= m.width || int(y) >= m.height {
			return {}, fmt.tprintf(`%s: the owner cell is outside map "%s"`, what, map_name)
		}
		return owner_cell(mi, int(x), int(y)), ""
	}
	return {}, fmt.tprintf(`%s: the owner's "kind" must be "character", "feature" or "cell"`, what)
}
