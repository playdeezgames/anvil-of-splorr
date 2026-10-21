#+build !js
package common

import "core:strings"
import "core:testing"

// The sprite world plus character types "slime" (sprite creatures/slime) and "bat" (creatures/bat),
// a map "m" of 3 x 2 (from sample_world), and three characters: Goo (slime, at 1,0 of m), Flap (bat,
// off the map) and Pip (slime, off the map).
character_world :: proc() -> ^World {
	w := sprite_world()
	world_seed_uuids(w, 12345)
	a := world_add_char_type(w, "slime")
	b := world_add_char_type(w, "bat")
	name_assign(&w.char_types[b].sprite, "bat")
	goo := world_add_character(w, a)
	name_assign(&w.characters[goo].name, "Goo")
	flap := world_add_character(w, b)
	name_assign(&w.characters[flap].name, "Flap")
	pip := world_add_character(w, a)
	name_assign(&w.characters[pip].name, "Pip")
	world_place_character(w, 0, 1, 0, w.characters[goo].uuid)
	return w
}

@(test)
test_uuids_are_written_and_read_in_the_standard_form :: proc(t: ^testing.T) {
	u := Uuid{0x3f, 0x2a, 0x9c, 0x1e, 0x7b, 0x4d, 0x4e, 0x0a, 0x9c, 0x11, 0x5d, 0x2e, 0x8f, 0x6a, 0x0b, 0x17}
	testing.expect_value(t, uuid_to_string(u), "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17")
	testing.expect_value(t, uuid_short(u), "3f2a9c1e")
	back, ok := uuid_from_string("3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b17")
	testing.expect(t, ok && back == u)
	upper, ok2 := uuid_from_string("3F2A9C1E-7B4D-4E0A-9C11-5D2E8F6A0B17")
	testing.expect(t, ok2 && upper == u)
	for bad in ([]string{"", "3f2a9c1e7b4d4e0a9c115d2e8f6a0b17", "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b1", "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b1g", "3f2a9c1e_7b4d-4e0a-9c11-5d2e8f6a0b17", "3f2a9c1e-7b4d-4e0a-9c11-5d2e8f6a0b177"}) {
		_, good := uuid_from_string(bad)
		testing.expectf(t, !good, "%q was accepted", bad)
	}
	testing.expect(t, uuid_is_none(UUID_NONE) && !uuid_is_none(u))
}

@(test)
test_new_uuids_are_version_4_distinct_and_repeatable_from_a_seed :: proc(t: ^testing.T) {
	a := new_world()
	b := new_world()
	defer free(a)
	defer free(b)
	world_seed_uuids(a, 7)
	world_seed_uuids(b, 7)
	seen := make(map[Uuid]bool, context.temp_allocator)
	for _ in 0 ..< 2000 {
		u := world_new_uuid(a)
		testing.expect(t, u[6] >> 4 == 4 && u[8] >> 6 == 2 && !uuid_is_none(u))
		testing.expect(t, !(u in seen))
		seen[u] = true
		testing.expect_value(t, world_new_uuid(b), u) // the same seed gives the same uuids
	}
	world_seed_uuids(b, 8)
	testing.expect(t, world_new_uuid(b) != world_new_uuid(a))
	// It never hands out a uuid a character already has.
	w := character_world()
	defer free(w)
	taken := w.characters[0].uuid
	world_seed_uuids(w, 12345) // the stream that produced the first character again
	for _ in 0 ..< 5 {
		testing.expect(t, world_new_uuid(w) != taken)
	}
}

@(test)
test_character_types_have_unique_names_and_a_sprite :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	testing.expect(t, w.char_type_count == 2 && name_str(&w.char_types[0].sprite_set) == "creatures" && name_str(&w.char_types[0].sprite) == "slime")
	sp := world_char_type_sprite(w, &w.char_types[1])
	testing.expect(t, sp != nil && name_str(&sp.name) == "bat")
	n := world_add_char_type(w)
	testing.expect_value(t, name_str(&w.char_types[n].name), "character_type")
	testing.expect_value(t, world_check_char_type_name(w, n, "bat"), Name_Problem.In_Use)
	testing.expect_value(t, world_check_char_type_name(w, n, ""), Name_Problem.Empty)
	testing.expect_value(t, world_check_char_type_name(w, n, "character_type"), Name_Problem.None)
	d := world_duplicate_char_type(w, 0)
	testing.expect(t, d == 1 && name_str(&w.char_types[1].name) == "slime_copy" && name_str(&w.char_types[1].sprite) == "slime")
	for w.char_type_count < WORLD_MAX_CHARACTER_TYPES {
		testing.expect(t, world_add_char_type(w) >= 0)
	}
	testing.expect_value(t, world_add_char_type(w), -1)
	testing.expect_value(t, world_duplicate_char_type(w, 0), -1)
	// With no sprite anywhere, a new type is not set.
	e := new_world()
	defer free(e)
	i := world_add_char_type(e)
	testing.expect(t, e.char_types[i].sprite_set.len == 0 && world_char_type_sprite(e, &e.char_types[i]) == nil)
}

@(test)
test_a_type_with_characters_cannot_be_deleted_and_renames_follow :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	testing.expect_value(t, world_char_type_uses(w, "slime"), 2)
	testing.expect_value(t, world_delete_char_type(w, 0), 2)
	testing.expect_value(t, w.char_type_count, 2)
	testing.expect_value(t, world_rename_char_type(w, 0, "goop"), Name_Problem.None)
	testing.expect(t, name_str(&w.characters[0].type) == "goop" && name_str(&w.characters[2].type) == "goop" && name_str(&w.characters[1].type) == "bat")
	testing.expect_value(t, world_rename_char_type(w, 0, "bat"), Name_Problem.In_Use)
	// Free the type: delete the characters that have it.
	world_delete_character(w, 2)
	world_delete_character(w, 0)
	testing.expect_value(t, world_delete_char_type(w, 0), 0)
	testing.expect(t, w.char_type_count == 1 && name_str(&w.char_types[0].name) == "bat")
}

@(test)
test_sprites_and_sprite_sets_that_types_use_are_protected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	testing.expect_value(t, world_sprite_set_uses(w, "creatures"), 2)
	testing.expect_value(t, world_sprite_uses(w, "creatures", "bat"), 1)
	testing.expect(t, !world_delete_sprite_set(w, 0) && w.sprite_set_count == 1)
	testing.expect(t, !world_delete_sprite(w, 0, 0) && !world_delete_sprite(w, 0, 1) && w.sprite_sets[0].count == 2)
	// Renames follow.
	testing.expect_value(t, world_rename_sprite_set(w, 0, "zoo"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.char_types[0].sprite_set), "zoo")
	testing.expect_value(t, world_rename_sprite(w, 0, 1, "bat2"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.char_types[1].sprite), "bat2")
	testing.expect_value(t, world_rename_sprite(w, 0, 1, "slime"), Name_Problem.In_Use)
	testing.expect_value(t, name_str(&w.char_types[1].sprite), "bat2")
	// Once no type draws them, they can go.
	for i in 0 ..< 3 {
		world_delete_character(w, 2 - i)
	}
	world_delete_char_type(w, 1)
	testing.expect(t, world_delete_sprite(w, 0, 1))
	world_delete_char_type(w, 0)
	testing.expect(t, world_delete_sprite_set(w, 0))
}

@(test)
test_characters_have_a_table_name_type_and_uuid :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	testing.expect(t, w.character_count == 3 && name_str(&w.characters[0].name) == "Goo" && name_str(&w.characters[1].type) == "bat")
	testing.expect(t, w.characters[0].uuid != w.characters[1].uuid && world_find_character(w, w.characters[1].uuid) == 1)
	testing.expect_value(t, world_find_character(w, UUID_NONE), -1)
	// Names are labels: duplicates are fine, text rules apply.
	testing.expect_value(t, world_rename_character(w, 1, "Goo"), Name_Problem.None)
	testing.expect_value(t, world_rename_character(w, 1, ""), Name_Problem.Empty)
	testing.expect_value(t, world_rename_character(w, 1, "caf\xe9"), Name_Problem.Bad_Character)
	testing.expect_value(t, world_rename_character(w, 9, "x"), Name_Problem.Empty)
	testing.expect(t, world_set_character_type(w, 1, 0) && name_str(&w.characters[1].type) == "slime" && !world_set_character_type(w, 1, 9) && !world_set_character_type(w, 9, 0))
	testing.expect_value(t, world_add_character(w, 9), -2)
	d := world_duplicate_character(w, 0)
	testing.expect(t, d == 3 && name_str(&w.characters[3].name) == "Goo_copy" && w.characters[3].uuid != w.characters[0].uuid)
	_, _, _, placed := world_character_location(w, w.characters[3].uuid)
	testing.expect(t, !placed) // a copy stands nowhere
	for w.character_count < WORLD_MAX_CHARACTERS {
		testing.expect(t, world_add_character(w, 0) >= 0)
	}
	testing.expect_value(t, world_add_character(w, 0), -1)
	testing.expect_value(t, world_duplicate_character(w, 0), -1)
}

@(test)
test_placing_moving_and_taking_characters_off_maps :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	goo, flap := w.characters[0].uuid, w.characters[1].uuid
	mi, x, y, ok := world_character_location(w, goo)
	testing.expect(t, ok && mi == 0 && x == 1 && y == 0)
	testing.expect_value(t, world_character_at(w, 0, 1, 0), 0)
	testing.expect_value(t, world_character_at(w, 0, 0, 0), -1)
	testing.expect_value(t, world_character_at(w, 0, 9, 9), -1)
	// One character per cell.
	testing.expect_value(t, world_place_character(w, 0, 1, 0, flap), Place_Result.Taken)
	testing.expect_value(t, world_place_character(w, 0, 1, 0, goo), Place_Result.Placed) // already there
	testing.expect_value(t, world_place_character(w, 0, 5, 0, flap), Place_Result.Outside)
	testing.expect_value(t, world_place_character(w, 4, 0, 0, flap), Place_Result.Unknown)
	testing.expect_value(t, world_place_character(w, 0, 0, 0, UUID_NONE), Place_Result.Unknown)
	// Placing a placed character moves it.
	testing.expect_value(t, world_place_character(w, 0, 2, 1, goo), Place_Result.Placed)
	testing.expect(t, world_character_at(w, 0, 1, 0) == -1 && world_character_at(w, 0, 2, 1) == 0)
	testing.expect_value(t, world_map_character_count(w, 0), 1)
	// ... also from one map to another.
	m2 := world_add_map(w, 0, "second")
	world_place_character(w, m2, 3, 3, goo)
	testing.expect(t, world_character_at(w, 0, 2, 1) == -1 && world_character_at(w, m2, 3, 3) == 0)
	testing.expect(t, world_unplace_character(w, goo) && !world_unplace_character(w, goo))
	testing.expect_value(t, world_map_character_count(w, m2), 0)
	// Deleting a map takes its characters off but keeps them in the table.
	world_place_character(w, m2, 0, 0, flap)
	world_delete_map(w, m2)
	testing.expect_value(t, w.character_count, 3)
	_, _, _, still := world_character_location(w, flap)
	testing.expect(t, !still)
}

@(test)
test_the_player_is_any_character_or_nobody :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	goo := w.characters[0].uuid
	testing.expect(t, uuid_is_none(w.player))
	testing.expect(t, world_set_player(w, goo) && w.player == goo)
	testing.expect(t, !world_set_player(w, Uuid{0 = 1}) && w.player == goo) // no such character
	testing.expect(t, world_set_player(w, UUID_NONE) && uuid_is_none(w.player))
	world_set_player(w, w.characters[1].uuid) // not on any map: fine
	// Deleting the player clears it, and takes the character off the map.
	world_set_player(w, goo)
	testing.expect(t, world_delete_character(w, 0))
	testing.expect(t, uuid_is_none(w.player) && world_character_at(w, 0, 1, 0) == -1 && w.character_count == 2)
	testing.expect(t, !world_delete_character(w, 9))
	testing.expect_value(t, name_str(&w.characters[0].name), "Flap")
}

@(test)
test_a_map_cannot_shrink_over_a_character :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world() // Goo at 1,0 of a 3 x 2 map
	defer free(w)
	testing.expect_value(t, world_map_shrink_blocked(w, 0, 3, 2), 0)
	testing.expect_value(t, world_map_shrink_blocked(w, 0, 1, 2), 1)
	testing.expect_value(t, world_map_shrink_blocked(w, 0, 3, 1), 0)
	testing.expect(t, !world_map_set_size(w, 0, 1, 2) && w.maps[0].width == 3)
	testing.expect(t, world_map_set_size(w, 0, 3, 1) && w.maps[0].height == 1)
	testing.expect(t, world_character_at(w, 0, 1, 0) == 0)
	testing.expect(t, world_map_set_size(w, 0, 6, 5)) // growing is always fine
	world_place_character(w, 0, 5, 4, w.characters[1].uuid)
	testing.expect_value(t, world_map_shrink_blocked(w, 0, 3, 3), 1)
	world_unplace_character(w, w.characters[1].uuid)
	testing.expect(t, world_map_set_size(w, 0, 3, 3))
}

@(test)
test_flips_and_rotations_carry_characters :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	world_map_set_size(w, 0, 3, 3)
	goo := w.characters[0].uuid // at 1,0
	m := &w.maps[0]
	// A flip that changes nothing in the terrain still moves the character.
	testing.expect(t, map_flip_horizontal(m))
	testing.expect(t, world_character_at(w, 0, 1, 0) == 0) // the middle column stays
	world_place_character(w, 0, 0, 0, w.characters[1].uuid)
	testing.expect(t, map_flip_horizontal(m))
	testing.expect(t, world_character_at(w, 0, 2, 0) == 1 && world_character_at(w, 0, 1, 0) == 0)
	testing.expect(t, map_flip_vertical(m))
	testing.expect(t, world_character_at(w, 0, 2, 2) == 1 && world_character_at(w, 0, 1, 2) == 0)
	map_flip_vertical(m)
	map_flip_horizontal(m)
	// Quarter turns: the top row becomes the right column.
	testing.expect(t, map_rotate_right(m))
	x, y: int
	_, x, y, _ = world_character_location(w, goo)
	testing.expect(t, x == 2 && y == 1)
	testing.expect(t, map_rotate_left(m))
	_, x, y, _ = world_character_location(w, goo)
	testing.expect(t, x == 1 && y == 0)
	testing.expect(t, map_rotate_180(m))
	_, x, y, _ = world_character_location(w, goo)
	testing.expect(t, x == 1 && y == 2)
	_, x, y, _ = world_character_location(w, w.characters[1].uuid)
	testing.expect(t, x == 2 && y == 2)
}

@(test)
test_characters_round_trip_in_the_world_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	world_set_player(w, w.characters[2].uuid)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `"character_types": [`))
	testing.expect(t, strings.contains(text, `{"name": "slime", "sprite_set": "creatures", "sprite": "slime"}`))
	testing.expect(t, strings.contains(text, uuid_to_string(w.characters[0].uuid)))
	testing.expect(t, strings.contains(text, `"x": 1, "y": 0, "character": "`))
	testing.expect(t, strings.contains(text, `"player": "`+""))
	back := new_world()
	defer free(back)
	world_seed_uuids(back, 999)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect(t, back.char_type_count == 2 && back.character_count == 3 && back.player == w.characters[2].uuid)
	testing.expect_value(t, world_character_at(back, 0, 1, 0), 0)
	testing.expect_value(t, back.uuid_state, u64(999)) // loading keeps the running generator
	// A world from before characters loads with none.
	empty := new_world()
	defer free(empty)
	old, _ := strings.replace(world_to_json(empty), `"character_types"`, `"character_types_x"`, 1, context.temp_allocator)
	old, _ = strings.replace(old, `"characters"`, `"characters_x"`, 1, context.temp_allocator)
	old, _ = strings.replace(old, `"player"`, `"player_x"`, 1, context.temp_allocator)
	testing.expect_value(t, world_from_json(transmute([]u8)old, back), "")
	testing.expect(t, back.character_count == 0 && back.char_type_count == 0 && uuid_is_none(back.player))
}

@(test)
test_bad_character_data_is_rejected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	world_set_player(w, w.characters[2].uuid)
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	goo := uuid_to_string(w.characters[0].uuid)
	flap := uuid_to_string(w.characters[1].uuid)
	variations := [][2]string {
		{`"name": "slime", "sprite_set": "creatures"`, `"name": "bat", "sprite_set": "creatures"`}, // duplicate type name
		{`"sprite_set": "creatures", "sprite": "slime"}`, `"sprite_set": "nope", "sprite": "slime"}`},
		{`"sprite_set": "creatures", "sprite": "slime"}`, `"sprite_set": "creatures", "sprite": "nope"}`},
		{`"sprite_set": "creatures", "sprite": "slime"}`, `"sprite_set": "creatures", "sprite": ""}`},
		{`"type": "slime"}`, `"type": "ghost"}`},
		{cat(`"uuid": "`, goo, `"`), `"uuid": "not-a-uuid"`},
		{cat(`"uuid": "`, goo, `"`), `"uuid": "00000000-0000-0000-0000-000000000000"`},
		{cat(`"uuid": "`, goo, `"`), cat(`"uuid": "`, flap, `"`)}, // a uuid twice in the table
		{`"name": "Goo", "type"`, `"name": "", "type"`},
		{cat(`"x": 1, "y": 0, "character": "`, goo), cat(`"x": 7, "y": 0, "character": "`, goo)}, // outside the map
		{cat(`"x": 1, "y": 0, "character": "`, goo), `"x": 1, "y": 0, "character": "ffffffff-ffff-4fff-bfff-ffffffffffff`}, // unknown
		{`"player": "`, `"player": "ffffffff-ffff-4fff-bfff-ffffffffffff`},
		{`"player": "`, `"player": 3, "unused": "`},
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		testing.expectf(t, load_error(bad) != "", "variation %d was accepted", i)
	}
	// Two characters in one cell, and one character in two cells.
	two_in_cell, _ := strings.replace(good, cat(`"characters": [{"x": 1, "y": 0, "character": "`, goo, `"}]`), cat(`"characters": [{"x": 1, "y": 0, "character": "`, goo, `"}, {"x": 1, "y": 0, "character": "`, flap, `"}]`), 1, context.temp_allocator)
	testing.expect(t, two_in_cell != good && load_error(two_in_cell) != "")
	two_cells, _ := strings.replace(good, cat(`"characters": [{"x": 1, "y": 0, "character": "`, goo, `"}]`), cat(`"characters": [{"x": 1, "y": 0, "character": "`, goo, `"}, {"x": 2, "y": 0, "character": "`, goo, `"}]`), 1, context.temp_allocator)
	testing.expect(t, two_cells != good && load_error(two_cells) != "")
	// A failed load leaves the destination alone.
	dst := character_world()
	defer free(dst)
	before := world_to_json(dst)
	testing.expect(t, world_from_json(transmute([]u8)string(`{"tile_width": 4, "tile_height": 4, "palette": [], "characters": 5}`), dst) != "")
	testing.expect_value(t, world_to_json(dst), before)
}

cat :: proc(parts: ..string) -> string {
	return strings.concatenate(parts, context.temp_allocator)
}
