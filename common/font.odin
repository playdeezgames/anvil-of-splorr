package common

import "base:intrinsics"

// The editors' own text is drawn with the user's hand-drawn font, default-font.json, compiled into
// the program (`#load`) and parsed the first time text is measured or drawn. Edit that file in the
// font editor, rebuild, and every tool's text changes.
//
// The font is a pure cell grid: every glyph's blank bottom row and blank right column are part of
// the glyph, so nothing adds spacing. Text advances by each glyph's width, lines by the font's
// height (GLYPH_H, also the line pitch), and text_width is the sum of the cell widths. Layout code
// relies on GLYPH_H; a test fails if the file's height stops matching it.

DEFAULT_FONT_SOURCE :: #load("../default-font.json")

GLYPH_H :: 6
LINE_ADVANCE :: GLYPH_H

// A character the font has no glyph for is drawn as a solid block this wide, so the gap is visible.
MISSING_GLYPH_W :: 3
MISSING_GLYPH_H :: 5
MISSING_ADVANCE :: 4

@(private = "file")
ui_store: Pixel_Font // about 1 MB, filled once by ui_font()
@(private = "file")
ui_state: u32 // 0 = not loaded, 1 = loading, 2 = ready
@(private = "file")
ui_error_buf: [160]u8
@(private = "file")
ui_error_len: int

// The UI font, loading it on first use. Safe to call from several threads (the tests do).
ui_font :: proc() -> ^Pixel_Font {
	if intrinsics.atomic_load_explicit(&ui_state, .Acquire) == 2 {
		return &ui_store
	}
	if _, won := intrinsics.atomic_compare_exchange_strong(&ui_state, 0, 1); won {
		if err := pixel_font_from_json(DEFAULT_FONT_SOURCE, &ui_store); err != "" {
			pixel_font_reset(&ui_store, GLYPH_H) // no glyphs: every character shows as the missing block
			ui_error_len = min(len(err), len(ui_error_buf))
			copy(ui_error_buf[:], err[:ui_error_len])
		}
		intrinsics.atomic_store_explicit(&ui_state, 2, .Release)
	} else {
		for intrinsics.atomic_load_explicit(&ui_state, .Acquire) != 2 {
			intrinsics.cpu_relax()
		}
	}
	return &ui_store
}

// Why default-font.json could not be loaded, or "" if it loaded fine.
ui_font_error :: proc() -> string {
	ui_font()
	return string(ui_error_buf[:ui_error_len])
}

// True if the UI font has a glyph for ch (a character code 0..255).
font_has :: proc(ch: rune) -> bool {
	return ch >= 0 && ch < PIXEL_FONT_CHARS && ui_font().present[ch]
}

// True if every character of s is in the UI font. Text strings in the tools should pass this.
text_is_drawable :: proc(s: string) -> bool {
	f := ui_font()
	for i in 0 ..< len(s) {
		if !f.present[s[i]] {
			return false
		}
	}
	return true
}

// Width in pixels of s at the given integer scale: the sum of the glyph cell widths, including the
// blank column each glyph carries on its right (0 for the empty string).
text_width :: proc(s: string, scale := 1) -> int {
	if len(s) == 0 {
		return 0
	}
	f := ui_font()
	w := 0
	for i in 0 ..< len(s) {
		code := s[i]
		w += f.present[code] ? f.glyphs[code].width : MISSING_ADVANCE
	}
	return w * scale
}

// Draws s with its top-left at (x, y). Horizontal runs of lit pixels become one fill_rect.
draw_text :: proc(r: ^Renderer, x, y: int, s: string, c: Color, scale := 1) {
	f := ui_font()
	cx := x
	for i in 0 ..< len(s) {
		code := s[i]
		if !f.present[code] {
			renderer_fill_rect(r, cx, y, MISSING_GLYPH_W * scale, MISSING_GLYPH_H * scale, c)
			cx += MISSING_ADVANCE * scale
			continue
		}
		g := &f.glyphs[code]
		for gy in 0 ..< g.height {
			run_start := -1
			for gx in 0 ..= g.width {
				lit := gx < g.width && g.bits[gy][gx]
				if lit && run_start < 0 {
					run_start = gx
				} else if !lit && run_start >= 0 {
					renderer_fill_rect(r, cx + run_start * scale, y + gy * scale, (gx - run_start) * scale, scale, c)
					run_start = -1
				}
			}
		}
		cx += g.width * scale
	}
}
