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
		switch e.point_tool { 	// a click tool armed with the mouse
		case .Flood_Fill:
			return fmt.tprintf("CLICK TO FLOOD  %s: CANCEL", label(e, .Red))
		case .Replace_Color:
			return fmt.tprintf("CLICK TO REPLACE  %s: CANCEL", label(e, .Red))
		case .None:
		}
	}
	return fmt.tprintf("DRAWING   %s: PAINT", label(e, .Green))
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .Rect:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE CORNER", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: DRAW IT  %s: CANCEL", l(e, .Green), l(e, .Red)),
			"MOUSE: CLICK THE OPPOSITE CORNER",
			"",
		}
		return lines, 3
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE SETTING OR ACTION", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE VALUE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: RUN A TRANSFORM OR TOOL", l(e, .Green)),
			e.embedded ? fmt.tprintf("%s: DONE", l(e, .Red)) : fmt.tprintf("%s: DONE  %s: SAVE / LOAD", l(e, .Red), l(e, .Blue)),
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
			e.embedded ? fmt.tprintf("%s: BACK TO THE TILES", l(e, .Red)) : fmt.tprintf("%s: SAVE / LOAD  %s: MAIN MENU", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK/DRAG PAINTS, RIGHT CLICK PICKS",
		}
	}
	return lines, MAX_HELP_LINES
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

// Marks the pixels the rectangle being placed will cover with a small yellow square in each.
draw_shape_preview :: proc(e: ^Editor, r: ^cm.Renderer) {
	img := &e.image
	c := cell_size(img.width, img.height)
	m := max(1, c / 2)
	for y in min(e.ay, e.cy) ..= max(e.ay, e.cy) {
		for x in min(e.ax, e.cx) ..= max(e.ax, e.cx) {
			if cm.shape_has_cell(e.shape, e.ax, e.ay, e.cx, e.cy, x, y) {
				cr := cell_rect(img.width, img.height, x, y)
				fill(r, Rect{cr.x + (c - m) / 2, cr.y + (c - m) / 2, m, m}, HILITE)
			}
		}
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	img := &e.image

	// Canvas and cursor (the cursor is dimmed while a setup or file mode is active).
	cm.canvas_draw_image(r, CANVAS, img, &e.palette, e.cx, e.cy, BG, e.mode == .Draw || e.mode == .Rect ? HILITE : DIM)
	if e.mode == .Rect {
		draw_shape_preview(e, r)
	}

	// Banner.
	fill(r, BANNER, e.confirm_exit ? WARN : (e.mode == .Draw ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (e.confirm_exit || e.mode != .Draw) ? BG : TEXT)

	// Readout: where the cursor is and the colour index under it.
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	} else {
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("CURSOR: %d,%d  PIXEL %d%s", e.cx, e.cy, img.pixels[e.cy][e.cx], e.dirty ? " *" : ""), TEXT)
	}

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
		if e.lock_size {
			continue // the tileset owns the size: nothing to press
		}
		fill(r, btn.rc, PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.txt)) / 2, btn.rc.y + 3, btn.txt, TEXT)
	}
	fill(r, Rect{COLOR_CHIP.x - 1, COLOR_CHIP.y - 1, COLOR_CHIP.w + 2, COLOR_CHIP.h + 2}, PANEL)
	fill(r, COLOR_CHIP, e.palette[e.color])
	cm.draw_text(r, ROW_LABEL_X, COLOR_CHIP.y + 2, "COLOR", row_color(e, .Color))
	cm.draw_text(r, ROW_VALUE_X, COLOR_CHIP.y + 2, fmt.tprintf("%d", e.color), row_color(e, .Color))
	mark(r, e, .Color, COLOR_CHIP.y + 2)
	// Width and height are dimmed when the tileset owns them.
	size_color :: proc(e: ^Editor, row: Setup_Row) -> cm.Color {
		return e.lock_size ? DIM : row_color(e, row)
	}
	cm.draw_text(r, ROW_LABEL_X, WIDTH_MINUS.y + 3, "WIDTH", size_color(e, .Width))
	cm.draw_text(r, ROW_VALUE_X, WIDTH_MINUS.y + 3, fmt.tprintf("%d", img.width), size_color(e, .Width))
	mark(r, e, .Width, WIDTH_MINUS.y + 3)
	cm.draw_text(r, ROW_LABEL_X, HEIGHT_MINUS.y + 3, "HEIGHT", size_color(e, .Height))
	cm.draw_text(r, ROW_VALUE_X, HEIGHT_MINUS.y + 3, fmt.tprintf("%d", img.height), size_color(e, .Height))
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

	// Buttons. The transform and rectangle buttons are lit while their Setup row is selected, and a
	// rectangle tool is also lit while it is armed.
	for btn in ([13]struct {
			rc:    Rect,
			txt:   string,
			row:   Maybe(Setup_Row),
			shape: cm.Shape,
			point: Point_Tool,
		}{
			{SAVE_BUTTON, "SAVE", nil, .None, .None},
			{LOAD_BUTTON, "LOAD", nil, .None, .None},
			{MENU_BUTTON, "MENU", nil, .None, .None},
			{FLIP_H_BUTTON, "FLIP H", .Flip_Horizontal, .None, .None},
			{FLIP_V_BUTTON, "FLIP V", .Flip_Vertical, .None, .None},
			{ROT_L_BUTTON, "ROT L", .Rotate_Left, .None, .None},
			{ROT_R_BUTTON, "ROT R", .Rotate_Right, .None, .None},
			{ROT_180_BUTTON, "ROT 180", .Rotate_180, .None, .None},
			{FRAME_BUTTON, "FRAME", .Frame, .Frame, .None},
			{FILL_BUTTON, "FILL", .Fill, .Fill, .None},
			{FLOOD_BUTTON, "FLOOD", .Flood_Fill, .None, .Flood_Fill},
			{REPLACE_BUTTON, "REPLACE", .Replace_Color, .None, .Replace_Color},
			{CLEAR_BUTTON, "CLEAR", .Clear, .None, .None},
		}) {
		if e.embedded && (btn.rc == SAVE_BUTTON || btn.rc == LOAD_BUTTON) {
			continue // the tileset editor owns the file
		}
		lit := (btn.shape != .None && e.shape == btn.shape) || (btn.point != .None && e.point_tool == btn.point)
		if row, has := btn.row.?; has && e.mode == .Setup && e.row == row {
			lit = true
		}
		// A quarter turn is unavailable on a non-square tile in a tileset.
		turn_blocked := e.lock_size && e.image.width != e.image.height && (btn.rc == ROT_L_BUTTON || btn.rc == ROT_R_BUTTON)
		text := btn.rc == MENU_BUTTON && e.embedded ? "BACK" : btn.txt
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(text)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, text, lit ? BG : (turn_blocked ? DIM : TEXT))
	}

	// Help.
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}

	cm.renderer_present(r)
}
