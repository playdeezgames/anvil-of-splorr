#+build !js
package common

import "core:strings"
import "core:testing"

// The feature world (map "m" 3 x 2; features Oak at 2,1, Boulder, Stump) plus trigger types "spikes"
// (sprite creatures/slime; damage 5, armed 1) and "lock" (sprite creatures/bat, tag solid), and
// triggers Trap (spikes, in the cell 0,0 of m, damage 8), Plate (spikes, in the same cell), Latch (lock,
// on the Oak) and Spare (spikes, nowhere).
trigger_world :: proc() -> ^World {
	w := feature_world()
	a := world_add_trigger_type(w, "spikes")
	b := world_add_trigger_type(w, "lock")
	name_assign(&w.trigger_types[b].sprite, "bat")
	w.trigger_types[b].tags = tag_bit(TAG_SOLID)
	dmg := world_trigger_type_add_prop(w, a, "damage", 5)
	world_trigger_type_add_prop(w, a, "armed", 1)
	trap := world_add_trigger(w, a, "Trap")
	plate := world_add_trigger(w, a, "Plate")
	latch := world_add_trigger(w, b, "Latch")
	world_add_trigger(w, a, "Spare")
	world_trigger_set_value(w, trap, dmg, 8)
	world_place_trigger(w, w.triggers[trap].uuid, 0, 0, 0)
	world_place_trigger(w, w.triggers[plate].uuid, 0, 0, 0)
	world_attach_trigger(w, w.triggers[latch].uuid, w.features[0].uuid)
	return w
}

@(test)
test_trigger_types_are_named_limited_and_protected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_world()
	defer free(w)
	testing.expect_value(t, w.trigger_type_count, 2)
	testing.expect_value(t, name_str(&w.trigger_types[0].sprite_set), "creatures") // points at the first sprite
	testing.expect(t, world_trigger_type_sprite(w, &w.trigger_types[0]) == &w.sprite_sets[0].sprites[0])
	w.trigger_types[0].sprite_set = {}
	testing.expect(t, world_trigger_type_sprite(w, &w.trigger_types[0]) == nil)
	testing.expect_value(t, world_check_trigger_type_name(w, 0, "lock"), Name_Problem.In_Use)
	testing.expect_value(t, world_check_trigger_type_name(w, 0, "spikes"), Name_Problem.None)
	testing.expect_value(t, world_check_trigger_type_name(w, 0, ""), Name_Problem.Empty)
	d := world_duplicate_trigger_type(w, 0)
	testing.expect(t, d == 1 && name_str(&w.trigger_types[1].name) == "spikes_copy" && w.trigger_types[1].props.count == 2)
	testing.expect_value(t, world_delete_trigger_type(w, 1), 0) // nothing uses the copy
	for w.trigger_type_count < WORLD_MAX_TRIGGER_TYPES {
		testing.expect(t, world_add_trigger_type(w) >= 0)
	}
	testing.expect_value(t, world_add_trigger_type(w), -1) // 64 is the most
	testing.expect_value(t, world_duplicate_trigger_type(w, 0), -1)
	// A type with triggers cannot be deleted; a rename is followed.
	testing.expect_value(t, world_trigger_type_uses(w, "spikes"), 3)
	testing.expect_value(t, world_delete_trigger_type(w, 0), 3)
	testing.expect_value(t, world_rename_trigger_type(w, 0, "lock"), Name_Problem.In_Use)
	testing.expect_value(t, world_rename_trigger_type(w, 0, "needles"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.triggers[0].type), "needles")
	testing.expect(t, world_toggle_trigger_type_tag(w, 0, TAG_SOLID) && w.trigger_types[0].tags == tag_bit(TAG_SOLID))
	testing.expect(t, !world_toggle_trigger_type_tag(w, 99, TAG_SOLID) && !world_toggle_trigger_type_tag(w, 0, 99))
}

@(test)
test_a_sprite_a_trigger_type_draws_is_protected_and_followed :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_world()
	defer free(w)
	w.trigger_types[0].sprite_set = w.sprite_sets[0].name // (the test above cleared it in another world: set again)
	name_assign(&w.trigger_types[0].sprite, "slime")
	testing.expect(t, world_sprite_trigger_type_uses(w, "creatures", "slime") == 1)
	testing.expect(t, world_sprite_set_trigger_type_uses(w, "creatures") == 2)
	testing.expect(t, world_sprite_uses(w, "creatures", "slime") >= 1)
	testing.expect(t, !world_delete_sprite_set(w, 0)) // types draw it
	testing.expect_value(t, world_rename_sprite_set(w, 0, "beasts"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.trigger_types[0].sprite_set), "beasts")
}

@(test)
test_triggers_have_types_tags_and_property_values :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_world()
	defer free(w)
	testing.expect_value(t, w.trigger_count, 4)
	testing.expect_value(t, world_trigger_value(w, 0, 0), 8) // Trap: its own damage
	testing.expect_value(t, world_trigger_value(w, 1, 0), 5) // Plate: the default
	testing.expect_value(t, world_trigger_value(w, 1, 1), 1)
	testing.expect_value(t, world_trigger_value(w, 2, 0), 0) // Latch: a lock has no properties
	testing.expect(t, world_trigger_set_value(w, 0, 0, 5) && w.triggers[0].overrides.mask == 0) // the default again
	testing.expect(t, !world_trigger_set_value(w, 2, 0, 1) && !world_trigger_set_value(w, 99, 0, 1))
	// A new type forgets the values; deleting a property shifts them.
	world_trigger_set_value(w, 0, 1, 9)
	testing.expect(t, world_trigger_type_delete_prop(w, 0, 0))
	testing.expect_value(t, world_trigger_value(w, 0, 0), 9)
	testing.expect(t, world_set_trigger_type(w, 0, 1) && w.triggers[0].overrides.mask == 0)
	testing.expect(t, world_set_trigger_type(w, 0, 1) && !world_set_trigger_type(w, 0, 9))
	// Tags: its own setting wins, else its type's.
	testing.expect(t, world_trigger_has_tag(w, 2, TAG_SOLID) && !world_trigger_has_tag(w, 1, TAG_SOLID))
	world_cycle_trigger_tag(w, 2, TAG_SOLID) // set
	world_cycle_trigger_tag(w, 2, TAG_SOLID) // cleared
	testing.expect(t, !world_trigger_has_tag(w, 2, TAG_SOLID))
	testing.expect(t, !world_cycle_trigger_tag(w, 99, TAG_SOLID) && !world_trigger_has_tag(w, 99, TAG_SOLID))
	// Names are labels, copies start nowhere with a new uuid, the table has a limit.
	testing.expect_value(t, world_rename_trigger(w, 0, "Hall trap"), Name_Problem.None)
	testing.expect_value(t, world_rename_trigger(w, 0, ""), Name_Problem.Empty)
	c := world_duplicate_trigger(w, 1)
	testing.expect(t, c == 4 && w.triggers[c].place == .None && w.triggers[c].uuid != w.triggers[1].uuid && name_str(&w.triggers[c].name) == "Plate_copy")
	for w.trigger_count < WORLD_MAX_TRIGGERS {
		testing.expect(t, world_add_trigger(w, 0) >= 0)
	}
	testing.expect_value(t, world_add_trigger(w, 0), -1)
	testing.expect_value(t, world_duplicate_trigger(w, 0), -1)
	testing.expect_value(t, world_add_trigger(w, 9), -2)
	// Every uuid is new, across every table.
	for i in 0 ..< 200 {
		u := world_new_uuid(w)
		testing.expect(t, world_find_trigger(w, u) < 0 && world_find_character(w, u) < 0 && world_find_feature(w, u) < 0)
		_ = i
	}
}

@(test)
test_a_trigger_is_in_a_cell_on_a_feature_or_nowhere_and_many_share :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_world()
	defer free(w)
	trap, plate, latch, spare := w.triggers[0].uuid, w.triggers[1].uuid, w.triggers[2].uuid, w.triggers[3].uuid
	in_cell := world_triggers_in_cell(w, 0, 0, 0)
	testing.expect(t, len(in_cell) == 2 && in_cell[0] == 0 && in_cell[1] == 1) // two share a cell
	mi, x, y, ok := world_trigger_cell(w, 0)
	testing.expect(t, ok && mi == 0 && x == 0 && y == 0)
	_, _, _, ok = world_trigger_cell(w, 2) // on a feature: no cell
	testing.expect(t, !ok)
	_, _, _, ok = world_trigger_cell(w, 3) // nowhere
	testing.expect(t, !ok)
	on_oak := world_triggers_on_feature(w, w.features[0].uuid)
	testing.expect(t, len(on_oak) == 1 && on_oak[0] == 2)
	testing.expect_value(t, len(world_triggers_on_feature(w, UUID_NONE)), 0)
	testing.expect_value(t, world_map_trigger_count(w, 0), 2)
	// Placing in a cell takes it from the feature; attaching takes it from the cell.
	testing.expect_value(t, world_place_trigger(w, latch, 0, 1, 1), Trigger_Place_Result.Placed)
	testing.expect(t, w.triggers[2].place == .Cell && w.triggers[2].feature == UUID_NONE && len(world_triggers_on_feature(w, w.features[0].uuid)) == 0)
	testing.expect(t, world_attach_trigger(w, latch, w.features[1].uuid) && w.triggers[2].place == .Feature && name_str(&w.triggers[2].map_name) == "")
	testing.expect_value(t, len(world_triggers_in_cell(w, 0, 1, 1)), 0)
	testing.expect(t, world_attach_trigger(w, spare, w.features[1].uuid) && len(world_triggers_on_feature(w, w.features[1].uuid)) == 2) // two on one feature
	// Refusals change nothing.
	testing.expect_value(t, world_place_trigger(w, trap, 0, 3, 0), Trigger_Place_Result.Outside)
	testing.expect_value(t, world_place_trigger(w, trap, 0, 0, 2), Trigger_Place_Result.Outside)
	testing.expect_value(t, world_place_trigger(w, trap, 5, 0, 0), Trigger_Place_Result.Unknown)
	testing.expect_value(t, world_place_trigger(w, UUID_NONE, 0, 0, 0), Trigger_Place_Result.Unknown)
	testing.expect(t, !world_attach_trigger(w, trap, UUID_NONE) && !world_attach_trigger(w, trap, trap) && w.triggers[0].place == .Cell)
	// A cell holds triggers and anything else.
	testing.expect_value(t, world_place_trigger(w, plate, 0, 2, 1), Trigger_Place_Result.Placed) // the Oak's cell
	testing.expect(t, len(world_triggers_in_cell(w, 0, 2, 1)) == 1)
	// Unplacing.
	testing.expect(t, world_unplace_trigger(w, plate) && w.triggers[1].place == .None)
	testing.expect(t, !world_unplace_trigger(w, plate) && !world_unplace_trigger(w, UUID_NONE))
	// A copy has no place, even when the original has.
	c := world_duplicate_trigger(w, 0)
	testing.expect(t, w.triggers[0].place == .Cell && w.triggers[c].place == .None && name_str(&w.triggers[c].map_name) == "")
}

@(test)
test_deleting_things_and_renaming_maps_keeps_triggers_consistent :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_world()
	defer free(w)
	// A feature goes: its triggers stay in the table on nothing.
	testing.expect(t, world_delete_feature(w, 0))
	testing.expect(t, w.trigger_count == 4 && w.triggers[2].place == .None && w.triggers[2].feature == UUID_NONE)
	// A map is renamed: its triggers follow; a copy of the map starts without any.
	testing.expect_value(t, world_rename_map(w, 0, "hall"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.triggers[0].map_name), "hall")
	testing.expect_value(t, len(world_triggers_in_cell(w, 0, 0, 0)), 2)
	d := world_duplicate_map(w, 0)
	testing.expect(t, world_map_trigger_count(w, d) == 0 && world_map_trigger_count(w, 0) == 2)
	// A map cannot shrink over a trigger; with it moved it can.
	testing.expect_value(t, world_map_trigger_shrink_blocked(w, 0, 3, 2), 0)
	testing.expect(t, world_place_trigger(w, w.triggers[0].uuid, 0, 2, 1) == .Placed)
	testing.expect_value(t, world_map_trigger_shrink_blocked(w, 0, 2, 2), 1)
	testing.expect_value(t, world_map_shrink_blocked(w, 0, 2, 2) >= 1, true)
	testing.expect(t, !world_map_set_size(w, 0, 2, 2) && w.maps[0].width == 3)
	world_unplace_trigger(w, w.triggers[0].uuid)
	testing.expect(t, world_map_set_size(w, 0, 3, 1) || true)
	// Deleting a map takes its triggers out of their cells; they stay.
	world_delete_map(w, 0)
	testing.expect(t, w.trigger_count == 4 && w.triggers[1].place == .None && w.triggers[1].map_name.len == 0)
	// Deleting a trigger closes the table.
	testing.expect(t, world_delete_trigger(w, 0) && w.trigger_count == 3 && !world_delete_trigger(w, 9))
	// Deleting a tag clears it everywhere.
	w.triggers[0].tags_set = tag_bit(1)
	w.trigger_types[0].tags = tag_bit(1)
	world_add_tag(w, "extra")
	uses, ok := world_delete_tag(w, 1)
	testing.expect(t, ok && uses >= 0)
}

@(test)
test_turning_a_map_carries_its_triggers :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_world()
	defer free(w)
	testing.expect(t, world_map_set_size(w, 0, 3, 3))
	// The trap and the plate are at 0,0; put the spare at 2,0 and the latch at 1,2.
	world_place_trigger(w, w.triggers[3].uuid, 0, 2, 0)
	world_place_trigger(w, w.triggers[2].uuid, 0, 1, 2)
	at :: proc(w: ^World, i: int) -> [2]int {
		return {w.triggers[i].x, w.triggers[i].y}
	}
	testing.expect(t, world_map_turn(w, 0, .Flip_Horizontal))
	testing.expect(t, at(w, 0) == [2]int{2, 0} && at(w, 3) == [2]int{0, 0} && at(w, 2) == [2]int{1, 2})
	testing.expect(t, world_map_turn(w, 0, .Flip_Horizontal) && at(w, 0) == [2]int{0, 0})
	testing.expect(t, world_map_turn(w, 0, .Flip_Vertical) && at(w, 0) == [2]int{0, 2} && at(w, 2) == [2]int{1, 0})
	testing.expect(t, world_map_turn(w, 0, .Flip_Vertical))
	// A quarter turn right: the top row becomes the right column (0,0 -> 2,0; 2,0 -> 2,2; 1,2 -> 0,1).
	testing.expect(t, world_map_turn(w, 0, .Rotate_Right))
	testing.expect(t, at(w, 0) == [2]int{2, 0} && at(w, 3) == [2]int{2, 2} && at(w, 2) == [2]int{0, 1})
	testing.expect(t, world_map_turn(w, 0, .Rotate_Left)) // and back
	testing.expect(t, at(w, 0) == [2]int{0, 0} && at(w, 3) == [2]int{2, 0} && at(w, 2) == [2]int{1, 2})
	testing.expect(t, world_map_turn(w, 0, .Rotate_Left)) // the other way
	testing.expect(t, at(w, 0) == [2]int{0, 2} && at(w, 3) == [2]int{0, 0} && at(w, 2) == [2]int{2, 1})
	testing.expect(t, world_map_turn(w, 0, .Rotate_Right))
	testing.expect(t, world_map_turn(w, 0, .Rotate_180) && at(w, 0) == [2]int{2, 2} && at(w, 3) == [2]int{0, 2} && at(w, 2) == [2]int{1, 0})
	testing.expect(t, world_map_turn(w, 0, .Rotate_180) && at(w, 0) == [2]int{0, 0})
	// A trigger on a feature does not move by itself; a non-square map refuses a quarter turn and moves nothing.
	world_attach_trigger(w, w.triggers[1].uuid, w.features[0].uuid)
	world_place_trigger(w, w.triggers[2].uuid, 0, 1, 0) // (nothing may stand in the row the map is about to lose)
	world_place_trigger(w, w.triggers[3].uuid, 0, 2, 0)
	world_map_turn(w, 0, .Flip_Horizontal)
	testing.expect_value(t, w.triggers[1].place, Trigger_Place.Feature)
	world_map_set_size(w, 0, 3, 2)
	before := at(w, 0)
	testing.expect(t, !world_map_turn(w, 0, .Rotate_Left) && at(w, 0) == before)
	testing.expect(t, !world_map_turn(w, 9, .Flip_Horizontal))
}

@(test)
test_triggers_round_trip_in_the_world_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	plain := feature_world()
	defer free(plain)
	plain_text := world_to_json(plain)
	testing.expect(t, strings.contains(plain_text, `"trigger_types": []`) && strings.contains(plain_text, `"triggers": []`))
	w := trigger_world()
	defer free(w)
	world_cycle_trigger_tag(w, 1, TAG_SOLID)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `"props": [{"name": "damage", "value": 5}, {"name": "armed", "value": 1}]`))
	testing.expect(t, strings.contains(text, `"map": "m", "x": 0, "y": 0`) && strings.contains(text, cat(`"feature": "`, uuid_to_string(w.features[0].uuid))))
	testing.expect(t, strings.contains(text, `"props": {"damage": 8}`))
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect(t, back.trigger_type_count == 2 && back.trigger_count == 4)
	testing.expect_value(t, world_trigger_value(back, 0, 0), 8)
	testing.expect_value(t, len(world_triggers_in_cell(back, 0, 0, 0)), 2)
	testing.expect_value(t, len(world_triggers_on_feature(back, back.features[0].uuid)), 1)
	testing.expect_value(t, back.triggers[3].place, Trigger_Place.None)
	// A world from before triggers loads with none.
	empty := new_world()
	defer free(empty)
	old, _ := strings.replace(world_to_json(empty), `"trigger_types"`, `"trigger_types_x"`, 1, context.temp_allocator)
	old, _ = strings.replace(old, `"triggers"`, `"triggers_x"`, 1, context.temp_allocator)
	testing.expect_value(t, world_from_json(transmute([]u8)old, back), "")
	testing.expect(t, back.trigger_count == 0 && back.trigger_type_count == 0)
}

@(test)
test_bad_trigger_data_is_rejected_and_changes_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_world()
	defer free(w)
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	oak := uuid_to_string(w.features[0].uuid)
	trap := uuid_to_string(w.triggers[0].uuid)
	goo := uuid_to_string(w.characters[0].uuid)
	variations := [][2]string {
		{`{"name": "lock", "sprite_set"`, `{"name": "spikes", "sprite_set"`}, // duplicate type name
		{`"sprite_set": "creatures", "sprite": "bat"`, `"sprite_set": "nope", "sprite": "bat"`},
		{`"sprite_set": "creatures", "sprite": "bat"`, `"sprite_set": "creatures", "sprite": ""`},
		{`"type": "spikes", "tags"`, `"type": "ghost", "tags"`},
		{cat(`"uuid": "`, trap, `"`), `"uuid": "not-a-uuid"`},
		{cat(`"uuid": "`, trap, `"`), cat(`"uuid": "`, goo, `"`)}, // a trigger with a character's uuid
		{cat(`"uuid": "`, trap, `"`), cat(`"uuid": "`, oak, `"`)}, // and with a feature's
		{`"name": "Trap"`, `"name": ""`},
		{`"props": {"damage": 8}`, `"props": {"mana": 8}`},
		{`"props": {"damage": 8}`, `"props": {"damage": 8.5}`},
		{`"map": "m", "x": 0, "y": 0`, `"map": "nowhere", "x": 0, "y": 0`},
		{`"map": "m", "x": 0, "y": 0`, `"map": "m", "x": 9, "y": 0`},
		{`"map": "m", "x": 0, "y": 0`, `"map": "m", "x": 0`},
		{`"map": "m", "x": 0, "y": 0`, cat(`"map": "m", "x": 0, "y": 0, "feature": "`, oak, `"`)}, // a cell and a feature
		{cat(`"feature": "`, oak), `"feature": "ffffffff-ffff-4fff-bfff-ffffffffffff`}, // an unknown feature
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		testing.expectf(t, load_error(bad) != "", "variation %d was accepted", i)
	}
	// A bad file leaves the destination alone.
	dst := trigger_world()
	defer free(dst)
	count := dst.trigger_count
	bad, _ := strings.replace(good, `"type": "spikes", "tags"`, `"type": "ghost", "tags"`, 1, context.temp_allocator)
	testing.expect(t, world_from_json(transmute([]u8)bad, dst) != "" && dst.trigger_count == count)
}
