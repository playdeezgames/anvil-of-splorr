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
	// 5 wide: one byte per row, leftmost pixel in the top bit: #.... = 10000000b = 128,
	// ..#.. = 00100000b = 32, ....# = 00001000b = 8.
	testing.expect_value(t, text, "{\n  \"width\": 5,\n  \"height\": 3,\n  \"bytes\": [\n    128,\n    32,\n    8\n  ]\n}\n")
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
		{`{"width": 2.5, "height": 1, "bytes": [192]}`, "whole numbers"},
		{`{"width": 0, "height": 1, "bytes": []}`, "out of range"},
		{`{"width": 65, "height": 1, "bytes": []}`, "out of range"},
		{`{"width": 2, "height": 2}`, `needs "bytes"`},
		{`{"width": 2, "height": 2, "bytes": [192]}`, "1 entries but a 2 x 2 image needs 2 (1 per row)"},
		{`{"width": 9, "height": 2, "bytes": [255, 128]}`, "2 entries but a 9 x 2 image needs 4 (2 per row)"}, // 9 wide: 2 bytes per row
		{`{"width": 2, "height": 1, "bytes": [192, 0]}`, "2 entries but a 2 x 1 image needs 1"},
		{`{"width": 2, "height": 1, "bytes": [256]}`, "entry 0 is not a whole number from 0 to 255"},
		{`{"width": 2, "height": 1, "bytes": [-1]}`, "entry 0 is not a whole number"},
		{`{"width": 2, "height": 1, "bytes": [1.5]}`, "entry 0 is not a whole number"},
		{`{"width": 2, "height": 1, "bytes": ["192"]}`, "entry 0 is not a whole number"},
		{`{"width": 2, "height": 1, "bytes": 5}`, `"bytes" must be a list`},
	}
	for c in cases {
		_, err := bitmap_from_json(transmute([]u8)c.json)
		testing.expectf(t, strings.contains(err, c.want), "input %q: error %q should contain %q", c.json, err, c.want)
	}
	// Extra fields are ignored.
	_, err := bitmap_from_json(transmute([]u8)string(`{"name": "A", "width": 1, "height": 1, "bytes": [128]}`))
	testing.expect_value(t, err, "")
}

@(test)
test_bitmap_pack_layout :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Widths and the bytes per row they need.
	for pair in ([][2]int{{1, 1}, {7, 1}, {8, 1}, {9, 2}, {16, 2}, {17, 3}, {63, 8}, {64, 8}}) {
		testing.expect_value(t, bitmap_row_bytes(pair[0]), pair[1])
		testing.expect_value(t, bitmap_packed_size(pair[0], 3), pair[1] * 3)
	}
	g := bitmap_make(10, 2)
	for x in 0 ..< 10 {
		bitmap_set(&g, x, 0, true) // a full row
	}
	bitmap_set(&g, 0, 1, true) // only the leftmost pixel
	bitmap_set(&g, 9, 1, true) // and the rightmost
	packed := bitmap_pack(&g)
	// Row 0: 11111111 11000000; row 1: 10000000 01000000. The padding bits are zero.
	testing.expect(t, len(packed) == 4 && packed[0] == 255 && packed[1] == 0b11000000 && packed[2] == 0b10000000 && packed[3] == 0b01000000)
	// The other widths' edge pixels.
	for w in ([]int{1, 7, 8, 9, 15, 16, 17, 33, 64}) {
		g8 := bitmap_make(w, 1)
		bitmap_set(&g8, w - 1, 0, true) // the last pixel
		p := bitmap_pack(&g8)
		bit := w - 1
		testing.expectf(t, p[bit / 8] == 0x80 >> uint(bit % 8), "width %d: last pixel in the wrong bit", w)
		for i in 0 ..< len(p) {
			if i != bit / 8 {
				testing.expect(t, p[i] == 0)
			}
		}
	}
}

@(test)
test_bitmap_unpack_round_trips_and_ignores_padding :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for w in ([]int{1, 3, 8, 9, 16, 21, 64}) {
		for h in ([]int{1, 2, 13}) {
			g := bitmap_make(w, h)
			for y in 0 ..< h {
				for x in 0 ..< w {
					bitmap_set(&g, x, y, (x * 7 + y * 3) % 5 < 2)
				}
			}
			back := bitmap_make(w, h)
			back.bits[0][0] = true // unpack replaces the old pixels
			testing.expect(t, bitmap_unpack(&back, bitmap_pack(&g)))
			testing.expectf(t, bitmap_visible_equal(&g, &back), "%dx%d did not round trip", w, h)
		}
	}
	// Set padding bits (here the low 6 bits of a 2 wide image) are ignored.
	g := bitmap_make(2, 1)
	testing.expect(t, bitmap_unpack(&g, []u8{0xFF}))
	testing.expect(t, g.bits[0][0] && g.bits[0][1])
	testing.expect(t, !g.bits[0][2]) // nothing leaks outside the visible width
	// A wrong length changes nothing.
	g.bits[0][0] = false
	testing.expect(t, !bitmap_unpack(&g, []u8{1, 2}) && !bitmap_unpack(&g, nil))
	testing.expect(t, !g.bits[0][0])
}

@(test)
test_bitmap_file_examples_from_the_format_comment :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	g, err := bitmap_from_json(transmute([]u8)string(`{ "width": 3, "height": 2, "bytes": [ 160, 64 ] }`))
	testing.expect_value(t, err, "")
	testing.expect(t, g.bits[0][0] && !g.bits[0][1] && g.bits[0][2] && !g.bits[1][0] && g.bits[1][1] && !g.bits[1][2])
	g, err = bitmap_from_json(transmute([]u8)string(`{ "width": 10, "height": 1, "bytes": [ 255, 192 ] }`))
	testing.expect_value(t, err, "")
	for x in 0 ..< 10 {
		testing.expect(t, g.bits[0][x])
	}
	text := bitmap_to_json(&g)
	testing.expect(t, strings.contains(text, "255, 192"))
	testing.expect(t, !strings.contains(text, "\"rows\"") && !strings.contains(text, "#"))
}

@(test)
test_bitmap_old_rows_files_still_load :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	g, err := bitmap_from_json(transmute([]u8)string(`{"width": 5, "height": 3, "rows": ["#....", "..#..", "....#"]}`))
	testing.expect_value(t, err, "")
	new_form, _ := bitmap_from_json(transmute([]u8)string(`{"width": 5, "height": 3, "bytes": [128, 32, 8]}`))
	testing.expect(t, bitmap_visible_equal(&g, &new_form))
	// It is written back in the new form.
	testing.expect(t, strings.contains(bitmap_to_json(&g), `"bytes"`))
	// The old format's own errors are still reported.
	for c in ([]struct {
			json, want: string,
		}{
			{`{"width": 2, "height": 2, "rows": ["##"]}`, "1 entries"},
			{`{"width": 2, "height": 1, "rows": ["###"]}`, "3 characters"},
			{`{"width": 2, "height": 1, "rows": [5]}`, "not a string"},
			{`{"width": 2, "height": 1, "rows": ["#x"]}`, `only "#" and "."`},
		}) {
		_, e := bitmap_from_json(transmute([]u8)c.json)
		testing.expectf(t, strings.contains(e, c.want), "input %q: error %q should contain %q", c.json, e, c.want)
	}
	// "bytes" wins if a file somehow has both.
	both, e2 := bitmap_from_json(transmute([]u8)string(`{"width": 1, "height": 1, "bytes": [128], "rows": ["."]}`))
	testing.expect(t, e2 == "" && both.bits[0][0])
}
