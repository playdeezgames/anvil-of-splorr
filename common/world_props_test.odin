#+build !js
package common

import "core:strings"
import "core:testing"

// The feature world (character types slime and bat; characters Goo, Flap, Pip; feature types tree and
// rock; features Oak, Boulder, Stump) with properties: slime has health 10 and speed 3, tree has
// hardness 4. Goo has health 7; Oak has hardness 9.
props_world :: proc() -> ^World {
	w := feature_world()
	h := world_char_type_add_prop(w, 0, "health", 10)
	world_char_type_add_prop(w, 0, "speed", 3)
	world_character_set_value(w, 0, h, 7)
	hard := world_feature_type_add_prop(w, 0, "hardness", 4)
	world_feature_set_value(w, 0, hard, 9)
	return w
}

@(test)
test_character_and_feature_values_are_their_own_or_the_types_default :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := props_world()
	defer free(w)
	testing.expect_value(t, world_character_value(w, 0, 0), 7) // Goo's own
	testing.expect_value(t, world_character_value(w, 2, 0), 10) // Pip: the default
	testing.expect_value(t, world_character_value(w, 0, 1), 3)
	testing.expect_value(t, world_character_value(w, 1, 0), 0) // Flap is a bat: no properties
	testing.expect_value(t, world_character_value(w, 99, 0), 0)
	testing.expect_value(t, world_character_value(w, 0, 9), 0)
	testing.expect_value(t, world_feature_value(w, 0, 0), 9)
	testing.expect_value(t, world_feature_value(w, 2, 0), 4)
	// A value equal to the default is not kept as an override.
	testing.expect(t, world_character_set_value(w, 0, 0, 10) && w.characters[0].overrides.mask == 0)
	testing.expect(t, world_feature_set_value(w, 0, 0, 4) && w.features[0].overrides.mask == 0)
	testing.expect(t, !world_character_set_value(w, 1, 0, 5) && !world_character_set_value(w, 0, 5, 5) && !world_feature_set_value(w, 99, 0, 1))
	// The type's default moves everything that follows it.
	w.char_types[0].props.values[0] = 12
	testing.expect_value(t, world_character_value(w, 0, 0), 12)
	testing.expect(t, world_char_type_add_prop(w, 99) == -1)
	for w.char_types[0].props.count < PROP_MAX {
		world_char_type_add_prop(w, 0)
	}
	testing.expect_value(t, world_char_type_add_prop(w, 0), -1)
}

@(test)
test_changing_the_type_forgets_values_and_deleting_a_property_shifts_them :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := props_world()
	defer free(w)
	world_character_set_value(w, 0, 1, 8) // Goo: health 7, speed 8
	world_character_set_value(w, 2, 1, 5) // Pip: speed 5
	testing.expect(t, world_char_type_delete_prop(w, 0, 0)) // health goes: speed is property 0 now
	testing.expect_value(t, w.char_types[0].props.count, 1)
	testing.expect_value(t, world_character_value(w, 0, 0), 8)
	testing.expect_value(t, world_character_value(w, 2, 0), 5)
	testing.expect_value(t, w.characters[0].overrides.mask, u16(1))
	testing.expect(t, !world_char_type_delete_prop(w, 0, 5) && !world_char_type_delete_prop(w, 99, 0))
	// Another type: the values go.
	testing.expect(t, world_set_character_type(w, 0, 1))
	testing.expect_value(t, w.characters[0].overrides.mask, u16(0))
	testing.expect(t, world_set_character_type(w, 0, 1) && true) // the same type again changes nothing
	// A feature: the same.
	testing.expect(t, world_feature_type_delete_prop(w, 0, 0))
	testing.expect_value(t, w.features[0].overrides.mask, u16(0))
	world_feature_type_add_prop(w, 0, "a", 1)
	world_feature_set_value(w, 0, 0, 2)
	testing.expect(t, world_set_feature_type(w, 0, 1) && w.features[0].overrides.mask == 0)
	// Renaming the type keeps the values with their characters.
	world_char_type_add_prop(w, 1, "mana", 1)
	world_character_set_value(w, 0, 0, 40)
	testing.expect_value(t, world_rename_char_type(w, 1, "flyer"), Name_Problem.None)
	testing.expect_value(t, world_character_value(w, 0, 0), 40)
}

@(test)
test_properties_round_trip_in_the_world_file_and_are_absent_when_unused :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	plain := feature_world()
	defer free(plain)
	plain_text := world_to_json(plain)
	testing.expect(t, !strings.contains(plain_text, `"props"`)) // nothing unused is written
	w := props_world()
	defer free(w)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `"props": [{"name": "health", "value": 10}, {"name": "speed", "value": 3}]`))
	testing.expect(t, strings.contains(text, `"props": [{"name": "hardness", "value": 4}]`))
	testing.expect(t, strings.contains(text, `"props": {"health": 7}`) && strings.contains(text, `"props": {"hardness": 9}`))
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect_value(t, world_character_value(back, 0, 0), 7)
	testing.expect_value(t, world_character_value(back, 2, 0), 10)
	testing.expect_value(t, world_feature_value(back, 0, 0), 9)
	// A world from before properties loads with none.
	testing.expect_value(t, world_from_json(transmute([]u8)plain_text, back), "")
	testing.expect(t, back.char_types[0].props.count == 0 && back.characters[0].overrides.mask == 0)
}

@(test)
test_bad_property_data_is_rejected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := props_world()
	defer free(w)
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	variations := [][2]string {
		{`{"name": "health", "value": 10}`, `{"name": "health", "value": 10.5}`},
		{`{"name": "health", "value": 10}`, `{"name": "speed", "value": 10}`}, // a property twice
		{`{"name": "health", "value": 10}`, `{"name": "", "value": 10}`},
		{`"props": {"health": 7}`, `"props": {"mana": 7}`}, // not a property of the type
		{`"props": {"health": 7}`, `"props": {"health": "seven"}`},
		{`"props": {"health": 7}`, `"props": [7]`},
		{`"props": {"hardness": 9}`, `"props": {"hardness": 99999999999}`},
		{`"props": [{"name": "hardness", "value": 4}]`, `"props": {"hardness": 4}`},
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		testing.expectf(t, load_error(bad) != "", "variation %d was accepted", i)
	}
}
