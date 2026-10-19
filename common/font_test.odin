#+build !js
package common

import "core:testing"

Drawn_Rect :: struct {
	x, y, w, h: int,
}

Recorder :: struct {
	rects:    [dynamic]Drawn_Rect,
	cleared:  int,
	presents: int,
}

recorder_renderer :: proc(rec: ^Recorder) -> Renderer {
	return Renderer {
		data = rec,
		clear = proc(data: rawptr, c: Color) {(^Recorder)(data).cleared += 1},
		fill_rect = proc(data: rawptr, x, y, w, h: int, c: Color) {
			append(&(^Recorder)(data).rects, Drawn_Rect{x, y, w, h})
		},
		present = proc(data: rawptr) {(^Recorder)(data).presents += 1},
	}
}

@(test)
test_text_width :: proc(t: ^testing.T) {
	testing.expect_value(t, text_width(""), 0)
	testing.expect_value(t, text_width("A"), 3)
	testing.expect_value(t, text_width("AB"), 7)
	testing.expect_value(t, text_width("AB", 2), 14)
}

@(test)
test_lowercase_maps_to_uppercase :: proc(t: ^testing.T) {
	testing.expect(t, glyph_for('q') == glyph_for('Q'))
	testing.expect(t, glyph_for('~') == Glyph{0b111, 0b101, 0b101, 0b101, 0b111})
}

@(test)
test_draw_text_merges_runs :: proc(t: ^testing.T) {
	rec: Recorder
	defer delete(rec.rects)
	r := recorder_renderer(&rec)
	// '-' is a single 3-wide row at y offset 2.
	draw_text(&r, 10, 20, "-", {255, 255, 255}, 2)
	testing.expect_value(t, len(rec.rects), 1)
	testing.expect(t, rec.rects[0] == Drawn_Rect{10, 24, 6, 2})
}

@(test)
test_draw_text_advances_per_glyph :: proc(t: ^testing.T) {
	rec: Recorder
	defer delete(rec.rects)
	r := recorder_renderer(&rec)
	draw_text(&r, 0, 0, "..", {1, 2, 3})
	// '.' is a single pixel at column 1, row 4; the second glyph is shifted by GLYPH_ADVANCE.
	testing.expect_value(t, len(rec.rects), 2)
	testing.expect(t, rec.rects[0] == Drawn_Rect{1, 4, 1, 1})
	testing.expect(t, rec.rects[1] == Drawn_Rect{1 + GLYPH_ADVANCE, 4, 1, 1})
}

@(test)
test_fill_rect_ignores_empty :: proc(t: ^testing.T) {
	rec: Recorder
	defer delete(rec.rects)
	r := recorder_renderer(&rec)
	renderer_fill_rect(&r, 0, 0, 0, 5, {})
	renderer_fill_rect(&r, 0, 0, 5, -1, {})
	testing.expect_value(t, len(rec.rects), 0)
}

@(test)
test_font_has_and_drawable :: proc(t: ^testing.T) {
	testing.expect(t, font_has('A') && font_has('z') && font_has('7') && font_has(',') && font_has('+'))
	testing.expect(t, !font_has(';') && !font_has('~') && !font_has('@'))
	testing.expect(t, text_is_drawable("UP/DOWN: SAVE / LOAD (RIGHT = BG)"))
	testing.expect(t, !text_is_drawable("A; B"))
	testing.expect(t, text_is_drawable(""))
}

@(test)
test_font_has_agrees_with_glyph_for :: proc(t: ^testing.T) {
	for c in 0 ..< 256 {
		ch := rune(c)
		// A character is missing exactly when it draws as the fallback box; '0' is the one real
		// glyph that happens to look the same.
		looks_like_fallback := glyph_for(ch) == FALLBACK_GLYPH && ch != '0'
		testing.expectf(t, font_has(ch) == !looks_like_fallback, "font_has(%d) disagrees with glyph_for", c)
	}
	testing.expect(t, font_has('0') && text_is_drawable("CLIP: 10 0"))
}
