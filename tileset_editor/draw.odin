package tileset_editor

import cm "../common"
import ie "../image_editor"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
DIM :: cm.Color{120, 120, 134}
HILITE :: cm.Color{255, 220, 80}
WARN :: cm.Color{235, 100, 90}
EMPTY_SLOT :: cm.Color{22, 22, 28}

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.confirm_delete {
		return fmt.tprintf("DELETE IMAGE?  %s: CONFIRM", label(e, .Green))
	}
	if e.confirm_exit {
		return fmt.tprintf("UNSAVED  %s: LEAVE ANYWAY", label(e, .Red))
	}
	switch e.mode {
	case .Pick:
		return fmt.tprintf("TILES   %s: EDIT IMAGE", label(e, .Green))
	case .Setup:
		return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
	case .File:
		return fmt.tprintf("%s: SAVE  %s: LOAD", label(e, .Green), label(e, .Yellow))
	case .Edit, .Text:
		// These modes draw their own screens.
	}
	return ""
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE SETTING OR ACTION", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE THE TILE SIZE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: RUN RENAME / NEW / DUP / DELETE / COPY / PASTE / MOVE", l(e, .Green)),
			fmt.tprintf("%s: DONE  %s: SAVE / LOAD", l(e, .Red), l(e, .Blue)),
		}
		return lines, 4
	case .File:
		lines = {fmt.tprintf("%s: SAVE  %s: LOAD", l(e, .Green), l(e, .Yellow)), fmt.tprintf("%s: CANCEL", l(e, .Red)), "", ""}
		return lines, 2
	case .Pick, .Edit, .Text:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: EDIT IMAGE  %s: SETUP / RENAME / NEW", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: SAVE / LOAD  %s: MAIN MENU", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK A TILE, AGAIN TO EDIT; WHEEL SCROLLS",
		}
		return lines, 4
	}
	return lines, 0
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

// The label on each button and the Setup row it belongs to (nil for the file buttons).
Button :: struct {
	rc:    Rect,
	text:  string,
	row:   Maybe(Setup_Row),
	needs: bool, // true if it only makes sense with an image selected
}

buttons :: proc() -> [12]Button {
	return {
		{RENAME_BUTTON, "RENAME", .Rename, true},
		{NEW_BUTTON, "NEW", .New, false},
		{DUPLICATE_BUTTON, "DUP", .Duplicate, true},
		{DELETE_BUTTON, "DEL", .Delete, true},
		{COPY_BUTTON, "COPY", .Copy, true},
		{PASTE_BUTTON, "PASTE", .Paste, true},
		{MOVE_LEFT_BUTTON, "MV <", .Move_Left, true},
		{MOVE_RIGHT_BUTTON, "MV >", .Move_Right, true},
		{SAVE_BUTTON, "SAVE", nil, false},
		{LOAD_BUTTON, "LOAD", nil, false},
		{EDIT_BUTTON, "EDIT", nil, true},
		{MENU_BUTTON, "MENU", nil, false},
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	switch e.mode {
	case .Edit:
		ie.editor_draw(&e.editor, r)
		return
	case .Text:
		cm.text_entry_draw(&e.entry, r, e.labels)
		return
	case .Pick, .Setup, .File:
	}
	ts := &e.tileset
	cm.renderer_clear(r, BG)

	// The thumbnail grid. The selected image has a frame in the gap around it.
	for row in 0 ..< GRID_ROWS {
		for col in 0 ..< GRID_COLS {
			index := (e.scroll + row) * GRID_COLS + col
			rc := grid_cell_rect(col, row)
			if index < ts.count {
				fill(r, rc, PANEL)
				cm.canvas_draw_thumbnail(r, rc, &ts.images[index], &e.palette)
			} else {
				fill(r, rc, EMPTY_SLOT)
			}
		}
	}
	if has_images(e) {
		row := e.sel / GRID_COLS - e.scroll
		if row >= 0 && row < GRID_ROWS {
			c := grid_cell_rect(e.sel % GRID_COLS, row)
			frame := e.mode == .Pick ? HILITE : DIM
			fill(r, Rect{c.x - 1, c.y - 1, c.w + 2, 1}, frame)
			fill(r, Rect{c.x - 1, c.y + c.h, c.w + 2, 1}, frame)
			fill(r, Rect{c.x - 1, c.y, 1, c.h}, frame)
			fill(r, Rect{c.x + c.w, c.y, 1, c.h}, frame)
		}
	}

	// Banner, the message or the image count, and the selected name.
	warning := e.confirm_exit || e.confirm_delete
	fill(r, BANNER, warning ? WARN : (e.mode == .Pick ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (warning || e.mode != .Pick) ? BG : TEXT)
	switch {
	case e.note != "":
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	case has_images(e):
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("IMAGE %d OF %d%s", e.sel + 1, ts.count, e.dirty ? " *" : ""), TEXT)
	case:
		cm.draw_text(r, INFO_X, INFO_Y, e.dirty ? "NO IMAGES YET *" : "NO IMAGES YET", DIM)
	}
	if has_images(e) {
		cm.draw_text(r, INFO_X, NAME_Y, selected_name(e), HILITE)
	}

	// Tile size rows.
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
	cm.draw_text(r, ROW_VALUE_X, WIDTH_MINUS.y + 3, fmt.tprintf("%d", ts.width), row_color(e, .Width))
	mark(r, e, .Width, WIDTH_MINUS.y + 3)
	cm.draw_text(r, ROW_LABEL_X, HEIGHT_MINUS.y + 3, "HEIGHT", row_color(e, .Height))
	cm.draw_text(r, ROW_VALUE_X, HEIGHT_MINUS.y + 3, fmt.tprintf("%d", ts.height), row_color(e, .Height))
	mark(r, e, .Height, HEIGHT_MINUS.y + 3)

	// A larger preview of the selected image.
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, cm.Color{14, 14, 20})
	if has_images(e) {
		cm.canvas_draw_thumbnail(r, PREVIEW_INNER, &ts.images[e.sel], &e.palette)
	} else {
		cm.draw_text(r, PREVIEW_INNER.x + 12, PREVIEW_INNER.y + 23, "EMPTY", DIM)
	}

	// The clipboard.
	if e.has_clip {
		cm.draw_text(r, CLIP_X, CLIP_Y, fmt.tprintf("CLIP: %s", string(e.clip_name[:e.clip_name_len])), TEXT)
	} else {
		cm.draw_text(r, CLIP_X, CLIP_Y, "CLIP: NONE", DIM)
	}

	// Buttons: the one whose Setup row is selected is lit; ones that need an image are dim without one.
	for btn in buttons() {
		lit := false
		if row, has := btn.row.?; has && e.mode == .Setup && e.row == row {
			lit = true
		}
		enabled := !btn.needs || has_images(e)
		if btn.row == .Paste {
			enabled = enabled && e.has_clip
		}
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.text)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.text, lit ? BG : (enabled ? TEXT : DIM))
	}

	// Help.
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
