#+build !js
package common

import "core:strings"
import "core:testing"

new_font :: proc(height := DEFAULT_FONT_HEIGHT) -> ^Pixel_Font {
	f := new(Pixel_Font)
	pixel_font_reset(f, height)
	return f
}

parse_font :: proc(text: string, dst: ^Pixel_Font) -> string {
	return pixel_font_from_json(transmute([]u8)text, dst)
}

@(test)
test_new_font_is_empty_with_default_sizes :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	testing.expect_value(t, f.height, DEFAULT_FONT_HEIGHT)
	for c in 0 ..< PIXEL_FONT_CHARS {
		testing.expect(t, !f.present[c])
		testing.expect(t, f.glyphs[c].width == DEFAULT_GLYPH_WIDTH && f.glyphs[c].height == DEFAULT_FONT_HEIGHT)
	}
	defined, total := pixel_font_coverage(f)
	testing.expect(t, defined == 0 && total == 96)
	f2 := new_font(1000) // clamped
	defer free(f2)
	testing.expect_value(t, f2.height, BITMAP_MAX)
}

@(test)
test_all_256_codes_are_addressable :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	for c in 0 ..< PIXEL_FONT_CHARS {
		testing.expect(t, pixel_font_set_present(f, c, true))
		g := pixel_font_glyph(f, c)
		testing.expect(t, g != nil && bitmap_set(g, c % 8, c / 32, true))
	}
	testing.expect(t, pixel_font_glyph(f, -1) == nil && pixel_font_glyph(f, 256) == nil)
	testing.expect(t, !pixel_font_set_present(f, 256, true) && !pixel_font_set_present(f, -1, true))
	testing.expect(t, !pixel_font_set_present(f, 7, true)) // already present: no change
}

@(test)
test_height_is_shared_widths_are_per_glyph :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	testing.expect(t, pixel_font_set_width(f, 'i', 3))
	testing.expect(t, pixel_font_set_width(f, 'W', 12))
	testing.expect(t, f.glyphs['i'].width == 3 && f.glyphs['W'].width == 12 && f.glyphs['a'].width == 8)
	testing.expect(t, !pixel_font_set_width(f, 'i', 3)) // unchanged
	testing.expect(t, pixel_font_set_height(f, 10))
	for c in 0 ..< PIXEL_FONT_CHARS {
		testing.expect(t, f.glyphs[c].height == 10)
	}
	testing.expect(t, f.glyphs['i'].width == 3) // widths untouched
	testing.expect(t, !pixel_font_set_height(f, 10))
	testing.expect(t, pixel_font_set_height(f, 0) && f.height == BITMAP_MIN) // clamped
	testing.expect(t, !pixel_font_set_width(f, 300, 4)) // no such code
}

@(test)
test_shrinking_height_keeps_hidden_rows :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	bitmap_set(&f.glyphs['A'], 0, 7, true)
	pixel_font_set_height(f, 4)
	testing.expect(t, !bitmap_get(&f.glyphs['A'], 0, 7))
	pixel_font_set_height(f, 8)
	testing.expect(t, bitmap_get(&f.glyphs['A'], 0, 7))
}

@(test)
test_coverage_counts_only_printable_range :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	for c in 0 ..< 256 {
		pixel_font_set_present(f, c, c < 32 || c > 127) // everything except the printable range
	}
	defined, total := pixel_font_coverage(f)
	testing.expect(t, defined == 0 && total == 96)
	pixel_font_set_present(f, 32, true)
	pixel_font_set_present(f, 127, true)
	pixel_font_set_present(f, 'A', true)
	defined, _ = pixel_font_coverage(f)
	testing.expect_value(t, defined, 3)
}

@(test)
test_text_width_uses_each_glyphs_own_width :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	pixel_font_set_present(f, 'i', true)
	pixel_font_set_present(f, 'W', true)
	pixel_font_set_width(f, 'i', 3)
	pixel_font_set_width(f, 'W', 11)
	testing.expect_value(t, pixel_font_text_width(f, "iWi"), 17)
	testing.expect_value(t, pixel_font_text_width(f, "i?W"), 14) // '?' has no glyph: no space
	testing.expect_value(t, pixel_font_text_width(f, ""), 0)
	pixel_font_set_present(f, 200, true)
	testing.expect_value(t, pixel_font_text_width(f, "\xC8"), 8) // codes above 127 count
}

@(test)
test_font_json_round_trip :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	f := new_font(5)
	defer free(f)
	pixel_font_set_present(f, 'A', true)
	pixel_font_set_width(f, 'A', 3)
	bitmap_set(&f.glyphs['A'], 1, 0, true)
	bitmap_set(&f.glyphs['A'], 0, 4, true)
	pixel_font_set_present(f, 0, true) // code 0 and 255 are valid too
	pixel_font_set_present(f, 255, true)
	pixel_font_set_width(f, 255, 20)
	bitmap_set(&f.glyphs[255], 19, 4, true)

	text := pixel_font_to_json(f)
	back := new(Pixel_Font)
	defer free(back)
	err := parse_font(text, back)
	testing.expectf(t, err == "", "round trip: %s", err)
	testing.expect(t, back.height == 5 && back.present == f.present)
	for c in 0 ..< PIXEL_FONT_CHARS {
		if f.present[c] {
			testing.expectf(t, back.glyphs[c] == f.glyphs[c], "glyph %d differs", c)
		}
	}
	testing.expect(t, strings.contains(text, `"65": {`) && strings.contains(text, `"255": {`))
	// Absent glyphs are not listed.
	testing.expect(t, !strings.contains(text, `"66"`))
}

@(test)
test_empty_font_round_trips :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	f := new_font(9)
	defer free(f)
	text := pixel_font_to_json(f)
	testing.expect_value(t, text, "{\n  \"height\": 9,\n  \"glyphs\": {}\n}\n")
	back := new(Pixel_Font)
	defer free(back)
	testing.expect_value(t, parse_font(text, back), "")
	testing.expect(t, back.height == 9)
	defined, _ := pixel_font_coverage(back)
	testing.expect(t, defined == 0)
	// "glyphs" may also be left out entirely.
	testing.expect_value(t, parse_font(`{"height": 4}`, back), "")
	testing.expect(t, back.height == 4)
}

@(test)
test_font_file_exact_text :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	f := new_font(2)
	defer free(f)
	pixel_font_set_present(f, 'A', true)
	pixel_font_set_width(f, 'A', 2)
	bitmap_set(&f.glyphs['A'], 0, 0, true)
	pixel_font_set_present(f, 'B', true)
	pixel_font_set_width(f, 'B', 1)
	bitmap_set(&f.glyphs['B'], 0, 1, true)
	// A: "#." / ".." = 128, 0.  B: "." / "#" = 0, 128.
	want := "{\n  \"height\": 2,\n  \"glyphs\": {\n    \"65\": {\n      \"width\": 2,\n      \"bytes\": [\n        128,\n        0\n      ]\n    },\n    \"66\": {\n      \"width\": 1,\n      \"bytes\": [\n        0,\n        128\n      ]\n    }\n  }\n}\n"
	testing.expect_value(t, pixel_font_to_json(f), want)
}

@(test)
test_bad_font_files_are_rejected_and_change_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dst := new_font(6)
	defer free(dst)
	pixel_font_set_present(dst, 'Z', true)
	cases := [?]struct {
		json, want: string,
	} {
		{"", "not valid JSON"},
		{"[]", "top level"},
		{`{}`, `"height"`},
		{`{"height": 0}`, `"height"`},
		{`{"height": 65}`, `"height"`},
		{`{"height": 2.5}`, `"height"`},
		{`{"height": 2, "glyphs": []}`, `"glyphs" must be an object`},
		{`{"height": 2, "glyphs": {"abc": {}}}`, "not a character code"},
		{`{"height": 2, "glyphs": {"256": {}}}`, "not a character code"},
		{`{"height": 2, "glyphs": {"-1": {}}}`, "not a character code"},
		{`{"height": 2, "glyphs": {"65": 5}}`, "glyph 65 must be an object"},
		{`{"height": 2, "glyphs": {"65": {"bytes": [128, 0]}}}`, `glyph 65: "width"`},
		{`{"height": 2, "glyphs": {"65": {"width": 0, "bytes": []}}}`, `glyph 65: "width"`},
		{`{"height": 2, "glyphs": {"65": {"width": 1}}}`, `glyph 65: needs "bytes"`},
		{`{"height": 2, "glyphs": {"65": {"width": 1, "bytes": [128]}}}`, "glyph 65: "}, // one byte, height is 2
		{`{"height": 1, "glyphs": {"65": {"width": 9, "bytes": [255]}}}`, "glyph 65: "}, // 9 wide needs 2 bytes
		{`{"height": 1, "glyphs": {"66": {"width": 1, "bytes": [300]}}}`, `glyph 66: "bytes" entry 0`},
	}
	for c in cases {
		err := parse_font(c.json, dst)
		testing.expectf(t, strings.contains(err, c.want), "input %q: error %q should contain %q", c.json, err, c.want)
		testing.expectf(t, dst.height == 6 && dst.present['Z'], "a rejected file changed the font: %q", c.json)
	}
	// A good glyph followed by a bad one still changes nothing.
	err := parse_font(`{"height": 1, "glyphs": {"65": {"width": 1, "bytes": [128]}, "66": {"width": 1, "bytes": [999]}}}`, dst)
	testing.expect(t, err != "" && dst.height == 6 && !dst.present['A'])
	// Extra fields are ignored.
	testing.expect_value(t, parse_font(`{"name": "x", "height": 1, "glyphs": {"65": {"note": 1, "width": 1, "bytes": [128]}}}`, dst), "")
	testing.expect(t, dst.height == 1 && dst.present['A'] && !dst.present['Z'])
}

@(test)
test_largest_font_round_trips :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	f := new_font(BITMAP_MAX)
	defer free(f)
	for c in 0 ..< PIXEL_FONT_CHARS {
		pixel_font_set_present(f, c, true)
		pixel_font_set_width(f, c, BITMAP_MAX)
		bitmap_set(&f.glyphs[c], c % BITMAP_MAX, c % BITMAP_MAX, true)
	}
	text := pixel_font_to_json(f)
	back := new(Pixel_Font)
	defer free(back)
	err := parse_font(text, back)
	testing.expectf(t, err == "", "largest font: %s", err)
	testing.expect(t, back.present == f.present)
	for c in 0 ..< PIXEL_FONT_CHARS {
		testing.expectf(t, back.glyphs[c] == f.glyphs[c], "glyph %d differs", c)
	}
	testing.expectf(t, len(text) < 1_500_000, "worst-case file is %d bytes", len(text)) // fits the web buffers
}

@(test)
test_delete_clears_everything :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	pixel_font_set_present(f, 'A', true)
	pixel_font_set_width(f, 'A', 12)
	bitmap_set(&f.glyphs['A'], 3, 3, true)
	bitmap_set(&f.glyphs['A'], 11, 7, true)
	pixel_font_set_height(f, 4) // pixel (3,3) stays visible, (11,7) row is hidden
	testing.expect(t, pixel_font_delete(f, 'A'))
	testing.expect(t, !f.present['A'] && f.glyphs['A'].width == DEFAULT_GLYPH_WIDTH && f.glyphs['A'].height == 4)
	pixel_font_set_height(f, 8) // growing back finds no hidden pixels either
	for y in 0 ..< 8 {
		for x in 0 ..< 64 {
			testing.expect(t, !f.glyphs['A'].bits[y][x])
		}
	}
	testing.expect(t, !pixel_font_delete(f, 'A')) // nothing left to delete
	testing.expect(t, !pixel_font_delete(f, 300) && !pixel_font_delete(f, -1))
	// Hiding (present = no) is different: it keeps the pixels.
	pixel_font_set_present(f, 'B', true)
	bitmap_set(&f.glyphs['B'], 1, 1, true)
	pixel_font_set_present(f, 'B', false)
	testing.expect(t, f.glyphs['B'].bits[1][1])
}

@(test)
test_copy_and_paste_glyphs :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	clip: Bitmap
	testing.expect(t, !pixel_font_copy_glyph(f, 'A', &clip)) // absent: nothing to copy
	pixel_font_set_present(f, 'A', true)
	pixel_font_set_width(f, 'A', 5)
	bitmap_set(&f.glyphs['A'], 4, 7, true)
	bitmap_set(&f.glyphs['A'], 0, 0, true)
	testing.expect(t, pixel_font_copy_glyph(f, 'A', &clip))
	testing.expect(t, clip.width == 5 && clip.height == 8 && clip.bits[7][4])
	testing.expect(t, !pixel_font_copy_glyph(f, 256, &clip) && !pixel_font_copy_glyph(f, -1, &clip))

	// Pasting creates the target with the same width and pixels, and does not touch the source.
	testing.expect(t, pixel_font_paste_glyph(f, 'B', &clip))
	testing.expect(t, f.present['B'] && f.glyphs['B'].width == 5 && f.glyphs['B'].bits[7][4] && f.glyphs['B'].bits[0][0])
	testing.expect(t, f.present['A'] && f.glyphs['A'].bits[7][4])
	// Pasting again changes nothing; editing the copy leaves the original alone.
	testing.expect(t, !pixel_font_paste_glyph(f, 'B', &clip))
	bitmap_toggle(&f.glyphs['B'], 4, 7)
	testing.expect(t, f.glyphs['A'].bits[7][4] && !f.glyphs['B'].bits[7][4])
	testing.expect(t, pixel_font_paste_glyph(f, 'B', &clip)) // restores: a change
	// Pasting over a different glyph replaces its width too.
	pixel_font_set_present(f, 'C', true)
	pixel_font_set_width(f, 'C', 9)
	testing.expect(t, pixel_font_paste_glyph(f, 'C', &clip) && f.glyphs['C'].width == 5)
	testing.expect(t, !pixel_font_paste_glyph(f, 300, &clip))
}

@(test)
test_paste_fits_the_clipboard_to_the_current_height :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	pixel_font_set_present(f, 'A', true)
	bitmap_set(&f.glyphs['A'], 2, 1, true)
	clip: Bitmap
	pixel_font_copy_glyph(f, 'A', &clip)
	pixel_font_set_height(f, 12) // the font grew after the copy
	testing.expect(t, pixel_font_paste_glyph(f, 'B', &clip))
	testing.expect(t, f.glyphs['B'].height == 12 && f.glyphs['B'].bits[1][2])
	pixel_font_set_height(f, 3) // and shrank
	testing.expect(t, pixel_font_paste_glyph(f, 'C', &clip))
	testing.expect(t, f.glyphs['C'].height == 3 && f.glyphs['C'].bits[1][2])
	for c in 0 ..< PIXEL_FONT_CHARS {
		testing.expect(t, f.glyphs[c].height == f.height)
	}
}

@(test)
test_visible_equal_ignores_hidden_bits :: proc(t: ^testing.T) {
	a, b := bitmap_make(4, 4), bitmap_make(4, 4)
	bitmap_set(&a, 1, 1, true)
	bitmap_set(&b, 1, 1, true)
	testing.expect(t, bitmap_visible_equal(&a, &b))
	a.bits[10][10] = true // outside the visible 4 x 4
	testing.expect(t, bitmap_visible_equal(&a, &b))
	bitmap_set(&b, 2, 2, true)
	testing.expect(t, !bitmap_visible_equal(&a, &b))
	c := bitmap_make(4, 5)
	testing.expect(t, !bitmap_visible_equal(&a, &c)) // different size
}

@(test)
test_wide_glyphs_use_one_extra_byte_per_row :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	f := new_font(2)
	defer free(f)
	pixel_font_set_present(f, 'W', true)
	pixel_font_set_width(f, 'W', 12) // 12 wide: 2 bytes per row, 4 pad bits
	for x in 0 ..< 12 {
		bitmap_set(&f.glyphs['W'], x, 1, true)
	}
	bitmap_set(&f.glyphs['W'], 11, 0, true)
	text := pixel_font_to_json(f)
	testing.expect(t, strings.contains(text, "0, 16,\n        255, 240\n")) // 00000000 00010000 / 11111111 11110000
	back := new(Pixel_Font)
	defer free(back)
	testing.expect_value(t, parse_font(text, back), "")
	testing.expect(t, back.glyphs['W'] == f.glyphs['W'])
}

@(test)
test_old_string_font_files_still_load :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	old := `{"height": 2, "glyphs": {"65": {"width": 2, "rows": ["#.", ".."]}, "66": {"width": 1, "rows": [".", "#"]}}}`
	f := new(Pixel_Font)
	defer free(f)
	testing.expect_value(t, parse_font(old, f), "")
	testing.expect(t, f.present['A'] && f.present['B'] && f.glyphs['A'].bits[0][0] && f.glyphs['B'].bits[1][0])
	text := pixel_font_to_json(f)
	testing.expect(t, strings.contains(text, `"bytes"`) && !strings.contains(text, `"rows"`))
}

@(test)
test_builtin_font_converts_faithfully :: proc(t: ^testing.T) {
	f := new_font()
	defer free(f)
	pixel_font_load_builtin(f)
	testing.expect_value(t, f.height, GLYPH_H)
	count := 0
	for code in 0 ..< PIXEL_FONT_CHARS {
		ch := rune(code)
		testing.expectf(t, f.present[code] == font_has(ch), "code %d presence", code)
		if !f.present[code] {
			continue
		}
		count += 1
		g := &f.glyphs[code]
		testing.expect(t, g.width == GLYPH_ADVANCE && g.height == GLYPH_H)
		rows := glyph_for(ch)
		for y in 0 ..< GLYPH_H {
			for x in 0 ..< GLYPH_W {
				want := (rows[y] >> uint(GLYPH_W - 1 - x)) & 1 == 1
				testing.expectf(t, g.bits[y][x] == want, "code %d pixel (%d,%d)", code, x, y)
			}
			testing.expectf(t, !g.bits[y][GLYPH_W], "code %d: the spacing column must be blank", code) // column 3
		}
	}
	testing.expect_value(t, count, 81) // space, 52 letters, 10 digits, 18 punctuation marks
	testing.expect(t, f.glyphs['a'] == f.glyphs['A']) // lowercase shares the capital shapes
	testing.expect(t, f.glyphs['z'] == f.glyphs['Z'])
	// The packed form of one glyph, as it appears in the file: 'A' is .#. / #.# / ### / #.# / #.#.
	packed := bitmap_pack(&f.glyphs['A'])
	testing.expect(t, len(packed) == 5 && packed[0] == 0x40 && packed[1] == 0xA0 && packed[2] == 0xE0 && packed[3] == 0xA0 && packed[4] == 0xA0)
}

@(test)
test_the_committed_default_font_file_is_a_valid_font :: proc(t: ^testing.T) {
	// default-font.json is hand drawn and the user's to edit, so it only has to be a valid font
	// file (it is no longer generated from the built-in font).
	defer free_all(context.temp_allocator)
	loaded := new(Pixel_Font)
	defer free(loaded)
	err := pixel_font_from_json(#load("../default-font.json"), loaded)
	testing.expectf(t, err == "", "default-font.json is invalid: %s", err)
	if err == "" {
		defined, total := pixel_font_coverage(loaded)
		testing.expectf(t, defined > 0 && total == 96, "default-font.json has no printable glyphs (%d/%d)", defined, total)
		for code in 0 ..< PIXEL_FONT_CHARS {
			testing.expect(t, loaded.glyphs[code].height == loaded.height) // every glyph shares the font's height
		}
	}
}
