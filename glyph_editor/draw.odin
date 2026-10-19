package glyph_editor

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

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.confirm_exit {
		return fmt.tprintf("UNSAVED   %s: LEAVE ANYWAY", label(e, .Red))
	}
	switch e.mode {
	case .Size:
		return fmt.tprintf("SIZE   %s: DONE", label(e, .Red))
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
	case .Size:
		lines = {
			fmt.tprintf("%s/%s: WIDTH -/+ 1", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s/%s: HEIGHT +/- 1", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: DONE  %s: SAVE / LOAD", l(e, .Red), l(e, .Blue)),
			"MOUSE: THE - AND + BUTTONS",
		}
	case .File:
		lines = {fmt.tprintf("%s: SAVE  %s: LOAD", l(e, .Green), l(e, .Yellow)), fmt.tprintf("%s: CANCEL", l(e, .Red)), mouse, ""}
		n = 3
		return lines, n
	case .Draw:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: TOGGLE PIXEL  %s: SIZE", l(e, .Green), l(e, .Yellow)),
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

	// Readouts.
	state := cm.bitmap_get(b, e.cx, e.cy) ? "ON" : "OFF"
	cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("CURSOR: %d,%d%s", e.cx, e.cy, e.dirty ? " *" : ""), TEXT)
	cm.draw_text(r, INFO_X, INFO_Y + 8, fmt.tprintf("PIXEL: %s", state), TEXT)

	// Size controls.
	size_color := e.mode == .Size ? HILITE : TEXT
	cm.draw_text(r, SIZE_LABEL_X, WIDTH_MINUS.y + 3, "WIDTH", size_color)
	cm.draw_text(r, SIZE_LABEL_X, HEIGHT_MINUS.y + 3, "HEIGHT", size_color)
	for pair in ([4]struct {
			rc:  Rect,
			txt: string,
		}{{WIDTH_MINUS, "-"}, {WIDTH_PLUS, "+"}, {HEIGHT_MINUS, "-"}, {HEIGHT_PLUS, "+"}}) {
		fill(r, pair.rc, PANEL)
		cm.draw_text(r, pair.rc.x + (pair.rc.w - cm.text_width(pair.txt)) / 2, pair.rc.y + 3, pair.txt, TEXT)
	}
	cm.draw_text(r, SIZE_VALUE_X, WIDTH_MINUS.y + 3, fmt.tprintf("%d", b.width), size_color)
	cm.draw_text(r, SIZE_VALUE_X, HEIGHT_MINUS.y + 3, fmt.tprintf("%d", b.height), size_color)

	// Actual-size preview.
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, Rect{PREVIEW_FRAME.x + 1, PREVIEW_FRAME.y + 1, b.width, b.height}, OFF)
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
			fill(r, Rect{PREVIEW_FRAME.x + 1 + start, PREVIEW_FRAME.y + 1 + y, x - start, 1}, ON)
		}
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
