#+build !js
package common

import "core:strings"
import "core:testing"

// The character world plus feature types "tree" (scenery/tree... the sprites of "creatures" stand in)
// and "rock", and features Oak (tree, at 2,1 of the 3 x 2 map m), Boulder (rock, off the map) and
// Stump (tree, off the map).
feature_world :: proc() -> ^World {
	w := character_world()
	a := world_add_feature_type(w, "tree")
	b := world_add_feature_type(w, "rock")
	name_assign(&w.feature_types[b].sprite, "bat")
	oak := world_add_feature(w, a)
	name_assign(&w.features[oak].name, "Oak")
	boulder := world_add_feature(w, b)
	name_assign(&w.features[boulder].name, "Boulder")
	stump := world_add_feature(w, a)
	name_assign(&w.features[stump].name, "Stump")
	world_place_feature(w, 0, 2, 1, w.features[oak].uuid)
	return w
}

@(test)
test_feature_types_have_unique_names_and_a_sprite :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sprite_world()
	defer free(w)
	a := world_add_feature_type(w, "tree")
	b := world_add_feature_type(w, "tree") // made unique
	testing.expect(t, a == 0 && b == 1 && name_str(&w.feature_types[1].name) == "tree_2")
	testing.expect_value(t, name_str(&w.feature_types[a].sprite_set), "creatures") // points at the first sprite
	testing.expect_value(t, name_str(&w.feature_types[a].sprite), "slime")
	testing.expect(t, world_feature_type_sprite(w, &w.feature_types[a]) == &w.sprite_sets[0].sprites[0])
	w.feature_types[a].sprite_set = {}
	testing.expect(t, world_feature_type_sprite(w, &w.feature_types[a]) == nil)
	testing.expect_value(t, world_check_feature_type_name(w, 0, "tree_2"), Name_Problem.In_Use)
	testing.expect_value(t, world_check_feature_type_name(w, 0, ""), Name_Problem.Empty)
	testing.expect_value(t, world_check_feature_type_name(w, 0, "tree"), Name_Problem.None) // its own name is fine
	c := world_duplicate_feature_type(w, 0)
	testing.expect(t, c == 1 && name_str(&w.feature_types[1].name) == "tree_copy" && w.feature_type_count == 3)
	for _ in 3 ..< WORLD_MAX_FEATURE_TYPES {
		testing.expect(t, world_add_feature_type(w) >= 0)
	}
	testing.expect_value(t, world_add_feature_type(w), -1) // 64 is the most
	testing.expect_value(t, world_duplicate_feature_type(w, 0), -1)
}

@(test)
test_a_type_with_features_cannot_be_deleted_and_renames_follow :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world()
	defer free(w)
	testing.expect_value(t, world_feature_type_uses(w, "tree"), 2)
	testing.expect_value(t, world_delete_feature_type(w, 0), 2)
	testing.expect_value(t, w.feature_type_count, 2)
	testing.expect_value(t, world_rename_feature_type(w, 0, "rock"), Name_Problem.In_Use)
	testing.expect_value(t, world_rename_feature_type(w, 0, "oak_tree"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.features[0].type), "oak_tree")
	testing.expect_value(t, name_str(&w.features[2].type), "oak_tree")
	world_delete_feature(w, 2)
	world_delete_feature(w, 0)
	testing.expect_value(t, world_delete_feature_type(w, 0), 0)
	testing.expect(t, w.feature_type_count == 1 && name_str(&w.feature_types[0].name) == "rock")
}

@(test)
test_sprites_that_feature_types_draw_are_protected_and_followed :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world() // tree draws creatures/slime; rock draws creatures/bat; character types draw them too
	defer free(w)
	// Remove the character types' claim so only the feature types remain.
	for w.character_count > 0 {
		world_delete_character(w, 0)
	}
	world_delete_char_type(w, 1)
	world_delete_char_type(w, 0)
	testing.expect_value(t, w.char_type_count, 0)
	testing.expect_value(t, w.feature_type_count, 2)
	testing.expect_value(t, world_sprite_uses(w, "creatures", "slime"), 1)
	testing.expect_value(t, world_sprite_set_uses(w, "creatures"), 2)
	testing.expect(t, !world_delete_sprite(w, 0, 0)) // the tree's sprite
	testing.expect(t, !world_delete_sprite_set(w, 0))
	testing.expect_value(t, world_rename_sprite(w, 0, 0, "blob"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.feature_types[0].sprite), "blob")
	testing.expect_value(t, world_rename_sprite_set(w, 0, "critters"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.feature_types[0].sprite_set), "critters")
	testing.expect_value(t, name_str(&w.feature_types[1].sprite_set), "critters")
	// Deleting the types frees the sprites.
	for w.feature_count > 0 {
		world_delete_feature(w, 0)
	}
	world_delete_feature_type(w, 1)
	world_delete_feature_type(w, 0)
	testing.expect(t, world_delete_sprite(w, 0, 0) && world_delete_sprite_set(w, 0))
}

@(test)
test_features_have_a_table_name_type_and_uuid_shared_with_characters :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world()
	defer free(w)
	testing.expect_value(t, w.feature_count, 3)
	testing.expect(t, name_str(&w.features[0].name) == "Oak" && name_str(&w.features[0].type) == "tree")
	testing.expect_value(t, world_add_feature(w, 9), -2) // no such type
	testing.expect_value(t, world_add_feature(w, -1), -2)
	d := world_duplicate_feature(w, 0)
	testing.expect(t, d == 3 && name_str(&w.features[d].name) == "Oak_copy" && w.features[d].uuid != w.features[0].uuid)
	_, _, _, placed := world_feature_location(w, w.features[d].uuid)
	testing.expect(t, !placed) // a copy stands nowhere
	testing.expect_value(t, world_rename_feature(w, 0, "Big oak"), Name_Problem.None)
	testing.expect_value(t, world_rename_feature(w, 0, "Big oak"), Name_Problem.None) // labels need not be unique
	testing.expect_value(t, world_rename_feature(w, 0, ""), Name_Problem.Empty)
	testing.expect(t, world_set_feature_type(w, 0, 1) && name_str(&w.features[0].type) == "rock")
	testing.expect(t, !world_set_feature_type(w, 0, 7) && !world_set_feature_type(w, 9, 0))
	// uuids never collide across the two tables.
	seen := make(map[Uuid]bool, context.temp_allocator)
	for i in 0 ..< w.character_count {
		seen[w.characters[i].uuid] = true
	}
	for _ in 0 ..< 300 {
		u := world_new_uuid(w)
		testing.expect(t, !(u in seen))
		seen[u] = true
	}
	for w.feature_count < WORLD_MAX_FEATURES {
		testing.expect(t, world_add_feature(w, 0) >= 0)
	}
	testing.expect_value(t, world_add_feature(w, 0), -1)
	testing.expect_value(t, world_duplicate_feature(w, 0), -1)
	// Every feature uuid is distinct.
	for i in 0 ..< w.feature_count {
		testing.expect(t, !(w.features[i].uuid in seen))
		seen[w.features[i].uuid] = true
	}
}

@(test)
test_placing_moving_and_taking_features_off_maps :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world() // Oak at 2,1; Goo (a character) at 1,0
	defer free(w)
	oak, boulder := w.features[0].uuid, w.features[1].uuid
	testing.expect_value(t, world_feature_at(w, 0, 2, 1), 0)
	testing.expect_value(t, world_feature_at(w, 0, 0, 0), -1)
	testing.expect_value(t, world_feature_at(w, 0, 9, 9), -1)
	testing.expect_value(t, world_feature_at(w, 5, 0, 0), -1)
	mi, x, y, ok := world_feature_location(w, oak)
	testing.expect(t, ok && mi == 0 && x == 2 && y == 1)
	_, _, _, ok = world_feature_location(w, boulder)
	testing.expect(t, !ok)
	testing.expect_value(t, world_place_feature(w, 0, 0, 0, boulder), Place_Result.Placed)
	testing.expect_value(t, world_place_feature(w, 0, 0, 0, boulder), Place_Result.Placed) // already there
	testing.expect_value(t, world_place_feature(w, 0, 0, 0, oak), Place_Result.Taken) // one feature a cell
	testing.expect(t, world_feature_at(w, 0, 2, 1) == 0) // refused: the oak did not move
	testing.expect_value(t, world_place_feature(w, 0, 3, 0, boulder), Place_Result.Outside)
	testing.expect_value(t, world_place_feature(w, 0, 0, -1, boulder), Place_Result.Outside)
	testing.expect_value(t, world_place_feature(w, 4, 0, 0, boulder), Place_Result.Unknown)
	testing.expect_value(t, world_place_feature(w, 0, 0, 0, Uuid{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}), Place_Result.Unknown)
	// Placing a placed feature moves it.
	testing.expect_value(t, world_place_feature(w, 0, 1, 1, boulder), Place_Result.Placed)
	testing.expect(t, world_feature_at(w, 0, 0, 0) == -1 && world_feature_at(w, 0, 1, 1) == 1)
	testing.expect_value(t, world_map_feature_count(w, 0), 2)
	testing.expect(t, world_unplace_feature(w, boulder) && !world_unplace_feature(w, boulder))
	// Deleting a feature takes it off its map.
	testing.expect(t, world_delete_feature(w, 0))
	testing.expect_value(t, world_map_feature_count(w, 0), 0)
	testing.expect(t, !world_delete_feature(w, 40))
}

@(test)
test_a_feature_and_a_character_never_share_a_cell :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world() // Goo (character 0) at 1,0; Oak at 2,1
	defer free(w)
	goo, flap := w.characters[0].uuid, w.characters[1].uuid
	oak, boulder := w.features[0].uuid, w.features[1].uuid
	testing.expect_value(t, world_place_feature(w, 0, 1, 0, boulder), Place_Result.Character_There)
	testing.expect_value(t, world_place_character(w, 0, 2, 1, flap), Place_Result.Feature_There)
	testing.expect(t, world_feature_at(w, 0, 1, 0) == -1 && world_character_at(w, 0, 2, 1) == -1)
	// Moving either onto its own cell is fine, and after it leaves the cell is free.
	testing.expect_value(t, world_place_character(w, 0, 1, 0, goo), Place_Result.Placed)
	world_unplace_feature(w, oak)
	testing.expect_value(t, world_place_character(w, 0, 2, 1, flap), Place_Result.Placed)
	testing.expect_value(t, world_place_feature(w, 0, 2, 1, oak), Place_Result.Character_There)
}

@(test)
test_feature_tags_inherit_set_and_clear_and_follow_tag_deletion :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world()
	defer free(w)
	water := world_add_tag(w, "water") // tag 1
	// The tree type is solid-by-type; Oak inherits, Stump clears it, Boulder (a rock) has it set itself.
	testing.expect(t, world_toggle_feature_type_tag(w, 0, TAG_SOLID))
	testing.expect(t, world_feature_has_tag(w, 0, TAG_SOLID)) // Oak inherits
	testing.expect(t, world_cycle_feature_tag(w, 2, TAG_SOLID)) // Stump: inherit -> set
	testing.expect(t, world_cycle_feature_tag(w, 2, TAG_SOLID)) // -> cleared
	testing.expect(t, !world_feature_has_tag(w, 2, TAG_SOLID))
	testing.expect(t, world_cycle_feature_tag(w, 1, TAG_SOLID)) // Boulder: set
	testing.expect(t, world_feature_has_tag(w, 1, TAG_SOLID))
	testing.expect(t, world_cycle_feature_tag(w, 2, TAG_SOLID)) // Stump back to inherit
	testing.expect(t, world_feature_has_tag(w, 2, TAG_SOLID))
	testing.expect(t, !world_feature_has_tag(w, 0, water) && !world_feature_has_tag(w, 9, TAG_SOLID))
	testing.expect(t, !world_toggle_feature_type_tag(w, 0, 9) && !world_cycle_feature_tag(w, 0, 9))
	// A deleted tag leaves every feature type and feature, and is counted.
	world_toggle_feature_type_tag(w, 1, water)
	world_cycle_feature_tag(w, 0, water)
	testing.expect_value(t, world_tag_uses(w, water), 2)
	uses, ok := world_delete_tag(w, water)
	testing.expect(t, ok && uses == 2)
	testing.expect_value(t, w.feature_types[1].tags, Tag_Mask(0))
	testing.expect_value(t, w.features[0].tags_set, Tag_Mask(0))
	testing.expect(t, world_feature_has_tag(w, 0, TAG_SOLID)) // the other tags are untouched
}

@(test)
test_a_map_cannot_shrink_over_a_feature_and_flips_and_rotations_carry_them :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world() // Oak at 2,1 of a 3 x 2 map; Goo at 1,0
	defer free(w)
	testing.expect_value(t, world_map_shrink_blocked(w, 0, 3, 2), 0)
	testing.expect_value(t, world_map_shrink_blocked(w, 0, 2, 2), 1) // the oak
	testing.expect_value(t, world_map_shrink_blocked(w, 0, 1, 2), 2) // the oak and Goo
	testing.expect(t, !world_map_set_size(w, 0, 2, 2) && w.maps[0].width == 3)
	testing.expect(t, world_map_set_size(w, 0, 3, 3))
	oak, boulder := w.features[0].uuid, w.features[1].uuid
	m := &w.maps[0]
	// Oak at 2,1 of 3 x 3: a flip moves it with its cell even when the terrain does not change.
	testing.expect(t, map_flip_horizontal(m))
	_, x, y, _ := world_feature_location(w, oak)
	testing.expect(t, x == 0 && y == 1)
	testing.expect(t, map_flip_vertical(m))
	_, x, y, _ = world_feature_location(w, oak)
	testing.expect(t, x == 0 && y == 1) // the middle row stays
	world_place_feature(w, 0, 2, 0, boulder)
	map_flip_vertical(m)
	_, x, y, _ = world_feature_location(w, boulder)
	testing.expect(t, x == 2 && y == 2)
	map_flip_vertical(m)
	// Quarter turns: the top row becomes the right column; four turns bring everything home.
	testing.expect(t, map_rotate_right(m))
	_, x, y, _ = world_feature_location(w, boulder) // (2,0) -> (2,2)
	testing.expect(t, x == 2 && y == 2)
	map_rotate_left(m)
	_, x, y, _ = world_feature_location(w, boulder)
	testing.expect(t, x == 2 && y == 0)
	testing.expect(t, map_rotate_180(m))
	_, x, y, _ = world_feature_location(w, oak) // (0,1) -> (2,1)
	testing.expect(t, x == 2 && y == 1)
	// A shrink is refused only while a feature would be cut off.
	world_place_feature(w, 0, 2, 2, boulder)
	testing.expect(t, !world_map_set_size(w, 0, 2, 3))
	world_unplace_feature(w, boulder)
	world_unplace_feature(w, oak)
	testing.expect(t, world_map_set_size(w, 0, 2, 3) || world_character_at(w, 0, 1, 0) >= 0)
}

@(test)
test_a_duplicated_map_has_no_characters_or_features :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world()
	defer free(w)
	d := world_duplicate_map(w, 0)
	testing.expect(t, d == 1)
	testing.expect_value(t, world_map_feature_count(w, 1), 0)
	testing.expect_value(t, world_map_character_count(w, 1), 0)
	testing.expect_value(t, world_map_feature_count(w, 0), 1) // the original keeps its own
	testing.expect_value(t, load_error(world_to_json(w)), "") // and the file is valid: nobody stands twice
}

@(test)
test_features_round_trip_in_the_world_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world()
	defer free(w)
	world_toggle_feature_type_tag(w, 0, TAG_SOLID)
	world_cycle_feature_tag(w, 1, TAG_SOLID)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `"feature_types": [`))
	testing.expect(t, strings.contains(text, `{"name": "tree", "sprite_set": "creatures", "sprite": "slime", "tags": ["solid"]}`))
	testing.expect(t, strings.contains(text, uuid_to_string(w.features[0].uuid)))
	testing.expect(t, strings.contains(text, `"x": 2, "y": 1, "feature": "`))
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect(t, back.feature_type_count == 2 && back.feature_count == 3 && back.character_count == 3)
	testing.expect_value(t, world_feature_at(back, 0, 2, 1), 0)
	testing.expect(t, world_feature_has_tag(back, 0, TAG_SOLID) && world_feature_has_tag(back, 1, TAG_SOLID))
	// A world from before features loads with none.
	empty := new_world()
	defer free(empty)
	old, _ := strings.replace(world_to_json(empty), `"feature_types"`, `"feature_types_x"`, 1, context.temp_allocator)
	old, _ = strings.replace(old, `"features"`, `"features_x"`, 1, context.temp_allocator)
	testing.expect_value(t, world_from_json(transmute([]u8)old, back), "")
	testing.expect(t, back.feature_count == 0 && back.feature_type_count == 0)
}

@(test)
test_bad_feature_data_is_rejected_and_changes_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := feature_world()
	defer free(w)
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	oak := uuid_to_string(w.features[0].uuid)
	boulder := uuid_to_string(w.features[1].uuid)
	goo := uuid_to_string(w.characters[0].uuid)
	variations := [][2]string {
		{`"name": "tree", "sprite_set": "creatures"`, `"name": "rock", "sprite_set": "creatures"`}, // duplicate type name
		{`{"name": "rock", "sprite_set": "creatures", "sprite": "bat"`, `{"name": "rock", "sprite_set": "nope", "sprite": "bat"`},
		{`{"name": "rock", "sprite_set": "creatures", "sprite": "bat"`, `{"name": "rock", "sprite_set": "creatures", "sprite": "nope"`},
		{`{"name": "rock", "sprite_set": "creatures", "sprite": "bat"`, `{"name": "rock", "sprite_set": "creatures", "sprite": ""`},
		{`"type": "tree", "tags"`, `"type": "ghost", "tags"`},
		{cat(`"uuid": "`, oak, `"`), `"uuid": "not-a-uuid"`},
		{cat(`"uuid": "`, oak, `"`), cat(`"uuid": "`, boulder, `"`)}, // a uuid twice in the features table
		{cat(`"uuid": "`, oak, `"`), cat(`"uuid": "`, goo, `"`)}, // a feature with a character's uuid
		{`"name": "Oak", "type"`, `"name": "", "type"`},
		{cat(`"x": 2, "y": 1, "feature": "`, oak), cat(`"x": 7, "y": 1, "feature": "`, oak)}, // outside the map
		{cat(`"x": 2, "y": 1, "feature": "`, oak), `"x": 2, "y": 1, "feature": "ffffffff-ffff-4fff-bfff-ffffffffffff`}, // unknown
		{cat(`"x": 2, "y": 1, "feature": "`, oak), cat(`"x": 1, "y": 0, "feature": "`, oak)}, // on Goo's cell: a feature and a character
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		testing.expectf(t, load_error(bad) != "", "variation %d was accepted", i)
	}
	// Two features in one cell, and one feature in two cells.
	two_in_cell, _ := strings.replace(good, `"features": [{"x": 2, "y": 1, "feature": "`, cat(`"features": [{"x": 2, "y": 1, "feature": "`, boulder, `"}, {"x": 2, "y": 1, "feature": "`), 1, context.temp_allocator)
	testing.expect(t, load_error(two_in_cell) != "")
	two_cells, _ := strings.replace(good, cat(`"features": [{"x": 2, "y": 1, "feature": "`, oak, `"}`), cat(`"features": [{"x": 2, "y": 1, "feature": "`, oak, `"}, {"x": 0, "y": 0, "feature": "`, oak, `"}`), 1, context.temp_allocator)
	testing.expect(t, load_error(two_cells) != "")
	// A bad file leaves the destination alone.
	dst := feature_world()
	defer free(dst)
	count := dst.feature_count
	bad, _ := strings.replace(good, `"type": "tree", "tags"`, `"type": "ghost", "tags"`, 1, context.temp_allocator)
	testing.expect(t, world_from_json(transmute([]u8)bad, dst) != "" && dst.feature_count == count)
}
