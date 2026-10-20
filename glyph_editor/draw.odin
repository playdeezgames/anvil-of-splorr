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
	case .Rect:
		return e.shape == .Fill ? "FILL: PLACE 2ND CORNER" : "FRAME: PLACE 2ND CORNER"
	case .Setup:
		return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
	case .File:
		return fmt.tprintf("%s: SAVE  %s: LOAD", label(e, .Green), label(e, .Yellow))
	case .Draw:
		if e.shape != .None { 	// a rectangle tool armed with the mouse
			return fmt.tprintf("DRAG A %s  %s: CANCEL", e.shape == .Fill ? "FILL" : "FRAME", label(e, .Red))
		}
	}
	return fmt.tprintf("DRAWING   %s: TOGGLE", label(e, .Green))
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	mouse := "MOUSE: CLICK OR DRAG TO PAINT"
	switch e.mode {
	case .Rect:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE CORNER", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: DRAW IT  %s: CANCEL", l(e, .Green), l(e, .Red)),
			"FROM A LIT PIXEL IT ERASES (RED DOTS)",
			"MOUSE: CLICK THE OPPOSITE CORNER",
		}
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE SETTING OR ACTION", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE VALUE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: RUN INVERT / FLIP / ROTATE / RECT", l(e, .Green)),
			fmt.tprintf("%s: DONE  %s: SAVE / LOAD", l(e, .Red), l(e, .Blue)),
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

// Marks the pixels the rectangle being placed will change: a small yellow square in each cell when
// it will draw, red when it will erase.
draw_shape_preview :: proc(e: ^Editor, r: ^cm.Renderer) {
	b := &e.bitmap
	c := cell_size(b.width, b.height)
	m := max(1, c / 2)
	color := e.shape_on ? HILITE : WARN
	for y in min(e.ay, e.cy) ..= max(e.ay, e.cy) {
		for x in min(e.ax, e.cx) ..= max(e.ax, e.cx) {
			if cm.shape_has_cell(e.shape, e.ax, e.ay, e.cx, e.cy, x, y) {
				cr := cell_rect(b.width, b.height, x, y)
				cm.renderer_fill_rect(r, cr.x + (c - m) / 2, cr.y + (c - m) / 2, m, m, color)
			}
		}
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
		cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
	}
	b := &e.bitmap

	// Canvas and cursor (the cursor is dimmed while a setup or file mode is active).
	cm.canvas_draw(r, CANVAS, b, e.cx, e.cy, {on = ON, off = OFF, grid = BG, cursor = e.mode == .Draw || e.mode == .Rect ? HILITE : DIM})
	if e.mode == .Rect {
		draw_shape_preview(e, r)
	}

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

	// Buttons. The transform and tool buttons are lit while their Setup row is selected, and a
	// rectangle tool is also lit while it is armed.
	for btn in ([11]struct {
			rc:    Rect,
			txt:   string,
			row:   Maybe(Setup_Row),
			shape: cm.Shape,
		}{
			{SAVE_BUTTON, "SAVE", nil, .None},
			{LOAD_BUTTON, "LOAD", nil, .None},
			{MENU_BUTTON, "MENU", nil, .None},
			{FLIP_H_BUTTON, "FLIP H", .Flip_Horizontal, .None},
			{FLIP_V_BUTTON, "FLIP V", .Flip_Vertical, .None},
			{ROT_L_BUTTON, "ROT L", .Rotate_Left, .None},
			{ROT_R_BUTTON, "ROT R", .Rotate_Right, .None},
			{ROT_180_BUTTON, "ROT 180", .Rotate_180, .None},
			{FRAME_BUTTON, "FRAME", .Frame, .Frame},
			{FILL_BUTTON, "FILL", .Fill, .Fill},
			{INVERT_BUTTON, "INVERT", .Invert, .None},
		}) {
		lit := btn.shape != .None && e.shape == btn.shape
		if row, has := btn.row.?; has && e.mode == .Setup && e.row == row {
			lit = true
		}
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.txt)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.txt, lit ? BG : TEXT)
	}

	// Help.
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}

	cm.renderer_present(r)
}
