#+build !js
package common

import "core:strings"
import "core:testing"

@(test)
test_image4_make_get_set :: proc(t: ^testing.T) {
	img := image4_make(0, 1000)
	testing.expect(t, img.width == IMAGE_MIN && img.height == IMAGE_MAX)
	img = image4_make(4, 3)
	testing.expect(t, image4_set(&img, 3, 2, 9))
	testing.expect_value(t, image4_get(&img, 3, 2), 9)
	testing.expect(t, !image4_set(&img, 3, 2, 9)) // same colour: no change
	testing.expect(t, image4_set(&img, 3, 2, 100)) // clamped to 15
	testing.expect_value(t, image4_get(&img, 3, 2), 15)
	testing.expect(t, !image4_set(&img, 0, 0, -4)) // clamped to 0, which it already is: no change
	testing.expect(t, image4_set(&img, 3, 2, -4)) // clamped to 0, and that is a change from 15
	testing.expect_value(t, image4_get(&img, 3, 2), 0)
	testing.expect(t, !image4_set(&img, 4, 0, 1) && !image4_set(&img, 0, 3, 1) && !image4_set(&img, -1, 0, 1)) // out of range
	testing.expect_value(t, image4_get(&img, 4, 0), 0)
	testing.expect_value(t, image4_get(&img, -1, 0), 0)
}

@(test)
test_image4_resize_keeps_hidden_pixels :: proc(t: ^testing.T) {
	img := image4_make(8, 8)
	image4_set(&img, 6, 6, 11)
	testing.expect(t, image4_resize(&img, 4, 4))
	testing.expect_value(t, image4_get(&img, 6, 6), 0) // hidden
	testing.expect(t, image4_resize(&img, 8, 8))
	testing.expect_value(t, image4_get(&img, 6, 6), 11) // restored
	testing.expect(t, !image4_resize(&img, 8, 8))
	testing.expect(t, image4_resize(&img, 500, -3) && img.width == IMAGE_MAX && img.height == IMAGE_MIN)
}

@(test)
test_image4_pack_layout :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for pair in ([][2]int{{1, 1}, {2, 1}, {3, 2}, {4, 2}, {5, 3}, {63, 32}, {64, 32}}) {
		testing.expect_value(t, image4_row_bytes(pair[0]), pair[1])
		testing.expect_value(t, image4_packed_size(pair[0], 5), pair[1] * 5)
	}
	// Even width: two pixels per byte, the left pixel in the high nibble.
	img := image4_make(4, 1)
	for c, x in ([]int{1, 2, 15, 0}) {
		image4_set(&img, x, 0, c)
	}
	packed := image4_pack(&img)
	testing.expect(t, len(packed) == 2 && packed[0] == 0x12 && packed[1] == 0xF0)
	// Odd width: the last pixel is a high nibble, the low nibble is padding (0).
	odd := image4_make(3, 2)
	for c, x in ([]int{0xA, 0xB, 0xC}) {
		image4_set(&odd, x, 0, c)
		image4_set(&odd, x, 1, 15 - c)
	}
	packed = image4_pack(&odd)
	testing.expect(t, len(packed) == 4)
	testing.expect(t, packed[0] == 0xAB && packed[1] == 0xC0) // row 0: A B | C pad
	testing.expect(t, packed[2] == 0x54 && packed[3] == 0x30) // row 1: 5 4 | 3 pad
}

@(test)
test_image4_unpack_round_trips_and_ignores_padding :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for w in ([]int{1, 2, 3, 8, 9, 31, 64}) {
		for h in ([]int{1, 2, 7}) {
			img := image4_make(w, h)
			for y in 0 ..< h {
				for x in 0 ..< w {
					image4_set(&img, x, y, (x * 5 + y * 3) % 16)
				}
			}
			back := image4_make(w, h)
			back.pixels[0][0] = 7 // unpack replaces what was there
			testing.expect(t, image4_unpack(&back, image4_pack(&img)))
			testing.expectf(t, image4_visible_equal(&img, &back), "%dx%d did not round trip", w, h)
		}
	}
	// A set padding nibble (the low half of a 1 wide row) is ignored.
	img := image4_make(1, 1)
	testing.expect(t, image4_unpack(&img, []u8{0x9F}))
	testing.expect_value(t, img.pixels[0][0], 9)
	testing.expect_value(t, img.pixels[0][1], 0) // nothing leaks beyond the visible width
	// A wrong length changes nothing.
	testing.expect(t, !image4_unpack(&img, []u8{1, 2}) && !image4_unpack(&img, nil))
	testing.expect_value(t, img.pixels[0][0], 9)
}

@(test)
test_image4_json_round_trip_and_exact_text :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	img := image4_make(3, 2)
	for c, x in ([]int{1, 2, 3}) {
		image4_set(&img, x, 0, c)
	}
	image4_set(&img, 2, 1, 15)
	text := image4_to_json(&img)
	// Row 0: pixels 1 2 | 3 -> 0x12 = 18, 0x30 = 48.  Row 1: 0 0 | 15 -> 0x00 = 0, 0xF0 = 240.
	testing.expect_value(t, text, "{\n  \"width\": 3,\n  \"height\": 2,\n  \"bytes\": [\n    18, 48,\n    0, 240\n  ]\n}\n")
	back, err := image4_from_json(transmute([]u8)text)
	testing.expect_value(t, err, "")
	testing.expect(t, back == img)

	big := image4_make(IMAGE_MAX, IMAGE_MAX)
	for y in 0 ..< IMAGE_MAX {
		for x in 0 ..< IMAGE_MAX {
			image4_set(&big, x, y, (x + y) % 16)
		}
	}
	text = image4_to_json(&big)
	back, err = image4_from_json(transmute([]u8)text)
	testing.expectf(t, err == "" && back == big, "64x64 round trip: %s", err)
}

@(test)
test_image4_file_holds_only_the_visible_region :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	img := image4_make(8, 8)
	image4_set(&img, 7, 7, 5)
	image4_resize(&img, 2, 2)
	back, err := image4_from_json(transmute([]u8)image4_to_json(&img))
	testing.expect_value(t, err, "")
	testing.expect(t, back.width == 2 && back.height == 2 && back.pixels[7][7] == 0)
}

@(test)
test_image4_json_errors :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := [?]struct {
		json, want: string,
	} {
		{"", "not valid JSON"},
		{"[]", "top level"},
		{`{}`, "whole numbers"},
		{`{"width": 2.5, "height": 1, "bytes": [0]}`, "whole numbers"},
		{`{"width": 0, "height": 1, "bytes": []}`, "out of range"},
		{`{"width": 65, "height": 1, "bytes": []}`, "out of range"},
		{`{"width": 2, "height": 2}`, `needs "bytes"`},
		{`{"width": 2, "height": 2, "bytes": [0]}`, "1 entries but a 2 x 2 image needs 2 (1 per row)"},
		{`{"width": 3, "height": 2, "bytes": [0, 0]}`, "2 entries but a 3 x 2 image needs 4 (2 per row)"}, // odd width pads to 2 bytes
		{`{"width": 2, "height": 1, "bytes": [1, 2]}`, "2 entries but a 2 x 1 image needs 1"},
		{`{"width": 2, "height": 1, "bytes": [256]}`, "entry 0 is not a whole number from 0 to 255"},
		{`{"width": 2, "height": 1, "bytes": [-1]}`, "entry 0 is not a whole number"},
		{`{"width": 2, "height": 1, "bytes": [1.5]}`, "entry 0 is not a whole number"},
		{`{"width": 2, "height": 1, "bytes": ["18"]}`, "entry 0 is not a whole number"},
		{`{"width": 2, "height": 1, "bytes": 18}`, `needs "bytes"`},
	}
	for c in cases {
		_, err := image4_from_json(transmute([]u8)c.json)
		testing.expectf(t, strings.contains(err, c.want), "input %q: error %q should contain %q", c.json, err, c.want)
	}
	_, err := image4_from_json(transmute([]u8)string(`{"name": "x", "width": 2, "height": 1, "bytes": [18]}`))
	testing.expect_value(t, err, "") // extra fields are ignored
}

@(test)
test_image4_flips :: proc(t: ^testing.T) {
	for size in ([][2]int{{1, 1}, {2, 3}, {3, 2}, {5, 5}, {8, 4}, {9, 9}, {64, 64}}) {
		w, h := size[0], size[1]
		img := image4_make(w, h)
		for y in 0 ..< h {
			for x in 0 ..< w {
				image4_set(&img, x, y, (x * 3 + y * 7) % 16)
			}
		}
		orig := img
		image4_flip_horizontal(&img)
		for y in 0 ..< h {
			for x in 0 ..< w {
				testing.expectf(t, img.pixels[y][w - 1 - x] == orig.pixels[y][x], "%dx%d horizontal (%d,%d)", w, h, x, y)
			}
		}
		image4_flip_horizontal(&img)
		testing.expectf(t, image4_visible_equal(&img, &orig), "%dx%d: two horizontal flips must restore", w, h)
		image4_flip_vertical(&img)
		for y in 0 ..< h {
			for x in 0 ..< w {
				testing.expectf(t, img.pixels[h - 1 - y][x] == orig.pixels[y][x], "%dx%d vertical (%d,%d)", w, h, x, y)
			}
		}
		image4_flip_vertical(&img)
		testing.expectf(t, image4_visible_equal(&img, &orig), "%dx%d: two vertical flips must restore", w, h)
	}
}

@(test)
test_image4_flip_reports_changes_and_keeps_hidden_pixels :: proc(t: ^testing.T) {
	img := image4_make(4, 4)
	testing.expect(t, !image4_flip_horizontal(&img) && !image4_flip_vertical(&img)) // all colour 0
	image4_set(&img, 0, 0, 7)
	testing.expect(t, image4_flip_horizontal(&img) && img.pixels[0][3] == 7)
	testing.expect(t, image4_flip_vertical(&img) && img.pixels[3][3] == 7)
	image4_set(&img, 0, 3, 7)
	testing.expect(t, !image4_flip_horizontal(&img)) // row 3 is now symmetric
	// Two different colours are not "symmetric".
	image4_set(&img, 0, 3, 8)
	testing.expect(t, image4_flip_horizontal(&img) && img.pixels[3][0] == 7 && img.pixels[3][3] == 8)
	// Hidden pixels stay put.
	big := image4_make(8, 8)
	big.pixels[0][20] = 5
	image4_resize(&big, 4, 4)
	image4_set(&big, 0, 0, 1)
	image4_flip_horizontal(&big)
	image4_flip_vertical(&big)
	testing.expect_value(t, big.pixels[0][20], 5)
	testing.expect(t, big.pixels[3][3] == 1 && big.pixels[0][0] == 0)
}

@(test)
test_image4_clear :: proc(t: ^testing.T) {
	img := sample_image(5, 4)
	img.pixels[9][9] = 3 // hidden
	testing.expect(t, image4_clear(&img, 7))
	for y in 0 ..< 4 {
		for x in 0 ..< 5 {
			testing.expect_value(t, img.pixels[y][x], 7)
		}
	}
	testing.expect_value(t, img.pixels[9][9], 3) // hidden pixels untouched
	testing.expect(t, !image4_clear(&img, 7)) // already that colour
	testing.expect(t, image4_clear(&img, 99) && img.pixels[0][0] == 15) // clamped
	testing.expect(t, image4_clear(&img, -3) && img.pixels[3][4] == 0)
}

@(test)
test_image4_replace_color :: proc(t: ^testing.T) {
	img := image4_make(4, 3)
	for y in 0 ..< 3 {
		for x in 0 ..< 4 {
			image4_set(&img, x, y, (x + y) % 3) // colours 0, 1, 2
		}
	}
	img.pixels[8][8] = 1 // hidden: must not change
	before := img
	testing.expect(t, image4_replace_color(&img, 1, 9))
	for y in 0 ..< 3 {
		for x in 0 ..< 4 {
			want: u8 = before.pixels[y][x] == 1 ? 9 : before.pixels[y][x]
			testing.expectf(t, img.pixels[y][x] == want, "(%d,%d)", x, y)
		}
	}
	testing.expect_value(t, img.pixels[8][8], 1)
	testing.expect(t, !image4_replace_color(&img, 1, 5)) // no pixel of that colour left
	testing.expect(t, !image4_replace_color(&img, 9, 9)) // same colour: nothing to do
	testing.expect(t, image4_replace_color(&img, 2, 0) && img.pixels[0][2] == 0)
}

@(test)
test_image4_flood_fill :: proc(t: ^testing.T) {
	// 5 x 5, a ring of colour 1 around a centre of colour 0, and a stray 0 pixel outside the ring.
	img := image4_make(5, 5)
	for i in 0 ..< 5 {
		image4_set(&img, i, 0, 1)
		image4_set(&img, i, 4, 1)
		image4_set(&img, 0, i, 1)
		image4_set(&img, 4, i, 1)
	}
	testing.expect(t, image4_flood_fill(&img, 2, 2, 5)) // the inside
	for y in 1 ..= 3 {
		for x in 1 ..= 3 {
			testing.expect_value(t, img.pixels[y][x], 5)
		}
	}
	testing.expect_value(t, img.pixels[0][0], 1) // the ring is untouched
	testing.expect(t, !image4_flood_fill(&img, 2, 2, 5)) // already that colour
	testing.expect(t, image4_flood_fill(&img, 0, 0, 8)) // the whole ring (it is one connected region)
	testing.expect(t, img.pixels[0][4] == 8 && img.pixels[4][0] == 8 && img.pixels[2][2] == 5)
	testing.expect(t, !image4_flood_fill(&img, -1, 0, 3) && !image4_flood_fill(&img, 0, 9, 3))
}

@(test)
test_image4_flood_fill_does_not_cross_diagonals :: proc(t: ^testing.T) {
	img := image4_make(3, 3) // all 0
	image4_set(&img, 1, 0, 1)
	image4_set(&img, 0, 1, 1)
	image4_set(&img, 2, 1, 1)
	image4_set(&img, 1, 2, 1) // a diamond of 1s around the centre
	testing.expect(t, image4_flood_fill(&img, 1, 1, 7)) // the centre is only diagonally next to the corners
	testing.expect(t, img.pixels[1][1] == 7)
	testing.expect(t, img.pixels[0][0] == 0 && img.pixels[0][2] == 0 && img.pixels[2][0] == 0 && img.pixels[2][2] == 0)
}

@(test)
test_image4_flood_fill_handles_the_largest_image_and_a_snake :: proc(t: ^testing.T) {
	img := image4_make(IMAGE_MAX, IMAGE_MAX)
	testing.expect(t, image4_flood_fill(&img, 0, 0, 3)) // 4096 pixels in one region
	for y in 0 ..< IMAGE_MAX {
		for x in 0 ..< IMAGE_MAX {
			if img.pixels[y][x] != 3 {
				testing.expectf(t, false, "(%d,%d) was missed", x, y)
				return
			}
		}
	}
	// A winding one pixel wide corridor (walls of colour 1): the fill follows it all the way.
	snake := image4_make(IMAGE_MAX, IMAGE_MAX)
	for y in 0 ..< IMAGE_MAX {
		for x in 0 ..< IMAGE_MAX {
			image4_set(&snake, x, y, y % 2 == 1 ? 1 : 0) // alternate rows are walls
		}
	}
	for y in 1 ..< IMAGE_MAX {
		if y % 2 == 1 { 	// a gap in each wall, alternating ends, joins the corridors
			image4_set(&snake, (y / 2) % 2 == 0 ? IMAGE_MAX - 1 : 0, y, 0)
		}
	}
	testing.expect(t, image4_flood_fill(&snake, 0, 0, 9))
	testing.expect(t, snake.pixels[IMAGE_MAX - 2][IMAGE_MAX - 1] == 9 || snake.pixels[IMAGE_MAX - 2][0] == 9) // reached the far end
	testing.expect(t, snake.pixels[1][1] == 1) // walls stay
}
