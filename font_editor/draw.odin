package font_editor

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
DIM :: cm.Color{120, 120, 134}
HILITE :: cm.Color{255, 220, 80}
WARN :: cm.Color{235, 100, 90}
OFF :: cm.Color{14, 14, 20} // a clear pixel
ON :: cm.Color{240, 240, 250} // a set pixel
CELL_PRESENT :: cm.Color{48, 48, 62}
CELL_ABSENT :: cm.Color{22, 22, 28}
CELL_MISSING :: cm.Color{74, 30, 34} // a printable (32..127) character with no glyph yet

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.confirm_exit {
		return fmt.tprintf("UNSAVED  %s: LEAVE ANYWAY", label(e, .Red))
	}
	switch e.mode {
	case .Pick:
		return fmt.tprintf("FONT   %s: EDIT GLYPH", label(e, .Green))
	case .Edit:
		return fmt.tprintf("GLYPH   %s: TOGGLE", label(e, .Green))
	case .Setup:
		return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
	case .File:
		return fmt.tprintf("%s: SAVE  %s: LOAD", label(e, .Green), label(e, .Yellow))
	}
	return ""
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	move := fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right))
	switch e.mode {
	case .Pick:
		lines = {
			move,
			fmt.tprintf("%s: EDIT GLYPH  %s: SETUP", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: SAVE / LOAD  %s: MAIN MENU", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK A CELL, AGAIN TO EDIT",
		}
	case .Edit:
		lines = {
			move,
			fmt.tprintf("%s: TOGGLE PIXEL  %s: SETUP", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: SAVE / LOAD  %s: BACK TO GRID", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK OR DRAG TO PAINT",
		}
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE SETTING", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE VALUE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: DONE  %s: SAVE / LOAD", l(e, .Red), l(e, .Blue)),
			"MOUSE: - + AND YES/NO BUTTONS",
		}
	case .File:
		lines = {fmt.tprintf("%s: SAVE  %s: LOAD", l(e, .Green), l(e, .Yellow)), fmt.tprintf("%s: CANCEL", l(e, .Red)), "", ""}
		return lines, 2
	}
	return lines, MAX_HELP_LINES
}

// Name shown beside a character code: the character itself when the built-in font can draw it.
char_name :: proc(code: int) -> string {
	switch {
	case code == ' ':
		return "SPACE"
	case code > ' ' && code < 127 && cm.font_has(rune(code)):
		return fmt.tprintf("%c", rune(code))
	}
	return ""
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

// Draws the set pixels of g with its top-left at (ox, oy), each scaled by `scale`, as horizontal
// runs clipped to `clip`.
draw_glyph_pixels :: proc(r: ^cm.Renderer, g: ^cm.Bitmap, ox, oy, scale: int, color: cm.Color, clip: Rect) {
	for y in 0 ..< g.height {
		x := 0
		for x < g.width {
			if !g.bits[y][x] {
				x += 1
				continue
			}
			start := x
			for x < g.width && g.bits[y][x] {
				x += 1
			}
			run := Rect{ox + start * scale, oy + y * scale, (x - start) * scale, scale}
			if clipped, ok := intersect(run, clip); ok {
				fill(r, clipped, color)
			}
		}
	}
}

draw_grid :: proc(e: ^Editor, r: ^cm.Renderer) {
	for code in 0 ..< cm.PIXEL_FONT_CHARS {
		cell := grid_cell_rect(code)
		g := &e.font.glyphs[code]
		bg := CELL_ABSENT
		if e.font.present[code] {
			bg = CELL_PRESENT
		} else if code >= cm.PRINTABLE_FIRST && code <= cm.PRINTABLE_LAST {
			bg = CELL_MISSING
		}
		fill(r, cell, bg)
		if e.font.present[code] {
			draw_glyph_pixels(r, g, cell.x, cell.y, 1, ON, cell) // 1:1, clipped to the cell
		}
	}
	// Selection frame, in the gap around the cell.
	c := grid_cell_rect(e.code)
	frame := e.mode == .Pick ? HILITE : DIM
	fill(r, Rect{c.x - 1, c.y - 1, c.w + 2, 1}, frame)
	fill(r, Rect{c.x - 1, c.y + c.h, c.w + 2, 1}, frame)
	fill(r, Rect{c.x - 1, c.y, 1, c.h}, frame)
	fill(r, Rect{c.x + c.w, c.y, 1, c.h}, frame)
}

draw_sample :: proc(e: ^Editor, r: ^cm.Renderer) {
	f := &e.font
	text := SAMPLE_TEXT // a variable, so it can be indexed
	fill(r, SAMPLE_FRAME, PANEL)
	fill(r, SAMPLE_INNER, OFF)
	if cm.pixel_font_text_width(f, text) == 0 {
		cm.draw_text(r, SAMPLE_INNER.x + 2, SAMPLE_INNER.y + 2, "SAMPLE TEXT SHOWS HERE", DIM)
		return
	}
	x, y := SAMPLE_INNER.x, SAMPLE_INNER.y
	for i in 0 ..< len(text) {
		c := int(text[i])
		if !f.present[c] {
			continue
		}
		g := &f.glyphs[c]
		if x + g.width > SAMPLE_INNER.x + SAMPLE_INNER.w && x > SAMPLE_INNER.x { 	// wrap
			x = SAMPLE_INNER.x
			y += f.height + 1
		}
		if y >= SAMPLE_INNER.y + SAMPLE_INNER.h {
			return // out of room (tall font): the rest is not shown
		}
		draw_glyph_pixels(r, g, x, y, 1, ON, SAMPLE_INNER)
		x += g.width
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	g := glyph(e)

	// Left side: the pixel canvas while editing, otherwise the character grid.
	if showing_canvas(e) {
		cursor := e.mode == .Edit ? HILITE : DIM
		cm.canvas_draw(r, CANVAS, g, e.cx, e.cy, {on = ON, off = OFF, grid = BG, cursor = cursor})
	} else {
		draw_grid(e, r)
	}

	// Banner and the selected character.
	fill(r, BANNER, e.confirm_exit ? WARN : (e.mode == .Pick ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (e.confirm_exit || e.mode != .Pick) ? BG : TEXT)
	cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("CODE %d  $%02X  %s%s", e.code, e.code, char_name(e.code), e.dirty ? "  *" : ""), TEXT)

	// Setting rows. The selected one is marked and highlighted while Setup is the active mode.
	row_color :: proc(e: ^Editor, row: Setup_Row) -> cm.Color {
		return e.mode == .Setup && e.row == row ? HILITE : TEXT
	}
	mark :: proc(r: ^cm.Renderer, e: ^Editor, row: Setup_Row, y: int) {
		if e.mode == .Setup && e.row == row {
			cm.draw_text(r, ROW_MARKER_X, y, ">", HILITE)
		}
	}
	for btn in ([4]struct {
			rc:  Rect,
			txt: string,
		}{{WIDTH_MINUS, "-"}, {WIDTH_PLUS, "+"}, {HEIGHT_MINUS, "-"}, {HEIGHT_PLUS, "+"}}) {
		fill(r, btn.rc, PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.txt)) / 2, btn.rc.y + 3, btn.txt, TEXT)
	}
	cm.draw_text(r, ROW_LABEL_X, WIDTH_MINUS.y + 3, "WIDTH", row_color(e, .Width))
	cm.draw_text(r, ROW_VALUE_X, WIDTH_MINUS.y + 3, fmt.tprintf("%d", g.width), row_color(e, .Width))
	mark(r, e, .Width, WIDTH_MINUS.y + 3)
	cm.draw_text(r, ROW_LABEL_X, HEIGHT_MINUS.y + 3, "HEIGHT", row_color(e, .Height))
	cm.draw_text(r, ROW_VALUE_X, HEIGHT_MINUS.y + 3, fmt.tprintf("%d", e.font.height), row_color(e, .Height))
	mark(r, e, .Height, HEIGHT_MINUS.y + 3)
	cm.draw_text(r, ROW_LABEL_X, PRESENT_BUTTON.y + 3, "PRESENT", row_color(e, .Present))
	fill(r, PRESENT_BUTTON, present(e) ? CELL_PRESENT : PANEL)
	yes_no := present(e) ? "YES" : "NO"
	cm.draw_text(r, PRESENT_BUTTON.x + (PRESENT_BUTTON.w - cm.text_width(yes_no)) / 2, PRESENT_BUTTON.y + 3, yes_no, present(e) ? ON : DIM)
	mark(r, e, .Present, PRESENT_BUTTON.y + 3)

	// The selected glyph, scaled to fit its frame.
	fill(r, GLYPH_FRAME, PANEL)
	fill(r, GLYPH_INNER, OFF)
	if present(e) {
		cm.canvas_draw(r, GLYPH_INNER, g, -1, 0, {on = ON, off = OFF, grid = BG, cursor = HILITE})
	} else {
		cm.draw_text(r, GLYPH_INNER.x + 3, GLYPH_INNER.y + 20, "ABSENT", DIM)
	}

	// Coverage of the printable range.
	defined, total := cm.pixel_font_coverage(&e.font)
	cm.draw_text(r, COVER_X, COVER_Y, "ASCII 32-127", DIM)
	cm.draw_text(r, COVER_X, COVER_Y + 8, fmt.tprintf("DEFINED %d/%d", defined, total), TEXT)
	if defined == total {
		cm.draw_text(r, COVER_X, COVER_Y + 16, "COMPLETE", HILITE)
	} else {
		cm.draw_text(r, COVER_X, COVER_Y + 16, fmt.tprintf("MISSING %d", total - defined), WARN)
	}

	draw_sample(e, r)

	// Buttons.
	edit_label := e.mode == .Edit ? "GRID" : "EDIT"
	for btn in ([4]struct {
			rc:  Rect,
			txt: string,
		}{{SAVE_BUTTON, "SAVE"}, {LOAD_BUTTON, "LOAD"}, {EDIT_BUTTON, edit_label}, {MENU_BUTTON, "MENU"}}) {
		fill(r, btn.rc, PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.txt)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.txt, TEXT)
	}

	// Help.
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}

	cm.renderer_present(r)
}
