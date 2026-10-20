#+build !js
package common

import "core:strings"
import "core:testing"

new_tileset :: proc(w := 4, h := 3) -> ^Tileset {
	ts := new(Tileset)
	tileset_reset(ts, w, h)
	return ts
}

parse_tileset :: proc(text: string, dst: ^Tileset) -> string {
	return tileset_from_json(transmute([]u8)text, dst)
}

@(test)
test_a_new_tileset_is_empty_with_the_given_size :: proc(t: ^testing.T) {
	ts := new_tileset(5, 7)
	defer free(ts)
	testing.expect(t, ts.width == 5 && ts.height == 7 && ts.count == 0)
	ts2 := new_tileset(0, 1000) // clamped
	defer free(ts2)
	testing.expect(t, ts2.width == IMAGE_MIN && ts2.height == IMAGE_MAX)
	ts3 := new(Tileset)
	defer free(ts3)
	tileset_reset(ts3)
	testing.expect(t, ts3.width == TILESET_DEFAULT_SIZE && ts3.height == TILESET_DEFAULT_SIZE)
}

@(test)
test_insert_blank_names_images_uniquely :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset()
	defer free(ts)
	testing.expect_value(t, tileset_insert_blank(ts, 0), 0)
	testing.expect_value(t, tileset_insert_blank(ts, 1), 1)
	testing.expect_value(t, tileset_insert_blank(ts, 2, "grass"), 2)
	testing.expect_value(t, tileset_insert_blank(ts, 3, "grass"), 3)
	testing.expect(t, tileset_name(ts, 0) == "image" && tileset_name(ts, 1) == "image_2")
	testing.expect(t, tileset_name(ts, 2) == "grass" && tileset_name(ts, 3) == "grass_2")
	testing.expect(t, ts.count == 4 && ts.images[3].width == 4 && ts.images[3].height == 3)
	// Inserting in the middle shifts the rest and keeps names with their images.
	image4_set(&ts.images[1], 0, 0, 9)
	testing.expect_value(t, tileset_insert_blank(ts, 1, "wall"), 1)
	testing.expect(t, tileset_name(ts, 1) == "wall" && tileset_name(ts, 2) == "image_2" && ts.images[2].pixels[0][0] == 9)
	testing.expect(t, ts.images[1].pixels[0][0] == 0)
	testing.expect_value(t, tileset_insert_blank(ts, 999), 5) // past the end: appended
	testing.expect_value(t, tileset_name(ts, 99), "")
}

@(test)
test_unique_names_fit_and_do_not_collide :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset()
	defer free(ts)
	long := strings.repeat("x", TILESET_NAME_MAX, context.temp_allocator)
	for _ in 0 ..< 5 {
		tileset_insert_blank(ts, ts.count, long) // a name at the limit still gets distinct, fitting variants
	}
	for i in 0 ..< ts.count {
		testing.expectf(t, len(tileset_name(ts, i)) <= TILESET_NAME_MAX && len(tileset_name(ts, i)) > 0, "image %d name length", i)
		for j in i + 1 ..< ts.count {
			testing.expectf(t, tileset_name(ts, i) != tileset_name(ts, j), "images %d and %d share a name", i, j)
		}
	}
	testing.expect_value(t, tileset_unique_name(ts, ""), "image")
	// A name that is too long is cut to fit.
	testing.expect(t, len(tileset_unique_name(ts, strings.repeat("y", 100, context.temp_allocator))) == TILESET_NAME_MAX)
}

@(test)
test_the_tileset_fills_up_at_256 :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset(1, 1)
	defer free(ts)
	for i in 0 ..< TILESET_MAX_IMAGES {
		testing.expectf(t, tileset_insert_blank(ts, ts.count) == i, "image %d did not fit", i)
	}
	testing.expect_value(t, ts.count, TILESET_MAX_IMAGES)
	testing.expect_value(t, tileset_insert_blank(ts, 0), -1)
	testing.expect_value(t, tileset_duplicate(ts, 0), -1)
	for i in 0 ..< ts.count { // every one of the 256 names is distinct
		testing.expect(t, tileset_find(ts, tileset_name(ts, i)) == i)
	}
}

@(test)
test_names_are_validated :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset()
	defer free(ts)
	tileset_insert_blank(ts, 0, "a")
	tileset_insert_blank(ts, 1, "b")
	testing.expect_value(t, tileset_check_name(ts, 0, ""), Name_Problem.Empty)
	testing.expect_value(t, tileset_check_name(ts, 0, strings.repeat("z", 33, context.temp_allocator)), Name_Problem.Too_Long)
	testing.expect_value(t, tileset_check_name(ts, 0, "caf\xC3\xA9"), Name_Problem.Bad_Character)
	testing.expect_value(t, tileset_check_name(ts, 0, "tab\there"), Name_Problem.Bad_Character)
	testing.expect_value(t, tileset_check_name(ts, 0, "b"), Name_Problem.In_Use) // another image has it
	testing.expect_value(t, tileset_check_name(ts, 0, "a"), Name_Problem.None) // keeping its own name is fine
	testing.expect_value(t, tileset_check_name(ts, -1, "a"), Name_Problem.In_Use) // a new image may not reuse it
	testing.expect_value(t, tileset_check_name(ts, 0, "Brick wall #1 (a/b)"), Name_Problem.None) // spaces and punctuation are fine
	testing.expect_value(t, tileset_check_name(ts, 0, "A"), Name_Problem.None) // case matters
	testing.expect_value(t, tileset_set_name(ts, 0, "b"), Name_Problem.In_Use)
	testing.expect_value(t, tileset_name(ts, 0), "a") // a refused rename changes nothing
	testing.expect_value(t, tileset_set_name(ts, 0, "renamed"), Name_Problem.None)
	testing.expect_value(t, tileset_name(ts, 0), "renamed")
	testing.expect_value(t, tileset_set_name(ts, 9, "x"), Name_Problem.Empty) // no such image
	testing.expect_value(t, tileset_set_name(ts, 0, strings.repeat("m", 32, context.temp_allocator)), Name_Problem.None) // exactly at the limit
}

@(test)
test_a_shorter_name_leaves_no_stale_characters :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset()
	defer free(ts)
	tileset_insert_blank(ts, 0, "longername")
	tileset_set_name(ts, 0, "ab")
	testing.expect_value(t, tileset_name(ts, 0), "ab")
	testing.expect(t, ts.names[0][2] == 0) // cleared, so equal tilesets compare equal
}

@(test)
test_duplicate_copies_pixels_and_names_the_copy :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset()
	defer free(ts)
	tileset_insert_blank(ts, 0, "tile")
	tileset_insert_blank(ts, 1, "other")
	image4_set(&ts.images[0], 2, 1, 7)
	n := tileset_duplicate(ts, 0)
	testing.expect_value(t, n, 1) // right after the original
	testing.expect(t, tileset_name(ts, 1) == "tile_copy" && tileset_name(ts, 2) == "other")
	testing.expect(t, ts.images[1].pixels[1][2] == 7 && image4_visible_equal(&ts.images[0], &ts.images[1]))
	image4_set(&ts.images[1], 0, 0, 3) // the copy is independent
	testing.expect_value(t, ts.images[0].pixels[0][0], 0)
	testing.expect_value(t, tileset_duplicate(ts, 0), 1) // again: gets its own unique name
	testing.expect(t, tileset_name(ts, 1) == "tile_copy_2" && tileset_name(ts, 2) == "tile_copy")
	testing.expect_value(t, tileset_duplicate(ts, 99), -1)
}

@(test)
test_delete_closes_the_gap :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset()
	defer free(ts)
	for name in ([]string{"a", "b", "c", "d"}) {
		i := tileset_insert_blank(ts, ts.count, name)
		image4_set(&ts.images[i], 0, 0, int(name[0] - 'a') + 1)
	}
	testing.expect(t, tileset_delete(ts, 1))
	testing.expect_value(t, ts.count, 3)
	testing.expect(t, tileset_name(ts, 0) == "a" && tileset_name(ts, 1) == "c" && tileset_name(ts, 2) == "d")
	testing.expect(t, ts.images[1].pixels[0][0] == 3 && ts.images[2].pixels[0][0] == 4) // pixels travelled with the names
	testing.expect_value(t, tileset_name(ts, 3), "")
	testing.expect(t, ts.name_len[3] == 0 && ts.images[3].width == 0) // the vacated slot is cleared
	testing.expect(t, tileset_delete(ts, 2) && tileset_delete(ts, 0) && tileset_delete(ts, 0))
	testing.expect(t, ts.count == 0 && !tileset_delete(ts, 0) && !tileset_delete(ts, -1))
}

@(test)
test_move_swaps_neighbours :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset()
	defer free(ts)
	for name in ([]string{"a", "b", "c"}) {
		i := tileset_insert_blank(ts, ts.count, name)
		image4_set(&ts.images[i], 1, 1, int(name[0] - 'a') + 1)
	}
	testing.expect_value(t, tileset_move(ts, 0, 1), 1)
	testing.expect(t, tileset_name(ts, 0) == "b" && tileset_name(ts, 1) == "a" && tileset_name(ts, 2) == "c")
	testing.expect(t, ts.images[0].pixels[1][1] == 2 && ts.images[1].pixels[1][1] == 1)
	testing.expect_value(t, tileset_move(ts, 1, -1), 0)
	testing.expect_value(t, tileset_name(ts, 0), "a")
	testing.expect_value(t, tileset_move(ts, 0, -1), 0) // already first
	testing.expect_value(t, tileset_move(ts, 2, 1), 2) // already last
	testing.expect_value(t, tileset_move(ts, 9, 1), 9)
	testing.expect_value(t, tileset_move(ts, 1, 0), 1)
}

@(test)
test_resizing_the_tileset_resizes_every_image_and_keeps_hidden_pixels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset(8, 8)
	defer free(ts)
	for _ in 0 ..< 3 {
		tileset_insert_blank(ts, ts.count)
	}
	image4_set(&ts.images[2], 7, 7, 5)
	testing.expect(t, tileset_set_size(ts, 4, 6))
	for i in 0 ..< 3 {
		testing.expect(t, ts.images[i].width == 4 && ts.images[i].height == 6)
	}
	testing.expect_value(t, image4_get(&ts.images[2], 7, 7), 0) // hidden
	testing.expect(t, tileset_set_size(ts, 8, 8))
	testing.expect_value(t, image4_get(&ts.images[2], 7, 7), 5) // restored
	testing.expect(t, !tileset_set_size(ts, 8, 8))
	testing.expect(t, tileset_set_size(ts, 500, -4) && ts.width == IMAGE_MAX && ts.height == IMAGE_MIN)
	// New images take the current size.
	testing.expect(t, tileset_insert_blank(ts, 0) == 0 && ts.images[0].width == IMAGE_MAX)
}

@(test)
test_tileset_json_exact_text_and_round_trip :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset(3, 2)
	defer free(ts)
	a := tileset_insert_blank(ts, 0, "grass")
	b := tileset_insert_blank(ts, 1, "say \"hi\"\\")
	for c, x in ([]int{1, 2, 3}) {
		image4_set(&ts.images[a], x, 0, c)
	}
	image4_set(&ts.images[b], 2, 1, 15)
	text := tileset_to_json(ts)
	want := "{\n  \"width\": 3,\n  \"height\": 2,\n  \"images\": [\n    {\n      \"name\": \"grass\",\n      \"bytes\": [\n        18, 48,\n        0, 0\n      ]\n    },\n    {\n      \"name\": \"say \\\"hi\\\"\\\\\",\n      \"bytes\": [\n        0, 0,\n        0, 240\n      ]\n    }\n  ]\n}\n"
	testing.expect_value(t, text, want)
	back := new(Tileset)
	defer free(back)
	testing.expect_value(t, parse_tileset(text, back), "")
	testing.expect(t, back.width == 3 && back.height == 2 && back.count == 2)
	testing.expect(t, tileset_name(back, 0) == "grass" && tileset_name(back, 1) == "say \"hi\"\\")
	testing.expect(t, image4_visible_equal(&back.images[0], &ts.images[0]) && image4_visible_equal(&back.images[1], &ts.images[1]))
}

@(test)
test_an_empty_tileset_round_trips :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset(16, 16)
	defer free(ts)
	text := tileset_to_json(ts)
	testing.expect_value(t, text, "{\n  \"width\": 16,\n  \"height\": 16,\n  \"images\": []\n}\n")
	back := new(Tileset)
	defer free(back)
	testing.expect_value(t, parse_tileset(text, back), "")
	testing.expect(t, back.count == 0 && back.width == 16)
	testing.expect_value(t, parse_tileset(`{"width": 2, "height": 2}`, back), "") // "images" may be left out
}

@(test)
test_bad_tileset_files_are_rejected_and_change_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dst := new_tileset(6, 6)
	defer free(dst)
	tileset_insert_blank(dst, 0, "keep")
	cases := [?]struct {
		json, want: string,
	} {
		{"", "not valid JSON"},
		{"[]", "top level"},
		{`{}`, "whole numbers"},
		{`{"width": 0, "height": 4}`, "out of range"},
		{`{"width": 4, "height": 65}`, "out of range"},
		{`{"width": 2, "height": 2, "images": 5}`, `"images" must be a list`},
		{`{"width": 2, "height": 2, "images": [5]}`, "image 0 must be an object"},
		{`{"width": 2, "height": 2, "images": [{"bytes": [0, 0]}]}`, `"name" must be text`},
		{`{"width": 2, "height": 2, "images": [{"name": "", "bytes": [0, 0]}]}`, "the name is empty"},
		{`{"width": 2, "height": 2, "images": [{"name": "café", "bytes": [0, 0]}]}`, "other than printable ASCII"},
		{`{"width": 2, "height": 2, "images": [{"name": "a", "bytes": [0, 0]}, {"name": "a", "bytes": [0, 0]}]}`, `"a" is used more than once`},
		{`{"width": 2, "height": 2, "images": [{"name": "a"}]}`, `needs "bytes"`},
		{`{"width": 2, "height": 2, "images": [{"name": "a", "bytes": [0]}]}`, "1 entries but a 2 x 2 image needs 2 (1 per row)"},
		{`{"width": 3, "height": 2, "images": [{"name": "a", "bytes": [0, 0]}]}`, "needs 4 (2 per row)"},
		{`{"width": 2, "height": 1, "images": [{"name": "a", "bytes": [300]}]}`, "entry 0 is not a whole number"},
		{`{"width": 2, "height": 1, "images": [{"name": "a", "bytes": [1.5]}]}`, "entry 0 is not a whole number"},
	}
	for c in cases {
		err := parse_tileset(c.json, dst)
		testing.expectf(t, strings.contains(err, c.want), "input %q: error %q should contain %q", c.json, err, c.want)
		testing.expectf(t, dst.width == 6 && dst.count == 1 && tileset_name(dst, 0) == "keep", "a rejected file changed the tileset: %q", c.json)
	}
	// A good image followed by a bad one still changes nothing.
	err := parse_tileset(`{"width": 1, "height": 1, "images": [{"name": "ok", "bytes": [16]}, {"name": "bad", "bytes": [1, 2]}]}`, dst)
	testing.expect(t, err != "" && dst.width == 6 && dst.count == 1)
	// Too many images.
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"width": 1, "height": 1, "images": [`)
	for i in 0 ..< TILESET_MAX_IMAGES + 1 {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		strings.write_string(&b, `{"name": "n`)
		strings.write_int(&b, i)
		strings.write_string(&b, `", "bytes": [0]}`)
	}
	strings.write_string(&b, "]}")
	err = parse_tileset(strings.to_string(b), dst)
	testing.expect(t, strings.contains(err, "more than the 256 allowed") && dst.width == 6)
	// Extra fields are ignored.
	testing.expect_value(t, parse_tileset(`{"note": "x", "width": 1, "height": 1, "images": [{"id": 5, "name": "a", "bytes": [16]}]}`, dst), "")
	testing.expect(t, dst.count == 1 && dst.images[0].pixels[0][0] == 1)
}

@(test)
test_the_largest_tileset_round_trips_and_fits_the_web_buffer :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	ts := new_tileset(IMAGE_MAX, IMAGE_MAX)
	defer free(ts)
	for i in 0 ..< TILESET_MAX_IMAGES {
		n := tileset_insert_blank(ts, ts.count)
		for k in 0 ..< IMAGE_MAX {
			image4_set(&ts.images[n], k, k, 8 + (i + k) % 8) // colours 8..15: three digit bytes, the worst case
			image4_set(&ts.images[n], IMAGE_MAX - 1 - k, k, 15)
		}
	}
	text := tileset_to_json(ts)
	back := new(Tileset)
	defer free(back)
	err := parse_tileset(text, back)
	testing.expectf(t, err == "", "largest tileset: %s", err)
	testing.expect(t, back.count == TILESET_MAX_IMAGES)
	for i in 0 ..< TILESET_MAX_IMAGES {
		if !image4_visible_equal(&back.images[i], &ts.images[i]) || tileset_name(back, i) != tileset_name(ts, i) {
			testing.expectf(t, false, "image %d differs after the round trip", i)
			return
		}
	}
	testing.expectf(t, len(text) < 3_800_000, "the worst-case file is %d bytes: it must fit the web buffer", len(text))
}
