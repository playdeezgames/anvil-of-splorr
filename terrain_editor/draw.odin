package terrain_editor

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

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.confirm_delete {
		return fmt.tprintf("DELETE TERRAIN?  %s: CONFIRM", label(e, .Green))
	}
	switch e.mode {
	case .Pick:
		return fmt.tprintf("TERRAINS   %s: PICTURE", label(e, .Green))
	case .Setup:
		return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
	case .Image:
		return fmt.tprintf("PICTURE   %s: USE", label(e, .Green))
	case .Tags:
		return fmt.tprintf("TAGS   %s: SET / CLEAR", label(e, .Green))
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
			fmt.tprintf("%s/%s: CHANGE TILESET / IMAGE", l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: RUN RENAME / NEW / DUP / DELETE / DEFAULT / TAGS", l(e, .Green)),
			fmt.tprintf("%s: DONE", l(e, .Red)),
		}
		return lines, 4
	case .Image:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: USE THIS IMAGE  %s: CANCEL", l(e, .Green), l(e, .Red)),
			"MOUSE: CLICK AN IMAGE; WHEEL SCROLLS",
			"",
		}
		return lines, 3
	case .Tags:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE A TAG", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: SET OR CLEAR IT FOR THIS TERRAIN", l(e, .Green)),
			fmt.tprintf("%s: BACK", l(e, .Red)),
			"MOUSE: CLICK A TAG; WHEEL SCROLLS",
		}
		return lines, 4
	case .Pick, .Text:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: CHOOSE PICTURE  %s: SETUP", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: BACK TO THE WORLD", l(e, .Red)),
			"MOUSE: CLICK A TERRAIN, AGAIN FOR ITS PICTURE",
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

draw_picture :: proc(e: ^Editor, r: ^cm.Renderer, area: Rect, t: ^cm.Terrain) {
	if img := cm.world_terrain_image(e.world, t); img != nil {
		cm.canvas_draw_thumbnail(r, area, img, &e.world.palette)
	} else {
		fill(r, area, UNSET)
	}
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
		{PICK_BUTTON, "PICK IMG", .Choose},
		{DEFAULT_BUTTON, "DEFAULT", .Default},
		{TAGS_BUTTON, "TAGS", .Tags},
		{BACK_BUTTON, "BACK", nil},
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	if e.mode == .Text {
		cm.text_entry_draw(&e.entry, r, e.labels)
		return
	}
	set := current_set(e)
	t := current_terrain(e)
	cm.renderer_clear(r, BG)
	if e.mode == .Tags {
		draw_tags_screen(e, r)
		return
	}

	// The grid: terrains (Pick, Setup) or the images of the terrain's tileset (Image).
	if e.mode == .Image {
		ti := cm.world_find_tileset(e.world, cm.name_str(&t.tileset))
		for row in 0 ..< GRID_ROWS {
			for col in 0 ..< GRID_COLS {
				index := (e.pick_scroll + row) * GRID_COLS + col
				rc := grid_cell_rect(col, row)
				if ti >= 0 && index < e.world.tilesets[ti].count {
					fill(r, rc, PANEL)
					cm.canvas_draw_thumbnail(r, rc, &e.world.tilesets[ti].images[index], &e.world.palette)
				} else {
					fill(r, rc, EMPTY_SLOT)
				}
			}
		}
		if row := e.pick_sel / GRID_COLS - e.pick_scroll; row >= 0 && row < GRID_ROWS {
			c := grid_cell_rect(e.pick_sel % GRID_COLS, row)
			frame(r, c, HILITE)
		}
	} else {
		for row in 0 ..< GRID_ROWS {
			for col in 0 ..< GRID_COLS {
				index := (e.scroll + row) * GRID_COLS + col
				rc := grid_cell_rect(col, row)
				if index < set.count {
					fill(r, rc, PANEL)
					draw_picture(e, r, rc, &set.terrains[index])
					if set.terrains[index].tags & cm.tag_bit(cm.TAG_SOLID) != 0 {
						fill(r, Rect{rc.x + rc.w - 3, rc.y, 3, 3}, WARN) // corner mark: solid
					}
					if index == set.default {
						fill(r, Rect{rc.x, rc.y, 3, 3}, HILITE) // corner mark: the default
					}
				} else {
					fill(r, rc, EMPTY_SLOT)
				}
			}
		}
		if row := e.sel / GRID_COLS - e.scroll; row >= 0 && row < GRID_ROWS {
			frame(r, grid_cell_rect(e.sel % GRID_COLS, row), e.mode == .Pick ? HILITE : DIM)
		}
	}

	// Banner, message or position, and the name.
	warning := e.confirm_delete
	fill(r, BANNER, warning ? WARN : (e.mode == .Pick ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (warning || e.mode != .Pick) ? BG : TEXT)
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	} else {
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("TERRAIN %d OF %d%s", e.sel + 1, set.count, e.dirty ? " *" : ""), TEXT)
	}
	cm.draw_text(r, INFO_X, NAME_Y, shown(terrain_name(e, e.sel)), HILITE)

	// The setting rows.
	row_color :: proc(e: ^Editor, row: Setup_Row) -> cm.Color {
		return e.mode == .Setup && e.row == row ? HILITE : TEXT
	}
	ts_name := cm.name_str(&t.tileset)
	img_name := cm.name_str(&t.image)
	rows := [2]struct {
		minus, plus: Rect,
		row:         Setup_Row,
		name:        string,
		value:       string,
		warn:        bool,
	} {
		{TILESET_MINUS, TILESET_PLUS, .Tileset, "TILESET", ts_name == "" ? "NOT SET" : ts_name, ts_name == ""},
		{IMAGE_MINUS, IMAGE_PLUS, .Image, "IMAGE", img_name == "" ? "NOT SET" : img_name, img_name == ""},
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
	// The terrain's tags: a readout (the TAGS button or its Setup row opens the list).
	cm.draw_text(r, ROW_LABEL_X, TAGS_ROW_Y + 3, "TAGS", row_color(e, .Tags))
	cm.draw_text(r, ROW_VALUE_X, TAGS_ROW_Y + 3, shown(cm.tag_names_text(e.world, tag_view(e))), row_color(e, .Tags))
	if e.mode == .Setup && e.row == .Tags {
		cm.draw_text(r, ROW_MARKER_X, TAGS_ROW_Y + 3, ">", HILITE)
	}
	fill(r, DEFAULT_SWITCH, PANEL)
	cm.draw_text(r, DEFAULT_SWITCH.x + (DEFAULT_SWITCH.w - cm.text_width("SET")) / 2, DEFAULT_SWITCH.y + 3, "SET", TEXT)
	if e.mode == .Setup && e.row == .Default {
		cm.draw_text(r, ROW_MARKER_X, DEFAULT_SWITCH.y + 3, ">", HILITE)
	}
	cm.draw_text(r, ROW_LABEL_X, DEFAULT_SWITCH.y + 3, "DEFAULT", row_color(e, .Default))
	cm.draw_text(r, ROW_VALUE_X, DEFAULT_SWITCH.y + 3, set.default == e.sel ? "YES" : "NO", row_color(e, .Default))

	// A larger preview of the picture.
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, EMPTY_SLOT)
	draw_picture(e, r, PREVIEW_INNER, t)

	// Buttons: the one whose Setup row is selected is lit.
	for btn in buttons() {
		lit := false
		if row, has := btn.row.?; has && e.mode == .Setup && e.row == row {
			lit = true
		}
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.text)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.text, lit ? BG : TEXT)
	}

	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}

frame :: proc(r: ^cm.Renderer, c: Rect, color: cm.Color) {
	fill(r, Rect{c.x - 1, c.y - 1, c.w + 2, 1}, color)
	fill(r, Rect{c.x - 1, c.y + c.h, c.w + 2, 1}, color)
	fill(r, Rect{c.x - 1, c.y, 1, c.h}, color)
	fill(r, Rect{c.x + c.w, c.y, 1, c.h}, color)
}

// The Tags screen: the world's tags with a box for each (on or off for this terrain), the terrain
// and its picture beside the list.
draw_tags_screen :: proc(e: ^Editor, r: ^cm.Renderer) {
	t := current_terrain(e)
	fill(r, BANNER, HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), BG)
	cm.tag_list_draw(r, e.world, &e.tags, tag_view(e), true)
	cm.draw_text(r, INFO_X, INFO_Y, e.note != "" ? e.note : fmt.tprintf("TERRAIN %s", shown(terrain_name(e, e.sel))), e.note != "" ? WARN : TEXT)
	// Beside the list (which ends at x 208): the terrain's picture, name and tag count.
	preview := Rect{214, 28, 24, 24}
	fill(r, preview, PANEL)
	fill(r, Rect{preview.x + 1, preview.y + 1, preview.w - 2, preview.h - 2}, EMPTY_SLOT)
	draw_picture(e, r, Rect{preview.x + 1, preview.y + 1, preview.w - 2, preview.h - 2}, t)
	cm.draw_text(r, 214, 58, shown(terrain_name(e, e.sel)), HILITE)
	cm.draw_text(r, 214, 68, cm.tag_count_text(e.world, tag_view(e)), TEXT)
	fill(r, BACK_BUTTON, PANEL)
	cm.draw_text(r, BACK_BUTTON.x + (BACK_BUTTON.w - cm.text_width("BACK")) / 2, BACK_BUTTON.y + (BACK_BUTTON.h - cm.GLYPH_H) / 2, "BACK", TEXT)
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
