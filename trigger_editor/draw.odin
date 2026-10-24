package trigger_editor

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
		return fmt.tprintf("DELETE TRIGGER?  %s: CONFIRM", label(e, .Green))
	}
	switch e.mode {
	case .List:
		return fmt.tprintf("TRIGGERS   %s: RENAME", label(e, .Green))
	case .Setup:
		return fmt.tprintf("ACTIONS   %s: DONE", label(e, .Red))
	case .Tags:
		return fmt.tprintf("TAGS   %s: CYCLE", label(e, .Green))
	case .Props:
		return fmt.tprintf("PROPERTIES   %s: VALUE", label(e, .Green))
	case .Attach:
		return fmt.tprintf("PUT IT ON A FEATURE   %s: USE", label(e, .Green))
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
			fmt.tprintf("%s: RUN THE ACTION", l(e, .Green)),
			fmt.tprintf("%s: DONE", l(e, .Red)),
		}
		return lines, 4
	case .Tags:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE A TAG", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: INHERIT, THEN SET, THEN CLEAR", l(e, .Green)),
			fmt.tprintf("%s: BACK", l(e, .Red)),
			"MOUSE: CLICK A TAG; WHEEL SCROLLS",
		}
		return lines, 4
	case .Attach:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE A FEATURE", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: PUT THE TRIGGER ON IT  %s: CANCEL", l(e, .Green), l(e, .Red)),
			"MOUSE: CLICK A FEATURE, AGAIN TO USE IT",
			"",
		}
		return lines, 3
	case .Props:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE  %s/%s: VALUE -1 / +1", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: TYPE THE VALUE", l(e, .Green)),
			fmt.tprintf("%s: BACK TO THE TYPE'S DEFAULT", l(e, .Yellow)),
			fmt.tprintf("%s: BACK", l(e, .Red)),
		}
		return lines, 4
	case .List, .Text:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: RENAME  %s: ACTIONS", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: BACK TO THE WORLD", l(e, .Red)),
			"MOUSE: CLICK A TRIGGER, AGAIN TO RENAME; WHEEL SCROLLS",
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

// A trigger over a checkerboard (a dark red block if it has no picture), drawn by the same code
// the game and the map editor use.
draw_trigger :: proc(w: ^cm.World, r: ^cm.Renderer, area: Rect, c: ^cm.Trigger) {
	cm.canvas_draw_checker(r, area, CHECK_A, CHECK_B, max(2, area.w / 4))
	// (c points into w.triggers: its index is the pointer's distance from the table's start)
	ci := (int(uintptr(c)) - int(uintptr(&w.triggers[0]))) / size_of(cm.Trigger)
	cm.world_draw_trigger(r, w, ci, area, cm.SURFACE, UNSET)
}

Button :: struct {
	rc:   Rect,
	text: string,
	row:  Maybe(Setup_Row),
}

buttons :: proc() -> [9]Button {
	return {
		{RENAME_BUTTON, "RENAME", .Rename},
		{NEW_BUTTON, "NEW", .New},
		{DUPLICATE_BUTTON, "DUP", .Duplicate},
		{DELETE_BUTTON, "DEL", .Delete},
		{UNPLACE_BUTTON, "UNPLACE", .Unplace},
		{TAGS_BUTTON, "TAGS", .Tags},
		{PROPS_BUTTON, "PROPS", .Props},
		{ATTACH_BUTTON, "ATTACH", .Attach},
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
	if e.mode == .Tags {
		draw_tags_screen(e, r)
		return
	}
	if e.mode == .Props {
		draw_props_screen(e, r)
		return
	}
	warning := e.confirm_delete
	fill(r, BANNER, warning ? WARN : (e.mode == .List ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (warning || e.mode != .List) ? BG : TEXT)

	switch {
	case e.note != "":
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	case has_triggers(e):
		cm.draw_text(r, INFO_X, INFO_Y, info_text(e), TEXT)
	case:
		cm.draw_text(r, INFO_X, INFO_Y, e.dirty ? "NO TRIGGERS YET *" : "NO TRIGGERS YET", DIM)
	}

	// Choosing a feature to put the trigger on: the world's features, one per line.
	if e.mode == .Attach {
		for row in 0 ..< LIST_ROWS {
			index := e.attach_scroll + row
			if index >= w.feature_count {
				break
			}
			rc := list_row_rect(row)
			isel := index == e.attach_sel
			if isel {
				fill(r, rc, HILITE)
			}
			cm.draw_text(r, rc.x + 3, rc.y + 2, cm.name_str(&w.features[index].name), isel ? BG : TEXT)
			place := fmt.tprintf("%d TRIG", len(cm.world_triggers_on_feature(w, w.features[index].uuid)))
			cm.draw_text(r, LIST_X + LIST_W - cm.text_width(place) - 3, rc.y + 2, place, isel ? BG : DIM)
		}
	}
	// The list: name on the left, the place on the right.
	for row in 0 ..< (e.mode == .Attach ? 0 : LIST_ROWS) {
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
		cm.draw_text(r, rc.x + 3, rc.y + 2, trigger_name(e, index), on ? BG : TEXT)
		place := place_text(e, index)
		cm.draw_text(r, LIST_X + LIST_W - cm.text_width(place) - 3, rc.y + 2, place, on ? BG : DIM)
	}

	// The panel.
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, EMPTY_SLOT)
	if has_triggers(e) {
		c := current(e)
		draw_trigger(w, r, PREVIEW_INNER, c)
		cm.draw_text(r, ID_X, ID_Y, fmt.tprintf("ID %s", upper(cm.uuid_short(c.uuid))), DIM)
		type_name := cm.name_str(&c.type)
		cm.draw_text(r, PANEL_X, TYPE_LABEL_Y, "TYPE", e.mode == .Setup && e.row == .Type ? HILITE : TEXT)
		cm.draw_text(r, PANEL_X, TYPE_NAME_Y, shown(type_name), TEXT)
		cm.draw_text(r, PANEL_X, TAGS_Y, cm.tag_count_text(w, tag_view(e)), DIM)
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
		enabled := !needs || has_triggers(e)
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.text)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.text, lit ? BG : (enabled ? TEXT : DIM))
	}

	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}

// The place of trigger `index` for the list: "AT 3,4", "ON <feature>" or "NO PLACE".
place_text :: proc(e: ^Editor, index: int) -> string {
	t := &e.world.triggers[index]
	switch t.place {
	case .None:
	case .Cell:
		return fmt.tprintf("AT %d,%d", t.x, t.y)
	case .Feature:
		if fi := cm.world_find_feature(e.world, t.feature); fi >= 0 {
			name := cm.name_str(&e.world.features[fi].name)
			return fmt.tprintf("ON %s", name[:min(len(name), 14)])
		}
	}
	return "NO PLACE"
}

// The line under the banner for the selected trigger: its position in the list and where it is.
info_text :: proc(e: ^Editor) -> string {
	where_text := ""
	if t := &e.world.triggers[e.sel]; t.place == .Cell {
		name := cm.name_str(&t.map_name)
		where_text = fmt.tprintf("  MAP %s", name[:min(len(name), 14)])
	}
	return fmt.tprintf("%d OF %d%s%s", e.sel + 1, count(e), where_text, e.dirty ? "  *" : "")
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

// The Tags screen: the world's tags with a box (on or off) and where each value comes from (the
// trigger's own setting or its type's), with the trigger and its picture beside the list.
draw_tags_screen :: proc(e: ^Editor, r: ^cm.Renderer) {
	w := e.world
	fill(r, BANNER, HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), BG)
	cm.tag_list_draw(r, w, &e.tags, tag_view(e), true)
	cm.draw_text(r, INFO_X, INFO_Y, e.note != "" ? e.note : fmt.tprintf("TRIGGER %s", shown(trigger_name(e, e.sel))), e.note != "" ? WARN : TEXT)
	preview := Rect{214, 28, 24, 24}
	fill(r, preview, PANEL)
	fill(r, Rect{preview.x + 1, preview.y + 1, preview.w - 2, preview.h - 2}, EMPTY_SLOT)
	draw_trigger(w, r, Rect{preview.x + 1, preview.y + 1, preview.w - 2, preview.h - 2}, current(e))
	cm.draw_text(r, 214, 58, shown(trigger_name(e, e.sel)), HILITE)
	cm.draw_text(r, 214, 68, cm.tag_count_text(w, tag_view(e)), TEXT)
	fill(r, BACK_BUTTON, PANEL)
	cm.draw_text(r, BACK_BUTTON.x + (BACK_BUTTON.w - cm.text_width("BACK")) / 2, BACK_BUTTON.y + (BACK_BUTTON.h - cm.GLYPH_H) / 2, "BACK", TEXT)
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}

// The Props screen: the type's properties with this trigger's values; a value that differs from the
// default says so.
draw_props_screen :: proc(e: ^Editor, r: ^cm.Renderer) {
	fill(r, BANNER, HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), BG)
	name := trigger_name(e, e.sel)
	ps := type_props(e)
	cm.draw_text(r, PROP_INFO_X, PROP_INFO_Y, e.note != "" ? e.note : fmt.tprintf("TRIGGER %s", name[:min(len(name), 12)]), e.note != "" ? WARN : TEXT)
	if ps != nil {
		for i in 0 ..< ps.count {
			rc := prop_row_rect(i)
			lit := i == e.prop_sel
			fill(r, rc, lit ? PANEL : BG)
			y := rc.y + (rc.h - cm.GLYPH_H) / 2
			changed := current(e).overrides.mask & (1 << uint(i)) != 0
			pname := cm.name_str(&ps.names[i])
			cm.draw_text(r, rc.x + 2, y, pname[:min(len(pname), 14)], lit ? HILITE : TEXT)
			cm.draw_text(r, rc.x + PROP_VALUE_X, y, fmt.tprintf("%d", prop_value(e, i)), lit ? HILITE : TEXT)
			cm.draw_text(r, rc.x + PROP_VALUE_X + 56, y, changed ? "CHANGED" : "DEFAULT", changed ? HILITE : DIM)
		}
	}
	buttons := [?]struct {
		rc:   Rect,
		text: string,
	}{{PROP_VALUE_BUTTON, "VALUE"}, {PROP_DEFAULT_BUTTON, "DEFAULT"}, {PROP_MINUS, "-"}, {PROP_PLUS, "+"}, {BACK_BUTTON, "BACK"}}
	for b in buttons {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.text)) / 2, b.rc.y + (b.rc.h - cm.GLYPH_H) / 2, b.text, TEXT)
	}
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
