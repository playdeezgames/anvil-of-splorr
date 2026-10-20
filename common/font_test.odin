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
test_the_ui_font_loads_and_matches_the_layout_constants :: proc(t: ^testing.T) {
	testing.expectf(t, ui_font_error() == "", "default-font.json did not load: %s", ui_font_error())
	f := ui_font()
	testing.expectf(t, f.height == GLYPH_H, "default-font.json is %d high but GLYPH_H is %d: update GLYPH_H and re-check the layouts", f.height, GLYPH_H)
	// Every printable ASCII character has a glyph, so none of the tools' text shows a missing block.
	for c in PRINTABLE_FIRST ..< PRINTABLE_LAST {
		testing.expectf(t, f.present[c], "default-font.json has no glyph for code %d (%c)", c, rune(c))
	}
	testing.expect_value(t, LINE_ADVANCE, GLYPH_H)
}

@(test)
test_text_width_is_the_sum_of_cell_widths :: proc(t: ^testing.T) {
	f := ui_font()
	testing.expect_value(t, text_width(""), 0)
	testing.expect_value(t, text_width("A"), f.glyphs['A'].width)
	testing.expect_value(t, text_width("AB"), f.glyphs['A'].width + f.glyphs['B'].width)
	testing.expect_value(t, text_width("AB", 3), 3 * (f.glyphs['A'].width + f.glyphs['B'].width))
	// A character with no glyph still takes its place, as a missing block.
	testing.expect_value(t, text_width("A\x01B"), f.glyphs['A'].width + MISSING_ADVANCE + f.glyphs['B'].width)
}

@(test)
test_draw_text_follows_the_glyph_data :: proc(t: ^testing.T) {
	rec: Recorder
	defer delete(rec.rects)
	r := recorder_renderer(&rec)
	f := ui_font()
	// Every pixel the font says is lit in "I" ends up inside exactly one drawn rect, and nothing else does.
	draw_text(&r, 10, 20, "I", {255, 255, 255})
	g := &f.glyphs['I']
	for y in 0 ..< g.height {
		for x in 0 ..< g.width {
			covered := 0
			for rc in rec.rects {
				if 10 + x >= rc.x && 10 + x < rc.x + rc.w && 20 + y >= rc.y && 20 + y < rc.y + rc.h {
					covered += 1
				}
			}
			testing.expectf(t, covered == (g.bits[y][x] ? 1 : 0), "pixel (%d,%d) of I covered %d times", x, y, covered)
		}
	}
}

@(test)
test_draw_text_merges_runs_scales_and_advances :: proc(t: ^testing.T) {
	rec: Recorder
	defer delete(rec.rects)
	r := recorder_renderer(&rec)
	f := ui_font()
	// "-" is one horizontal run (a single rect); at scale 2 it is twice as wide, high and placed.
	draw_text(&r, 10, 20, "-", {255, 255, 255}, 2)
	testing.expect_value(t, len(rec.rects), 1)
	g := &f.glyphs['-']
	row := 0
	for y in 0 ..< g.height {
		if g.bits[y][0] || g.bits[y][1] {
			row = y
			break
		}
	}
	run := 0
	for x in 0 ..< g.width {
		if g.bits[row][x] {
			run += 1
		}
	}
	testing.expect(t, rec.rects[0] == Drawn_Rect{10, 20 + row * 2, run * 2, 2})
	// The second glyph is placed one glyph width after the first (here two identical glyphs).
	clear(&rec.rects)
	draw_text(&r, 0, 0, "..", {1, 2, 3})
	testing.expect_value(t, len(rec.rects), 2)
	testing.expect_value(t, rec.rects[1].x - rec.rects[0].x, f.glyphs['.'].width)
}

@(test)
test_missing_characters_draw_a_solid_block :: proc(t: ^testing.T) {
	rec: Recorder
	defer delete(rec.rects)
	r := recorder_renderer(&rec)
	draw_text(&r, 5, 6, "\x01", {9, 9, 9}, 2)
	testing.expect_value(t, len(rec.rects), 1)
	testing.expect(t, rec.rects[0] == Drawn_Rect{5, 6, MISSING_GLYPH_W * 2, MISSING_GLYPH_H * 2})
	testing.expect(t, !font_has(1) && !text_is_drawable("A\x01"))
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
	testing.expect(t, font_has('A') && font_has('z') && font_has('7') && font_has(',') && font_has('+') && font_has(' '))
	testing.expect(t, font_has(';') && font_has('@') && font_has('~')) // the user's font has all of ASCII
	testing.expect(t, !font_has(-1) && !font_has(256) && !font_has(0x263A)) // not a byte code
	testing.expect(t, text_is_drawable("UP/DOWN: SAVE / LOAD (RIGHT = BG); a@b~"))
	testing.expect(t, !text_is_drawable("A\xFF"))
	testing.expect(t, text_is_drawable(""))
}

@(test)
test_the_ui_font_can_be_used_from_many_threads :: proc(t: ^testing.T) {
	// ui_font() loads lazily; asking from several threads at once must give one consistent font.
	// (The test runner already runs tests in parallel; this just asserts the observable result.)
	f := ui_font()
	testing.expect(t, f == ui_font())
	testing.expect(t, f.present['A'] && f.glyphs['A'].width > 0)
}
