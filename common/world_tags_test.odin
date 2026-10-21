#+build !js
package common

import "core:strings"
import "core:testing"

// The character world with extra tags "water" (1) and "hostile" (2).
tag_world :: proc() -> ^World {
	w := character_world()
	world_add_tag(w, "water")
	world_add_tag(w, "hostile")
	return w
}

@(test)
test_a_new_world_has_the_solid_tag_and_it_is_reserved :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	testing.expect(t, w.tag_count == 1 && name_str(&w.tags[0]) == "solid" && world_find_tag(w, "solid") == TAG_SOLID)
	testing.expect(t, tag_is_reserved(0) && !tag_is_reserved(1))
	testing.expect_value(t, world_rename_tag(w, 0, "walls"), Name_Problem.In_Use)
	testing.expect_value(t, name_str(&w.tags[0]), "solid")
	uses, ok := world_delete_tag(w, 0)
	testing.expect(t, !ok && uses == 0 && w.tag_count == 1)
}

@(test)
test_tags_are_named_uniquely_and_limited :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	a := world_add_tag(w)
	b := world_add_tag(w)
	testing.expect(t, name_str(&w.tags[a]) == "tag" && name_str(&w.tags[b]) == "tag_2")
	testing.expect_value(t, world_check_tag_name(w, b, "tag"), Name_Problem.In_Use)
	testing.expect_value(t, world_check_tag_name(w, b, "solid"), Name_Problem.In_Use)
	testing.expect_value(t, world_check_tag_name(w, b, ""), Name_Problem.Empty)
	testing.expect_value(t, world_check_tag_name(w, b, "tag_2"), Name_Problem.None)
	testing.expect_value(t, world_rename_tag(w, b, "water"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.tags[b]), "water")
	testing.expect_value(t, world_rename_tag(w, 9, "x"), Name_Problem.Empty)
	for w.tag_count < WORLD_MAX_TAGS {
		testing.expect(t, world_add_tag(w) >= 0)
	}
	testing.expect_value(t, world_add_tag(w), -1)
	testing.expect_value(t, tag_bit(63), Tag_Mask(1) << 63)
}

@(test)
test_terrains_and_character_types_have_or_lack_a_tag :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := tag_world() // rock (terrain 1) is already solid in the sample; grass (terrain 0) has no tags
	defer free(w)
	testing.expect(t, !world_terrain_has_tag(w, 0, 0, TAG_SOLID) && world_terrain_has_tag(w, 0, 1, TAG_SOLID))
	testing.expect(t, world_toggle_terrain_tag(w, 0, 0, TAG_SOLID) && world_terrain_has_tag(w, 0, 0, TAG_SOLID))
	testing.expect(t, world_toggle_terrain_tag(w, 0, 0, 1) && w.sets[0].terrains[0].tags == 3)
	world_toggle_terrain_tag(w, 0, 0, TAG_SOLID)
	testing.expect_value(t, w.sets[0].terrains[0].tags, tag_bit(1))
	testing.expect(t, !world_toggle_terrain_tag(w, 0, 9, 1) && !world_toggle_terrain_tag(w, 9, 0, 1) && !world_toggle_terrain_tag(w, 0, 1, 3)) // tag 3 does not exist
	testing.expect(t, world_toggle_char_type_tag(w, 1, 2) && w.char_types[1].tags == tag_bit(2))
	testing.expect(t, !world_toggle_char_type_tag(w, 7, 2) && !world_toggle_char_type_tag(w, 1, 9))
}

@(test)
test_characters_inherit_set_or_clear_a_tag :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := tag_world()
	defer free(w)
	world_toggle_char_type_tag(w, 0, 1) // slimes are "water"
	goo := 0 // a slime
	testing.expect(t, world_character_has_tag(w, goo, 1) && !world_character_has_tag(w, goo, 2))
	testing.expect_value(t, tag_state(w.characters[goo].tags_set, w.characters[goo].tags_cleared, 1), Tag_State.Inherit)
	// Cycling: inherit -> set -> cleared -> inherit.
	world_cycle_character_tag(w, goo, 1)
	testing.expect_value(t, tag_state(w.characters[goo].tags_set, w.characters[goo].tags_cleared, 1), Tag_State.Set)
	testing.expect(t, world_character_has_tag(w, goo, 1))
	world_cycle_character_tag(w, goo, 1)
	testing.expect_value(t, tag_state(w.characters[goo].tags_set, w.characters[goo].tags_cleared, 1), Tag_State.Cleared)
	testing.expect(t, !world_character_has_tag(w, goo, 1)) // cleared on this one, though its type has it
	world_cycle_character_tag(w, goo, 1)
	testing.expect(t, world_character_has_tag(w, goo, 1) && w.characters[goo].tags_set == 0 && w.characters[goo].tags_cleared == 0)
	// Setting a tag its type lacks; the other slime keeps inheriting.
	world_cycle_character_tag(w, goo, 2)
	testing.expect(t, world_character_has_tag(w, goo, 2) && !world_character_has_tag(w, 2, 2))
	// A bat does not have "water" unless it says so.
	testing.expect(t, !world_character_has_tag(w, 1, 1))
	testing.expect(t, !world_cycle_character_tag(w, 9, 1) && !world_cycle_character_tag(w, 0, 9) && !world_character_has_tag(w, 9, 1))
}

@(test)
test_a_cell_inherits_its_terrains_tags_unless_it_says_otherwise :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := tag_world() // map "m" 3 x 2; cell (1,0) holds terrain 1 (rock, solid), the rest terrain 0
	defer free(w)
	testing.expect(t, world_cell_has_tag(w, 0, 1, 0, TAG_SOLID) && !world_cell_has_tag(w, 0, 0, 0, TAG_SOLID))
	world_cycle_cell_tag(w, 0, 1, 0, TAG_SOLID) // inherit -> set
	world_cycle_cell_tag(w, 0, 1, 0, TAG_SOLID) // set -> cleared: a passable rock
	testing.expect(t, !world_cell_has_tag(w, 0, 1, 0, TAG_SOLID))
	testing.expect(t, world_cell_has_tag(w, 0, 0, 0, TAG_SOLID) == false)
	world_cycle_cell_tag(w, 0, 0, 0, TAG_SOLID) // a solid grass cell
	testing.expect(t, world_cell_has_tag(w, 0, 0, 0, TAG_SOLID))
	// Changing the terrain under a cell changes what it inherits.
	w.maps[0].cells[1][1] = 1
	world_toggle_terrain_tag(w, 0, 1, 2)
	testing.expect(t, world_cell_has_tag(w, 0, 1, 1, 2) && !world_cell_has_tag(w, 0, 0, 1, 2))
	testing.expect(t, !world_cell_has_tag(w, 0, 9, 9, 0) && !world_cell_has_tag(w, 4, 0, 0, 0) && !world_cycle_cell_tag(w, 0, 9, 9, 0) && !world_cycle_cell_tag(w, 0, 0, 0, 5))
}

@(test)
test_deleting_a_tag_clears_it_everywhere_and_closes_the_gap :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := tag_world() // tags: solid, water, hostile
	defer free(w)
	water, hostile := 1, 2
	world_toggle_terrain_tag(w, 0, 0, water)
	world_toggle_terrain_tag(w, 0, 1, hostile)
	world_toggle_char_type_tag(w, 0, water)
	world_toggle_char_type_tag(w, 1, hostile)
	world_cycle_character_tag(w, 0, water) // set
	world_cycle_character_tag(w, 1, hostile) // set
	world_cycle_character_tag(w, 1, hostile) // cleared
	world_cycle_cell_tag(w, 0, 2, 1, water)
	world_cycle_cell_tag(w, 0, 0, 0, hostile)
	testing.expect_value(t, world_tag_uses(w, water), 4) // terrain, type, character, cell
	testing.expect_value(t, world_tag_uses(w, hostile), 4) // a terrain, a type, a character, a cell
	uses, ok := world_delete_tag(w, water)
	testing.expect(t, ok && uses == 4 && w.tag_count == 2)
	testing.expect_value(t, name_str(&w.tags[1]), "hostile") // the later tag moved down
	// "hostile" is tag 1 now, everywhere; "solid" is untouched.
	testing.expect_value(t, w.sets[0].terrains[0].tags, Tag_Mask(0))
	testing.expect_value(t, w.sets[0].terrains[1].tags, tag_bit(TAG_SOLID) | tag_bit(1)) // rock was solid already
	testing.expect_value(t, w.char_types[0].tags, Tag_Mask(0))
	testing.expect_value(t, w.char_types[1].tags, tag_bit(1))
	testing.expect_value(t, w.characters[0].tags_set, Tag_Mask(0))
	testing.expect_value(t, w.characters[1].tags_cleared, tag_bit(1))
	testing.expect_value(t, w.maps[0].cell_tags[1][2].set, Tag_Mask(0))
	testing.expect_value(t, w.maps[0].cell_tags[0][0].set, tag_bit(1))
	testing.expect(t, world_cell_has_tag(w, 0, 0, 0, 1))
	// The reserved tag and bad indexes stay.
	_, ok = world_delete_tag(w, 0)
	testing.expect(t, !ok && w.tag_count == 2)
	_, ok = world_delete_tag(w, 7)
	testing.expect(t, !ok)
	// Deleting the last one.
	_, ok = world_delete_tag(w, 1)
	testing.expect(t, ok && w.tag_count == 1 && w.sets[0].terrains[1].tags == tag_bit(TAG_SOLID))
}

@(test)
test_flips_rotations_and_shrinking_carry_a_cells_own_tags :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := tag_world()
	defer free(w)
	world_unplace_character(w, w.characters[0].uuid) // so that the map may shrink
	world_map_set_size(w, 0, 3, 3)
	m := &w.maps[0]
	world_cycle_cell_tag(w, 0, 0, 0, 1) // a "water" mark at the top left
	testing.expect(t, map_flip_horizontal(m))
	testing.expect_value(t, m.cell_tags[0][2].set, tag_bit(1))
	testing.expect_value(t, m.cell_tags[0][0].set, Tag_Mask(0))
	testing.expect(t, map_flip_vertical(m))
	testing.expect_value(t, m.cell_tags[2][2].set, tag_bit(1))
	testing.expect(t, map_rotate_right(m)) // the bottom right goes to the bottom left
	testing.expect_value(t, m.cell_tags[2][0].set, tag_bit(1))
	testing.expect(t, map_rotate_left(m))
	testing.expect(t, map_rotate_180(m))
	testing.expect_value(t, m.cell_tags[0][0].set, tag_bit(1))
	// A mark on a cell that is cut off is forgotten, not brought back by growing.
	testing.expect(t, world_map_set_size(w, 0, 2, 2) && world_map_set_size(w, 0, 3, 3))
	world_cycle_cell_tag(w, 0, 0, 0, 1) // inherit state: first set
	world_cycle_cell_tag(w, 0, 1, 1, 1)
	world_map_set_size(w, 0, 1, 1)
	world_map_set_size(w, 0, 3, 3)
	testing.expect_value(t, m.cell_tags[1][1], Cell_Tags{})
}

@(test)
test_tags_round_trip_in_the_world_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := tag_world()
	defer free(w)
	world_toggle_terrain_tag(w, 0, 0, 1)
	world_toggle_char_type_tag(w, 0, 2)
	world_cycle_character_tag(w, 0, 1)
	world_cycle_character_tag(w, 1, 2)
	world_cycle_character_tag(w, 1, 2)
	world_cycle_cell_tag(w, 0, 2, 1, 1)
	world_cycle_cell_tag(w, 0, 2, 1, TAG_SOLID)
	world_cycle_cell_tag(w, 0, 2, 1, TAG_SOLID)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `"tags": ["solid", "water", "hostile"]`))
	testing.expect(t, strings.contains(text, `"name": "rock", "tags": ["solid"], "tileset"`))
	testing.expect(t, strings.contains(text, `"tags": ["water"], "tags_cleared": []`))
	testing.expect(t, strings.contains(text, `"cell_tags": [{"x": 2, "y": 1, "tags": ["water"], "tags_cleared": ["solid"]}]`))
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect(t, back.tag_count == 3 && back.sets[0].terrains[1].tags == 1 && back.char_types[0].tags == tag_bit(2))
	testing.expect(t, back.characters[0].tags_set == tag_bit(1) && back.characters[1].tags_cleared == tag_bit(2))
	testing.expect(t, back.maps[0].cell_tags[1][2] == Cell_Tags{tag_bit(1), tag_bit(TAG_SOLID)})
}

@(test)
test_old_files_without_tags_still_load_and_solid_becomes_the_tag :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := tag_world()
	defer free(w)
	text := world_to_json(w)
	// A file from before tags: no "tags" list anywhere, terrains carry "solid".
	old, _ := strings.replace(text, `  "tags": ["solid", "water", "hostile"],`, ``, 1, context.temp_allocator)
	old, _ = strings.replace(old, `"name": "grass", "tags": []`, `"name": "grass", "solid": false`, 1, context.temp_allocator)
	old, _ = strings.replace(old, `"name": "rock", "tags": ["solid"]`, `"name": "rock", "solid": true`, 1, context.temp_allocator)
	testing.expect(t, old != text)
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)old, back), "")
	testing.expect(t, back.tag_count == 1 && back.sets[0].terrains[0].tags == 0 && back.sets[0].terrains[1].tags == 1)
	testing.expect(t, strings.contains(world_to_json(back), `"name": "rock", "tags": ["solid"]`)) // written the new way
}

@(test)
test_bad_tag_data_is_rejected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := tag_world()
	defer free(w)
	world_cycle_character_tag(w, 0, 1)
	world_cycle_cell_tag(w, 0, 2, 1, 1)
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	variations := [][2]string {
		{`"tags": ["solid", "water", "hostile"]`, `"tags": []`},
		{`"tags": ["solid", "water", "hostile"]`, `"tags": ["water", "solid"]`}, // solid must come first
		{`"tags": ["solid", "water", "hostile"]`, `"tags": ["solid", "water", "water"]`},
		{`"tags": ["solid", "water", "hostile"]`, `"tags": ["solid", 5]`},
		{`"tags": ["solid", "water", "hostile"]`, `"tags": "solid"`},
		{`"tags": ["solid", "water", "hostile"]`, `"tags": ["solid", ""]`},
		{`"name": "slime", "sprite_set": "creatures", "sprite": "slime", "tags": []`, `"name": "slime", "sprite_set": "creatures", "sprite": "slime", "tags": ["lava"]`},
		{`"tags": ["water"], "tags_cleared": []}`, `"tags": ["water"], "tags_cleared": ["water"]}`}, // set and cleared
		{`"tags": ["water"], "tags_cleared": []}`, `"tags": ["water"], "tags_cleared": ["lava"]}`},
		{`"x": 2, "y": 1, "tags": ["water"]`, `"x": 9, "y": 1, "tags": ["water"]`},
		{`"x": 2, "y": 1, "tags": ["water"]`, `"x": 2, "y": 1, "tags": ["lava"]`},
		{`"cell_tags": [`, `"cell_tags": {"a": [`},
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		testing.expectf(t, load_error(bad) != "", "variation %d was accepted", i)
	}
	// Two entries for one cell.
	dup, _ := strings.replace(good, `"cell_tags": [{"x": 2, "y": 1, "tags": ["water"], "tags_cleared": []}]`, `"cell_tags": [{"x": 2, "y": 1, "tags": ["water"]}, {"x": 2, "y": 1, "tags": []}]`, 1, context.temp_allocator)
	testing.expect(t, dup != good && load_error(dup) != "")
}
