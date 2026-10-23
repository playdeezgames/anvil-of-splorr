package inventory_editor

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
		return fmt.tprintf("DELETE THE ENTRY?  %s: CONFIRM", label(e, .Green))
	}
	switch e.mode {
	case .List:
		return fmt.tprintf("ITEMS   %s: OPEN", label(e, .Green))
	case .Props:
		return fmt.tprintf("PROPERTIES   %s: VALUE", label(e, .Green))
	case .Types:
		return fmt.tprintf("ADD AN ITEM   %s: USE", label(e, .Green))
	case .Text:
	}
	return ""
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .List:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE  %s/%s: COUNT -1 / +1", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: PROPERTIES, OR ADD ON THE LAST ROW", l(e, .Green)),
			fmt.tprintf("%s: TYPE THE COUNT  %s: DELETE (%s CONFIRMS)", l(e, .Yellow), l(e, .Blue), l(e, .Green)),
			fmt.tprintf("%s: BACK", l(e, .Red)),
		}
		return lines, 4
	case .Props:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE  %s/%s: VALUE -1 / +1", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: TYPE THE VALUE", l(e, .Green)),
			fmt.tprintf("%s: BACK TO THE TYPE'S DEFAULT", l(e, .Yellow)),
			fmt.tprintf("%s: BACK", l(e, .Red)),
		}
		return lines, 4
	case .Types:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE A TYPE", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: PUT ONE IN  %s: CANCEL", l(e, .Green), l(e, .Red)),
			"MOUSE: CLICK A TYPE, AGAIN TO USE IT",
			"",
		}
		return lines, 3
	case .Text:
	}
	return lines, 0
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

// Names are cut to what a row can show.
shown :: proc(name: string) -> string {
	return len(name) > NAME_CHARS ? name[:NAME_CHARS] : name
}

// What the inventory belongs to, for the info line.
owner_text :: proc(e: ^Editor) -> string {
	w := e.world
	switch e.owner.kind {
	case .Cell:
		if e.owner.map_index >= 0 && e.owner.map_index < w.map_count {
			name := cm.name_str(&w.maps[e.owner.map_index].name)
			return fmt.tprintf("CELL %d,%d OF %s", e.owner.x, e.owner.y, name[:min(len(name), 16)])
		}
	case .Character:
		if i := cm.world_find_character(w, e.owner.uuid); i >= 0 {
			name := cm.name_str(&w.characters[i].name)
			return fmt.tprintf("CHARACTER %s", name[:min(len(name), 20)])
		}
	case .Feature:
		if i := cm.world_find_feature(w, e.owner.uuid); i >= 0 {
			name := cm.name_str(&w.features[i].name)
			return fmt.tprintf("FEATURE %s", name[:min(len(name), 20)])
		}
	}
	return "NOBODY"
}

// An item type's picture in a small square (a dark red block if it has none).
draw_icon :: proc(e: ^Editor, r: ^cm.Renderer, area: Rect, ti: int) {
	cm.canvas_draw_checker(r, area, CHECK_A, CHECK_B, max(2, area.w / 4))
	if ti >= 0 && ti < e.world.item_type_count {
		cm.world_draw_item_type(r, e.world, ti, area, area, UNSET)
	} else {
		fill(r, area, UNSET)
	}
}

Button :: struct {
	rc:      Rect,
	text:    string,
	enabled: bool,
}

// The buttons of the current mode; `enabled` says whether they would do anything now.
buttons :: proc(e: ^Editor) -> (list: [8]Button, n: int) {
	has := current_entry(e) != nil
	switch e.mode {
	case .List:
		list = {
			{MINUS, "-", has},
			{PLUS, "+", has},
			{COUNT_BUTTON, "COUNT", has},
			{PROPS_BUTTON, "PROPS", has},
			{NEW_BUTTON, "NEW", true},
			{DELETE_BUTTON, "DEL", has},
			{BACK_BUTTON, "BACK", true},
			{},
		}
		return list, 7
	case .Props:
		list = {{MINUS, "-", true}, {PLUS, "+", true}, {COUNT_BUTTON, "VALUE", true}, {PROPS_BUTTON, "DEFAULT", true}, {BACK_BUTTON, "BACK", true}, {}, {}, {}}
		return list, 5
	case .Types:
		list = {{NEW_BUTTON, "USE", true}, {BACK_BUTTON, "BACK", true}, {}, {}, {}, {}, {}, {}}
		return list, 2
	case .Text:
	}
	return list, 0
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	if e.mode == .Text {
		cm.text_entry_draw(&e.entry, r, e.labels)
		return
	}
	w := e.world
	cm.renderer_clear(r, BG)
	warning := e.confirm_delete
	fill(r, BANNER, warning ? WARN : HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), BG)

	en := current_entry(e)
	ti := en == nil ? -1 : entry_type(e, en)
	n := entry_count(e)
	info: string
	switch {
	case e.note != "":
		info = e.note
	case e.mode == .List:
		info = fmt.tprintf("%s  %d ENTR%s%s", owner_text(e), n, n == 1 ? "Y" : "IES", e.dirty ? " *" : "")
	case:
		info = owner_text(e)
	}
	cm.draw_text(r, INFO_X, INFO_Y, info, e.note != "" ? WARN : TEXT)

	switch e.mode {
	case .List:
		for row in 0 ..< LIST_ROWS {
			i := e.scroll + row
			if i >= list_rows(e) {
				break
			}
			rc := list_row_rect(row)
			lit := i == e.sel
			fill(r, rc, lit ? PANEL : BG)
			y := rc.y + (rc.h - cm.GLYPH_H) / 2
			if item := cm.world_owner_entry(w, e.owner, i); item != nil {
				draw_icon(e, r, Rect{rc.x, rc.y, ICON, ICON}, entry_type(e, item))
				cm.draw_text(r, rc.x + NAME_X, y, shown(cm.name_str(&item.type)), lit ? HILITE : TEXT)
				cm.draw_text(r, rc.x + VALUE_X, y, fmt.tprintf("X%d", item.count), lit ? HILITE : TEXT)
			} else {
				cm.draw_text(r, rc.x + 2, y, "NEW ITEM", lit ? HILITE : DIM)
			}
		}
	case .Props:
		if ti >= 0 {
			ps := &w.item_types[ti].props
			for row in 0 ..< LIST_ROWS {
				i := e.prop_scroll + row
				if i >= ps.count {
					break
				}
				rc := list_row_rect(row)
				lit := i == e.prop_sel
				fill(r, rc, lit ? PANEL : BG)
				y := rc.y + (rc.h - cm.GLYPH_H) / 2
				changed := en.overrides.mask & (1 << uint(i)) != 0
				cm.draw_text(r, rc.x + 2, y, shown(cm.name_str(&ps.names[i])), lit ? HILITE : TEXT)
				cm.draw_text(r, rc.x + VALUE_X, y, fmt.tprintf("%d", cm.prop_value(ps, &en.overrides, i)), lit ? HILITE : TEXT)
				cm.draw_text(r, rc.x + VALUE_X + 56, y, changed ? "CHANGED" : "DEFAULT", changed ? HILITE : DIM)
			}
		}
	case .Types:
		for row in 0 ..< LIST_ROWS {
			i := e.type_scroll + row
			if i >= w.item_type_count {
				break
			}
			rc := list_row_rect(row)
			lit := i == e.type_sel
			fill(r, rc, lit ? PANEL : BG)
			draw_icon(e, r, Rect{rc.x, rc.y, ICON, ICON}, i)
			cm.draw_text(r, rc.x + NAME_X, rc.y + (rc.h - cm.GLYPH_H) / 2, shown(cm.name_str(&w.item_types[i].name)), lit ? HILITE : TEXT)
		}
	case .Text:
	}

	// The picture of the chosen item, and its stack size.
	shown_type := e.mode == .Types ? e.type_sel : ti
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, EMPTY_SLOT)
	if shown_type >= 0 {
		draw_icon(e, r, PREVIEW_INNER, shown_type)
		cm.draw_text(r, PANEL_X, PREVIEW_FRAME.y + PREVIEW_FRAME.h + 4, fmt.tprintf("STACK %d", w.item_types[shown_type].max_stack), DIM)
	}

	list, count := buttons(e)
	for b in list[:count] {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.text)) / 2, b.rc.y + (b.rc.h - cm.GLYPH_H) / 2, b.text, b.enabled ? TEXT : DIM)
	}
	lines, k := help_lines(e)
	for line, i in lines[:k] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
