#+build !js
package common

import "core:strings"
import "core:testing"

@(test)
test_parameters_are_added_named_uniquely_renamed_and_deleted :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	a := world_add_param(w)
	b := world_add_param(w)
	testing.expect(t, name_str(&w.params[a].name) == "param" && name_str(&w.params[b].name) == "param_2")
	testing.expect(t, w.params[a].kind == .Number && w.params[a].number == 0)
	testing.expect_value(t, world_check_param_name(w, b, "param"), Name_Problem.In_Use)
	testing.expect_value(t, world_check_param_name(w, b, "param_2"), Name_Problem.None)
	testing.expect_value(t, world_check_param_name(w, b, ""), Name_Problem.Empty)
	testing.expect_value(t, world_check_param_name(w, b, "caf\xe9"), Name_Problem.Bad_Character)
	testing.expect_value(t, world_rename_param(w, b, "round_seconds"), Name_Problem.None)
	testing.expect_value(t, world_rename_param(w, a, "round_seconds"), Name_Problem.In_Use)
	testing.expect_value(t, world_rename_param(w, 9, "x"), Name_Problem.Empty)
	testing.expect_value(t, world_find_param(w, "round_seconds"), b)
	d := world_duplicate_param(w, b)
	testing.expect(t, d == b + 1 && name_str(&w.params[d].name) == "round_seconds_copy" && w.params[d].number == w.params[b].number && w.param_count == 3)
	testing.expect(t, world_delete_param(w, d) && world_delete_param(w, a) && w.param_count == 1 && name_str(&w.params[0].name) == "round_seconds")
	testing.expect(t, !world_delete_param(w, 3))
	for w.param_count < WORLD_MAX_PARAMS {
		testing.expect(t, world_add_param(w) >= 0)
	}
	testing.expect_value(t, world_add_param(w), -1)
	testing.expect_value(t, world_duplicate_param(w, 0), -1)
	testing.expect_value(t, world_duplicate_param(w, 99), -1)
}

@(test)
test_numbers_are_whole_32_bit_values_and_texts_are_short_ascii :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	i := world_add_param(w)
	testing.expect(t, world_set_param_number(w, i, 60) && w.params[i].number == 60)
	world_set_param_number(w, i, 5_000_000_000)
	testing.expect_value(t, w.params[i].number, PARAM_NUMBER_MAX) // clamped to 32 bits
	world_set_param_number(w, i, -5_000_000_000)
	testing.expect_value(t, w.params[i].number, PARAM_NUMBER_MIN)
	testing.expect(t, !world_set_param_number(w, 4, 1))
	testing.expect_value(t, world_set_param_text(w, i, "Go Get It!"), Name_Problem.None)
	testing.expect(t, w.params[i].kind == .Text && name_str(&w.params[i].text) == "Go Get It!")
	testing.expect_value(t, world_set_param_text(w, i, ""), Name_Problem.None) // empty is fine
	testing.expect_value(t, world_set_param_text(w, i, strings.repeat("x", PARAM_TEXT_MAX, context.temp_allocator)), Name_Problem.None)
	testing.expect_value(t, world_set_param_text(w, i, strings.repeat("x", PARAM_TEXT_MAX + 1, context.temp_allocator)), Name_Problem.Too_Long)
	testing.expect_value(t, world_set_param_text(w, i, "caf\xe9"), Name_Problem.Bad_Character)
	testing.expect_value(t, len(name_str(&w.params[i].text)), PARAM_TEXT_MAX) // a refused text changed nothing
	testing.expect_value(t, world_set_param_text(w, 9, "x"), Name_Problem.Empty)
	// Switching kind keeps the other value.
	world_set_param_number(w, i, 42)
	world_set_param_text(w, i, "hello")
	testing.expect(t, world_toggle_param_kind(w, i) && w.params[i].kind == .Number && w.params[i].number == 42)
	testing.expect(t, world_toggle_param_kind(w, i) && w.params[i].kind == .Text && name_str(&w.params[i].text) == "hello")
	testing.expect(t, !world_toggle_param_kind(w, 9))
	testing.expect_value(t, param_value_text(&w.params[i]), "hello")
	world_toggle_param_kind(w, i)
	testing.expect_value(t, param_value_text(&w.params[i]), "42")
}

@(test)
test_parameters_are_read_by_name_with_a_default :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	n := world_add_param(w, "round_seconds")
	world_set_param_number(w, n, 90)
	s := world_add_param(w, "title")
	world_set_param_text(w, s, "Go Get the Thing!")
	testing.expect_value(t, world_param_number(w, "round_seconds", 30), 90)
	testing.expect_value(t, world_param_number(w, "points", 1), 1) // absent: the default
	testing.expect_value(t, world_param_number(w, "title", 7), 7) // a text is not a number
	testing.expect_value(t, world_param_text(w, "title", "?"), "Go Get the Thing!")
	testing.expect_value(t, world_param_text(w, "missing", "?"), "?")
	testing.expect_value(t, world_param_text(w, "round_seconds", "?"), "?") // a number is not a text
}

@(test)
test_parameters_round_trip_and_old_files_load_without_them :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	a := world_add_param(w, "round_seconds")
	world_set_param_number(w, a, 60)
	b := world_add_param(w, "points_per_pickup")
	world_set_param_number(w, b, -3)
	c := world_add_param(w, "title")
	world_set_param_text(w, c, `say "hi" \ ok`)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `{"name": "round_seconds", "number": 60}`))
	testing.expect(t, strings.contains(text, `{"name": "points_per_pickup", "number": -3}`))
	testing.expect(t, strings.contains(text, `{"name": "title", "text": "say \"hi\" \\ ok"}`))
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect(t, back.param_count == 3 && back.params[0].number == 60 && back.params[1].number == -3 && name_str(&back.params[2].text) == `say "hi" \ ok`)
	// An extreme number and an empty text survive.
	world_set_param_number(w, a, PARAM_NUMBER_MIN)
	world_set_param_text(w, c, "")
	back2 := new_world()
	defer free(back2)
	testing.expect_value(t, world_from_json(transmute([]u8)world_to_json(w), back2), "")
	testing.expect(t, back2.params[0].number == PARAM_NUMBER_MIN && back2.params[2].kind == .Text && name_str(&back2.params[2].text) == "")
	// A file from before parameters has none.
	empty := new_world()
	defer free(empty)
	old, _ := strings.replace(world_to_json(empty), `"params": [],`, ``, 1, context.temp_allocator)
	testing.expect(t, old != world_to_json(empty))
	testing.expect_value(t, world_from_json(transmute([]u8)old, back), "")
	testing.expect_value(t, back.param_count, 0)
	testing.expect(t, strings.contains(world_to_json(empty), `"params": [],`))
}

@(test)
test_bad_parameter_data_is_rejected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	n := world_add_param(w, "round")
	world_set_param_number(w, n, 60)
	t_ := world_add_param(w, "title")
	world_set_param_text(w, t_, "hi")
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	variations := [][2]string {
		{`"params": [`, `"params": {"a": [`},
		{`{"name": "round", "number": 60}`, `{"name": "round", "number": 60.5}`},
		{`{"name": "round", "number": 60}`, `{"name": "round", "number": 2147483648}`},
		{`{"name": "round", "number": 60}`, `{"name": "round", "number": -2147483649}`},
		{`{"name": "round", "number": 60}`, `{"name": "round", "number": "60"}`},
		{`{"name": "round", "number": 60}`, `{"name": "round"}`}, // neither
		{`{"name": "round", "number": 60}`, `{"name": "round", "number": 60, "text": "x"}`}, // both
		{`{"name": "round", "number": 60}`, `{"name": "", "number": 60}`},
		{`{"name": "round", "number": 60}`, `{"name": "title", "number": 60}`}, // a name twice
		{`{"name": "title", "text": "hi"}`, `{"name": "title", "text": 5}`},
		{`{"name": "title", "text": "hi"}`, `{"name": "title", "text": "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"}`}, // 33 characters
		{`{"name": "title", "text": "hi"}`, `{"name": "title", "text": "café"}`},
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		testing.expectf(t, load_error(bad) != "", "variation %d was accepted", i)
	}
	// More than 64.
	full := new_world()
	defer free(full)
	for full.param_count < WORLD_MAX_PARAMS {
		world_add_param(full)
	}
	text := world_to_json(full)
	testing.expect_value(t, load_error(text), "")
	extra, _ := strings.replace(text, `"params": [`, `"params": [{"name": "one_more", "number": 1}, `, 1, context.temp_allocator)
	testing.expect(t, load_error(extra) != "")
}
