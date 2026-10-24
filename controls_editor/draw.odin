package controls_editor

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
DIM :: cm.Color{120, 120, 134}
HILITE :: cm.Color{255, 220, 80}
WARN :: cm.Color{235, 100, 90}

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.map_, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.confirm_leave {
		return fmt.tprintf("UNSAVED CHANGES   %s: LEAVE ANYWAY", label(e, .Red))
	}
	if e.confirm_reset {
		return fmt.tprintf("RESET TO DEFAULTS?   %s: CONFIRM", label(e, .Green))
	}
	switch e.mode {
	case .Table:
		return fmt.tprintf("CONTROLS   %s: CHANGE", label(e, .Green))
	case .Capture:
		what := e.capture_col == .Key ? "KEY" : "PAD BUTTON"
		return fmt.tprintf("PRESS THE NEW %s FOR %s", what, label(e, action_at(e.row)))
	case .File:
		return fmt.tprintf("FILE: %s SAVE  %s LOAD", label(e, .Green), label(e, .Yellow))
	case .Text:
	}
	return ""
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .Table:
		lines = {
			fmt.tprintf("%s/%s: COMMAND  %s/%s: COLUMN", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: CHANGE  %s: UNBIND", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: FILE  %s: BACK TO THE MENU", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK A CELL TO CHANGE IT",
		}
		return lines, 4
	case .Capture:
		lines = {
			"PRESS THE KEY OR PAD BUTTON YOU WANT",
			"MOUSE: CLICK CANCEL, OR WAIT, TO GIVE UP",
			"",
			"",
		}
		return lines, 2
	case .File:
		lines = {fmt.tprintf("%s: SAVE  %s: LOAD AGAIN", l(e, .Green), l(e, .Yellow)), fmt.tprintf("%s: CANCEL", l(e, .Red)), "", ""}
		return lines, 2
	case .Text:
	}
	return lines, 0
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

// The buttons of the screen; the second says whether it would do anything now.
buttons :: proc(e: ^Editor) -> (list: [5]Button, n: int) {
	if e.mode == .Capture {
		list[0] = {CANCEL_BUTTON, "CANCEL", true}
		return list, 1
	}
	list = {{SAVE_BUTTON, "SAVE", editor_dirty(e) || true}, {LOAD_BUTTON, "LOAD", true}, {UNBIND_BUTTON, "UNBIND", !on_defaults(e)}, {MENU_BUTTON, "MENU", true}, {}}
	return list, 4
}

Button :: struct {
	rc:      Rect,
	text:    string,
	enabled: bool,
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	if e.mode == .Text {
		cm.text_entry_draw(&e.entry, r, e.map_)
		return
	}
	cm.renderer_clear(r, BG)
	warning := e.confirm_leave || e.confirm_reset
	fill(r, BANNER, warning ? WARN : (e.mode == .Table ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (warning || e.mode != .Table) ? BG : TEXT)
	switch {
	case e.note != "":
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	case on_defaults(e):
		cm.draw_text(r, INFO_X, INFO_Y, e.map_^ == cm.default_input_map() ? "ALREADY THE DEFAULTS" : "GREEN TWICE: BACK TO THE DEFAULTS", DIM)
	case:
		a := action_at(e.row)
		what := e.col == .Pad && e.map_.pad[a] != cm.NO_BUTTON ? fmt.tprintf("PAD BUTTON %d: %s", e.map_.pad[a], pad_name(e.map_.pad[a])) : fmt.tprintf("%s%s", cm.ACTION_NAMES[a], editor_dirty(e) ? " *" : "")
		cm.draw_text(r, INFO_X, INFO_Y, what, TEXT)
	}

	// Header and rows.
	cm.draw_text(r, CMD_X, HEADER_Y, "COMMAND", DIM)
	cm.draw_text(r, KEY_CELL.x + 2, HEADER_Y, "KEY", DIM)
	cm.draw_text(r, PAD_CELL.x + 2, HEADER_Y, "PAD", DIM)
	cm.draw_text(r, LABEL_CELL.x + 2, HEADER_Y, "LABEL", DIM)
	for row in 0 ..< ROW_COUNT {
		rc := row_rect(row)
		on_row := e.row == row
		fill(r, rc, on_row ? cm.Color{44, 44, 56} : BG)
		y := rc.y + (rc.h - cm.GLYPH_H) / 2
		if row >= len(cm.Action) {
			cm.draw_text(r, CMD_X, y, "RESET TO DEFAULTS", on_row ? HILITE : TEXT)
			continue
		}
		a := action_at(row)
		cm.draw_text(r, CMD_X, y, cm.DEFAULT_LABELS[a], on_row ? HILITE : TEXT)
		for col in Column {
			cell := cell_rect(row, col)
			picked := on_row && e.col == col
			if picked {
				fill(r, cell, e.mode == .Capture && e.capture_col == col ? HILITE : PANEL)
			}
			text: string
			switch col {
			case .Key:
				text = key_text(e, a)
			case .Pad:
				text = pad_text(e, a)
			case .Label:
				text = label(e, a)
			}
			color := TEXT
			switch {
			case picked && e.mode == .Capture && e.capture_col == col:
				text, color = "...", BG
			case picked:
				color = HILITE
			case text == "-":
				color = DIM
			}
			cm.draw_text(r, cell.x + 2, y, text, color)
		}
	}

	list, n := buttons(e)
	for b in list[:n] {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.text)) / 2, b.rc.y + (b.rc.h - cm.GLYPH_H) / 2, b.text, b.enabled ? TEXT : DIM)
	}
	lines, k := help_lines(e)
	for line, i in lines[:k] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
