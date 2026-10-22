package common

// Drawing a world's maps and characters on a Renderer. The map editor, the game and the play mode all
// call these, so a tile looks the same everywhere. Everything here works in whole logical pixels of
// the 320 x 180 surface and clips instead of failing: cells outside the map, windows bigger than the
// map and windows hanging off the surface are drawn only where they are real and visible.
//
// A map is drawn through a `World_Draw`: which cells (a window), where on the surface the window's
// first cell goes, and how many pixels a cell takes. The game uses a whole-number zoom of the tile
// (`world_zoom_draw`); the editor fits the whole map in its canvas, scaling tiles to any size
// (down-sampling when a cell is smaller than the tile).

// How a window of a map goes on the surface.
World_Draw :: struct {
	map_index:        int,
	col, row:         int, // the first cell of the window (may be negative: those cells simply are not drawn)
	cols, rows:       int, // the window's size in cells (may exceed the map)
	x, y:             int, // the surface pixel of the top-left corner of cell (col, row)
	cell_w, cell_h:   int, // pixels per cell
	clip:             Rect, // nothing is drawn outside this rect (the whole surface by default)
	missing:          Color, // drawn for a cell or character whose picture is not set
	mark_player:      bool, // put a small mark in the corner of the player's cell
	player_mark:      Color,
}

SURFACE :: Rect{0, 0, SCREEN_W, SCREEN_H}
MISSING_PICTURE :: Color{110, 40, 40}

// A window at a whole-number zoom of the tiles: `zoom` surface pixels per tile pixel. The window is
// cols x rows cells starting at (col, row), with that cell's corner at pixel (x, y).
world_zoom_draw :: proc(w: ^World, map_index, col, row, cols, rows, x, y, zoom: int) -> World_Draw {
	z := max(zoom, 1)
	return World_Draw {
		map_index = map_index,
		col = col,
		row = row,
		cols = cols,
		rows = rows,
		x = x,
		y = y,
		cell_w = w.tile_w * z,
		cell_h = w.tile_h * z,
		clip = SURFACE,
		missing = MISSING_PICTURE,
		player_mark = Color{255, 220, 80},
	}
}

// The surface rectangle of a cell (it may be outside the surface or the map).
world_cell_rect :: proc(d: World_Draw, cx, cy: int) -> Rect {
	return Rect{d.x + (cx - d.col) * d.cell_w, d.y + (cy - d.row) * d.cell_h, d.cell_w, d.cell_h}
}

// The map cell under a surface pixel, if it is inside the window and the map.
world_cell_at :: proc(w: ^World, d: World_Draw, px, py: int) -> (cx, cy: int, ok: bool) {
	if d.cell_w <= 0 || d.cell_h <= 0 || d.map_index < 0 || d.map_index >= w.map_count {
		return 0, 0, false
	}
	dx, dy := px - d.x, py - d.y
	if dx < 0 || dy < 0 {
		return 0, 0, false
	}
	cx, cy = d.col + dx / d.cell_w, d.row + dy / d.cell_h
	m := &w.maps[d.map_index]
	return cx, cy, cx < d.col + d.cols && cy < d.row + d.rows && cx >= 0 && cy >= 0 && cx < m.width && cy < m.height
}

// --- Clipping ----------------------------------------------------------------------------------

Clip_State :: struct {
	inner: ^Renderer,
	clip:  Rect,
}

// A Renderer that passes everything to `inner` but only inside `clip`. `state` must outlive it.
clipped_renderer :: proc(state: ^Clip_State, inner: ^Renderer, clip: Rect) -> Renderer {
	state^ = {inner, clip}
	return Renderer {
		data = state,
		clear = proc(d: rawptr, c: Color) {
			s := (^Clip_State)(d)
			s.inner.clear(s.inner.data, c)
		},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: Color) {
			s := (^Clip_State)(d)
			if cut, ok := rect_intersect(Rect{x, y, w, h}, s.clip); ok {
				renderer_fill_rect(s.inner, cut.x, cut.y, cut.w, cut.h, c)
			}
		},
		present = proc(d: rawptr) {
			s := (^Clip_State)(d)
			s.inner.present(s.inner.data)
		},
	}
}

// --- Terrain -----------------------------------------------------------------------------------

// Draws a window of a map's terrain: every cell that is in the window, in the map and (at least
// partly) inside the clip shows its terrain's tile image, scaled to the cell. A cell whose terrain
// has no picture shows `d.missing`. Cells and parts outside the clip are not drawn.
world_draw_terrain :: proc(r: ^Renderer, w: ^World, d: World_Draw) {
	if d.cell_w <= 0 || d.cell_h <= 0 || d.map_index < 0 || d.map_index >= w.map_count {
		return
	}
	m := &w.maps[d.map_index]
	set := world_map_set(w, d.map_index)
	if set == nil {
		return
	}
	cs: Clip_State
	cr := clipped_renderer(&cs, r, d.clip)
	// Only the cells that can reach the clip (a huge window costs nothing for what it hides).
	c0 := max(d.col, 0, d.col + (d.clip.x - d.x) / d.cell_w)
	r0 := max(d.row, 0, d.row + (d.clip.y - d.y) / d.cell_h)
	c1 := min(d.col + d.cols, m.width, d.col + (d.clip.x + d.clip.w - d.x + d.cell_w - 1) / d.cell_w)
	r1 := min(d.row + d.rows, m.height, d.row + (d.clip.y + d.clip.h - d.y + d.cell_h - 1) / d.cell_h)
	for cy in r0 ..< r1 {
		for cx in c0 ..< c1 {
			area := world_cell_rect(d, cx, cy)
			if _, visible := rect_intersect(area, d.clip); !visible {
				continue
			}
			ti := int(m.cells[cy][cx])
			if img := ti < set.count ? world_terrain_image(w, &set.terrains[ti]) : nil; img != nil {
				canvas_draw_thumbnail(&cr, area, img, &w.palette)
			} else {
				renderer_fill_rect(&cr, area.x, area.y, area.w, area.h, d.missing)
			}
		}
	}
}

// --- Characters --------------------------------------------------------------------------------

// The sprite a character draws (through its type), or nil.
world_character_sprite :: proc(w: ^World, ci: int) -> ^Sprite {
	if ci < 0 || ci >= w.character_count {
		return nil
	}
	ti := world_find_char_type(w, name_str(&w.characters[ci].type))
	return ti >= 0 ? world_char_type_sprite(w, &w.char_types[ti]) : nil
}

// Draws character `ci` into `area`: its sprite's tile image scaled to the area without the sprite's
// transparent colour, so whatever is already there shows through. A character with no picture is a
// block of `missing`. Nothing is drawn outside `clip`.
world_draw_character :: proc(r: ^Renderer, w: ^World, ci: int, area: Rect, clip: Rect, missing: Color) {
	if area.w <= 0 || area.h <= 0 || ci < 0 || ci >= w.character_count {
		return
	}
	cs: Clip_State
	cr := clipped_renderer(&cs, r, clip)
	if sp := world_character_sprite(w, ci); sp != nil {
		if img := world_sprite_image(w, sp); img != nil {
			canvas_draw_thumbnail(&cr, area, img, &w.palette, sp.transparent)
			return
		}
	}
	renderer_fill_rect(&cr, area.x, area.y, area.w, area.h, missing)
}

// Draws the features the map itself holds, over the terrain and under the characters: each in its cell,
// in the window and the clip.
world_draw_authored_features :: proc(r: ^Renderer, w: ^World, d: World_Draw) {
	if d.cell_w <= 0 || d.cell_h <= 0 || d.map_index < 0 || d.map_index >= w.map_count {
		return
	}
	m := &w.maps[d.map_index]
	cs: Clip_State
	cr := clipped_renderer(&cs, r, d.clip)
	for cy in max(d.row, 0) ..< min(d.row + d.rows, m.height) {
		for cx in max(d.col, 0) ..< min(d.col + d.cols, m.width) {
			u := m.features[cy][cx]
			if uuid_is_none(u) {
				continue
			}
			area := world_cell_rect(d, cx, cy)
			if _, visible := rect_intersect(area, d.clip); !visible {
				continue
			}
			world_draw_feature(&cr, w, world_find_feature(w, u), area, d.clip, d.missing)
		}
	}
}

// The sprite a feature draws (through its type), or nil.
world_feature_sprite :: proc(w: ^World, fi: int) -> ^Sprite {
	if fi < 0 || fi >= w.feature_count {
		return nil
	}
	ti := world_find_feature_type(w, name_str(&w.features[fi].type))
	return ti >= 0 ? world_feature_type_sprite(w, &w.feature_types[ti]) : nil
}

// Draws feature `fi` into `area`, like `world_draw_character`: its sprite's tile image without the
// sprite's transparent colour, or a block of `missing` when it has no picture. Nothing is drawn
// outside `clip`.
world_draw_feature :: proc(r: ^Renderer, w: ^World, fi: int, area: Rect, clip: Rect, missing: Color) {
	if area.w <= 0 || area.h <= 0 || fi < 0 || fi >= w.feature_count {
		return
	}
	cs: Clip_State
	cr := clipped_renderer(&cs, r, clip)
	if sp := world_feature_sprite(w, fi); sp != nil {
		if img := world_sprite_image(w, sp); img != nil {
			canvas_draw_thumbnail(&cr, area, img, &w.palette, sp.transparent)
			return
		}
	}
	renderer_fill_rect(&cr, area.x, area.y, area.w, area.h, missing)
}

// Draws the characters the map itself holds (where the authors put them), over the terrain: each in
// its cell, in the window and the clip. With `mark_player` the player's cell gets a small square in
// its top-left corner.
world_draw_authored_characters :: proc(r: ^Renderer, w: ^World, d: World_Draw) {
	if d.cell_w <= 0 || d.cell_h <= 0 || d.map_index < 0 || d.map_index >= w.map_count {
		return
	}
	m := &w.maps[d.map_index]
	cs: Clip_State
	cr := clipped_renderer(&cs, r, d.clip)
	for cy in max(d.row, 0) ..< min(d.row + d.rows, m.height) {
		for cx in max(d.col, 0) ..< min(d.col + d.cols, m.width) {
			u := m.characters[cy][cx]
			if uuid_is_none(u) {
				continue
			}
			area := world_cell_rect(d, cx, cy)
			if _, visible := rect_intersect(area, d.clip); !visible {
				continue
			}
			ci := world_find_character(w, u)
			if ci < 0 {
				continue
			}
			world_draw_character(&cr, w, ci, area, d.clip, d.missing)
			if d.mark_player && u == w.player && area.w >= 4 {
				k := max(2, area.w / 4)
				renderer_fill_rect(&cr, area.x, area.y, k, k, d.player_mark)
			}
		}
	}
}
