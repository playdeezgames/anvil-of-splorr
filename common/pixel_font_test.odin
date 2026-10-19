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
	want := "{\n  \"height\": 2,\n  \"glyphs\": {\n    \"65\": {\n      \"width\": 2,\n      \"rows\": [\n        \"#.\",\n        \"..\"\n      ]\n    },\n    \"66\": {\n      \"width\": 1,\n      \"rows\": [\n        \".\",\n        \"#\"\n      ]\n    }\n  }\n}\n"
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
		{`{"height": 2, "glyphs": {"65": {"rows": ["#","."]}}}`, `glyph 65: "width"`},
		{`{"height": 2, "glyphs": {"65": {"width": 0, "rows": []}}}`, `glyph 65: "width"`},
		{`{"height": 2, "glyphs": {"65": {"width": 1}}}`, `glyph 65: "rows"`},
		{`{"height": 2, "glyphs": {"65": {"width": 1, "rows": ["#"]}}}`, "glyph 65: "}, // one row, height is 2
		{`{"height": 1, "glyphs": {"65": {"width": 2, "rows": ["#"]}}}`, "glyph 65: "}, // row too short
		{`{"height": 1, "glyphs": {"66": {"width": 1, "rows": ["x"]}}}`, `glyph 66: row 0: only "#" and "."`},
	}
	for c in cases {
		err := parse_font(c.json, dst)
		testing.expectf(t, strings.contains(err, c.want), "input %q: error %q should contain %q", c.json, err, c.want)
		testing.expectf(t, dst.height == 6 && dst.present['Z'], "a rejected file changed the font: %q", c.json)
	}
	// A good glyph followed by a bad one still changes nothing.
	err := parse_font(`{"height": 1, "glyphs": {"65": {"width": 1, "rows": ["#"]}, "66": {"width": 1, "rows": ["?"]}}}`, dst)
	testing.expect(t, err != "" && dst.height == 6 && !dst.present['A'])
	// Extra fields are ignored.
	testing.expect_value(t, parse_font(`{"name": "x", "height": 1, "glyphs": {"65": {"note": 1, "width": 1, "rows": ["#"]}}}`, dst), "")
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
