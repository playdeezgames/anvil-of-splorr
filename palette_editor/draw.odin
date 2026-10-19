package palette_editor

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
HILITE :: cm.Color{255, 220, 80}
WHITE :: cm.Color{255, 255, 255}

channel_color :: proc(ch: cm.Channel) -> cm.Color {
	switch ch {
	case .R:
		return {230, 70, 70}
	case .G:
		return {70, 210, 90}
	case .B:
		return {80, 120, 240}
	}
	return WHITE
}

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.mode == .Edit {
		return fmt.tprintf("EDITING   %s: DONE", label(e, .Red))
	}
	return fmt.tprintf("BROWSING   %s: EDIT", label(e, .Green))
}

MAX_HELP_LINES :: 5

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	if e.mode == .Edit {
		lines = {
			fmt.tprintf("%s/%s: -/+ 1", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s/%s: +/- 16", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: NEXT CHANNEL", l(e, .Green)),
			fmt.tprintf("%s: SAVE  %s: LOAD", l(e, .Blue), l(e, .Yellow)),
			"MOUSE: CLICK/DRAG/WHEEL",
		}
		return lines, 5
	}
	lines = {
		fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
		fmt.tprintf("%s: EDIT COLOR", l(e, .Green)),
		fmt.tprintf("%s: SAVE", l(e, .Blue)),
		fmt.tprintf("%s: LOAD", l(e, .Yellow)),
		"MOUSE: CLICK/DRAG/WHEEL",
	}
	return lines, 5
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
		cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
	}

	// Swatch grid; the selected one gets a 2px outline.
	for i in 0 ..< cm.PALETTE_SIZE {
		rc := swatch_rect(i)
		if i == e.selected {
			fill(r, Rect{rc.x - 2, rc.y - 2, rc.w + 4, rc.h + 4}, e.mode == .Edit ? WHITE : HILITE)
		}
		fill(r, rc, e.palette[i])
	}

	// Mode banner: a bright bar while editing, a quiet one while browsing.
	editing := e.mode == .Edit
	fill(r, BANNER, editing ? HILITE : PANEL)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), editing ? BG : TEXT)

	// Channel sliders.
	cur := e.palette[e.selected]
	for ch in cm.Channel {
		rc := slider_rect(ch)
		active := e.mode == .Edit && ch == e.channel
		label_color := active ? HILITE : TEXT
		label := ch == .R ? "R" : ch == .G ? "G" : "B"
		cm.draw_text(r, rc.x - 16, rc.y + 3, active ? ">" : " ", HILITE)
		cm.draw_text(r, rc.x - 10, rc.y + 3, label, label_color)
		fill(r, rc, PANEL)
		value := int(cur[ch])
		filled := (value * (rc.w - 1) + 127) / 255 + 1
		fill(r, Rect{rc.x, rc.y, filled, rc.h}, channel_color(ch))
		fill(r, Rect{rc.x + filled - 1, rc.y - 2, 1, rc.h + 4}, WHITE)
		buf: [4]u8
		cm.draw_text(r, rc.x + rc.w + 6, rc.y + 3, fmt.bprintf(buf[:], "% 3d", value), label_color)
	}

	// Preview and readouts.
	fill(r, Rect{PREVIEW.x - 1, PREVIEW.y - 1, PREVIEW.w + 2, PREVIEW.h + 2}, PANEL)
	fill(r, PREVIEW, cur)
	hex: [16]u8
	cm.draw_text(
		r,
		PREVIEW.x,
		READOUT_Y,
		fmt.bprintf(hex[:], "%02d #%02X%02X%02X%s", e.selected, cur.r, cur.g, cur.b, e.dirty ? " *" : ""),
		TEXT,
	)

	// Buttons.
	for b in ([2]struct {
			rc:    Rect,
			label: string,
		}{{SAVE_BUTTON, "SAVE"}, {LOAD_BUTTON, "LOAD"}}) {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.label)) / 2, b.rc.y + 4, b.label, TEXT)
	}

	// Help for the current mode.
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}

	cm.renderer_present(r)
}
