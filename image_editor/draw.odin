package image_editor

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
DIM :: cm.Color{120, 120, 134}
HILITE :: cm.Color{255, 220, 80}
WARN :: cm.Color{235, 100, 90}
WHITE :: cm.Color{255, 255, 255}

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
	return fmt.tprintf("DRAWING   %s: PAINT", label(e, .Green))
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE SETTING", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE VALUE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: DONE  %s: SAVE / LOAD", l(e, .Red), l(e, .Blue)),
			"MOUSE: - + BUTTONS, CLICK A COLOR",
		}
	case .File:
		lines = {
			fmt.tprintf("%s: SAVE  %s: LOAD", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: CANCEL", l(e, .Red)),
			"MOUSE: CLICK OR DRAG TO PAINT",
			"",
		}
		return lines, 3
	case .Draw:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: PAINT  %s: SETUP / COLOR", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: SAVE / LOAD  %s: MAIN MENU", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK/DRAG PAINTS, RIGHT CLICK PICKS",
		}
	}
	return lines, MAX_HELP_LINES
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	img := &e.image

	// Canvas and cursor (the cursor is dimmed while a setup or file mode is active).
	cm.canvas_draw_image(r, CANVAS, img, &e.palette, e.cx, e.cy, BG, e.mode == .Draw ? HILITE : DIM)

	// Banner.
	fill(r, BANNER, e.confirm_exit ? WARN : (e.mode == .Draw ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (e.confirm_exit || e.mode != .Draw) ? BG : TEXT)

	// Readout: where the cursor is and the colour index under it.
	cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("CURSOR: %d,%d  PIXEL %d%s", e.cx, e.cy, img.pixels[e.cy][e.cx], e.dirty ? " *" : ""), TEXT)

	// Setting rows: colour (a chip), width and height (with - + buttons). The selected one is
	// marked and highlighted while Setup is the active mode.
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
	fill(r, Rect{COLOR_CHIP.x - 1, COLOR_CHIP.y - 1, COLOR_CHIP.w + 2, COLOR_CHIP.h + 2}, PANEL)
	fill(r, COLOR_CHIP, e.palette[e.color])
	cm.draw_text(r, ROW_LABEL_X, COLOR_CHIP.y + 2, "COLOR", row_color(e, .Color))
	cm.draw_text(r, ROW_VALUE_X, COLOR_CHIP.y + 2, fmt.tprintf("%d", e.color), row_color(e, .Color))
	mark(r, e, .Color, COLOR_CHIP.y + 2)
	cm.draw_text(r, ROW_LABEL_X, WIDTH_MINUS.y + 3, "WIDTH", row_color(e, .Width))
	cm.draw_text(r, ROW_VALUE_X, WIDTH_MINUS.y + 3, fmt.tprintf("%d", img.width), row_color(e, .Width))
	mark(r, e, .Width, WIDTH_MINUS.y + 3)
	cm.draw_text(r, ROW_LABEL_X, HEIGHT_MINUS.y + 3, "HEIGHT", row_color(e, .Height))
	cm.draw_text(r, ROW_VALUE_X, HEIGHT_MINUS.y + 3, fmt.tprintf("%d", img.height), row_color(e, .Height))
	mark(r, e, .Height, HEIGHT_MINUS.y + 3)

	// Palette strip; the drawing colour has a yellow ring.
	for i in 0 ..< cm.PALETTE_SIZE {
		rc := swatch_rect(i)
		fill(r, rc, e.palette[i])
		if i == e.color {
			fill(r, Rect{rc.x, rc.y, rc.w, 1}, HILITE)
			fill(r, Rect{rc.x, rc.y + rc.h - 1, rc.w, 1}, HILITE)
			fill(r, Rect{rc.x, rc.y, 1, rc.h}, HILITE)
			fill(r, Rect{rc.x + rc.w - 1, rc.y, 1, rc.h}, HILITE)
		}
	}

	// 3 x 3 tiled preview at a whole-number scale; what does not fit is clipped.
	s := preview_scale(img.width, img.height)
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, e.palette[0])
	for ty in 0 ..< TILES {
		for tx in 0 ..< TILES {
			for y in 0 ..< img.height {
				x := 0
				for x < img.width {
					color := img.pixels[y][x]
					start := x
					for x < img.width && img.pixels[y][x] == color {
						x += 1
					}
					if color == 0 {
						continue // colour 0 is the preview's background already
					}
					run := Rect {
						PREVIEW_INNER.x + (tx * img.width + start) * s,
						PREVIEW_INNER.y + (ty * img.height + y) * s,
						(x - start) * s,
						s,
					}
					if clipped, ok := intersect(run, PREVIEW_INNER); ok {
						fill(r, clipped, e.palette[color])
					}
				}
			}
		}
	}
	if preview_clipped(img.width, img.height) {
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
