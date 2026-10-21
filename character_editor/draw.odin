package character_editor

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
DIM :: cm.Color{120, 120, 134}
HILITE :: cm.Color{255, 220, 80}
WARN :: cm.Color{235, 100, 90}
UNSET :: cm.Color{110, 40, 40}
EMPTY_SLOT :: cm.Color{22, 22, 28}
CHECK_A :: cm.Color{96, 96, 108}
CHECK_B :: cm.Color{72, 72, 84}

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.confirm_delete {
		return fmt.tprintf("DELETE CHARACTER?  %s: CONFIRM", label(e, .Green))
	}
	switch e.mode {
	case .List:
		return fmt.tprintf("CHARACTERS   %s: RENAME", label(e, .Green))
	case .Setup:
		return fmt.tprintf("ACTIONS   %s: DONE", label(e, .Red))
	case .Text:
	}
	return ""
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE AN ACTION", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE THE TYPE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: RUN RENAME / NEW / DUP / DELETE / PLAYER / UNPLACE", l(e, .Green)),
			fmt.tprintf("%s: DONE", l(e, .Red)),
		}
		return lines, 4
	case .List, .Text:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: RENAME  %s: ACTIONS", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: BACK TO THE WORLD", l(e, .Red)),
			"MOUSE: CLICK A CHARACTER, AGAIN TO RENAME; WHEEL SCROLLS",
		}
		return lines, 4
	}
	return lines, 0
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

shown :: proc(name: string) -> string {
	return len(name) > VALUE_CHARS ? name[:VALUE_CHARS] : name
}

// The sprite a character draws (through its type), or nil.
character_sprite :: proc(w: ^cm.World, c: ^cm.Character) -> ^cm.Sprite {
	ti := cm.world_find_char_type(w, cm.name_str(&c.type))
	return ti >= 0 ? cm.world_char_type_sprite(w, &w.char_types[ti]) : nil
}

// A character over a checkerboard (a dark red block if it has no picture).
draw_character :: proc(w: ^cm.World, r: ^cm.Renderer, area: Rect, c: ^cm.Character) {
	cm.canvas_draw_checker(r, area, CHECK_A, CHECK_B, max(2, area.w / 4))
	if sp := character_sprite(w, c); sp != nil {
		if img := cm.world_sprite_image(w, sp); img != nil {
			cm.canvas_draw_thumbnail(r, area, img, &w.palette, sp.transparent)
			return
		}
	}
	fill(r, area, UNSET)
}

Button :: struct {
	rc:   Rect,
	text: string,
	row:  Maybe(Setup_Row),
}

buttons :: proc() -> [7]Button {
	return {
		{RENAME_BUTTON, "RENAME", .Rename},
		{NEW_BUTTON, "NEW", .New},
		{DUPLICATE_BUTTON, "DUP", .Duplicate},
		{DELETE_BUTTON, "DEL", .Delete},
		{PLAYER_BUTTON, "PLAYER", .Player},
		{UNPLACE_BUTTON, "UNPLACE", .Unplace},
		{BACK_BUTTON, "BACK", nil},
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	if e.mode == .Text {
		cm.text_entry_draw(&e.entry, r, e.labels)
		return
	}
	w := e.world
	cm.renderer_clear(r, BG)
	warning := e.confirm_delete
	fill(r, BANNER, warning ? WARN : (e.mode == .List ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (warning || e.mode != .List) ? BG : TEXT)

	switch {
	case e.note != "":
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	case has_characters(e):
		cm.draw_text(r, INFO_X, INFO_Y, info_text(e), TEXT)
	case:
		cm.draw_text(r, INFO_X, INFO_Y, e.dirty ? "NO CHARACTERS YET *" : "NO CHARACTERS YET", DIM)
	}

	// The list: name on the left (a yellow square marks the player), the place on the right.
	for row in 0 ..< LIST_ROWS {
		index := e.scroll + row
		if index >= count(e) {
			break
		}
		rc := list_row_rect(row)
		isel := index == e.sel
		if isel {
			fill(r, rc, e.mode == .List ? HILITE : PANEL)
		}
		on := isel && e.mode == .List
		if is_player(e, index) {
			fill(r, Rect{rc.x + 2, rc.y + 2, 4, 6}, on ? BG : HILITE)
		}
		cm.draw_text(r, rc.x + 9, rc.y + 2, character_name(e, index), on ? BG : TEXT)
		place := place_text(e, index)
		cm.draw_text(r, LIST_X + LIST_W - cm.text_width(place) - 3, rc.y + 2, place, on ? BG : DIM)
	}

	// The panel.
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, EMPTY_SLOT)
	if has_characters(e) {
		c := current(e)
		draw_character(w, r, PREVIEW_INNER, c)
		cm.draw_text(r, ID_X, ID_Y, fmt.tprintf("ID %s", upper(cm.uuid_short(c.uuid))), DIM)
		status := is_player(e, e.sel) ? "THE PLAYER" : ""
		cm.draw_text(r, STATUS_X, STATUS_Y, status, HILITE)
		type_name := cm.name_str(&c.type)
		cm.draw_text(r, PANEL_X, TYPE_LABEL_Y, "TYPE", e.mode == .Setup && e.row == .Type ? HILITE : TEXT)
		cm.draw_text(r, PANEL_X, TYPE_NAME_Y, shown(type_name), TEXT)
		if e.mode == .Setup && e.row == .Type {
			cm.draw_text(r, PANEL_X - 6, TYPE_LABEL_Y, ">", HILITE)
		}
	}
	for b in ([2]struct {
			rc:  Rect,
			txt: string,
		}{{TYPE_MINUS, "-"}, {TYPE_PLUS, "+"}}) {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + 3, b.txt, TEXT)
	}
	for btn in buttons() {
		lit := false
		if row, has := btn.row.?; has && e.mode == .Setup && e.row == row {
			lit = true
		}
		needs := btn.row != nil && btn.row != Setup_Row.New
		enabled := !needs || has_characters(e)
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.text)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.text, lit ? BG : (enabled ? TEXT : DIM))
	}

	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}

// The place of character `index` for the list: "AT 3,4" or "OFF MAP".
place_text :: proc(e: ^Editor, index: int) -> string {
	if _, x, y, ok := cm.world_character_location(e.world, e.world.characters[index].uuid); ok {
		return fmt.tprintf("AT %d,%d", x, y)
	}
	return "OFF MAP"
}

// The line under the banner for the selected character: its position in the list and its map.
info_text :: proc(e: ^Editor) -> string {
	map_text := ""
	if mi, _, _, ok := cm.world_character_location(e.world, e.world.characters[e.sel].uuid); ok {
		map_text = fmt.tprintf("  MAP %s", cm.name_str(&e.world.maps[mi].name))
	}
	return fmt.tprintf("%d OF %d%s%s", e.sel + 1, count(e), map_text, e.dirty ? "  *" : "")
}

// The id in capitals (the UI font has no lower case).
upper :: proc(s: string) -> string {
	b := make([]u8, len(s), context.temp_allocator)
	for i in 0 ..< len(s) {
		c := s[i]
		b[i] = c >= 'a' && c <= 'z' ? c - 32 : c
	}
	return string(b)
}
