package glyph_editor

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
DIM :: cm.Color{120, 120, 134}
HILITE :: cm.Color{255, 220, 80}
WARN :: cm.Color{235, 100, 90}
WHITE :: cm.Color{255, 255, 255}
OFF :: cm.Color{14, 14, 20} // a clear pixel on the canvas
ON :: cm.Color{240, 240, 250} // a set pixel on the canvas

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.confirm_exit {
		return fmt.tprintf("UNSAVED   %s: LEAVE ANYWAY", label(e, .Red))
	}
	switch e.mode {
	case .Setup:
		return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
	case .File:
		return fmt.tprintf("%s: SAVE  %s: LOAD", label(e, .Green), label(e, .Yellow))
	case .Draw:
	}
	return fmt.tprintf("DRAWING   %s: TOGGLE", label(e, .Green))
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	mouse := "MOUSE: CLICK OR DRAG TO PAINT"
	switch e.mode {
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE SETTING", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE VALUE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: DONE  %s: SAVE / LOAD", l(e, .Red), l(e, .Blue)),
			"MOUSE: - + BUTTONS, CLICK A COLOR (RIGHT = BG)",
		}
	case .File:
		lines = {fmt.tprintf("%s: SAVE  %s: LOAD", l(e, .Green), l(e, .Yellow)), fmt.tprintf("%s: CANCEL", l(e, .Red)), mouse, ""}
		return lines, 3
	case .Draw:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: TOGGLE PIXEL  %s: SETUP", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: SAVE / LOAD  %s: MAIN MENU", l(e, .Blue), l(e, .Red)),
			mouse,
		}
	}
	return lines, MAX_HELP_LINES
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
		cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
	}
	b := &e.bitmap
	c := cell_size(b.width, b.height)

	// Canvas: clear pixels, then set pixels. With cells of 3+ pixels each gets a 1 px gap so the
	// grid shows; smaller cells are merged into horizontal runs.
	fill(r, Rect{CANVAS.x, CANVAS.y, b.width * c, b.height * c}, OFF)
	gap := c >= 3 ? 1 : 0
	for y in 0 ..< b.height {
		x := 0
		for x < b.width {
			if !b.bits[y][x] {
				x += 1
				continue
			}
			if gap == 1 {
				cr := cell_rect(b.width, b.height, x, y)
				fill(r, Rect{cr.x, cr.y, c - 1, c - 1}, ON)
				x += 1
			} else {
				start := x
				for x < b.width && b.bits[y][x] {
					x += 1
				}
				cr := cell_rect(b.width, b.height, start, y)
				fill(r, Rect{cr.x, cr.y, (x - start) * c, c}, ON)
			}
		}
	}
	if gap == 1 { 	// grid lines on the clear pixels' gaps
		for x in 1 ..< b.width {
			fill(r, Rect{CANVAS.x + x * c - 1, CANVAS.y, 1, b.height * c}, BG)
		}
		for y in 1 ..< b.height {
			fill(r, Rect{CANVAS.x, CANVAS.y + y * c - 1, b.width * c, 1}, BG)
		}
	}

	// Cursor: a 1 px outline just outside its cell, so it shows on any pixel colour.
	cr := cell_rect(b.width, b.height, e.cx, e.cy)
	cc := e.mode == .Draw ? HILITE : DIM
	fill(r, Rect{cr.x - 1, cr.y - 1, cr.w + 2, 1}, cc)
	fill(r, Rect{cr.x - 1, cr.y + cr.h, cr.w + 2, 1}, cc)
	fill(r, Rect{cr.x - 1, cr.y, 1, cr.h}, cc)
	fill(r, Rect{cr.x + cr.w, cr.y, 1, cr.h}, cc)

	// Banner.
	fill(r, BANNER, e.confirm_exit ? WARN : (e.mode == .Draw ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (e.confirm_exit || e.mode != .Draw) ? BG : TEXT)

	// Readout.
	state := cm.bitmap_get(b, e.cx, e.cy) ? "ON" : "OFF"
	cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("CURSOR: %d,%d %s%s", e.cx, e.cy, state, e.dirty ? " *" : ""), TEXT)

	// Setup rows: width, height (with - + buttons), foreground, background (with a colour chip).
	// The selected row is marked and highlighted while Setup is the active mode.
	row_color :: proc(e: ^Editor, row: Setup_Row) -> cm.Color {
		return e.mode == .Setup && e.row == row ? HILITE : TEXT
	}
	mark :: proc(r: ^cm.Renderer, e: ^Editor, row: Setup_Row, y: int) {
		if e.mode == .Setup && e.row == row {
			cm.draw_text(r, ROW_MARKER_X, y, ">", HILITE)
		}
	}
	buttons := [4]struct {
		rc:  Rect,
		txt: string,
	}{{WIDTH_MINUS, "-"}, {WIDTH_PLUS, "+"}, {HEIGHT_MINUS, "-"}, {HEIGHT_PLUS, "+"}}
	for btn in buttons {
		fill(r, btn.rc, PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.txt)) / 2, btn.rc.y + 3, btn.txt, TEXT)
	}
	cm.draw_text(r, ROW_LABEL_X, WIDTH_MINUS.y + 3, "WIDTH", row_color(e, .Width))
	cm.draw_text(r, ROW_VALUE_X, WIDTH_MINUS.y + 3, fmt.tprintf("%d", b.width), row_color(e, .Width))
	mark(r, e, .Width, WIDTH_MINUS.y + 3)
	cm.draw_text(r, ROW_LABEL_X, HEIGHT_MINUS.y + 3, "HEIGHT", row_color(e, .Height))
	cm.draw_text(r, ROW_VALUE_X, HEIGHT_MINUS.y + 3, fmt.tprintf("%d", b.height), row_color(e, .Height))
	mark(r, e, .Height, HEIGHT_MINUS.y + 3)
	for chip in ([2]struct {
			row:  Setup_Row,
			rc:   Rect,
			name: string,
			idx:  int,
		}{{.Foreground, FG_CHIP, "FORE", e.fg}, {.Background, BG_CHIP, "BACK", e.bg}}) {
		fill(r, Rect{chip.rc.x - 1, chip.rc.y - 1, chip.rc.w + 2, chip.rc.h + 2}, PANEL)
		fill(r, chip.rc, e.palette[chip.idx])
		cm.draw_text(r, ROW_LABEL_X, chip.rc.y + 2, chip.name, row_color(e, chip.row))
		cm.draw_text(r, ROW_VALUE_X, chip.rc.y + 2, fmt.tprintf("%d", chip.idx), row_color(e, chip.row))
		mark(r, e, chip.row, chip.rc.y + 2)
	}

	// Palette strip. Foreground is outlined in yellow, background in white (one ring inside the
	// other when both are the same swatch).
	for i in 0 ..< cm.PALETTE_SIZE {
		rc := swatch_rect(i)
		fill(r, rc, e.palette[i])
		ring :: proc(r: ^cm.Renderer, rc: Rect, inset: int, c: cm.Color) {
			x, y, w, h := rc.x + inset, rc.y + inset, rc.w - 2 * inset, rc.h - 2 * inset
			cm.renderer_fill_rect(r, x, y, w, 1, c)
			cm.renderer_fill_rect(r, x, y + h - 1, w, 1, c)
			cm.renderer_fill_rect(r, x, y, 1, h, c)
			cm.renderer_fill_rect(r, x + w - 1, y, 1, h, c)
		}
		if i == e.fg {
			ring(r, rc, 0, HILITE)
		}
		if i == e.bg {
			ring(r, rc, i == e.fg ? 1 : 0, WHITE)
		}
	}

	// 3 x 3 tiled preview at a whole-number scale, in the chosen colours; what does not fit is clipped.
	s := preview_scale(b.width, b.height)
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, e.palette[e.bg])
	for ty in 0 ..< TILES {
		for tx in 0 ..< TILES {
			for y in 0 ..< b.height {
				x := 0
				for x < b.width {
					if !b.bits[y][x] {
						x += 1
						continue
					}
					start := x
					for x < b.width && b.bits[y][x] {
						x += 1
					}
					run := Rect {
						PREVIEW_INNER.x + (tx * b.width + start) * s,
						PREVIEW_INNER.y + (ty * b.height + y) * s,
						(x - start) * s,
						s,
					}
					if clipped, ok := intersect(run, PREVIEW_INNER); ok {
						fill(r, clipped, e.palette[e.fg])
					}
				}
			}
		}
	}
	if preview_clipped(b.width, b.height) {
		cm.draw_text(r, CLIPPED_X, CLIPPED_Y, "CLIPPED", DIM)
	}

	// File buttons.
	for btn in ([3]struct {
			rc:  Rect,
			txt: string,
		}{{SAVE_BUTTON, "SAVE"}, {LOAD_BUTTON, "LOAD"}, {MENU_BUTTON, "MENU"}}) {
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
