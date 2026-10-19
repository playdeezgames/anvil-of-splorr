#+build !js
package common

import "core:strings"
import "core:testing"

@(test)
test_default_map_matches_spec :: proc(t: ^testing.T) {
	m := default_input_map()
	// Gamepad: d-pad for directions; buttons 00/01/09/08 are red/green/blue/yellow.
	testing.expect_value(t, m.pad[.Up], 12)
	testing.expect_value(t, m.pad[.Down], 13)
	testing.expect_value(t, m.pad[.Left], 14)
	testing.expect_value(t, m.pad[.Right], 15)
	testing.expect_value(t, m.pad[.Red], 0)
	testing.expect_value(t, m.pad[.Green], 1)
	testing.expect_value(t, m.pad[.Blue], 9)
	testing.expect_value(t, m.pad[.Yellow], 8)
	// Keyboard: arrows, space = green, esc = red, tab = yellow, enter = blue.
	for c, a in ([Action]string{.Up = "ArrowUp", .Down = "ArrowDown", .Left = "ArrowLeft", .Right = "ArrowRight", .Green = "Space", .Red = "Escape", .Yellow = "Tab", .Blue = "Enter"}) {
		got, ok := action_for_key(&m, c)
		testing.expectf(t, ok && got == a, "key %s should be %v", c, a)
	}
}

@(test)
test_lookups :: proc(t: ^testing.T) {
	m := default_input_map()
	a, ok := action_for_pad_button(&m, 9)
	testing.expect(t, ok && a == .Blue)
	_, ok = action_for_pad_button(&m, 6) // triggers are unbound
	testing.expect(t, !ok)
	_, ok = action_for_pad_button(&m, -1)
	testing.expect(t, !ok)
	_, ok = action_for_key(&m, "KeyQ")
	testing.expect(t, !ok)
	_, ok = action_for_key(&m, "")
	testing.expect(t, !ok)
}

@(test)
test_every_action_has_a_default_key_and_button :: proc(t: ^testing.T) {
	m := default_input_map()
	for a in Action {
		testing.expectf(t, m.pad[a] != NO_BUTTON && m.keys[a].len > 0, "%v lacks a default binding", a)
		testing.expectf(t, is_known_key_code(key_name(&m.keys[a])), "%v default key is not a known key", a)
	}
}

parse :: proc(s: string) -> (Input_Map, string) {
	return input_map_from_json(transmute([]u8)s)
}

@(test)
test_json_round_trip_and_committed_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := default_input_map()
	text := input_map_to_json(m)
	got, err := parse(text)
	testing.expectf(t, err == "", "round trip failed: %s", err)
	testing.expect(t, got == m)

	// The repo's input_map.json must be valid and equal the defaults it documents.
	file, ferr := input_map_from_json(#load("../input_map.json"))
	testing.expectf(t, ferr == "", "input_map.json: %s", ferr)
	testing.expect(t, file == m)

	// Unbinding survives a round trip.
	m.pad[.Blue] = NO_BUTTON
	m.keys[.Blue] = {}
	got, err = parse(input_map_to_json(m))
	testing.expect(t, err == "" && got == m)
}

@(test)
test_partial_files_keep_defaults_and_null_unbinds :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	def := default_input_map()
	m, err := parse(`{"gamepad": {"red": 5, "green": null}, "_note": "hi"}`)
	testing.expect_value(t, err, "")
	testing.expect_value(t, m.pad[.Red], 5)
	testing.expect_value(t, m.pad[.Green], NO_BUTTON)
	testing.expect_value(t, m.pad[.Up], def.pad[.Up])
	testing.expect(t, m.keys == def.keys)
	m, err = parse(`{"keyboard": {"red": "KeyQ"}}`)
	testing.expect_value(t, err, "")
	testing.expect_value(t, key_name(&m.keys[.Red]), "KeyQ")
	m, err = parse(`{}`)
	testing.expect(t, err == "" && m == def)
}

@(test)
test_json_errors :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := [?]struct {
		json, want: string,
	} {
		{"", "not valid JSON"},
		{"[]", "top level"},
		{`{"gamepd": {}}`, `unknown section "gamepd"`},
		{`{"gamepad": []}`, `"gamepad" must be an object`},
		{`{"gamepad": {"gren": 1}}`, `unknown command "gren"`},
		{`{"gamepad": {"red": 17}}`, "out of range"},
		{`{"gamepad": {"red": -1}}`, "out of range"},
		{`{"gamepad": {"red": 1.5}}`, "expected a button number"},
		{`{"gamepad": {"red": "0"}}`, "expected a button number"},
		{`{"gamepad": {"red": 1}}`, `bound to both "green" and "red"`}, // green defaults to 1
		{`{"keyboard": {"red": "KeyRR"}}`, `unknown key "KeyRR"`},
		{`{"keyboard": {"red": 5}}`, "expected a key name"},
		{`{"keyboard": {"red": "Tab"}}`, `bound to both`}, // yellow defaults to Tab
	}
	for c in cases {
		_, err := parse(c.json)
		testing.expectf(t, strings.contains(err, c.want), "input %q: error %q should contain %q", c.json, err, c.want)
	}
}

@(test)
test_swapping_two_commands_is_valid :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m, err := parse(`{"gamepad": {"red": 1, "green": 0}}`)
	testing.expect_value(t, err, "")
	testing.expect_value(t, m.pad[.Red], 1)
	testing.expect_value(t, m.pad[.Green], 0)
}
