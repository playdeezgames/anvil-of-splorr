#+build !js
package common

import "core:strings"
import "core:testing"

// The feature world plus item types "sword" (never stacks; damage 5, durability 100), "gold" (stacks
// to 100) and "arrow" (stacks to 10; damage 2). Goo (character 0) carries a sword with durability 40
// and 250 gold (three entries: sword, 100, 100, 50 -> four), Oak (feature 0) holds 3 arrows, and the
// cell 0,0 of map m holds 5 gold.
item_world :: proc() -> ^World {
	w := feature_world()
	sword := world_add_item_type(w, "sword")
	world_item_type_add_prop(w, sword, "damage", 5)
	world_item_type_add_prop(w, sword, "durability", 100)
	gold := world_add_item_type(w, "gold")
	world_set_item_type_max_stack(w, gold, 100)
	arrow := world_add_item_type(w, "arrow")
	world_set_item_type_max_stack(w, arrow, 10)
	world_item_type_add_prop(w, arrow, "damage", 2)
	goo := owner_character(w.characters[0].uuid)
	hurt := Prop_Overrides{}
	prop_override_set(&w.item_types[sword].props, &hurt, 1, 40)
	world_owner_add(w, goo, sword, 1, hurt)
	world_owner_add(w, goo, gold, 250)
	world_owner_add(w, owner_feature(w.features[0].uuid), arrow, 3)
	world_owner_add(w, owner_cell(0, 0, 0), gold, 5)
	return w
}

goo_owner :: proc(w: ^World) -> Inventory_Owner {
	return owner_character(w.characters[0].uuid)
}

@(test)
test_properties_are_named_overridden_and_shifted :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: Prop_Set
	a := prop_set_add(&s, "damage", 5)
	b := prop_set_add(&s, "damage", 7) // made unique
	c := prop_set_add(&s, "weight", 3)
	testing.expect(t, a == 0 && b == 1 && c == 2 && name_str(&s.names[1]) == "damage_2")
	testing.expect_value(t, prop_set_check_name(&s, 0, "weight"), Name_Problem.In_Use)
	testing.expect_value(t, prop_set_check_name(&s, 0, "damage"), Name_Problem.None)
	testing.expect_value(t, prop_set_rename(&s, 1, "weight"), Name_Problem.In_Use)
	testing.expect_value(t, prop_set_rename(&s, 1, "range"), Name_Problem.None)
	for _ in 3 ..< PROP_MAX {
		testing.expect(t, prop_set_add(&s) >= 0)
	}
	testing.expect_value(t, prop_set_add(&s), -1) // 16 is the most
	o: Prop_Overrides
	testing.expect_value(t, prop_value(&s, &o, 1), 7)
	testing.expect(t, prop_override_set(&s, &o, 1, 9) && prop_value(&s, &o, 1) == 9 && o.mask == 2)
	testing.expect(t, prop_override_set(&s, &o, 2, 4) && o.mask == 6)
	testing.expect(t, prop_override_set(&s, &o, 1, 7) && o.mask == 4) // the default again: no override kept
	testing.expect(t, !prop_override_set(&s, &o, 99, 1))
	// Deleting property 0 moves the others down, overrides with them.
	prop_set_delete(&s, 0)
	prop_overrides_remove(&o, 0)
	testing.expect_value(t, name_str(&s.names[0]), "range")
	testing.expect(t, o.mask == 2 && prop_value(&s, &o, 1) == 4) // "weight" is property 1 now
	// Two ways to the same numbers are equal.
	x, y: Prop_Overrides
	prop_override_set(&s, &x, 1, 4)
	testing.expect(t, prop_values_equal(&s, &o, &x))
	prop_override_set(&s, &y, 0, 8)
	testing.expect(t, !prop_values_equal(&s, &o, &y))
}

@(test)
test_item_types_are_named_limited_and_protected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	testing.expect_value(t, w.item_type_count, 3)
	testing.expect_value(t, name_str(&w.item_types[0].sprite_set), "creatures") // points at the first sprite
	testing.expect(t, world_item_type_sprite(w, &w.item_types[0]) == &w.sprite_sets[0].sprites[0])
	testing.expect_value(t, w.item_types[0].max_stack, 1) // a new type never stacks
	testing.expect_value(t, world_add_item_type(w, "gold"), 3)
	testing.expect_value(t, name_str(&w.item_types[3].name), "gold_2")
	testing.expect_value(t, world_check_item_type_name(w, 0, "gold"), Name_Problem.In_Use)
	testing.expect_value(t, world_check_item_type_name(w, 0, "sword"), Name_Problem.None)
	testing.expect_value(t, world_check_item_type_name(w, 0, ""), Name_Problem.Empty)
	d := world_duplicate_item_type(w, 0)
	testing.expect(t, d == 1 && name_str(&w.item_types[1].name) == "sword_copy" && w.item_types[1].props.count == 2)
	world_delete_item_type(w, 1)
	for w.item_type_count < WORLD_MAX_ITEM_TYPES {
		testing.expect(t, world_add_item_type(w) >= 0)
	}
	testing.expect_value(t, world_add_item_type(w), -1) // 128 is the most
	testing.expect_value(t, world_duplicate_item_type(w, 0), -1)
	// A type with entries cannot be deleted; a rename is followed.
	testing.expect_value(t, world_item_type_uses(w, "gold"), 4) // 100, 100, 50 and the cell's 5
	testing.expect_value(t, world_delete_item_type(w, 1), 4)
	testing.expect_value(t, world_rename_item_type(w, 1, "sword"), Name_Problem.In_Use)
	testing.expect_value(t, world_rename_item_type(w, 1, "coin"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.entries[1].type), "coin")
	// Max stack: refused while an entry is bigger.
	testing.expect_value(t, world_set_item_type_max_stack(w, 1, 60), 2)
	testing.expect_value(t, w.item_types[1].max_stack, 100)
	testing.expect_value(t, world_set_item_type_max_stack(w, 1, 0), 4) // clamped to 1: every gold entry is in the way
	testing.expect_value(t, w.item_types[1].max_stack, 100)
	testing.expect_value(t, world_set_item_type_max_stack(w, 0, 0), 0) // swords are all single already
	testing.expect_value(t, w.item_types[0].max_stack, 1)
}

@(test)
test_a_sprite_an_item_type_draws_is_protected_and_followed :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	// The feature types draw "slime" and "bat", the item types "slime": none of the sprites can go.
	testing.expect(t, world_sprite_item_type_uses(w, "creatures", "slime") == 3)
	testing.expect(t, world_sprite_set_item_type_uses(w, "creatures") == 3)
	testing.expect(t, world_sprite_uses(w, "creatures", "slime") >= 3)
	testing.expect_value(t, world_rename_sprite_set(w, 0, "beasts"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.item_types[0].sprite_set), "beasts")
}

@(test)
test_items_stack_to_the_max_and_never_across_different_values :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	goo := goo_owner(w)
	testing.expect_value(t, world_owner_entry_count(w, goo), 4)
	counts := [4]int{}
	for i in 0 ..< 4 {
		counts[i] = world_owner_entry(w, goo, i).count
	}
	testing.expect_value(t, counts, [4]int{1, 100, 100, 50})
	// More gold fills the half stack first, then makes a new entry.
	left, res := world_owner_add(w, goo, 1, 80)
	testing.expect(t, left == 0 && res == .Added)
	testing.expect_value(t, world_owner_entry(w, goo, 3).count, 100)
	testing.expect_value(t, world_owner_entry(w, goo, 4).count, 30)
	// A second sword never joins the first, even with the same numbers; one at the default is its own entry.
	_, res = world_owner_add(w, goo, 0, 1)
	testing.expect_value(t, res, Add_Result.Added)
	_, res = world_owner_add(w, goo, 0, 1)
	testing.expect_value(t, world_owner_entry_count(w, goo), 7)
	// Arrows merge only with the same values.
	oak := owner_feature(w.features[0].uuid)
	world_owner_add(w, oak, 2, 4) // 3 + 4 = 7 in one stack
	testing.expect_value(t, world_owner_entry_count(w, oak), 1)
	testing.expect_value(t, world_owner_entry(w, oak, 0).count, 7)
	strong := Prop_Overrides{}
	prop_override_set(&w.item_types[2].props, &strong, 0, 9)
	world_owner_add(w, oak, 2, 5, strong)
	testing.expect_value(t, world_owner_entry_count(w, oak), 2)
	same := Prop_Overrides{}
	prop_override_set(&w.item_types[2].props, &same, 0, 2) // the default: counts as no override
	left, res = world_owner_add(w, oak, 2, 5, same)
	testing.expect(t, left == 0 && res == .Added && world_owner_entry(w, oak, 0).count == 10 && world_owner_entry(w, oak, 2).count == 2)
	testing.expect_value(t, world_owner_entry(w, oak, 2).overrides.mask, u16(0))
	// Properties an entry reads: its own, else the type's.
	testing.expect_value(t, world_entry_value(w, world_owner_entry(w, goo, 0), 0), 5)
	testing.expect_value(t, world_entry_value(w, world_owner_entry(w, goo, 0), 1), 40)
	testing.expect(t, world_entry_set_value(w, world_owner_entry(w, goo, 0), 1, 100) && world_owner_entry(w, goo, 0).overrides.mask == 0)
	// Refusals.
	_, res = world_owner_add(w, goo, 9, 1)
	testing.expect_value(t, res, Add_Result.Unknown_Type)
	_, res = world_owner_add(w, goo, 1, 0)
	testing.expect_value(t, res, Add_Result.Bad_Count)
	_, res = world_owner_add(w, owner_character(UUID_NONE), 1, 1)
	testing.expect_value(t, res, Add_Result.No_Owner)
	_, res = world_owner_add(w, owner_cell(0, 9, 9), 1, 1)
	testing.expect_value(t, res, Add_Result.No_Owner)
}

@(test)
test_an_inventory_has_at_most_256_entries_and_never_lingers_empty :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	pip := owner_character(w.characters[2].uuid)
	for _ in 0 ..< INVENTORY_MAX_ENTRIES {
		_, res := world_owner_add(w, pip, 0, 1) // swords never stack
		testing.expect_value(t, res, Add_Result.Added)
	}
	left, res := world_owner_add(w, pip, 0, 1)
	testing.expect(t, left == 1 && res == .None_Fit)
	testing.expect_value(t, world_owner_entry_count(w, pip), INVENTORY_MAX_ENTRIES)
	left, res = world_owner_add(w, pip, 1, 250) // gold: no room for a new entry either
	testing.expect(t, left == 250 && res == .None_Fit)
	// Take one sword off: now 100 of the gold fits, the rest does not.
	testing.expect_value(t, world_owner_remove(w, pip, 255, 1), 1)
	left, res = world_owner_add(w, pip, 1, 250)
	testing.expect(t, left == 150 && res == .Partly)
	// Nothing fit into a fresh owner's would-be inventory: it is not left behind.
	count := w.inventory_count
	pip2 := owner_character(w.characters[1].uuid)
	testing.expect_value(t, world_owner_inventory(w, pip2), UUID_NONE)
	world_owner_add(w, pip2, 0, 1)
	testing.expect_value(t, w.inventory_count, count + 1)
	// Removing the last item removes the inventory and the owner's reference to it.
	testing.expect_value(t, world_owner_remove(w, pip2, 0, 5), 1)
	testing.expect_value(t, w.inventory_count, count)
	testing.expect_value(t, world_owner_inventory(w, pip2), UUID_NONE)
	testing.expect_value(t, world_owner_remove(w, pip2, 0, 1), 0)
	// A partial take leaves the entry; taking all of an entry closes the gap.
	goo := goo_owner(w)
	testing.expect_value(t, world_owner_remove(w, goo, 1, 30), 30)
	testing.expect_value(t, world_owner_entry(w, goo, 1).count, 70)
	testing.expect_value(t, world_owner_remove(w, goo, 1, 1000), 70)
	testing.expect_value(t, world_owner_entry_count(w, goo), 3)
	testing.expect_value(t, world_owner_entry(w, goo, 1).count, 100)
	// Nothing is orphaned: every entry belongs to an inventory in the table.
	for e in 0 ..< w.entry_count {
		testing.expect(t, world_find_inventory(w, w.entries[e].inventory) >= 0)
	}
}

@(test)
test_inventories_go_with_their_owners :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	before := w.inventory_count
	testing.expect_value(t, before, 3)
	// A copy of a character or a feature carries nothing.
	c := world_duplicate_character(w, 0)
	testing.expect_value(t, w.characters[c].inventory, UUID_NONE)
	f := world_duplicate_feature(w, 0)
	testing.expect_value(t, w.features[f].inventory, UUID_NONE)
	// Deleting the feature deletes what it held.
	arrows := w.features[0].inventory
	testing.expect(t, world_inventory_entry_count(w, arrows) == 1)
	world_delete_feature(w, 0)
	testing.expect_value(t, world_find_inventory(w, arrows), -1)
	testing.expect_value(t, w.inventory_count, 2)
	// Deleting the character as well.
	world_delete_character(w, 0)
	testing.expect_value(t, w.inventory_count, 1)
	testing.expect_value(t, w.entry_count, 1) // the cell's 5 gold
	// A map takes its cells' inventories with it; a copy of a map has none.
	d := world_duplicate_map(w, 0)
	testing.expect_value(t, world_map_inventory_count(w, d), 0)
	testing.expect(t, world_delete_map(w, 0))
	testing.expect_value(t, w.inventory_count, 0)
	testing.expect_value(t, w.entry_count, 0)
}

@(test)
test_cell_inventories_move_with_flips_and_block_shrinking :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	m := &w.maps[0] // 3 x 2, an inventory at 0,0
	cell := owner_cell(0, 0, 0)
	u := world_owner_inventory(w, cell)
	testing.expect(t, !uuid_is_none(u))
	testing.expect(t, map_flip_horizontal(m))
	testing.expect_value(t, world_owner_inventory(w, owner_cell(0, 2, 0)), u)
	testing.expect_value(t, world_owner_inventory(w, cell), UUID_NONE)
	testing.expect(t, map_flip_vertical(m))
	testing.expect_value(t, world_owner_inventory(w, owner_cell(0, 2, 1)), u)
	testing.expect(t, map_rotate_180(m))
	testing.expect_value(t, world_owner_inventory(w, cell), u)
	// Cutting one off is refused, like a character (Oak stands at 2,1 too: move it first).
	world_unplace_feature(w, w.features[0].uuid)
	far := owner_cell(0, 2, 1)
	world_owner_add(w, far, 1, 1)
	testing.expect_value(t, world_map_inventory_shrink_blocked(w, 0, 2, 2), 1)
	testing.expect(t, !world_map_set_size(w, 0, 2, 2) && m.width == 3)
	world_owner_remove(w, far, 0, 1)
	testing.expect_value(t, world_map_inventory_shrink_blocked(w, 0, 2, 2), 0)
	testing.expect(t, world_map_set_size(w, 0, 2, 2) && m.width == 2)
	testing.expect_value(t, world_owner_inventory(w, cell), u)
}

@(test)
test_items_round_trip_in_the_world_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	world_toggle_item_type_tag_for_test(w)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `"item_types": [`))
	testing.expect(t, strings.contains(text, `"max_stack": 100`))
	testing.expect(t, strings.contains(text, `"props": [{"name": "damage", "value": 5}, {"name": "durability", "value": 100}]`))
	testing.expect(t, strings.contains(text, `{"type": "sword", "count": 1, "props": {"durability": 40}}`))
	testing.expect(t, strings.contains(text, `"owner": {"kind": "cell", "map": "m", "x": 0, "y": 0}`))
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect(t, back.item_type_count == 3 && back.inventory_count == 3 && back.entry_count == 6)
	testing.expect(t, back.item_types[0].tags == tag_bit(TAG_SOLID))
	testing.expect_value(t, world_entry_value(back, world_owner_entry(back, goo_owner(back), 0), 1), 40)
	// A world from before items loads with none.
	empty := new_world()
	defer free(empty)
	old, _ := strings.replace(world_to_json(empty), `"item_types"`, `"item_types_x"`, 1, context.temp_allocator)
	old, _ = strings.replace(old, `"inventories"`, `"inventories_x"`, 1, context.temp_allocator)
	testing.expect_value(t, world_from_json(transmute([]u8)old, back), "")
	testing.expect(t, back.item_type_count == 0 && back.inventory_count == 0 && back.entry_count == 0)
}

world_toggle_item_type_tag_for_test :: proc(w: ^World) {
	w.item_types[0].tags |= tag_bit(TAG_SOLID)
}

@(test)
test_bad_item_data_is_rejected_and_changes_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	goo := uuid_to_string(w.characters[0].uuid)
	oak := uuid_to_string(w.features[0].uuid)
	cell_inv := uuid_to_string(w.maps[0].inventories[0][0])
	variations := [][2]string {
		{`{"name": "gold", "sprite_set"`, `{"name": "sword", "sprite_set"`}, // duplicate type name
		{`"max_stack": 100`, `"max_stack": 0`},
		{`"max_stack": 100`, `"max_stack": "many"`},
		{`"sprite_set": "creatures", "sprite": "slime", "max_stack": 1,`, `"sprite_set": "nope", "sprite": "slime", "max_stack": 1,`},
		{`{"name": "damage", "value": 5}`, `{"name": "damage", "value": 5.5}`},
		{`{"name": "damage", "value": 5}`, `{"name": "durability", "value": 5}`}, // a property twice
		{`{"type": "sword", "count": 1,`, `{"type": "spear", "count": 1,`},
		{`{"type": "sword", "count": 1,`, `{"type": "sword", "count": 2,`}, // more than max_stack
		{`{"type": "sword", "count": 1,`, `{"type": "sword", "count": 0,`},
		{`"props": {"durability": 40}`, `"props": {"colour": 40}`},
		{cat(`"uuid": "`, cell_inv, `"`), cat(`"uuid": "`, goo, `"`)}, // an inventory with a character's uuid
		{cat(`"kind": "feature", "uuid": "`, oak), `"kind": "feature", "uuid": "ffffffff-ffff-4fff-bfff-ffffffffffff`},
		{cat(`"kind": "feature", "uuid": "`, oak), cat(`"kind": "character", "uuid": "`, goo)}, // two inventories on one owner
		{`"kind": "cell", "map": "m"`, `"kind": "cell", "map": "nowhere"`},
		{`"kind": "cell", "map": "m", "x": 0`, `"kind": "cell", "map": "m", "x": 9`},
		{`"kind": "cell"`, `"kind": "pocket"`},
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		testing.expectf(t, load_error(bad) != "", "variation %d was accepted", i)
	}
	// An inventory with no entries must not be in the file.
	empty_inv, _ := strings.replace(good, `"entries": [{"type": "arrow", "count": 3}]`, `"entries": []`, 1, context.temp_allocator)
	testing.expect(t, empty_inv != good && load_error(empty_inv) != "")
	// A bad file leaves the destination alone.
	dst := item_world()
	defer free(dst)
	count := dst.entry_count
	bad, _ := strings.replace(good, `"type": "sword", "count": 1`, `"type": "spear", "count": 1`, 1, context.temp_allocator)
	testing.expect(t, world_from_json(transmute([]u8)bad, dst) != "" && dst.entry_count == count)
}
