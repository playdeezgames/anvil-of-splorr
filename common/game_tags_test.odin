#+build !js
package common

import "core:strings"
import "core:testing"

parse_game_tags :: proc(text: string) -> (^Game_Tags, string) {
	g := new(Game_Tags, context.temp_allocator)
	err := game_tags_from_json(transmute([]u8)text, g)
	return g, err
}

@(test)
test_a_game_tags_file_lists_names_with_optional_notes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	g, err := parse_game_tags(`{"tags": [{"name": "thing", "note": "what the player picks up"}, {"name": "spawn"}, "solid"]}`)
	testing.expect_value(t, err, "")
	testing.expect(t, g.count == 3 && game_tag_name(g, 0) == "thing" && game_tag_note(g, 0) == "what the player picks up")
	testing.expect(t, game_tag_name(g, 1) == "spawn" && game_tag_note(g, 1) == "" && game_tag_name(g, 2) == "solid")
	testing.expect(t, game_tag_find(g, "spawn") == 1 && game_tag_find(g, "nope") == -1 && game_tag_name(g, 9) == "" && game_tag_note(g, -1) == "")
	empty, err2 := parse_game_tags(`{"tags": []}`)
	testing.expect(t, err2 == "" && empty.count == 0)
}

@(test)
test_bad_game_tags_files_are_refused_and_leave_the_destination :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	bad := []string {
		`nonsense`,
		`[]`,
		`{}`,
		`{"tags": "thing"}`,
		`{"tags": [5]}`,
		`{"tags": [{"note": "x"}]}`,
		`{"tags": [{"name": ""}]}`,
		`{"tags": [{"name": "café"}]}`,
		`{"tags": ["a", "a"]}`,
		`{"tags": [{"name": "a", "note": 3}]}`,
		`{"tags": [{"name": "a", "note": "xé"}]}`,
		`{"tags": [{"name": "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"}]}`,
	}
	for text, i in bad {
		_, err := parse_game_tags(text)
		testing.expectf(t, err != "", "file %d was accepted: %s", i, text)
	}
	long := strings.repeat("n", GAME_TAG_NOTE_MAX + 1, context.temp_allocator)
	_, err := parse_game_tags(strings.concatenate({`{"tags": [{"name": "a", "note": "`, long, `"}]}`}, context.temp_allocator))
	testing.expect(t, err != "")
	exact := strings.repeat("n", GAME_TAG_NOTE_MAX, context.temp_allocator)
	_, err = parse_game_tags(strings.concatenate({`{"tags": [{"name": "a", "note": "`, exact, `"}]}`}, context.temp_allocator))
	testing.expect_value(t, err, "")
	// More tags than a world can hold.
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"tags": [`)
	for i in 0 ..< WORLD_MAX_TAGS + 1 {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, `"t`)
		strings.write_int(&b, i)
		strings.write_string(&b, `"`)
	}
	strings.write_string(&b, "]}")
	_, err = parse_game_tags(strings.to_string(b))
	testing.expect(t, err != "")
	// A failed parse leaves the destination alone.
	dst := new(Game_Tags, context.temp_allocator)
	testing.expect_value(t, game_tags_from_json(transmute([]u8)string(`{"tags": ["keep"]}`), dst), "")
	testing.expect(t, game_tags_from_json(transmute([]u8)string(`{"tags": ["x", "x"]}`), dst) != "")
	testing.expect(t, dst.count == 1 && game_tag_name(dst, 0) == "keep")
}

@(test)
test_required_tags_are_missing_unused_or_present :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world() // tags: solid; rock (terrain 1) already has solid set
	defer free(w)
	g, err := parse_game_tags(`{"tags": ["solid", "thing", "spawn", "lava"]}`)
	testing.expect_value(t, err, "")
	testing.expect_value(t, game_tag_status(w, g, 0), Tag_Status.Present) // solid is used by the rock
	testing.expect_value(t, game_tag_status(w, g, 1), Tag_Status.Missing)
	missing := game_tags_missing(w, g)
	testing.expect(t, len(missing) == 3 && missing[0] == "thing" && missing[1] == "spawn" && missing[2] == "lava")
	world_add_tag(w, "thing")
	testing.expect_value(t, game_tag_status(w, g, 1), Tag_Status.Unused) // exists, nothing uses it
	world_toggle_char_type_tag(w, 0, 1)
	testing.expect_value(t, game_tag_status(w, g, 1), Tag_Status.Present)
	testing.expect_value(t, len(game_tags_missing(w, g)), 2)
	// Which world tag is a required one.
	testing.expect(t, world_tag_required(g, w, 0) == 0 && world_tag_required(g, w, 1) == 1 && world_tag_required(g, w, 5) == -1)
	extra := world_add_tag(w, "other")
	testing.expect_value(t, world_tag_required(g, w, extra), -1)
	// Even "solid" can be unused: a world nothing sets it on.
	w.sets[0].terrains[1].tags = 0
	testing.expect_value(t, game_tag_status(w, g, 0), Tag_Status.Unused)
}

@(test)
test_missing_tags_are_created_in_one_action :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	g, _ := parse_game_tags(`{"tags": ["solid", "thing", "spawn"]}`)
	created, no_room := world_create_missing_tags(w, g)
	testing.expect(t, created == 2 && no_room == 0 && w.tag_count == 3)
	testing.expect(t, name_str(&w.tags[1]) == "thing" && name_str(&w.tags[2]) == "spawn") // in the file's order
	created, no_room = world_create_missing_tags(w, g) // nothing left to create
	testing.expect(t, created == 0 && no_room == 0 && w.tag_count == 3)
	// A world with no room for them all gets as many as fit.
	f := new_world()
	defer free(f)
	for f.tag_count < WORLD_MAX_TAGS - 1 {
		world_add_tag(f)
	}
	created, no_room = world_create_missing_tags(f, g)
	testing.expect(t, created == 1 && no_room == 1 && f.tag_count == WORLD_MAX_TAGS)
}
