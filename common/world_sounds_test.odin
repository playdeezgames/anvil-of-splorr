#+build !js
package common

import "core:strings"
import "core:testing"

@(test)
test_sounds_are_added_renamed_copied_and_deleted :: proc(t: ^testing.T) {
	w := new_world()
	defer free(w)
	a := world_add_sound(w, "pickup")
	b := world_add_sound(w, "pickup") // made unique
	testing.expect(t, a == 0 && b == 1 && name_str(&w.sounds[1].name) == "pickup_2")
	testing.expect_value(t, world_set_sound_text(w, a, "T200 O5 L16 C E G >C"), Name_Problem.None)
	world_set_sound_loop(w, a, true)
	c := world_duplicate_sound(w, a)
	testing.expect(t, c == 1 && name_str(&w.sounds[1].name) == "pickup_copy" && sound_text(&w.sounds[1]) == "T200 O5 L16 C E G >C" && w.sounds[1].loop)
	testing.expect_value(t, w.sound_count, 3)
	testing.expect_value(t, world_rename_sound(w, 2, "pickup"), Name_Problem.In_Use)
	testing.expect_value(t, world_rename_sound(w, 2, ""), Name_Problem.Empty)
	testing.expect_value(t, world_rename_sound(w, 2, "over"), Name_Problem.None)
	testing.expect_value(t, world_find_sound(w, "over"), 2)
	testing.expect(t, world_delete_sound(w, 0) && w.sound_count == 2 && name_str(&w.sounds[0].name) == "pickup_copy")
	testing.expect(t, !world_delete_sound(w, 5) && w.sounds[2] == Sound{}) // gap closed and cleared
}

@(test)
test_sound_text_limits :: proc(t: ^testing.T) {
	w := new_world()
	defer free(w)
	i := world_add_sound(w)
	longest, _ := strings.repeat("C", SOUND_TEXT_MAX, context.temp_allocator)
	testing.expect_value(t, world_set_sound_text(w, i, longest), Name_Problem.None)
	testing.expect_value(t, w.sounds[i].text_len, SOUND_TEXT_MAX)
	too_long, _ := strings.repeat("C", SOUND_TEXT_MAX + 1, context.temp_allocator)
	testing.expect_value(t, world_set_sound_text(w, i, too_long), Name_Problem.Too_Long)
	testing.expect_value(t, w.sounds[i].text_len, SOUND_TEXT_MAX) // unchanged
	testing.expect_value(t, world_set_sound_text(w, i, "C\nD"), Name_Problem.Bad_Character)
	testing.expect_value(t, world_set_sound_text(w, i, ""), Name_Problem.None)
	testing.expect_value(t, w.sounds[i].text_len, 0)
	testing.expect_value(t, world_set_sound_text(w, 9, "C"), Name_Problem.Empty)
	for _ in 1 ..< WORLD_MAX_SOUNDS {
		testing.expect(t, world_add_sound(w) >= 0)
	}
	testing.expect_value(t, world_add_sound(w), -1) // 64 is the most
	testing.expect_value(t, world_duplicate_sound(w, 0), -1)
}

@(test)
test_sounds_round_trip_through_the_file_and_old_files_have_none :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	testing.expect_value(t, w.sound_count, 0)
	i := world_add_sound(w, "say \"hi\"")
	world_set_sound_text(w, i, `T120 "x\y" C`) // quotes and backslashes survive
	world_set_sound_loop(w, i, true)
	j := world_add_sound(w, "quiet")
	_ = j
	text := world_to_json(w)
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect(t, back.sound_count == 2 && name_str(&back.sounds[0].name) == `say "hi"` && sound_text(&back.sounds[0]) == `T120 "x\y" C` && back.sounds[0].loop)
	testing.expect(t, name_str(&back.sounds[1].name) == "quiet" && sound_text(&back.sounds[1]) == "" && !back.sounds[1].loop)
	// A world written before sounds existed still loads, with none.
	other := sample_world()
	defer free(other)
	old := world_to_json(other)
	testing.expect(t, strings.contains(old, `"sounds": [],`))
	stripped, _ := strings.replace_all(old, `  "sounds": [],`+"\n", "", context.temp_allocator)
	again := new_world()
	defer free(again)
	testing.expect_value(t, world_from_json(transmute([]u8)stripped, again), "")
	testing.expect_value(t, again.sound_count, 0)
}

@(test)
test_bad_sounds_in_a_file_are_refused_and_change_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	base := world_to_json(w)
	cases := []string {
		`"sounds": 5,`,
		`"sounds": [ 3 ],`,
		`"sounds": [ {"text": "C"} ],`,
		`"sounds": [ {"name": ""} ],`,
		`"sounds": [ {"name": "a"}, {"name": "a"} ],`,
		`"sounds": [ {"name": "a", "text": 5} ],`,
		`"sounds": [ {"name": "a", "text": "C\nD"} ],`,
		`"sounds": [ {"name": "a", "loop": "yes"} ],`,
	}
	for c in cases {
		bad, _ := strings.replace(base, `  "sounds": [],`, c, 1, context.temp_allocator)
		dst := new_world()
		world_add_sound(dst, "keep")
		testing.expectf(t, world_from_json(transmute([]u8)bad, dst) != "", "accepted: %s", c)
		testing.expectf(t, dst.sound_count == 1 && name_str(&dst.sounds[0].name) == "keep", "changed by: %s", c)
		free(dst)
	}
	many := strings.builder_make(context.temp_allocator)
	strings.write_string(&many, `"sounds": [`)
	for i in 0 ..< WORLD_MAX_SOUNDS + 1 {
		strings.write_string(&many, i > 0 ? `, ` : ``)
		strings.write_string(&many, `{"name": "s`)
		strings.write_int(&many, i)
		strings.write_string(&many, `"}`)
	}
	strings.write_string(&many, `],`)
	bad, _ := strings.replace(base, `  "sounds": [],`, strings.to_string(many), 1, context.temp_allocator)
	dst := new_world()
	defer free(dst)
	testing.expect(t, world_from_json(transmute([]u8)bad, dst) != "")
}
