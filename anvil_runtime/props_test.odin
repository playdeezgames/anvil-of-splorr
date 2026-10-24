#+build !js
package anvil_runtime

import cm "../common"
import "core:testing"

// The tiny game with properties: "player" has health 10 and speed 3, the Hero has health 7; the "gate"
// feature type (a new type and feature) has locked 1 and its feature overrides it to 0. Loaded
// through the file like a game gets it.
props_game :: proc() -> ^World {
	w := loaded_world()
	pt := cm.world_find_char_type(w, "player")
	h := cm.world_char_type_add_prop(w, pt, "health", 10)
	cm.world_char_type_add_prop(w, pt, "speed", 3)
	cm.world_character_set_value(w, index_of_character(w, "Hero"), h, 7)
	ft := cm.world_add_feature_type(w, "gate")
	locked := cm.world_feature_type_add_prop(w, ft, "locked", 1)
	gate := cm.world_add_feature(w, ft)
	cm.world_feature_set_value(w, gate, locked, 0)
	text := cm.world_to_json(w)
	free(w)
	back := new_world()
	assert(load(back, transmute([]u8)text) == "")
	return back
}

@(test)
test_a_game_reads_properties_as_authored :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := props_game()
	defer free(w)
	hero := index_of_character(w, "Hero")
	star := index_of_character(w, "Star")
	health, ok := character_prop_index(w, hero, "health")
	testing.expect(t, ok && health == 0)
	_, found := character_prop_index(w, hero, "mana")
	testing.expect(t, !found)
	_, found = character_prop_index(w, star, "health") // the star's type has none
	testing.expect(t, !found)
	_, found = character_prop_index(w, 99, "health")
	testing.expect(t, !found)
	speed, _ := character_prop_index(w, hero, "speed")
	testing.expect_value(t, character_value(w, hero, health), 7)
	testing.expect_value(t, character_value(w, hero, speed), 3)
	testing.expect_value(t, character_prop_default(w, hero, health), 10)
	testing.expect_value(t, character_prop_default(w, hero, 9), 0)
	testing.expect_value(t, character_value(w, star, 0), 0)
	locked, ok2 := feature_prop_index(w, 0, "locked")
	testing.expect(t, ok2 && locked == 0)
	testing.expect_value(t, feature_value(w, 0, locked), 0)
	testing.expect_value(t, feature_prop_default(w, 0, locked), 1)
	_, found = feature_prop_index(w, 7, "locked")
	testing.expect(t, !found)
}

@(test)
test_values_change_in_the_play_state_and_never_in_the_world :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := props_game()
	defer free(w)
	before := cm.world_to_json(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero := index_of_character(w, "Hero")
	testing.expect_value(t, play_character_value(ps, w, hero, 0), 7) // copied from the authors' value
	testing.expect_value(t, play_character_value(ps, w, hero, 1), 3)
	testing.expect(t, play_set_character_value(ps, w, hero, 0, 5) && play_set_character_value(ps, w, hero, 1, 3))
	testing.expect_value(t, play_character_value(ps, w, hero, 0), 5)
	testing.expect_value(t, ps.character_values[hero].mask, u16(1)) // a value equal to the default is no override
	testing.expect(t, play_set_character_value(ps, w, hero, 0, 10))
	testing.expect_value(t, play_character_value(ps, w, hero, 0), 10)
	testing.expect(t, !play_set_character_value(ps, w, hero, 9, 1) && !play_set_character_value(ps, w, 99, 0, 1))
	testing.expect(t, !play_set_character_value(ps, w, index_of_character(w, "Star"), 0, 1)) // no such property
	testing.expect_value(t, play_character_value(ps, w, 99, 0), 0)
	// Features.
	testing.expect_value(t, play_feature_value(ps, w, 0, 0), 0)
	testing.expect(t, play_set_feature_value(ps, w, 0, 0, 1))
	testing.expect_value(t, play_feature_value(ps, w, 0, 0), 1)
	testing.expect(t, !play_set_feature_value(ps, w, 3, 0, 1) && play_feature_value(ps, w, 3, 0) == 0)
	// The world is as it was, a copy of the state is independent, and play_init starts over.
	testing.expect_value(t, cm.world_to_json(w), before)
	testing.expect_value(t, character_value(w, hero, 0), 7)
	play_init(ps, w)
	testing.expect_value(t, play_character_value(ps, w, hero, 0), 7)
	testing.expect_value(t, play_feature_value(ps, w, 0, 0), 0)
}
