package character_type_editor

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
		return fmt.tprintf("DELETE TYPE?  %s: CONFIRM", label(e, .Green))
	}
	if e.mode == .Props && e.confirm_prop {
		return fmt.tprintf("DELETE PROPERTY?  %s: CONFIRM", label(e, .Green))
	}
	switch e.mode {
	case .Pick:
		return fmt.tprintf("TYPES   %s: SPRITE", label(e, .Green))
	case .Setup:
		return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
	case .Sprite:
		return fmt.tprintf("SPRITE   %s: USE", label(e, .Green))
	case .Tags:
		return fmt.tprintf("TAGS   %s: SET / CLEAR", label(e, .Green))
	case .Props:
		return fmt.tprintf("PROPERTIES   %s: VALUE", label(e, .Green))
	case .Text:
	}
	return ""
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE SETTING OR ACTION", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE THE VALUE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: RUN RENAME / NEW / DUP / DEL / PICK / TAGS / PROPS", l(e, .Green)),
			fmt.tprintf("%s: DONE", l(e, .Red)),
		}
		return lines, 4
	case .Sprite:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: USE THIS SPRITE  %s: CANCEL", l(e, .Green), l(e, .Red)),
			"MOUSE: CLICK A SPRITE; WHEEL SCROLLS",
			"",
		}
		return lines, 3
	case .Tags:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE A TAG", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: SET OR CLEAR IT FOR THIS TYPE", l(e, .Green)),
			fmt.tprintf("%s: BACK", l(e, .Red)),
			"MOUSE: CLICK A TAG; WHEEL SCROLLS",
		}
		return lines, 4
	case .Props:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE  %s/%s: VALUE -1 / +1", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: TYPE THE VALUE, OR ADD ON THE NEW ROW", l(e, .Green)),
			fmt.tprintf("%s: RENAME  %s: DELETE (%s CONFIRMS)", l(e, .Yellow), l(e, .Blue), l(e, .Green)),
			fmt.tprintf("%s: BACK", l(e, .Red)),
		}
		return lines, 4
	case .Pick, .Text:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: CHOOSE SPRITE  %s: SETUP", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: BACK TO THE WORLD", l(e, .Red)),
			"MOUSE: CLICK A TYPE, AGAIN FOR ITS SPRITE",
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

// A sprite drawn into `area` over a checkerboard or terrain backdrop (a dark red block if the
// sprite or its picture is missing).
draw_sprite_over :: proc(w: ^cm.World, r: ^cm.Renderer, area: Rect, sp: ^cm.Sprite, bg: ^cm.Terrain) {
	if bg != nil {
		if img := cm.world_terrain_image(w, bg); img != nil {
			cm.canvas_draw_thumbnail(r, area, img, &w.palette)
		} else {
			fill(r, area, UNSET)
		}
	} else {
		cm.canvas_draw_checker(r, area, CHECK_A, CHECK_B, max(2, area.w / 4))
	}
	if sp != nil {
		if img := cm.world_sprite_image(w, sp); img != nil {
			cm.canvas_draw_thumbnail(r, area, img, &w.palette, sp.transparent)
			return
		}
	}
	fill(r, area, UNSET)
}

// A character type drawn into `area` the same way.
draw_type :: proc(e: ^Editor, r: ^cm.Renderer, area: Rect, ct: ^cm.Character_Type) {
	draw_sprite_over(e.world, r, area, cm.world_char_type_sprite(e.world, ct), backdrop(e))
}

Button :: struct {
	rc:   Rect,
	text: string,
	row:  Maybe(Setup_Row),
}

buttons :: proc() -> [8]Button {
	return {
		{RENAME_BUTTON, "RENAME", .Rename},
		{NEW_BUTTON, "NEW", .New},
		{DUPLICATE_BUTTON, "DUP", .Duplicate},
		{DELETE_BUTTON, "DEL", .Delete},
		{PICK_BUTTON, "PICK SPR", .Choose},
		{TAGS_BUTTON, "TAGS", .Tags},
		{PROPS_BUTTON, "PROPS", .Props},
		{BACK_BUTTON, "BACK", nil},
	}
}

frame :: proc(r: ^cm.Renderer, c: Rect, color: cm.Color) {
	fill(r, Rect{c.x - 1, c.y - 1, c.w + 2, 1}, color)
	fill(r, Rect{c.x - 1, c.y + c.h, c.w + 2, 1}, color)
	fill(r, Rect{c.x - 1, c.y, 1, c.h}, color)
	fill(r, Rect{c.x + c.w, c.y, 1, c.h}, color)
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

	// The grid: types (Pick, Setup) or the sprites of the type's sprite set (Sprite).
	if e.mode == .Sprite && has_types(e) {
		si := cm.world_find_sprite_set(w, cm.name_str(&current_type(e).sprite_set))
		for row in 0 ..< GRID_ROWS {
			for col in 0 ..< GRID_COLS {
				index := (e.pick_scroll + row) * GRID_COLS + col
				rc := grid_cell_rect(col, row)
				if si >= 0 && index < w.sprite_sets[si].count {
					fill(r, rc, PANEL)
					draw_sprite_over(w, r, rc, &w.sprite_sets[si].sprites[index], backdrop(e))
				} else {
					fill(r, rc, EMPTY_SLOT)
				}
			}
		}
		if row := e.pick_sel / GRID_COLS - e.pick_scroll; row >= 0 && row < GRID_ROWS {
			frame(r, grid_cell_rect(e.pick_sel % GRID_COLS, row), HILITE)
		}
	} else {
		for row in 0 ..< GRID_ROWS {
			for col in 0 ..< GRID_COLS {
				index := (e.scroll + row) * GRID_COLS + col
				rc := grid_cell_rect(col, row)
				if index < type_count(e) {
					fill(r, rc, PANEL)
					draw_type(e, r, rc, &w.char_types[index])
				} else {
					fill(r, rc, EMPTY_SLOT)
				}
			}
		}
		if has_types(e) {
			if row := e.sel / GRID_COLS - e.scroll; row >= 0 && row < GRID_ROWS {
				frame(r, grid_cell_rect(e.sel % GRID_COLS, row), e.mode == .Pick ? HILITE : DIM)
			}
		}
	}

	// Banner, message or position, and the name.
	warning := e.confirm_delete
	fill(r, BANNER, warning ? WARN : (e.mode == .Pick ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (warning || e.mode != .Pick) ? BG : TEXT)
	switch {
	case e.note != "":
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	case has_types(e):
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("TYPE %d OF %d%s", e.sel + 1, type_count(e), e.dirty ? " *" : ""), TEXT)
	case:
		cm.draw_text(r, INFO_X, INFO_Y, e.dirty ? "NO TYPES YET *" : "NO TYPES YET", DIM)
	}
	ct: ^cm.Character_Type
	if has_types(e) {
		ct = current_type(e)
		cm.draw_text(r, INFO_X, NAME_Y, shown(type_name(e, e.sel)), HILITE)
		cm.draw_text(r, INFO_X, USES_Y, cm.tag_count_text(w, tag_view(e)), DIM)
		uses := cm.world_char_type_uses(w, type_name(e, e.sel))
		cm.draw_text(r, INFO_X + 90, USES_Y, uses == 0 ? "NO CHARACTERS" : fmt.tprintf("%d CHARACTER%s", uses, uses == 1 ? "" : "S"), DIM)
	}

	// The setting rows.
	row_color :: proc(e: ^Editor, row: Setup_Row) -> cm.Color {
		return e.mode == .Setup && e.row == row ? HILITE : TEXT
	}
	set_name, sprite_name := "", ""
	if ct != nil {
		set_name, sprite_name = cm.name_str(&ct.sprite_set), cm.name_str(&ct.sprite)
	}
	bg_set_name, bg_terrain_name := "NONE", "-"
	if e.bg_set >= 0 && e.bg_set < w.set_count {
		bg_set_name = cm.name_str(&w.sets[e.bg_set].name)
		if bg := backdrop(e); bg != nil {
			bg_terrain_name = cm.name_str(&bg.name)
		}
	}
	rows := [4]struct {
		minus, plus: Rect,
		row:         Setup_Row,
		name:        string,
		value:       string,
		warn:        bool,
	} {
		{SET_MINUS, SET_PLUS, .Set, "SET", set_name == "" ? "NOT SET" : set_name, ct != nil && set_name == ""},
		{SPRITE_MINUS, SPRITE_PLUS, .Sprite, "SPRITE", sprite_name == "" ? "NOT SET" : sprite_name, ct != nil && sprite_name == ""},
		{BG_SET_MINUS, BG_SET_PLUS, .Bg_Set, "BG SET", bg_set_name, false},
		{BG_TERRAIN_MINUS, BG_TERRAIN_PLUS, .Bg_Terrain, "BG TILE", bg_terrain_name, false},
	}
	for row in rows {
		for b in ([2]struct {
				rc:  Rect,
				txt: string,
			}{{row.minus, "-"}, {row.plus, "+"}}) {
			fill(r, b.rc, PANEL)
			cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + 3, b.txt, TEXT)
		}
		y := row.minus.y + 3
		if e.mode == .Setup && e.row == row.row {
			cm.draw_text(r, ROW_MARKER_X, y, ">", HILITE)
		}
		cm.draw_text(r, ROW_LABEL_X, y, row.name, row_color(e, row.row))
		cm.draw_text(r, ROW_VALUE_X, y, shown(row.value), row.warn ? WARN : row_color(e, row.row))
	}

	// A larger preview of the sprite over its backdrop.
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, EMPTY_SLOT)
	if ct != nil {
		draw_type(e, r, PREVIEW_INNER, ct)
	}

	// Buttons: the one whose Setup row is selected is lit.
	for btn in buttons() {
		lit := false
		if row, has := btn.row.?; has && e.mode == .Setup && e.row == row {
			lit = true
		}
		needs := btn.row != nil && btn.row != Setup_Row.New
		enabled := !needs || has_types(e)
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.text)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.text, lit ? BG : (enabled ? TEXT : DIM))
	}

	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}

// The Tags screen: the world's tags with a box for each (on or off for this type), the type and
// its picture beside the list (which ends at x 208).
draw_tags_screen :: proc(e: ^Editor, r: ^cm.Renderer) {
	fill(r, BANNER, HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), BG)
	cm.tag_list_draw(r, e.world, &e.tags, tag_view(e), true)
	cm.draw_text(r, INFO_X, INFO_Y, e.note != "" ? e.note : fmt.tprintf("TYPE %s", shown(type_name(e, e.sel))), e.note != "" ? WARN : TEXT)
	preview := Rect{214, 28, 24, 24}
	fill(r, preview, PANEL)
	fill(r, Rect{preview.x + 1, preview.y + 1, preview.w - 2, preview.h - 2}, EMPTY_SLOT)
	draw_type(e, r, Rect{preview.x + 1, preview.y + 1, preview.w - 2, preview.h - 2}, current_type(e))
	cm.draw_text(r, 214, 58, shown(type_name(e, e.sel)), HILITE)
	cm.draw_text(r, 214, 68, cm.tag_count_text(e.world, tag_view(e)), TEXT)
	fill(r, BACK_BUTTON, PANEL)
	cm.draw_text(r, BACK_BUTTON.x + (BACK_BUTTON.w - cm.text_width("BACK")) / 2, BACK_BUTTON.y + (BACK_BUTTON.h - cm.GLYPH_H) / 2, "BACK", TEXT)
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}

// The Props screen: the type's properties with their default values, then a NEW row; the type's
// picture sits beside the list.
draw_props_screen :: proc(e: ^Editor, r: ^cm.Renderer) {
	warning := e.confirm_prop
	fill(r, BANNER, warning ? WARN : HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), BG)
	ps := &current_type(e).props
	for i in 0 ..< props_rows(e) {
		rc := prop_row_rect(i)
		lit := i == e.prop_sel
		fill(r, rc, lit ? PANEL : BG)
		y := rc.y + (rc.h - cm.GLYPH_H) / 2
		if i < ps.count {
			name := cm.name_str(&ps.names[i])
			cm.draw_text(r, rc.x + 2, y, name[:min(len(name), 14)], lit ? HILITE : TEXT)
			cm.draw_text(r, rc.x + PROP_VALUE_X, y, fmt.tprintf("%d", ps.values[i]), lit ? HILITE : TEXT)
		} else {
			cm.draw_text(r, rc.x + 2, y, "NEW PROPERTY", lit ? HILITE : DIM)
		}
	}
	name := type_name(e, e.sel)
	cm.draw_text(r, INFO_X, INFO_Y, e.note != "" ? e.note : fmt.tprintf("TYPE %s  %d OF %d", name[:min(len(name), 10)], ps.count, cm.PROP_MAX), e.note != "" ? WARN : TEXT)
	on_property := e.prop_sel < ps.count
	buttons := [?]struct {
		rc:      Rect,
		text:    string,
		enabled: bool,
	}{{PROP_VALUE_BUTTON, "VALUE", true}, {PROP_NAME_BUTTON, "NAME", on_property}, {PROP_DELETE_BUTTON, "DEL", on_property}, {PROP_NEW_BUTTON, "NEW", ps.count < cm.PROP_MAX}, {PROP_MINUS, "-", on_property}, {PROP_PLUS, "+", on_property}, {BACK_BUTTON, "BACK", true}}
	for b in buttons {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.text)) / 2, b.rc.y + (b.rc.h - cm.GLYPH_H) / 2, b.text, b.enabled ? TEXT : DIM)
	}
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, EMPTY_SLOT)
	draw_type(e, r, PREVIEW_INNER, current_type(e))
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
