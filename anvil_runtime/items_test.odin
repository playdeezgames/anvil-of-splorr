#+build !js
package anvil_runtime

import cm "../common"
import "core:testing"

// The tiny game plus item types "sword" (never stacks; damage 5, durability 100) and "gold" (stacks
// to 100), loaded: the Hero carries a sword (durability 40) and 250 gold (entries 1, 100, 100, 50), and
// the cell 3,1 of "room" holds 5 gold. Hero is at 1,1 and the cell is two steps to the right.
item_world :: proc() -> ^World {
	w := loaded_world()
	sword := cm.world_add_item_type(w, "sword")
	cm.world_item_type_add_prop(w, sword, "damage", 5)
	cm.world_item_type_add_prop(w, sword, "durability", 100)
	gold := cm.world_add_item_type(w, "gold")
	cm.world_set_item_type_max_stack(w, gold, 100)
	w.item_types[gold].tags = cm.tag_bit(1) // "spawn"
	hero := cm.owner_character(w.characters[index_of_character(w, "Hero")].uuid)
	hurt: Prop_Overrides
	cm.prop_override_set(&w.item_types[sword].props, &hurt, 1, 40)
	cm.world_owner_add(w, hero, sword, 1, hurt)
	cm.world_owner_add(w, hero, gold, 250)
	cm.world_owner_add(w, cm.owner_cell(0, 3, 1), gold, 5)
	// Through the file and back, like a game gets it.
	text := cm.world_to_json(w)
	free(w)
	back := new_world()
	assert(load(back, transmute([]u8)text) == "")
	return back
}

@(test)
test_a_game_asks_about_item_types_as_authored :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	testing.expect_value(t, item_type_count(w), 2)
	sword, ok := find_item_type(w, "sword")
	testing.expect(t, ok && sword == 0)
	_, ok = find_item_type(w, "spear")
	testing.expect(t, !ok)
	gold, _ := find_item_type(w, "gold")
	testing.expect(t, item_type_max_stack(w, sword) == 1 && item_type_max_stack(w, gold) == 100 && item_type_max_stack(w, 9) == 0)
	durability, found := item_prop_index(w, sword, "durability")
	testing.expect(t, found && durability == 1 && item_prop_default(w, sword, durability) == 100)
	_, found = item_prop_index(w, gold, "durability")
	testing.expect(t, !found && item_prop_default(w, sword, 9) == 0)
	spawn, _ := find_tag(w, "spawn")
	testing.expect(t, item_type_has_tag(w, gold, spawn) && !item_type_has_tag(w, sword, spawn))
	testing.expect(t, item_type_sprite(w, sword) != nil && item_type_image(w, sword) != nil && item_type_image(w, 9) == nil)
}

@(test)
test_a_play_state_starts_with_the_authored_inventories_and_leaves_the_world_alone :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	before := cm.world_to_json(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero_i := index_of_character(w, "Hero")
	hero := owner_character(hero_i)
	testing.expect_value(t, play_entry_count(ps, hero), 4)
	sword := play_entry(ps, hero, 0)
	testing.expect(t, sword.item_type == 0 && sword.count == 1)
	testing.expect_value(t, play_entry_value(ps, w, sword, 0), 5) // the type's default
	testing.expect_value(t, play_entry_value(ps, w, sword, 1), 40) // its own
	testing.expect_value(t, play_entry(ps, hero, 2).count, 100)
	testing.expect_value(t, play_entry(ps, hero, 3).count, 50)
	testing.expect(t, play_entry(ps, hero, 4) == nil && play_entry(ps, hero, -1) == nil)
	testing.expect(t, play_cell_has_items(ps, 0, 3, 1) && !play_cell_has_items(ps, 0, 2, 1))
	testing.expect_value(t, len(play_cells_with_items(ps, 0)), 1)
	testing.expect_value(t, play_entry_count(ps, owner_character(index_of_character(w, "Star"))), 0)
	// Changing the play state changes nothing in the world, and a copy is independent.
	play_remove_item(ps, hero, 0, 1)
	play_clear_items(ps, owner_cell(0, 3, 1))
	testing.expect_value(t, cm.world_to_json(w), before)
	play_init(ps, w)
	testing.expect_value(t, play_entry_count(ps, hero), 4)
	testing.expect(t, play_cell_has_items(ps, 0, 3, 1))
}

@(test)
test_adding_stacks_merges_and_respects_the_limits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero := owner_character(index_of_character(w, "Hero"))
	// 80 more gold fills the half stack, then makes a new one.
	left, res := play_add_item(ps, w, hero, 1, 80)
	testing.expect(t, left == 0 && res == .Added)
	testing.expect_value(t, play_entry(ps, hero, 3).count, 100)
	testing.expect_value(t, play_entry(ps, hero, 4).count, 30)
	// A sword never joins another; a value equal to the default is no override.
	_, res = play_add_item(ps, w, hero, 0, 1)
	testing.expect_value(t, res, Add_Result.Added)
	testing.expect_value(t, play_entry_count(ps, hero), 6)
	same: Prop_Overrides
	cm.prop_override_set(&w.item_types[0].props, &same, 0, 5)
	same.mask |= 1 // forced: a caller may pass a default value as an override
	same.values[0] = 5
	play_add_item(ps, w, hero, 0, 1, same)
	testing.expect_value(t, play_entry(ps, hero, 6).overrides.mask, u16(0))
	// Refusals leave nothing behind.
	_, res = play_add_item(ps, w, hero, 9, 1)
	testing.expect_value(t, res, Add_Result.Unknown_Type)
	_, res = play_add_item(ps, w, hero, 1, 0)
	testing.expect_value(t, res, Add_Result.Bad_Count)
	_, res = play_add_item(ps, w, owner_character(99), 1, 1)
	testing.expect_value(t, res, Add_Result.No_Owner)
	_, res = play_add_item(ps, w, owner_cell(0, 9, 9), 1, 1)
	testing.expect_value(t, res, Add_Result.No_Owner)
	// Fill a feature-less cell with 256 swords: the 257th does not fit.
	cell := owner_cell(0, 0, 3)
	for _ in 0 ..< cm.INVENTORY_MAX_ENTRIES {
		_, res = play_add_item(ps, w, cell, 0, 1)
		testing.expect_value(t, res, Add_Result.Added)
	}
	left, res = play_add_item(ps, w, cell, 0, 1)
	testing.expect(t, left == 1 && res == .None_Fit)
	// Properties.
	testing.expect(t, play_set_entry_value(ps, w, hero, 0, 1, 10))
	testing.expect_value(t, play_entry_value(ps, w, play_entry(ps, hero, 0), 1), 10)
	testing.expect(t, play_set_entry_value(ps, w, hero, 0, 1, 100) && play_entry(ps, hero, 0).overrides.mask == 0)
	testing.expect(t, !play_set_entry_value(ps, w, hero, 0, 9, 1) && !play_set_entry_value(ps, w, hero, 99, 0, 1))
}

@(test)
test_removing_transferring_dropping_splitting_and_merging :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero := owner_character(index_of_character(w, "Hero"))
	star := owner_character(index_of_character(w, "Star"))
	// Removing takes what is there; an emptied entry goes.
	testing.expect_value(t, play_remove_item(ps, hero, 3, 20), 20)
	testing.expect_value(t, play_entry(ps, hero, 3).count, 30)
	testing.expect_value(t, play_remove_item(ps, hero, 3, 99), 30)
	testing.expect_value(t, play_entry_count(ps, hero), 3)
	testing.expect_value(t, play_remove_item(ps, hero, 7, 1), 0)
	// Transfer keeps the property values and merges at the target.
	testing.expect_value(t, play_transfer(ps, w, hero, 0, 1, star), 1)
	moved := play_entry(ps, star, 0)
	testing.expect(t, moved != nil && play_entry_value(ps, w, moved, 1) == 40)
	testing.expect_value(t, play_entry(ps, hero, 0).item_type, 1) // the sword left the hero
	testing.expect_value(t, play_transfer(ps, w, hero, 0, 150, star), 100) // one entry at a time
	testing.expect_value(t, play_entry_count(ps, star), 2) // sword, 100
	testing.expect_value(t, play_transfer(ps, w, star, 0, 1, star), 0) // to itself: nothing
	// Dropping is a transfer to a cell; the gold there merges.
	testing.expect_value(t, play_drop(ps, w, star, 1, 100, 0, 3, 1), 100)
	testing.expect_value(t, play_entry(ps, owner_cell(0, 3, 1), 0).count, 100)
	testing.expect_value(t, play_entry(ps, owner_cell(0, 3, 1), 1).count, 5)
	// A split makes a new entry right after; a merge puts it back.
	hero_gold := play_entry(ps, hero, 0)
	testing.expect_value(t, hero_gold.count, 100) // the second 100 of the original 250
	testing.expect(t, play_split(ps, hero, 0, 30))
	testing.expect_value(t, play_entry(ps, hero, 0).count, 70)
	testing.expect_value(t, play_entry(ps, hero, 1).count, 30)
	testing.expect(t, !play_split(ps, hero, 0, 70) && !play_split(ps, hero, 0, 0) && !play_split(ps, hero, 5, 1))
	testing.expect_value(t, play_merge(ps, w, hero, 0, 1), 30)
	testing.expect_value(t, play_entry_count(ps, hero), 1)
	testing.expect_value(t, play_entry(ps, hero, 0).count, 100)
	// Different property values do not merge.
	play_add_item(ps, w, hero, 0, 1)
	play_add_item(ps, w, hero, 0, 1)
	testing.expect_value(t, play_merge(ps, w, hero, 1, 2), 0) // swords never stack
	// Moving everything: as far as it fits, and the emptied source is gone.
	moved_all := play_transfer_all(ps, w, hero, star)
	testing.expect_value(t, moved_all, 102)
	testing.expect_value(t, play_entry_count(ps, hero), 0)
	testing.expect(t, !play_clear_items(ps, hero)) // already none
	testing.expect(t, play_clear_items(ps, star) && play_entry_count(ps, star) == 0)
}

@(test)
test_an_emptied_inventory_does_not_linger :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	used := 0
	for inv in ps.inventories {
		used += inv.in_use ? 1 : 0
	}
	testing.expect_value(t, used, 2)
	testing.expect_value(t, play_remove_item(ps, owner_cell(0, 3, 1), 0, 5), 5)
	testing.expect(t, !play_cell_has_items(ps, 0, 3, 1) && len(play_cells_with_items(ps, 0)) == 0)
	testing.expect_value(t, ps.entry_count, 4)
	// Adding that fits nothing never leaves an empty one: a full pool.
	ps.entry_count = cm.WORLD_MAX_ENTRIES
	left, res := play_add_item(ps, w, owner_cell(0, 0, 0), 1, 3)
	testing.expect(t, left == 3 && res == .None_Fit && !play_cell_has_items(ps, 0, 0, 0))
}

@(test)
test_stepping_onto_an_inventory_queues_a_contact_and_is_never_refused :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero_i := index_of_character(w, "Hero")
	testing.expect_value(t, play_step(ps, w, hero_i, 1, 0), Move_Result.Moved)
	_, any := play_take_contact(ps)
	testing.expect(t, !any) // (2,1) holds nothing
	look, _, _ := play_can_step(ps, w, hero_i, 1, 0) // a plain look queues nothing
	testing.expect_value(t, look, Move_Result.Moved)
	_, any = play_take_contact(ps)
	testing.expect(t, !any)
	testing.expect_value(t, play_step(ps, w, hero_i, 1, 0), Move_Result.Moved)
	c, got := play_take_contact(ps)
	testing.expect(t, got && c.mover == hero_i && c.map_index == 0 && c.x == 3 && c.y == 1 && c.dx == 1 && c.dy == 0)
	_, any = play_take_contact(ps)
	testing.expect(t, !any)
	// Stepping off and on again queues another; nobody who is placed there stops the hero meanwhile.
	play_step(ps, w, hero_i, -1, 0)
	play_step(ps, w, hero_i, 1, 0)
	_, got = play_take_contact(ps)
	testing.expect(t, got)
	// A full queue drops the oldest and counts them.
	play_clear_contacts(ps)
	for _ in 0 ..< MAX_COLLISIONS + 5 {
		play_step(ps, w, hero_i, -1, 0)
		play_step(ps, w, hero_i, 1, 0)
	}
	testing.expect_value(t, ps.contact_count, MAX_COLLISIONS)
	testing.expect_value(t, ps.contacts_lost, 5)
	play_clear_contacts(ps)
	_, got = play_take_contact(ps)
	testing.expect(t, !got && ps.contacts_lost == 0)
	// Picking it up (the game's choice) leaves the cell without an inventory, and no more contacts.
	play_transfer_all(ps, w, owner_cell(0, 3, 1), owner_character(hero_i))
	play_step(ps, w, hero_i, -1, 0)
	play_step(ps, w, hero_i, 1, 0)
	_, got = play_take_contact(ps)
	testing.expect(t, !got && !play_cell_has_items(ps, 0, 3, 1))
}

@(test)
test_a_game_draws_the_inventories_lying_on_the_map :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := item_world()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	log: Draw_Log
	defer delete(log.rects)
	defer delete(log.colors)
	r := draw_renderer(&log)
	d := zoom_window(w, 0, 0, 0, 5, 4, 20, 10, 3)
	draw_inventories(&r, w, ps, d)
	cell := cm.world_cell_rect(d, 3, 1)
	testing.expect(t, len(log.rects) > 0)
	for rc in log.rects {
		testing.expect(t, rc.x >= cell.x && rc.y >= cell.y && rc.x + rc.w <= cell.x + cell.w && rc.y + rc.h <= cell.y + cell.h)
	}
	// Only the first entry shows; a window without the cell draws nothing; so does an empty cell.
	clear(&log.rects)
	draw_inventories(&r, w, ps, zoom_window(w, 0, 0, 0, 3, 4, 20, 10, 3))
	testing.expect_value(t, len(log.rects), 0)
	play_clear_items(ps, owner_cell(0, 3, 1))
	draw_inventories(&r, w, ps, d)
	testing.expect_value(t, len(log.rects), 0)
	// A character's inventory is never drawn on the map.
	draw_inventories(&r, w, ps, zoom_window(w, 0, 0, 0, 5, 4, 20, 10, 3))
	testing.expect_value(t, len(log.rects), 0)
}
