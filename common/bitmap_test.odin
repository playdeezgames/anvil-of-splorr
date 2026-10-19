#+build !js
package common

import "core:strings"
import "core:testing"

@(test)
test_bitmap_make_clamps :: proc(t: ^testing.T) {
	g := bitmap_make(0, 1000)
	testing.expect_value(t, g.width, BITMAP_MIN)
	testing.expect_value(t, g.height, BITMAP_MAX)
	g = bitmap_make(8, 8)
	for y in 0 ..< 8 {
		for x in 0 ..< 8 {
			testing.expect(t, !bitmap_get(&g, x, y))
		}
	}
}

@(test)
test_bitmap_set_toggle_and_bounds :: proc(t: ^testing.T) {
	g := bitmap_make(4, 3)
	testing.expect(t, bitmap_toggle(&g, 3, 2)) // on
	testing.expect(t, bitmap_get(&g, 3, 2))
	testing.expect(t, !bitmap_toggle(&g, 3, 2)) // off again
	testing.expect(t, bitmap_set(&g, 0, 0, true))
	testing.expect(t, !bitmap_set(&g, 0, 0, true)) // no change
	testing.expect(t, !bitmap_set(&g, 4, 0, true)) // out of range
	testing.expect(t, !bitmap_set(&g, 0, -1, true))
	testing.expect(t, !bitmap_toggle(&g, 99, 99))
	testing.expect(t, !bitmap_get(&g, 4, 0) && !bitmap_get(&g, -1, 0))
}

@(test)
test_bitmap_resize_keeps_hidden_bits :: proc(t: ^testing.T) {
	g := bitmap_make(8, 8)
	bitmap_set(&g, 6, 6, true)
	testing.expect(t, bitmap_resize(&g, 4, 4))
	testing.expect(t, !bitmap_get(&g, 6, 6)) // outside the visible region
	testing.expect(t, bitmap_resize(&g, 8, 8))
	testing.expect(t, bitmap_get(&g, 6, 6)) // restored
	testing.expect(t, !bitmap_resize(&g, 8, 8)) // unchanged
	testing.expect(t, bitmap_resize(&g, 500, -3))
	testing.expect_value(t, g.width, BITMAP_MAX)
	testing.expect_value(t, g.height, BITMAP_MIN)
}

@(test)
test_bitmap_json_round_trip :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	g := bitmap_make(5, 3)
	bitmap_set(&g, 0, 0, true)
	bitmap_set(&g, 4, 2, true)
	bitmap_set(&g, 2, 1, true)
	text := bitmap_to_json(&g)
	testing.expect_value(t, text, "{\n  \"width\": 5,\n  \"height\": 3,\n  \"rows\": [\n    \"#....\",\n    \"..#..\",\n    \"....#\"\n  ]\n}\n")
	back, err := bitmap_from_json(transmute([]u8)text)
	testing.expect_value(t, err, "")
	testing.expect(t, back == g)

	// The largest image round-trips too.
	big := bitmap_make(BITMAP_MAX, BITMAP_MAX)
	for i in 0 ..< BITMAP_MAX {
		bitmap_set(&big, i, i, true)
		bitmap_set(&big, BITMAP_MAX - 1 - i, i, true)
	}
	text = bitmap_to_json(&big)
	back, err = bitmap_from_json(transmute([]u8)text)
	testing.expectf(t, err == "" && back == big, "64x64 round trip: %s", err)
}

@(test)
test_bitmap_file_holds_only_the_visible_region :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	g := bitmap_make(8, 8)
	bitmap_set(&g, 7, 7, true)
	bitmap_resize(&g, 2, 2)
	back, err := bitmap_from_json(transmute([]u8)bitmap_to_json(&g))
	testing.expect_value(t, err, "")
	testing.expect(t, back.width == 2 && back.height == 2 && !back.bits[7][7])
}

@(test)
test_bitmap_json_errors :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := [?]struct {
		json, want: string,
	} {
		{"", "not valid JSON"},
		{"[]", "top level"},
		{`{}`, "whole numbers"},
		{`{"width": 2.5, "height": 1, "rows": ["##"]}`, "whole numbers"},
		{`{"width": 0, "height": 1, "rows": [""]}`, "out of range"},
		{`{"width": 65, "height": 1, "rows": []}`, "out of range"},
		{`{"width": 2, "height": 2}`, `"rows"`},
		{`{"width": 2, "height": 2, "rows": ["##"]}`, "1 entries"},
		{`{"width": 2, "height": 1, "rows": ["###"]}`, "3 characters"},
		{`{"width": 2, "height": 1, "rows": [5]}`, "not a string"},
		{`{"width": 2, "height": 1, "rows": ["#x"]}`, `only "#" and "."`},
	}
	for c in cases {
		_, err := bitmap_from_json(transmute([]u8)c.json)
		testing.expectf(t, strings.contains(err, c.want), "input %q: error %q should contain %q", c.json, err, c.want)
	}
	// Extra fields are ignored.
	_, err := bitmap_from_json(transmute([]u8)string(`{"name": "A", "width": 1, "height": 1, "rows": ["#"]}`))
	testing.expect_value(t, err, "")
}
