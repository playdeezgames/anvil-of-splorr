package sprite_editor

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
		return fmt.tprintf("DELETE SPRITE?  %s: CONFIRM", label(e, .Green))
	}
	switch e.mode {
	case .Pick:
		return fmt.tprintf("SPRITES   %s: PICTURE", label(e, .Green))
	case .Setup:
		return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
	case .Image:
		return fmt.tprintf("PICTURE   %s: USE", label(e, .Green))
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
			fmt.tprintf("%s: RUN RENAME / NEW / DUP / DELETE / PICK", l(e, .Green)),
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
	case .Pick, .Text:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: CHOOSE PICTURE  %s: SETUP", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: BACK TO THE WORLD", l(e, .Red)),
			"MOUSE: CLICK A SPRITE, AGAIN FOR ITS PICTURE",
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

// A sprite drawn into `area` over the backdrop: the chosen terrain's tile, else a checkerboard.
// A sprite with no picture is a dark red block.
draw_sprite :: proc(e: ^Editor, r: ^cm.Renderer, area: Rect, sp: ^cm.Sprite) {
	if bg := backdrop(e); bg != nil {
		if img := cm.world_terrain_image(e.world, bg); img != nil {
			cm.canvas_draw_thumbnail(r, area, img, &e.world.palette)
		} else {
			fill(r, area, UNSET)
		}
	} else {
		cm.canvas_draw_checker(r, area, CHECK_A, CHECK_B, max(2, area.w / 4))
	}
	if img := cm.world_sprite_image(e.world, sp); img != nil {
		cm.canvas_draw_thumbnail(r, area, img, &e.world.palette, sp.transparent)
	} else {
		fill(r, area, UNSET)
	}
}

Button :: struct {
	rc:   Rect,
	text: string,
	row:  Maybe(Setup_Row),
}

buttons :: proc() -> [6]Button {
	return {
		{RENAME_BUTTON, "RENAME", .Rename},
		{NEW_BUTTON, "NEW", .New},
		{DUPLICATE_BUTTON, "DUP", .Duplicate},
		{DELETE_BUTTON, "DEL", .Delete},
		{PICK_BUTTON, "PICK IMG", .Choose},
		{BACK_BUTTON, "BACK", nil},
	}
}

frame :: proc(r: ^cm.Renderer, c: Rect, color: cm.Color) {
	fill(r, Rect{c.x - 1, c.y - 1, c.w + 2, 1}, color)
	fill(r, Rect{c.x - 1, c.y + c.h, c.w + 2, 1}, color)
	fill(r, Rect{c.x - 1, c.y, 1, c.h}, color)
	fill(r, Rect{c.x + c.w, c.y, 1, c.h}, color)
}

// The text of the transparent colour value.
transparent_text :: proc(sp: ^cm.Sprite) -> string {
	return sp.transparent < 0 ? "NONE" : fmt.tprintf("%d", sp.transparent)
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	if e.mode == .Text {
		cm.text_entry_draw(&e.entry, r, e.labels)
		return
	}
	set := current_set(e)
	cm.renderer_clear(r, BG)

	// The grid: sprites (Pick, Setup) or the images of the sprite's tileset (Image).
	if e.mode == .Image && has_sprites(e) {
		ti := cm.world_find_tileset(e.world, cm.name_str(&current_sprite(e).tileset))
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
			frame(r, grid_cell_rect(e.pick_sel % GRID_COLS, row), HILITE)
		}
	} else {
		for row in 0 ..< GRID_ROWS {
			for col in 0 ..< GRID_COLS {
				index := (e.scroll + row) * GRID_COLS + col
				rc := grid_cell_rect(col, row)
				if index < set.count {
					fill(r, rc, PANEL)
					draw_sprite(e, r, rc, &set.sprites[index])
				} else {
					fill(r, rc, EMPTY_SLOT)
				}
			}
		}
		if has_sprites(e) {
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
	case has_sprites(e):
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("SPRITE %d OF %d%s", e.sel + 1, set.count, e.dirty ? " *" : ""), TEXT)
	case:
		cm.draw_text(r, INFO_X, INFO_Y, e.dirty ? "NO SPRITES YET *" : "NO SPRITES YET", DIM)
	}
	if has_sprites(e) {
		cm.draw_text(r, INFO_X, NAME_Y, shown(sprite_name(e, e.sel)), HILITE)
	}

	// The setting rows.
	row_color :: proc(e: ^Editor, row: Setup_Row) -> cm.Color {
		return e.mode == .Setup && e.row == row ? HILITE : TEXT
	}
	ts_name, img_name, trans := "", "", "NONE"
	sp: ^cm.Sprite
	if has_sprites(e) {
		sp = current_sprite(e)
		ts_name, img_name, trans = cm.name_str(&sp.tileset), cm.name_str(&sp.image), transparent_text(sp)
	}
	bg_set_name, bg_terrain_name := "NONE", "-"
	if e.bg_set >= 0 && e.bg_set < e.world.set_count {
		bg_set_name = cm.name_str(&e.world.sets[e.bg_set].name)
		if bg := backdrop(e); bg != nil {
			bg_terrain_name = cm.name_str(&bg.name)
		}
	}
	rows := [5]struct {
		minus, plus: Rect,
		row:         Setup_Row,
		name:        string,
		value:       string,
		warn:        bool,
	} {
		{TILESET_MINUS, TILESET_PLUS, .Tileset, "TILESET", ts_name == "" ? "NOT SET" : ts_name, sp != nil && ts_name == ""},
		{IMAGE_MINUS, IMAGE_PLUS, .Image, "IMAGE", img_name == "" ? "NOT SET" : img_name, sp != nil && img_name == ""},
		{TRANSPARENT_MINUS, TRANSPARENT_PLUS, .Transparent, "TRANSP", trans, false},
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
	// A chip of the transparent colour next to its number.
	if sp != nil && sp.transparent >= 0 {
		chip := Rect{ROW_VALUE_X + cm.text_width(trans) + 4, TRANSPARENT_MINUS.y + 1, 8, 8}
		fill(r, Rect{chip.x - 1, chip.y - 1, chip.w + 2, chip.h + 2}, PANEL)
		fill(r, chip, e.world.palette[sp.transparent])
	}

	// A larger preview of the sprite over its backdrop.
	fill(r, PREVIEW_FRAME, PANEL)
	fill(r, PREVIEW_INNER, EMPTY_SLOT)
	if sp != nil {
		draw_sprite(e, r, PREVIEW_INNER, sp)
	}

	// Buttons: the one whose Setup row is selected is lit.
	for btn in buttons() {
		lit := false
		if row, has := btn.row.?; has && e.mode == .Setup && e.row == row {
			lit = true
		}
		needs := btn.row != nil && btn.row != Setup_Row.New
		enabled := !needs || has_sprites(e)
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.text)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.text, lit ? BG : (enabled ? TEXT : DIM))
	}

	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
