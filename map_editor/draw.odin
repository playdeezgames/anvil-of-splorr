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
	switch e.mode {
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
	switch e.mode {
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

buttons :: proc() -> [11]Button {
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
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	m := current_map(e)
	set := current_set(e)

	// The map: every visible cell shows its terrain's tile; the cursor is dimmed outside Draw and Rect.
	vw, vh := view_size(e)
	c := view_cell(e)
	fill(r, Rect{CANVAS.x, CANVAS.y, vw * c, vh * c}, BG)
	for y in e.vy ..< e.vy + vh {
		for x in e.vx ..< e.vx + vw {
			draw_terrain(e, r, cell_rect(e, x, y), set, int(m.cells[y][x]))
		}
	}
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
	fill(r, BANNER, e.mode == .Draw ? PANEL : HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), e.mode == .Draw ? TEXT : BG)
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
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
	rows := [5]struct {
		minus, plus: Rect,
		row:         Setup_Row,
		name:        string,
		value:       string,
	} {
		{TERRAIN_MINUS, TERRAIN_PLUS, .Terrain, "TERRAIN", fmt.tprintf("%d/%d %s", e.terrain + 1, terrain_count(e), terrain_name(e, e.terrain))},
		{COLUMNS_MINUS, COLUMNS_PLUS, .Columns, "COLUMNS", fmt.tprintf("%d", m.width)},
		{ROWS_MINUS, ROWS_PLUS, .Rows, "ROWS", fmt.tprintf("%d", m.height)},
		{SET_MINUS, SET_PLUS, .Set, "SET", cm.name_str(&m.set)},
		{ZOOM_MINUS, ZOOM_PLUS, .Zoom, "ZOOM", zoom_text},
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
		cm.draw_text(r, ROW_VALUE_X, y, shown(row.value), row_color(e, row.row))
	}

	// The picker: the page of 16 terrains holding the current one; the current one has a yellow frame.
	page := e.terrain / PICKER_PAGE * PICKER_PAGE
	for slot in 0 ..< PICKER_PAGE {
		rc := picker_rect(slot)
		if page + slot < terrain_count(e) {
			fill(r, rc, PANEL)
			draw_terrain(e, r, rc, set, page + slot)
			if page + slot == e.terrain {
				outline(r, rc, HILITE)
			}
			if set != nil && set.terrains[page + slot].solid {
				fill(r, Rect{rc.x + rc.w - 3, rc.y, 3, 3}, WARN) // a corner mark for solid terrain
			}
		} else {
			fill(r, rc, cm.Color{22, 22, 28})
		}
	}

	// Buttons: the one whose Setup row is selected is lit, and a tool is lit while armed.
	for btn in buttons() {
		lit := (btn.shape != .None && e.shape == btn.shape) || (btn.point != .None && e.point_tool == btn.point)
		if btn.rc != BACK_BUTTON && e.mode == .Setup && e.row == btn.row {
			lit = true
		}
		turn_blocked := m.width != m.height && (btn.rc == ROT_L_BUTTON || btn.rc == ROT_R_BUTTON)
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.txt)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.txt, lit ? BG : (turn_blocked ? DIM : TEXT))
	}

	// Help.
	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
