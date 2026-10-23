package anvil_runtime

import cm "../common"

// Items and inventories for a game (design in coxswain task #1 of project anvil). Item types and the
// authored inventories are the world's; what a game does with items happens in the Play_State, which
// `play_init` fills with a copy of the authored inventories.
//
// An inventory belongs to an Owner: a character (by index), a feature (by index) or a map cell. It
// holds entries {item type, count, property overrides}. A stack of one is a unique item (a sword with
// its own durability), a bigger stack a counted one (gold): the type's max stack decides. Entries
// merge only when type and every property value are equal, and never beyond the max stack. An
// inventory that runs empty is gone (its owner has none), and nothing about an inventory blocks a
// step: stepping onto a cell that holds one queues a `Contact` (`play_take_contact`) and the game
// decides what it means (pick it up, ignore it).
//
// Entry numbers are positions in an inventory, first entry 0; they change when entries are added or
// removed, so take a fresh look after each change.

Item_Type :: cm.Item_Type
Prop_Overrides :: cm.Prop_Overrides
Add_Result :: cm.Add_Result
Owner_Kind :: cm.Owner_Kind

// Who holds an inventory. For a character or a feature, `index` is its place in the world's table.
Owner :: struct {
	kind:      Owner_Kind,
	index:     int,
	map_index: int,
	x, y:      int,
}

owner_character :: proc(ci: int) -> Owner {
	return {kind = .Character, index = ci}
}

owner_feature :: proc(fi: int) -> Owner {
	return {kind = .Feature, index = fi}
}

owner_cell :: proc(mi, x, y: int) -> Owner {
	return {kind = .Cell, map_index = mi, x = x, y = y}
}

Play_Inventory :: struct {
	in_use: bool,
	owner:  Owner,
}

// One stack. `item_type` is an index into the world's item types.
Play_Entry :: struct {
	slot:      int, // the inventory (an index into Play_State.inventories)
	item_type: int,
	count:     int,
	overrides: Prop_Overrides,
}

// A character stepped onto a cell that holds an inventory (the step was not refused). The cell is the
// one entered, on `map_index`; (dx, dy) is the step.
Contact :: struct {
	mover:     int, // character index
	map_index: int,
	x, y:      int,
	dx, dy:    int,
}

// --- Item types (as authored) -------------------------------------------------------------------

item_type_count :: proc(w: ^World) -> int {
	return w.item_type_count
}

find_item_type :: proc(w: ^World, name: string) -> (index: int, ok: bool) {
	i := cm.world_find_item_type(w, name)
	return i, i >= 0
}

item_type :: proc(w: ^World, ti: int) -> ^Item_Type {
	if ti < 0 || ti >= w.item_type_count {
		return nil
	}
	return &w.item_types[ti]
}

// How many of a type fit in one stack (1 for a unique item); 0 for no such type.
item_type_max_stack :: proc(w: ^World, ti: int) -> int {
	it := item_type(w, ti)
	return it == nil ? 0 : it.max_stack
}

// The sprite an item type draws, or nil.
item_type_sprite :: proc(w: ^World, ti: int) -> ^Sprite {
	return cm.world_item_type_sprite_of(w, ti)
}

// The tile image of an item type's sprite, or nil (draw it without the sprite's `transparent` colour).
item_type_image :: proc(w: ^World, ti: int) -> ^Image4 {
	sp := item_type_sprite(w, ti)
	return sp == nil ? nil : cm.world_sprite_image(w, sp)
}

item_type_has_tag :: proc(w: ^World, ti, tag: int) -> bool {
	it := item_type(w, ti)
	return it != nil && tag >= 0 && tag < cm.WORLD_MAX_TAGS && it.tags & cm.tag_bit(tag) != 0
}

// The position of a property in an item type's list (what `play_entry_value` and
// `play_set_entry_value` take), by name.
item_prop_index :: proc(w: ^World, ti: int, name: string) -> (index: int, ok: bool) {
	it := item_type(w, ti)
	if it == nil {
		return 0, false
	}
	i := cm.prop_set_find(&it.props, name)
	return i, i >= 0
}

// A property's default for the type (0 for no such type or property).
item_prop_default :: proc(w: ^World, ti, p: int) -> i32 {
	it := item_type(w, ti)
	if it == nil || p < 0 || p >= it.props.count {
		return 0
	}
	return it.props.values[p]
}

// --- Starting: the authored inventories ---------------------------------------------------------

@(private = "package")
play_init_items :: proc(ps: ^Play_State, w: ^World) {
	for ii in 0 ..< w.inventory_count {
		u := w.inventories[ii].uuid
		o, ok := cm.world_inventory_owner(w, u)
		if !ok {
			continue
		}
		po: Owner
		switch o.kind {
		case .Cell:
			po = owner_cell(o.map_index, o.x, o.y)
		case .Character:
			po = owner_character(cm.world_find_character(w, o.uuid))
		case .Feature:
			po = owner_feature(cm.world_find_feature(w, o.uuid))
		}
		ps.inventories[ii] = {true, po}
	}
	for e in 0 ..< w.entry_count {
		en := &w.entries[e]
		slot := cm.world_find_inventory(w, en.inventory)
		ti := cm.world_find_item_type(w, cm.name_str(&en.type))
		if slot < 0 || ti < 0 {
			continue
		}
		ps.entries[ps.entry_count] = {slot, ti, en.count, en.overrides}
		ps.entry_count += 1
	}
}

// --- Looking ------------------------------------------------------------------------------------

@(private = "file")
owner_valid :: proc(ps: ^Play_State, w: ^World, o: Owner) -> bool {
	switch o.kind {
	case .Cell:
		columns, rows, ok := map_size(w, o.map_index)
		return ok && o.x >= 0 && o.y >= 0 && o.x < columns && o.y < rows
	case .Character:
		return o.index >= 0 && o.index < ps.count
	case .Feature:
		return o.index >= 0 && o.index < ps.feature_count
	}
	return false
}

@(private = "file")
find_slot :: proc(ps: ^Play_State, o: Owner) -> int {
	for i in 0 ..< cm.WORLD_MAX_INVENTORIES {
		if ps.inventories[i].in_use && ps.inventories[i].owner == o {
			return i
		}
	}
	return -1
}

@(private = "file")
slot_entries :: proc(ps: ^Play_State, slot: int) -> (n: int) {
	for e in 0 ..< ps.entry_count {
		if ps.entries[e].slot == slot {
			n += 1
		}
	}
	return
}

// The pool index of entry n of a slot, or -1.
@(private = "file")
slot_entry :: proc(ps: ^Play_State, slot, n: int) -> int {
	if slot < 0 || n < 0 {
		return -1
	}
	k := 0
	for e in 0 ..< ps.entry_count {
		if ps.entries[e].slot == slot {
			if k == n {
				return e
			}
			k += 1
		}
	}
	return -1
}

@(private = "file")
pool_remove :: proc(ps: ^Play_State, i: int) {
	for k in i ..< ps.entry_count - 1 {
		ps.entries[k] = ps.entries[k + 1]
	}
	ps.entries[ps.entry_count - 1] = {}
	ps.entry_count -= 1
}

// An inventory that ran empty goes (its owner has none).
@(private = "file")
tidy :: proc(ps: ^Play_State, slot: int) {
	if slot >= 0 && slot_entries(ps, slot) == 0 {
		ps.inventories[slot] = {}
	}
}

// How many entries the owner's inventory has (0 for none).
play_entry_count :: proc(ps: ^Play_State, o: Owner) -> int {
	return slot_entries(ps, find_slot(ps, o))
}

// Entry n of the owner's inventory, or nil. The pointer is good until the next change to any inventory.
play_entry :: proc(ps: ^Play_State, o: Owner, n: int) -> ^Play_Entry {
	if i := slot_entry(ps, find_slot(ps, o), n); i >= 0 {
		return &ps.entries[i]
	}
	return nil
}

// Whether a cell holds an inventory now.
play_cell_has_items :: proc(ps: ^Play_State, mi, x, y: int) -> bool {
	return find_slot(ps, owner_cell(mi, x, y)) >= 0
}

// The cells of a map that hold an inventory now, in no particular order. On the temp allocator unless
// another is given.
play_cells_with_items :: proc(ps: ^Play_State, mi: int, allocator := context.temp_allocator) -> [][2]int {
	out := make([dynamic][2]int, allocator)
	for i in 0 ..< cm.WORLD_MAX_INVENTORIES {
		inv := &ps.inventories[i]
		if inv.in_use && inv.owner.kind == .Cell && inv.owner.map_index == mi {
			append(&out, [2]int{inv.owner.x, inv.owner.y})
		}
	}
	return out[:]
}

// The effective value of property p of an entry: its own, else the type's default.
play_entry_value :: proc(ps: ^Play_State, w: ^World, e: ^Play_Entry, p: int) -> i32 {
	it := item_type(w, e.item_type)
	return it == nil ? 0 : cm.prop_value(&it.props, &e.overrides, p)
}

// --- Changing -----------------------------------------------------------------------------------

@(private = "file")
entries_match :: proc(w: ^World, a: ^Play_Entry, b_type: int, b_overrides: ^Prop_Overrides) -> bool {
	if a.item_type != b_type {
		return false
	}
	it := item_type(w, b_type)
	return it != nil && cm.prop_values_equal(&it.props, &a.overrides, b_overrides)
}

// Puts `count` items of a type (with these overrides) into the owner's inventory, made if the owner
// has none. Items fill stacks that match before new entries are made, and a stack never exceeds the
// type's max stack. Returns how many did not fit (an inventory holds 256 entries, a Play_State
// 8192 and 1024 inventories); nothing is left behind if nothing fit.
play_add_item :: proc(ps: ^Play_State, w: ^World, o: Owner, ti, count: int, overrides := Prop_Overrides{}) -> (left: int, result: Add_Result) {
	if !owner_valid(ps, w, o) {
		return count, .No_Owner
	}
	it := item_type(w, ti)
	if it == nil {
		return count, .Unknown_Type
	}
	if count < 1 {
		return count, .Bad_Count
	}
	want: Prop_Overrides // only overrides that differ from the defaults are kept
	for p in 0 ..< it.props.count {
		if overrides.mask & (1 << uint(p)) != 0 {
			cm.prop_override_set(&it.props, &want, p, overrides.values[p])
		}
	}
	slot := find_slot(ps, o)
	made := false
	if slot < 0 {
		for i in 0 ..< cm.WORLD_MAX_INVENTORIES {
			if !ps.inventories[i].in_use {
				slot = i
				break
			}
		}
		if slot < 0 {
			return count, .None_Fit
		}
		ps.inventories[slot] = {true, o}
		made = true
	}
	left = count
	in_inventory := slot_entries(ps, slot)
	for e in 0 ..< ps.entry_count {
		if left == 0 {
			break
		}
		en := &ps.entries[e]
		if en.slot == slot && entries_match(w, en, ti, &want) {
			if room := it.max_stack - en.count; room > 0 {
				put := min(room, left)
				en.count += put
				left -= put
			}
		}
	}
	for left > 0 && in_inventory < cm.INVENTORY_MAX_ENTRIES && ps.entry_count < cm.WORLD_MAX_ENTRIES {
		put := min(it.max_stack, left)
		ps.entries[ps.entry_count] = {slot, ti, put, want}
		ps.entry_count += 1
		in_inventory += 1
		left -= put
	}
	if made {
		tidy(ps, slot)
	}
	switch {
	case left == 0:
		return 0, .Added
	case left == count:
		return left, .None_Fit
	}
	return left, .Partly
}

// Takes up to `count` items from entry n of the owner's inventory (an entry that reaches 0 goes, and
// an inventory with nothing left goes with it). Returns how many were taken.
play_remove_item :: proc(ps: ^Play_State, o: Owner, n, count: int) -> (taken: int) {
	slot := find_slot(ps, o)
	i := slot_entry(ps, slot, n)
	if i < 0 || count < 1 {
		return 0
	}
	taken = min(count, ps.entries[i].count)
	ps.entries[i].count -= taken
	if ps.entries[i].count == 0 {
		pool_remove(ps, i)
		tidy(ps, slot)
	}
	return
}

// Moves up to `count` items from entry n of one owner's inventory to another's, keeping their
// property values. Only what fits moves; the rest stays. Returns how many moved (0 if nothing: no such
// entry, the same owner, the target full or missing).
play_transfer :: proc(ps: ^Play_State, w: ^World, from: Owner, n, count: int, to: Owner) -> (moved: int) {
	if from == to || count < 1 {
		return 0
	}
	e := play_entry(ps, from, n)
	if e == nil {
		return 0
	}
	ti, overrides := e.item_type, e.overrides
	want := min(count, e.count)
	left, _ := play_add_item(ps, w, to, ti, want, overrides)
	moved = want - left
	if moved > 0 {
		play_remove_item(ps, from, n, moved)
	}
	return
}

// Lets go of entry n of a character's or a feature's inventory onto a cell (`play_transfer` to the
// cell's inventory). Returns how many were dropped.
play_drop :: proc(ps: ^Play_State, w: ^World, from: Owner, n, count, mi, x, y: int) -> int {
	return play_transfer(ps, w, from, n, count, owner_cell(mi, x, y))
}

// Moves everything from one owner's inventory to another's, as far as it fits. Returns how many
// items moved.
play_transfer_all :: proc(ps: ^Play_State, w: ^World, from, to: Owner) -> (moved: int) {
	if from == to {
		return 0
	}
	k := 0
	for {
		e := play_entry(ps, from, k)
		if e == nil {
			return
		}
		before := e.count
		m := play_transfer(ps, w, from, k, before, to)
		moved += m
		if m < before {
			k += 1 // some stayed: look at the next entry
		}
	}
}

// Splits `count` off entry n into a new entry right after it, in the same inventory (so the two can
// be dealt with apart). `count` must be 1 .. entry.count - 1, and there must be room for another entry.
play_split :: proc(ps: ^Play_State, o: Owner, n, count: int) -> bool {
	slot := find_slot(ps, o)
	i := slot_entry(ps, slot, n)
	if i < 0 || count < 1 || count >= ps.entries[i].count {
		return false
	}
	if slot_entries(ps, slot) >= cm.INVENTORY_MAX_ENTRIES || ps.entry_count >= cm.WORLD_MAX_ENTRIES {
		return false
	}
	for k := ps.entry_count; k > i + 1; k -= 1 {
		ps.entries[k] = ps.entries[k - 1]
	}
	ps.entries[i + 1] = ps.entries[i]
	ps.entries[i + 1].count = count
	ps.entries[i].count -= count
	ps.entry_count += 1
	return true
}

// Moves items from entry b into entry a of the same inventory when they match (same type and values),
// up to the max stack. Returns how many moved; an emptied b goes. Entry numbers change after this.
play_merge :: proc(ps: ^Play_State, w: ^World, o: Owner, a, b: int) -> (moved: int) {
	slot := find_slot(ps, o)
	ia, ib := slot_entry(ps, slot, a), slot_entry(ps, slot, b)
	if ia < 0 || ib < 0 || ia == ib {
		return 0
	}
	ea, eb := &ps.entries[ia], &ps.entries[ib]
	if !entries_match(w, ea, eb.item_type, &eb.overrides) {
		return 0
	}
	moved = min(item_type_max_stack(w, ea.item_type) - ea.count, eb.count)
	if moved <= 0 {
		return 0
	}
	ea.count += moved
	eb.count -= moved
	if eb.count == 0 {
		pool_remove(ps, ib)
	}
	return
}

// Sets property p of entry n (a value equal to the type's default clears the override). It does not
// merge anything: a game that wants a stack back calls `play_merge`.
play_set_entry_value :: proc(ps: ^Play_State, w: ^World, o: Owner, n, p: int, value: i32) -> bool {
	e := play_entry(ps, o, n)
	it := e == nil ? nil : item_type(w, e.item_type)
	return it != nil && cm.prop_override_set(&it.props, &e.overrides, p, value)
}

// Throws away the owner's whole inventory. Returns true if it had one.
play_clear_items :: proc(ps: ^Play_State, o: Owner) -> bool {
	slot := find_slot(ps, o)
	if slot < 0 {
		return false
	}
	for e := ps.entry_count - 1; e >= 0; e -= 1 {
		if ps.entries[e].slot == slot {
			pool_remove(ps, e)
		}
	}
	ps.inventories[slot] = {}
	return true
}

// --- Contacts -----------------------------------------------------------------------------------

// The next contact since the last call (oldest first), or ok = false when there is none. A game
// drains these once a frame after its steps, as with collisions.
play_take_contact :: proc(ps: ^Play_State) -> (c: Contact, ok: bool) {
	if ps.contact_count == 0 {
		return {}, false
	}
	c = ps.contacts[ps.contact_head]
	ps.contact_head = (ps.contact_head + 1) % MAX_COLLISIONS
	ps.contact_count -= 1
	return c, true
}

// Forgets the contacts not yet taken (and the lost count).
play_clear_contacts :: proc(ps: ^Play_State) {
	ps.contact_head, ps.contact_count, ps.contacts_lost = 0, 0, 0
}

@(private = "package")
push_contact :: proc(ps: ^Play_State, c: Contact) {
	if ps.contact_count == MAX_COLLISIONS {
		ps.contact_head = (ps.contact_head + 1) % MAX_COLLISIONS
		ps.contact_count -= 1
		ps.contacts_lost += 1
	}
	ps.contacts[(ps.contact_head + ps.contact_count) % MAX_COLLISIONS] = c
	ps.contact_count += 1
}

// --- Drawing ------------------------------------------------------------------------------------

// Draws the inventories lying in cells of the window's map *now*: each cell shows the sprite of its
// first entry's item type, over the terrain. Draw them before the features and the characters.
draw_inventories :: proc(r: ^cm.Renderer, w: ^World, ps: ^Play_State, d: World_Draw) {
	if d.cell_w <= 0 || d.cell_h <= 0 {
		return
	}
	for i in 0 ..< cm.WORLD_MAX_INVENTORIES {
		inv := &ps.inventories[i]
		if !inv.in_use || inv.owner.kind != .Cell || inv.owner.map_index != d.map_index {
			continue
		}
		x, y := inv.owner.x, inv.owner.y
		if x < d.col || y < d.row || x >= d.col + d.cols || y >= d.row + d.rows {
			continue
		}
		if e := slot_entry(ps, i, 0); e >= 0 {
			cm.world_draw_item_type(r, w, ps.entries[e].item_type, cm.world_cell_rect(d, x, y), d.clip, d.missing)
		}
	}
}
