#+build !js
package common

import "core:testing"

Rect :: struct {
	x, y, w, h: int,
}

Recorder :: struct {
	rects:    [dynamic]Rect,
	cleared:  int,
	presents: int,
}

recorder_renderer :: proc(rec: ^Recorder) -> Renderer {
	return Renderer {
		data = rec,
		clear = proc(data: rawptr, c: Color) {(^Recorder)(data).cleared += 1},
		fill_rect = proc(data: rawptr, x, y, w, h: int, c: Color) {
			append(&(^Recorder)(data).rects, Rect{x, y, w, h})
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
	testing.expect(t, rec.rects[0] == Rect{10, 24, 6, 2})
}

@(test)
test_draw_text_advances_per_glyph :: proc(t: ^testing.T) {
	rec: Recorder
	defer delete(rec.rects)
	r := recorder_renderer(&rec)
	draw_text(&r, 0, 0, "..", {1, 2, 3})
	// '.' is a single pixel at column 1, row 4; the second glyph is shifted by GLYPH_ADVANCE.
	testing.expect_value(t, len(rec.rects), 2)
	testing.expect(t, rec.rects[0] == Rect{1, 4, 1, 1})
	testing.expect(t, rec.rects[1] == Rect{1 + GLYPH_ADVANCE, 4, 1, 1})
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
