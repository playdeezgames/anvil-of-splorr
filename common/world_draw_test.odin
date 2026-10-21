#+build !js
package common

import "core:testing"

// The character world (tile size 4; map "m" 3 x 2; terrain rock at 1,0 and 2,1 draws image "y" with
// a colour-9 dot at 2,1; Goo, a slime whose sprite draws image "x" with colour 0 transparent, is at
// 1,0) drawn through a recording renderer.
draw_log :: proc() -> (log: ^Thumb_Log, r: Renderer) {
	log = new(Thumb_Log)
	r = thumb_renderer(log)
	return
}

free_log :: proc(log: ^Thumb_Log) {
	delete(log.rects)
	delete(log.colors)
	free(log)
}

inside :: proc(rc, area: Rect) -> bool {
	return rc.x >= area.x && rc.y >= area.y && rc.x + rc.w <= area.x + area.w && rc.y + rc.h <= area.y + area.h
}

count_colour :: proc(log: ^Thumb_Log, c: Color) -> (n: int) {
	for k in log.colors {
		if k == c {
			n += 1
		}
	}
	return
}

@(test)
test_a_zoom_window_has_whole_number_cells_and_finds_cells_from_pixels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	d := world_zoom_draw(w, 0, 0, 0, 3, 2, 10, 20, 2)
	testing.expect(t, d.cell_w == 8 && d.cell_h == 8 && d.clip == SURFACE)
	testing.expect_value(t, world_cell_rect(d, 1, 1), Rect{18, 28, 8, 8})
	testing.expect_value(t, world_cell_rect(d, -1, 0), Rect{2, 20, 8, 8}) // outside the window: just geometry
	for cy in 0 ..< 2 {
		for cx in 0 ..< 3 {
			rc := world_cell_rect(d, cx, cy)
			for p in ([][2]int{{0, 0}, {7, 7}, {3, 4}} ) {
				x, y, ok := world_cell_at(w, d, rc.x + p.x, rc.y + p.y)
				testing.expectf(t, ok && x == cx && y == cy, "cell (%d,%d) point %v", cx, cy, p)
			}
		}
	}
	_, _, ok := world_cell_at(w, d, 9, 20)
	testing.expect(t, !ok)
	_, _, ok = world_cell_at(w, d, 10 + 3 * 8, 20) // right of the map
	testing.expect(t, !ok)
	_, _, ok = world_cell_at(w, d, 10, 20 + 2 * 8) // below it
	testing.expect(t, !ok)
	small := world_zoom_draw(w, 0, 1, 0, 1, 1, 0, 0, 3) // a one-cell window of the second column
	x, y, ok2 := world_cell_at(w, small, 5, 5)
	testing.expect(t, ok2 && x == 1 && y == 0)
	_, _, ok = world_cell_at(w, small, 13, 5) // the next cell is outside the window
	testing.expect(t, !ok)
	testing.expect_value(t, world_zoom_draw(w, 0, 0, 0, 1, 1, 0, 0, 0).cell_w, 4) // a zoom below 1 is 1
	// Non-square tiles.
	cm_set := w
	world_set_tile_size(cm_set, 6, 3)
	flat := world_zoom_draw(w, 0, 0, 0, 1, 1, 0, 0, 3)
	testing.expect(t, flat.cell_w == 18 && flat.cell_h == 9)
}

@(test)
test_terrain_tiles_are_drawn_at_their_cells_and_scale :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	log, r := draw_log()
	defer free_log(log)
	d := world_zoom_draw(w, 0, 0, 0, 3, 2, 10, 20, 2)
	world_draw_terrain(&r, w, d)
	area := Rect{10, 20, 3 * 8, 2 * 8}
	for rc in log.rects {
		testing.expect(t, inside(rc, area))
	}
	// The rock's dot (colour 9 at 2,1 of image "y") shows at 2x in both rock cells.
	dot1 := Rect{10 + 8 + 2 * 2, 20 + 1 * 2, 2, 2} // cell (1,0)
	dot2 := Rect{10 + 2 * 8 + 2 * 2, 20 + 8 + 1 * 2, 2, 2} // cell (2,1)
	found1, found2 := false, false
	for rc, i in log.rects {
		found1 ||= rc == dot1 && log.colors[i] == w.palette[9]
		found2 ||= rc == dot2 && log.colors[i] == w.palette[9]
	}
	testing.expect(t, found1 && found2 && count_colour(log, w.palette[9]) == 2)
	// Every cell is covered: the rects' areas add up to the window.
	total := 0
	for rc in log.rects {
		total += rc.w * rc.h
	}
	testing.expect_value(t, total, area.w * area.h)
	// The same at zoom 1 is half the size, drawn from the same code.
	clear(&log.rects)
	clear(&log.colors)
	world_draw_terrain(&r, w, world_zoom_draw(w, 0, 0, 0, 3, 2, 0, 0, 1))
	total = 0
	for rc in log.rects {
		total += rc.w * rc.h
	}
	testing.expect_value(t, total, 3 * 4 * 2 * 4)
}

@(test)
test_terrain_is_clipped_not_an_error :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	log, r := draw_log()
	defer free_log(log)
	// Hanging off the top left of the surface.
	d := world_zoom_draw(w, 0, 0, 0, 3, 2, -10, -5, 2)
	world_draw_terrain(&r, w, d)
	testing.expect(t, len(log.rects) > 0)
	for rc in log.rects {
		testing.expect(t, inside(rc, SURFACE))
	}
	// Hanging off the bottom right.
	clear(&log.rects)
	clear(&log.colors)
	world_draw_terrain(&r, w, world_zoom_draw(w, 0, 0, 0, 3, 2, 310, 175, 2))
	testing.expect(t, len(log.rects) > 0)
	for rc in log.rects {
		testing.expect(t, inside(rc, SURFACE))
	}
	// Completely off the surface: nothing.
	clear(&log.rects)
	world_draw_terrain(&r, w, world_zoom_draw(w, 0, 0, 0, 3, 2, 400, 0, 2))
	world_draw_terrain(&r, w, world_zoom_draw(w, 0, 0, 0, 3, 2, -100, 0, 2))
	world_draw_terrain(&r, w, world_zoom_draw(w, 0, 0, 0, 3, 2, 0, 300, 2))
	testing.expect_value(t, len(log.rects), 0)
	// A smaller clip: only inside it, and cells that miss it cost nothing.
	clip := Rect{18, 28, 8, 8} // exactly cell (1,1) of a window at (10,20) zoom 2
	d = world_zoom_draw(w, 0, 0, 0, 3, 2, 10, 20, 2)
	d.clip = clip
	clear(&log.rects)
	clear(&log.colors)
	world_draw_terrain(&r, w, d)
	testing.expect(t, len(log.rects) > 0)
	for rc in log.rects {
		testing.expect(t, inside(rc, clip))
	}
	total := 0
	for rc in log.rects {
		total += rc.w * rc.h
	}
	testing.expect_value(t, total, 64) // that one cell
	// A window bigger than the map draws only the map (3 x 2 cells), wherever the window starts.
	big := world_zoom_draw(w, 0, -4, -4, 20, 20, 0, 0, 1)
	// (cell (0,0) is 4 cells right of and below the window's first cell: at pixel (16,16))
	clear(&log.rects)
	clear(&log.colors)
	world_draw_terrain(&r, w, big)
	total = 0
	for rc in log.rects {
		testing.expect(t, inside(rc, Rect{16, 16, 12, 8}))
		total += rc.w * rc.h
	}
	testing.expect_value(t, total, 12 * 8)
	// Degenerate input: nothing, and no crash.
	clear(&log.rects)
	world_draw_terrain(&r, w, World_Draw{map_index = 0, cols = 3, rows = 2})
	world_draw_terrain(&r, w, world_zoom_draw(w, 9, 0, 0, 3, 2, 0, 0, 1))
	world_draw_terrain(&r, w, world_zoom_draw(w, 0, 0, 0, 0, 0, 0, 0, 1))
	testing.expect_value(t, len(log.rects), 0)
}

@(test)
test_a_cell_with_no_picture_shows_the_missing_colour :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	log, r := draw_log()
	defer free_log(log)
	w.sets[0].terrains[1].tileset, w.sets[0].terrains[1].image = {}, {} // rock has no picture now
	d := world_zoom_draw(w, 0, 0, 0, 3, 2, 0, 0, 2)
	d.missing = Color{1, 2, 3}
	world_draw_terrain(&r, w, d)
	testing.expect_value(t, count_colour(log, Color{1, 2, 3}), 2) // two rock cells
	for rc, i in log.rects {
		if log.colors[i] == (Color{1, 2, 3}) {
			testing.expect(t, rc.w == 8 && rc.h == 8)
		}
	}
}

@(test)
test_characters_are_drawn_without_their_transparent_colour :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world()
	defer free(w)
	log, r := draw_log()
	defer free_log(log)
	w.palette[0] = {1, 2, 3} // the slime's sprite makes colour 0 transparent: it must never be drawn
	image4_set(&w.tilesets[0].images[0], 1, 1, 5) // the slime's picture: one dot on colour 0
	area := Rect{40, 50, 8, 8}
	world_draw_character(&r, w, 0, area, SURFACE, Color{9, 9, 9})
	testing.expect(t, len(log.rects) > 0 && count_colour(log, Color{1, 2, 3}) == 0)
	for rc in log.rects {
		testing.expect(t, inside(rc, area))
	}
	// The bat has no transparent colour: its background (colour 0) is drawn.
	clear(&log.rects)
	clear(&log.colors)
	world_draw_character(&r, w, 1, area, SURFACE, Color{9, 9, 9})
	testing.expect(t, count_colour(log, Color{1, 2, 3}) > 0)
	// Clipped to part of the area.
	clear(&log.rects)
	clear(&log.colors)
	clip := Rect{44, 50, 4, 4}
	world_draw_character(&r, w, 1, area, clip, Color{9, 9, 9})
	for rc in log.rects {
		testing.expect(t, inside(rc, clip))
	}
	// No such character, an empty area, or no picture.
	clear(&log.rects)
	world_draw_character(&r, w, 9, area, SURFACE, Color{9, 9, 9})
	world_draw_character(&r, w, -1, area, SURFACE, Color{9, 9, 9})
	world_draw_character(&r, w, 0, Rect{0, 0, 0, 8}, SURFACE, Color{9, 9, 9})
	testing.expect_value(t, len(log.rects), 0)
	w.char_types[0].sprite_set, w.char_types[0].sprite = {}, {}
	clear(&log.rects)
	clear(&log.colors)
	world_draw_character(&r, w, 0, area, SURFACE, Color{9, 9, 9})
	testing.expect(t, len(log.rects) == 1 && log.rects[0] == area && log.colors[0] == (Color{9, 9, 9}))
	testing.expect(t, world_character_sprite(w, 0) == nil && world_character_sprite(w, 1) != nil && world_character_sprite(w, 7) == nil)
}

@(test)
test_the_maps_own_characters_are_drawn_in_their_cells_with_a_player_mark :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := character_world() // Goo at 1,0
	defer free(w)
	log, r := draw_log()
	defer free_log(log)
	image4_set(&w.tilesets[0].images[0], 1, 1, 5) // Goo's picture: one dot on the transparent colour
	d := world_zoom_draw(w, 0, 0, 0, 3, 2, 10, 20, 2)
	world_draw_authored_characters(&r, w, d)
	cell := world_cell_rect(d, 1, 0)
	testing.expect(t, len(log.rects) > 0)
	for rc in log.rects {
		testing.expect(t, inside(rc, cell)) // nothing outside Goo's cell
	}
	n := len(log.rects)
	// A window that does not include Goo's cell draws nothing.
	clear(&log.rects)
	clear(&log.colors)
	world_draw_authored_characters(&r, w, world_zoom_draw(w, 0, 0, 1, 3, 1, 10, 20, 2))
	world_draw_authored_characters(&r, w, world_zoom_draw(w, 0, 2, 0, 1, 2, 10, 20, 2))
	testing.expect_value(t, len(log.rects), 0)
	// Clipped away: nothing.
	d.clip = Rect{200, 100, 10, 10}
	world_draw_authored_characters(&r, w, d)
	testing.expect_value(t, len(log.rects), 0)
	// The player's mark only with mark_player, and only for the player.
	d.clip = SURFACE
	d.player_mark = Color{200, 100, 50}
	world_draw_authored_characters(&r, w, d)
	testing.expect_value(t, count_colour(log, Color{200, 100, 50}), 0)
	world_set_player(w, w.characters[0].uuid)
	d.mark_player = true
	clear(&log.rects)
	clear(&log.colors)
	world_draw_authored_characters(&r, w, d)
	testing.expect_value(t, count_colour(log, Color{200, 100, 50}), 1)
	testing.expect_value(t, len(log.rects), n + 1)
	mark := log.rects[len(log.rects) - 1]
	testing.expect(t, mark.x == cell.x && mark.y == cell.y && mark.w == 2 && mark.h == 2)
	world_set_player(w, w.characters[1].uuid) // another character is the player: Goo has no mark
	clear(&log.rects)
	clear(&log.colors)
	world_draw_authored_characters(&r, w, d)
	testing.expect_value(t, count_colour(log, Color{200, 100, 50}), 0)
	// A character with a missing uuid in the table is skipped, not an error.
	w.maps[0].characters[1][1] = Uuid{0 = 99}
	world_draw_authored_characters(&r, w, d)
}

@(test)
test_the_clipping_renderer_cuts_and_forwards :: proc(t: ^testing.T) {
	log, r := draw_log()
	defer free_log(log)
	cs: Clip_State
	cr := clipped_renderer(&cs, &r, Rect{10, 10, 20, 20})
	renderer_fill_rect(&cr, 0, 0, 15, 15, Color{1, 1, 1}) // overlaps the corner
	renderer_fill_rect(&cr, 12, 12, 4, 4, Color{2, 2, 2}) // inside
	renderer_fill_rect(&cr, 40, 40, 5, 5, Color{3, 3, 3}) // outside
	renderer_fill_rect(&cr, 5, 5, 5, 5, Color{4, 4, 4}) // touches only an edge
	testing.expect_value(t, len(log.rects), 2)
	testing.expect(t, log.rects[0] == Rect{10, 10, 5, 5} && log.colors[0] == (Color{1, 1, 1}))
	testing.expect(t, log.rects[1] == Rect{12, 12, 4, 4})
}
