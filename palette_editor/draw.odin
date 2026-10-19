package palette_editor

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
HILITE :: cm.Color{255, 220, 80}
DIM :: cm.Color{120, 120, 134}
WHITE :: cm.Color{255, 255, 255}
PASTE_OUTLINE :: cm.Color{90, 200, 255}

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

outline_color :: proc(m: Mode) -> cm.Color {
	switch m {
	case .Browse:
		return HILITE
	case .Edit:
		return WHITE
	case .Paste:
		return PASTE_OUTLINE
	}
	return HILITE
}

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	switch e.mode {
	case .Edit:
		return fmt.tprintf("EDITING   %s: DONE", label(e, .Red))
	case .Paste:
		return fmt.tprintf("PASTING   %s: DONE", label(e, .Red))
	case .Browse:
	}
	return fmt.tprintf("BROWSING   %s: EDIT", label(e, .Green))
}

MAX_HELP_LINES :: 5

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	mouse := "MOUSE: CLICK/DRAG/WHEEL"
	save_load := fmt.tprintf("%s: SAVE  %s: LOAD", l(e, .Blue), l(e, .Yellow))
	move := fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right))
	switch e.mode {
	case .Edit:
		lines = {
			fmt.tprintf("%s/%s: -/+ 1", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s/%s: +/- 16", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: NEXT CHANNEL", l(e, .Green)),
			save_load,
			mouse,
		}
	case .Paste:
		lines = {move, fmt.tprintf("%s: PASTE COLOR", l(e, .Green)), fmt.tprintf("%s: DONE", l(e, .Red)), save_load, mouse}
	case .Browse:
		lines = {move, fmt.tprintf("%s: EDIT COLOR", l(e, .Green)), fmt.tprintf("%s: COPY COLOR", l(e, .Red)), save_load, mouse}
	}
	return lines, MAX_HELP_LINES
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
			fill(r, Rect{rc.x - 2, rc.y - 2, rc.w + 4, rc.h + 4}, outline_color(e.mode))
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

	// Clipboard chip: the copied colour, if any.
	if c, has := e.clipboard.?; has {
		fill(r, Rect{CLIP_CHIP.x - 1, CLIP_CHIP.y - 1, CLIP_CHIP.w + 2, CLIP_CHIP.h + 2}, PANEL)
		fill(r, CLIP_CHIP, c)
		cm.draw_text(r, CLIP_CHIP.x + CLIP_CHIP.w + 4, READOUT_Y, "CLIP", DIM)
	}

	// Buttons.
	for b in ([4]struct {
			rc:    Rect,
			label: string,
		}{{SAVE_BUTTON, "SAVE"}, {LOAD_BUTTON, "LOAD"}, {COPY_BUTTON, "COPY"}, {PASTE_BUTTON, "PASTE"}}) {
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
