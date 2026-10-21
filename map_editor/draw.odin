package map_editor

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
DIM :: cm.Color{120, 120, 134}
HILITE :: cm.Color{255, 220, 80}
WARN :: cm.Color{235, 100, 90}
UNSET :: cm.Color{110, 40, 40} // a cell whose terrain has no image

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.layer == .Characters {
		if e.confirm_delete {
			return fmt.tprintf("DELETE IT?  %s: CONFIRM", label(e, .Green))
		}
		if e.mode == .Setup {
			return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
		}
		return fmt.tprintf("CHARACTERS   %s: PLACE", label(e, .Green))
	}
	switch e.mode {
	case .Text:
		return ""
	case .Tags:
		return fmt.tprintf("TAGS   %s: CYCLE", label(e, .Green))

	case .Rect:
		return e.shape == .Fill ? "FILL: PLACE 2ND CORNER" : "FRAME: PLACE 2ND CORNER"
	case .Setup:
		return fmt.tprintf("SETUP   %s: DONE", label(e, .Red))
	case .Draw:
		if e.shape != .None { 	// a rectangle tool armed with the mouse
			return fmt.tprintf("DRAG A %s  %s: CANCEL", e.shape == .Fill ? "FILL" : "FRAME", label(e, .Red))
		}
		switch e.point_tool { 	// a click tool armed with the mouse
		case .Flood_Fill:
			return fmt.tprintf("CLICK TO FLOOD  %s: CANCEL", label(e, .Red))
		case .Replace:
			return fmt.tprintf("CLICK TO REPLACE  %s: CANCEL", label(e, .Red))
		case .None:
		}
	}
	return fmt.tprintf("PAINTING   %s: PAINT", label(e, .Green))
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	if e.mode == .Tags {
		what := e.layer == .Characters ? "THIS CHARACTER" : "THIS CELL"
		lines = {
			fmt.tprintf("%s/%s: CHOOSE A TAG", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: INHERIT, THEN SET, THEN CLEAR FOR %s", l(e, .Green), what),
			fmt.tprintf("%s: BACK", l(e, .Red)),
			"MOUSE: CLICK A TAG; WHEEL SCROLLS",
		}
		return lines, 4
	}
	if e.layer == .Characters {
		if e.mode == .Setup {
			lines = {
				fmt.tprintf("%s/%s: CHOOSE A ROW  %s: NEXT 16", l(e, .Up), l(e, .Down), l(e, .Blue)),
				fmt.tprintf("%s/%s: CHANGE CHARACTER / TYPE / PLAYER", l(e, .Left), l(e, .Right)),
				fmt.tprintf("%s: RUN RENAME / NEW / UNPLACE / DELETE / LAYER", l(e, .Green)),
				fmt.tprintf("%s: DONE", l(e, .Red)),
			}
			return lines, 4
		}
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: PLACE OR PICK  %s: SETUP", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: NEXT 16 CHARACTERS  %s: BACK", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK PLACES OR PICKS; RIGHT CLICK PICKS",
		}
		return lines, 4
	}
	switch e.mode {
	case .Text, .Tags:
		return lines, 0
	case .Rect:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE CORNER", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: DRAW IT  %s: CANCEL", l(e, .Green), l(e, .Red)),
			"MOUSE: CLICK THE OPPOSITE CORNER",
			"",
		}
		return lines, 3
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE SETTING OR ACTION", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s/%s: CHANGE VALUE  %s: NEXT 16 TERRAINS", l(e, .Left), l(e, .Right), l(e, .Blue)),
			fmt.tprintf("%s: RUN A TRANSFORM OR TOOL", l(e, .Green)),
			fmt.tprintf("%s: DONE", l(e, .Red)),
		}
	case .Draw:
		lines = {
			fmt.tprintf("%s/%s/%s/%s: MOVE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: PAINT  %s: SETUP / TERRAIN", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: NEXT 16 TERRAINS  %s: BACK", l(e, .Blue), l(e, .Red)),
			"MOUSE: PAINT, RIGHT CLICK PICKS, WHEEL ZOOMS",
		}
	}
	return lines, MAX_HELP_LINES
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

outline :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	fill(r, Rect{rc.x - 1, rc.y - 1, rc.w + 2, 1}, c)
	fill(r, Rect{rc.x - 1, rc.y + rc.h, rc.w + 2, 1}, c)
	fill(r, Rect{rc.x - 1, rc.y, 1, rc.h}, c)
	fill(r, Rect{rc.x + rc.w, rc.y, 1, rc.h}, c)
}

// A name cut to what a value column can show.
shown :: proc(name: string) -> string {
	return len(name) > VALUE_CHARS ? name[:VALUE_CHARS] : name
}

// One terrain drawn into `area`: its tile image, or a dark red block while it has none.
draw_terrain :: proc(e: ^Editor, r: ^cm.Renderer, area: Rect, set: ^cm.Terrain_Set, terrain: int) {
	if set != nil && terrain < set.count {
		if img := cm.world_terrain_image(e.world, &set.terrains[terrain]); img != nil {
			cm.canvas_draw_thumbnail(r, area, img, &e.world.palette)
			return
		}
	}
	fill(r, area, UNSET)
}

// Marks the cells the rectangle being placed will cover with a small yellow square in each.
draw_shape_preview :: proc(e: ^Editor, r: ^cm.Renderer) {
	m := current_map(e)
	c := view_cell(e)
	k := max(1, c / 2)
	for y in min(e.ay, e.cy) ..= max(e.ay, e.cy) {
		for x in min(e.ax, e.cx) ..= max(e.ax, e.cx) {
			if cell_visible(e, x, y) && cm.shape_has_cell(e.shape, e.ax, e.ay, e.cx, e.cy, x, y) {
				cr := cell_rect(e, x, y)
				fill(r, Rect{cr.x + (c - k) / 2, cr.y + (c - k) / 2, k, k}, HILITE)
			}
		}
	}
}

Button :: struct {
	rc:    Rect,
	txt:   string,
	row:   Setup_Row,
	shape: cm.Shape,
	point: Point_Tool,
}

buttons :: proc() -> [12]Button {
	return {
		{FLIP_H_BUTTON, "FLIP H", .Flip_Horizontal, .None, .None},
		{FLIP_V_BUTTON, "FLIP V", .Flip_Vertical, .None, .None},
		{ROT_L_BUTTON, "ROT L", .Rotate_Left, .None, .None},
		{ROT_R_BUTTON, "ROT R", .Rotate_Right, .None, .None},
		{ROT_180_BUTTON, "ROT 180", .Rotate_180, .None, .None},
		{FRAME_BUTTON, "FRAME", .Frame, .Frame, .None},
		{FILL_BUTTON, "FILL", .Fill, .Fill, .None},
		{FLOOD_BUTTON, "FLOOD", .Flood_Fill, .None, .Flood_Fill},
		{REPLACE_BUTTON, "REPLACE", .Replace, .None, .Replace},
		{CLEAR_BUTTON, "CLEAR", .Clear, .None, .None},
		{BACK_BUTTON, "BACK", .Terrain, .None, .None},
		{LAYER_BUTTON, "LAYER", .Layer, .None, .None},
	}
}

// The Characters layer's buttons.
char_buttons :: proc() -> [7]Button {
	return {
		{CHAR_NEW_BUTTON, "NEW", .Char_New, .None, .None},
		{CHAR_UNPLACE_BUTTON, "UNPLACE", .Char_Unplace, .None, .None},
		{CHAR_DELETE_BUTTON, "DEL", .Char_Delete, .None, .None},
		{CHAR_PLAYER_BUTTON, "PLAYER", .Char_Player, .None, .None},
		{CHAR_RENAME_BUTTON, "RENAME", .Char_Rename, .None, .None},
		{BACK_BUTTON, "BACK", .Terrain, .None, .None},
		{LAYER_BUTTON, "LAYER", .Layer, .None, .None},
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	if e.mode == .Text {
		cm.text_entry_draw(&e.entry, r, e.labels)
		return
	}
	if e.mode == .Tags {
		draw_tags_screen(e, r)
		return
	}
	cm.renderer_clear(r, BG)
	m := current_map(e)
	set := current_set(e)

	// The map: every visible cell shows its terrain's tile; the cursor is dimmed outside Draw and Rect.
	vw, vh := view_size(e)
	c := view_cell(e)
	fill(r, Rect{CANVAS.x, CANVAS.y, vw * c, vh * c}, BG)
	window := cm.World_Draw {
		map_index   = e.index,
		col         = e.vx,
		row         = e.vy,
		cols        = vw,
		rows        = vh,
		x           = CANVAS.x,
		y           = CANVAS.y,
		cell_w      = c,
		cell_h      = c,
		clip        = Rect{CANVAS.x, CANVAS.y, vw * c, vh * c},
		missing     = UNSET,
		mark_player = true,
		player_mark = HILITE,
	}
	cm.world_draw_terrain(r, e.world, window) // the same code the game draws its maps with
	cm.world_draw_authored_characters(r, e.world, window)
	if cell_visible(e, e.cx, e.cy) {
		outline(r, cell_rect(e, e.cx, e.cy), e.mode == .Setup ? DIM : HILITE)
	}
	for bar in Bar {
		if !bar_shown(e, bar) {
			continue
		}
		track := bar == .Horizontal ? HBAR : VBAR
		fill(r, track, PANEL)
		if bar == .Horizontal {
			start, size := bar_thumb(m.width, vw, e.vx, track.w)
			fill(r, Rect{track.x + start, track.y, size, track.h}, e.bar_drag == Bar.Horizontal ? HILITE : TEXT)
		} else {
			start, size := bar_thumb(m.height, vh, e.vy, track.h)
			fill(r, Rect{track.x, track.y + start, track.w, size}, e.bar_drag == Bar.Vertical ? HILITE : TEXT)
		}
	}
	if e.mode == .Rect {
		draw_shape_preview(e, r)
	}

	// Banner and readout.
	warning := e.confirm_delete
	fill(r, BANNER, warning ? WARN : (e.mode == .Draw ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (warning || e.mode != .Draw) ? BG : TEXT)
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	} else if e.layer == .Characters {
		who := "-"
		if i := cm.world_character_at(e.world, e.index, e.cx, e.cy); i >= 0 {
			who = character_name(e, i)
		}
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("CURSOR: %d,%d  %s%s", e.cx, e.cy, who[:min(len(who), 18)], e.dirty ? " *" : ""), TEXT)
	} else {
		under := int(cm.map_get(m, e.cx, e.cy))
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("CURSOR: %d,%d  %s%s", e.cx, e.cy, shown(terrain_name(e, under))[:min(len(terrain_name(e, under)), 18)], e.dirty ? " *" : ""), TEXT)
	}

	// Setting rows.
	row_color :: proc(e: ^Editor, row: Setup_Row) -> cm.Color {
		return e.mode == .Setup && e.row == row ? HILITE : TEXT
	}
	sizes := ZOOM_SIZES
	zoom_text := e.zoom == 0 ? "FIT" : fmt.tprintf("%d PX", sizes[e.zoom])
	Panel_Row :: struct {
		minus, plus: Rect,
		row:         Setup_Row,
		name:        string,
		value:       string,
		buttons:     bool, // false: a readout with no - and + buttons
	}
	rows: [5]Panel_Row
	if e.layer == .Characters {
		cur_name, cur_type, player := "NONE", "-", "NO"
		if has_characters(e) {
			c := current_character(e)
			cur_name = fmt.tprintf("%d/%d %s", clamp(e.cur_char, 0, char_count(e) - 1) + 1, char_count(e), character_name(e, clamp(e.cur_char, 0, char_count(e) - 1)))
			cur_type = cm.name_str(&c.type)
			player = e.world.player == c.uuid ? "YES" : "NO"
		}
		at := has_characters(e) ? char_place_text(e, clamp(e.cur_char, 0, char_count(e) - 1)) : "-"
		rows = {
			{TERRAIN_MINUS, TERRAIN_PLUS, .Character, "CHAR", cur_name, true},
			{COLUMNS_MINUS, COLUMNS_PLUS, .Char_Type, "TYPE", cur_type, true},
			{ROWS_MINUS, ROWS_PLUS, .Char_Player, "PLAYER", player, true},
			{SET_MINUS, SET_PLUS, .Layer, "PLACE", at, false},
			{ZOOM_MINUS, ZOOM_PLUS, .Zoom, "ZOOM", zoom_text, true},
		}
	} else {
		rows = {
			{TERRAIN_MINUS, TERRAIN_PLUS, .Terrain, "TERRAIN", fmt.tprintf("%d/%d %s", e.terrain + 1, terrain_count(e), terrain_name(e, e.terrain)), true},
			{COLUMNS_MINUS, COLUMNS_PLUS, .Columns, "COLUMNS", fmt.tprintf("%d", m.width), true},
			{ROWS_MINUS, ROWS_PLUS, .Rows, "ROWS", fmt.tprintf("%d", m.height), true},
			{SET_MINUS, SET_PLUS, .Set, "SET", cm.name_str(&m.set), true},
			{ZOOM_MINUS, ZOOM_PLUS, .Zoom, "ZOOM", zoom_text, true},
		}
	}
	// The TAGS button sits right of the zoom value, in both layers.
	fill(r, TAGS_BUTTON, PANEL)
	cm.draw_text(r, TAGS_BUTTON.x + (TAGS_BUTTON.w - cm.text_width("TAGS")) / 2, TAGS_BUTTON.y + 3, "TAGS", e.mode == .Setup && e.row == .Tags ? HILITE : TEXT)
	for row in rows {
		for b in ([2]struct {
				rc:  Rect,
				txt: string,
			}{{row.minus, "-"}, {row.plus, "+"}}) {
			if !row.buttons {
				break
			}
			fill(r, b.rc, PANEL)
			cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + 3, b.txt, TEXT)
		}
		y := row.minus.y + 3
		if e.mode == .Setup && e.row == row.row && row.buttons {
			cm.draw_text(r, ROW_MARKER_X, y, ">", HILITE)
		}
		cm.draw_text(r, ROW_LABEL_X, y, row.name, row_color(e, row.row))
		cm.draw_text(r, ROW_VALUE_X, y, shown(row.value), row_color(e, row.row))
	}

	// The picker: the page of 16 terrains (or characters) holding the current one, which is framed.
	if e.layer == .Characters {
		draw_character_picker(e, r)
	} else {
		page := e.terrain / PICKER_PAGE * PICKER_PAGE
		for slot in 0 ..< PICKER_PAGE {
			rc := picker_rect(slot)
			if page + slot < terrain_count(e) {
				fill(r, rc, PANEL)
				draw_terrain(e, r, rc, set, page + slot)
				if page + slot == e.terrain {
					outline(r, rc, HILITE)
				}
				if set != nil && set.terrains[page + slot].tags & cm.tag_bit(cm.TAG_SOLID) != 0 {
					fill(r, Rect{rc.x + rc.w - 3, rc.y, 3, 3}, WARN) // a corner mark for solid terrain
				}
			} else {
				fill(r, rc, cm.Color{22, 22, 28})
			}
		}
	}

	// Buttons: the one whose Setup row is selected is lit, and a tool is lit while armed.
	draw_buttons :: proc(e: ^Editor, r: ^cm.Renderer, list: []Button) {
		m := current_map(e)
		for btn in list {
			lit := (btn.shape != .None && e.shape == btn.shape) || (btn.point != .None && e.point_tool == btn.point)
			if btn.rc != BACK_BUTTON && e.mode == .Setup && e.row == btn.row {
				lit = true
			}
			turn_blocked := m.width != m.height && (btn.rc == ROT_L_BUTTON || btn.rc == ROT_R_BUTTON)
			needs_char := e.layer == .Characters && !has_characters(e) && btn.row != .Char_New && btn.rc != BACK_BUTTON && btn.rc != LAYER_BUTTON
			fill(r, btn.rc, lit ? HILITE : PANEL)
			cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.txt)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.txt, lit ? BG : ((turn_blocked || needs_char) ? DIM : TEXT))
		}
	}
	if e.layer == .Characters {
		cb := char_buttons()
		draw_buttons(e, r, cb[:])
	} else {
		tb := buttons()
		draw_buttons(e, r, tb[:])
	}

	// Help.
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}

// One character's sprite in `area`; with `backdrop` a checkerboard goes behind it first. A character
// whose type has no picture is a dark red block.
draw_character_sprite :: proc(e: ^Editor, r: ^cm.Renderer, area: Rect, ci: int, backdrop: bool) {
	if backdrop {
		cm.canvas_draw_checker(r, area, cm.Color{96, 96, 108}, cm.Color{72, 72, 84}, max(2, area.w / 4))
	}
	cm.world_draw_character(r, e.world, ci, area, cm.SURFACE, UNSET)
}

// The picker of the Characters layer: the page holding the current character.
draw_character_picker :: proc(e: ^Editor, r: ^cm.Renderer) {
	page := clamp(e.cur_char, 0, max(char_count(e) - 1, 0)) / CHAR_PAGE * CHAR_PAGE
	for slot in 0 ..< PICKER_PAGE {
		rc := picker_rect(slot)
		i := page + slot
		if i >= char_count(e) {
			fill(r, rc, cm.Color{22, 22, 28})
			continue
		}
		fill(r, rc, PANEL)
		draw_character_sprite(e, r, rc, i, true)
		if i == e.cur_char {
			outline(r, rc, HILITE)
		}
		if e.world.player == e.world.characters[i].uuid {
			fill(r, Rect{rc.x, rc.y, 3, 3}, HILITE)
		}
	}
}

// The Tags screen: the world's tags with a box (on or off) and where each value comes from (the
// thing's own setting or its type's), with what is being tagged beside the list.
draw_tags_screen :: proc(e: ^Editor, r: ^cm.Renderer) {
	w := e.world
	cm.renderer_clear(r, BG)
	fill(r, BANNER, HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), BG)
	cm.tag_list_draw(r, w, &e.tags, tag_view(e), true)
	preview := Rect{214, 28, 24, 24}
	fill(r, preview, PANEL)
	inner := Rect{preview.x + 1, preview.y + 1, preview.w - 2, preview.h - 2}
	fill(r, inner, cm.Color{22, 22, 28})
	title, name := "", ""
	if e.layer == .Characters {
		if has_characters(e) {
			c := current_character(e)
			draw_character_sprite(e, r, inner, clamp(e.cur_char, 0, char_count(e) - 1), true)
			title, name = "CHARACTER", cm.name_str(&c.name)
		}
	} else {
		m := current_map(e)
		draw_terrain(e, r, inner, current_set(e), int(cm.map_get(m, e.cx, e.cy)))
		title, name = fmt.tprintf("CELL %d,%d", e.cx, e.cy), terrain_name(e, int(cm.map_get(m, e.cx, e.cy)))
	}
	cm.draw_text(r, INFO_X, INFO_Y, e.note != "" ? e.note : title, e.note != "" ? WARN : TEXT)
	cm.draw_text(r, 214, 58, shown(name), HILITE)
	cm.draw_text(r, 214, 68, cm.tag_count_text(w, tag_view(e)), TEXT)
	fill(r, BACK_BUTTON, PANEL)
	cm.draw_text(r, BACK_BUTTON.x + (BACK_BUTTON.w - cm.text_width("BACK")) / 2, BACK_BUTTON.y + (BACK_BUTTON.h - cm.GLYPH_H) / 2, "BACK", TEXT)
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
