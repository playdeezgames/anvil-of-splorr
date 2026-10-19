package common

// Built-in 3x5 font so no frontend needs font loading. Uppercase only; lowercase maps to
// uppercase and unknown characters draw as a hollow box.

GLYPH_W :: 3
GLYPH_H :: 5
GLYPH_ADVANCE :: GLYPH_W + 1
LINE_ADVANCE :: GLYPH_H + 1

// One byte per row, low 3 bits used, bit 2 is the leftmost pixel.
Glyph :: [GLYPH_H]u8

glyph_for :: proc(ch: rune) -> Glyph {
	switch ch {
	case 'a' ..= 'z':
		return glyph_for(ch - 'a' + 'A')
	case 'A' ..= 'Z':
		return letter_glyphs[ch - 'A']
	case '0' ..= '9':
		return digit_glyphs[ch - '0']
	case ' ':
		return {}
	case '.':
		return {0, 0, 0, 0, 0b010}
	case ':':
		return {0, 0b010, 0, 0b010, 0}
	case '-':
		return {0, 0, 0b111, 0, 0}
	case '+':
		return {0, 0b010, 0b111, 0b010, 0}
	case '=':
		return {0, 0b111, 0, 0b111, 0}
	case '#':
		return {0b101, 0b111, 0b101, 0b111, 0b101}
	case '/':
		return {0b001, 0b001, 0b010, 0b100, 0b100}
	case '<':
		return {0b001, 0b010, 0b100, 0b010, 0b001}
	case '>':
		return {0b100, 0b010, 0b001, 0b010, 0b100}
	case '!':
		return {0b010, 0b010, 0b010, 0, 0b010}
	case '?':
		return {0b110, 0b001, 0b010, 0, 0b010}
	case '_':
		return {0, 0, 0, 0, 0b111}
	case ',':
		return {0, 0, 0, 0b010, 0b100}
	case '(':
		return {0b010, 0b100, 0b100, 0b100, 0b010}
	case ')':
		return {0b010, 0b001, 0b001, 0b001, 0b010}
	case '[':
		return {0b110, 0b100, 0b100, 0b100, 0b110}
	case ']':
		return {0b011, 0b001, 0b001, 0b001, 0b011}
	}
	return {0b111, 0b101, 0b101, 0b101, 0b111}
}

@(private = "file")
letter_glyphs := [26]Glyph {
	{0b010, 0b101, 0b111, 0b101, 0b101}, // A
	{0b110, 0b101, 0b110, 0b101, 0b110}, // B
	{0b011, 0b100, 0b100, 0b100, 0b011}, // C
	{0b110, 0b101, 0b101, 0b101, 0b110}, // D
	{0b111, 0b100, 0b110, 0b100, 0b111}, // E
	{0b111, 0b100, 0b110, 0b100, 0b100}, // F
	{0b011, 0b100, 0b101, 0b101, 0b011}, // G
	{0b101, 0b101, 0b111, 0b101, 0b101}, // H
	{0b111, 0b010, 0b010, 0b010, 0b111}, // I
	{0b001, 0b001, 0b001, 0b101, 0b010}, // J
	{0b101, 0b101, 0b110, 0b101, 0b101}, // K
	{0b100, 0b100, 0b100, 0b100, 0b111}, // L
	{0b101, 0b111, 0b111, 0b101, 0b101}, // M
	{0b110, 0b101, 0b101, 0b101, 0b101}, // N
	{0b010, 0b101, 0b101, 0b101, 0b010}, // O
	{0b110, 0b101, 0b110, 0b100, 0b100}, // P
	{0b010, 0b101, 0b101, 0b110, 0b011}, // Q
	{0b110, 0b101, 0b110, 0b101, 0b101}, // R
	{0b011, 0b100, 0b010, 0b001, 0b110}, // S
	{0b111, 0b010, 0b010, 0b010, 0b010}, // T
	{0b101, 0b101, 0b101, 0b101, 0b111}, // U
	{0b101, 0b101, 0b101, 0b101, 0b010}, // V
	{0b101, 0b101, 0b111, 0b111, 0b101}, // W
	{0b101, 0b101, 0b010, 0b101, 0b101}, // X
	{0b101, 0b101, 0b010, 0b010, 0b010}, // Y
	{0b111, 0b001, 0b010, 0b100, 0b111}, // Z
}

@(private = "file")
digit_glyphs := [10]Glyph {
	{0b111, 0b101, 0b101, 0b101, 0b111}, // 0
	{0b010, 0b110, 0b010, 0b010, 0b111}, // 1
	{0b110, 0b001, 0b010, 0b100, 0b111}, // 2
	{0b110, 0b001, 0b010, 0b001, 0b110}, // 3
	{0b101, 0b101, 0b111, 0b001, 0b001}, // 4
	{0b111, 0b100, 0b110, 0b001, 0b110}, // 5
	{0b011, 0b100, 0b111, 0b101, 0b111}, // 6
	{0b111, 0b001, 0b010, 0b010, 0b010}, // 7
	{0b111, 0b101, 0b111, 0b101, 0b111}, // 8
	{0b111, 0b101, 0b111, 0b001, 0b110}, // 9
}

// Width in logical pixels of s at the given integer scale (no trailing gap).
text_width :: proc(s: string, scale := 1) -> int {
	n := 0
	for _ in s {
		n += 1
	}
	if n == 0 {
		return 0
	}
	return (n * GLYPH_ADVANCE - 1) * scale
}

// Draws s with its top-left at (x, y). Horizontal runs of lit pixels become one fill_rect.
draw_text :: proc(r: ^Renderer, x, y: int, s: string, c: Color, scale := 1) {
	cx := x
	for ch in s {
		g := glyph_for(ch)
		for row, ry in g {
			run_start := -1
			for col in 0 ..= GLYPH_W {
				lit := col < GLYPH_W && (row >> uint(GLYPH_W - 1 - col)) & 1 == 1
				if lit && run_start < 0 {
					run_start = col
				} else if !lit && run_start >= 0 {
					renderer_fill_rect(
						r,
						cx + run_start * scale,
						y + ry * scale,
						(col - run_start) * scale,
						scale,
						c,
					)
					run_start = -1
				}
			}
		}
		cx += GLYPH_ADVANCE * scale
	}
}
