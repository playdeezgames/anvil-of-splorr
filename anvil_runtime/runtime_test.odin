#+build !js
package anvil_runtime

import cm "../common"
import "core:testing"

// The world of a tiny game, built with the Anvil's own model procs and then written to JSON and
// loaded back through `load`, so the tests also cover the file path a game uses.
//   Tiles 4 x 4, palette default. Terrains: floor (tag "spawn"), wall (tag "solid").
//   Map "room", 5 x 4: wall across the top row, floor elsewhere.
//   Sprites: hero (transparent colour 0), star (no transparent colour).
//   Character types: player (hero), thing (star, tag "thing").
//   Characters: Hero (a player) at 1,1 - the world's player; Star (a thing) at 3,2.
build_world :: proc() -> ^World {
	w := new_world()
	cm.world_seed_uuids(w, 4242)
	cm.world_set_tile_size(w, 4, 4)
	ts := cm.world_add_tileset(w, "t")
	for name, k in ([]string{"floor", "wall", "hero", "star"}) {
		n := cm.tileset_insert_blank(&w.tilesets[ts], k, name)
		cm.image4_set(&w.tilesets[ts].images[n], k % 4, 0, k + 1) // every image is different
	}
	spawn := cm.world_add_tag(w, "spawn")
	thing := cm.world_add_tag(w, "thing")
	si := cm.world_add_terrain_set(w, "land")
	cm.name_assign(&w.sets[si].terrains[0].name, "floor")
	cm.name_assign(&w.sets[si].terrains[0].image, "floor")
	w.sets[si].terrains[0].tags = cm.tag_bit(spawn)
	wall := cm.world_add_terrain(w, si)
	cm.name_assign(&w.sets[si].terrains[wall].name, "wall")
	cm.name_assign(&w.sets[si].terrains[wall].image, "wall")
	w.sets[si].terrains[wall].tags = cm.tag_bit(TAG_SOLID)
	mi := cm.world_add_map(w, si, "room")
	cm.world_map_set_size(w, mi, 5, 4)
	for x in 0 ..< 5 {
		w.maps[mi].cells[0][x] = u8(wall)
	}
	ss := cm.world_add_sprite_set(w, "actors")
	hero_sprite := cm.world_add_sprite(w, ss)
	cm.name_assign(&w.sprite_sets[ss].sprites[hero_sprite].name, "hero")
	cm.name_assign(&w.sprite_sets[ss].sprites[hero_sprite].image, "hero")
	w.sprite_sets[ss].sprites[hero_sprite].transparent = 0
	star_sprite := cm.world_add_sprite(w, ss)
	cm.name_assign(&w.sprite_sets[ss].sprites[star_sprite].name, "star")
	cm.name_assign(&w.sprite_sets[ss].sprites[star_sprite].image, "star")
	w.sprite_sets[ss].sprites[star_sprite].transparent = cm.SPRITE_NO_TRANSPARENT
	player_type := cm.world_add_char_type(w, "player")
	cm.name_assign(&w.char_types[player_type].sprite, "hero")
	thing_type := cm.world_add_char_type(w, "thing")
	cm.name_assign(&w.char_types[thing_type].sprite, "star")
	w.char_types[thing_type].tags = cm.tag_bit(thing)
	hero := cm.world_add_character(w, player_type)
	cm.name_assign(&w.characters[hero].name, "Hero")
	star := cm.world_add_character(w, thing_type)
	cm.name_assign(&w.characters[star].name, "Star")
	cm.world_place_character(w, mi, 1, 1, w.characters[hero].uuid)
	cm.world_place_character(w, mi, 3, 2, w.characters[star].uuid)
	cm.world_set_player(w, w.characters[hero].uuid)
	return w
}

build_world_text :: proc() -> string {
	w := build_world()
	defer free(w)
	return cm.world_to_json(w)
}

loaded_world :: proc() -> ^World {
	w := new_world()
	err := load(w, transmute([]u8)build_world_text())
	assert(err == "", err)
	return w
}

index_of_character :: proc(w: ^World, name: string) -> int {
	for i in 0 ..< w.character_count {
		if cm.name_str(&w.characters[i].name) == name {
			return i
		}
	}
	return -1
}

@(test)
test_a_world_loads_and_a_bad_file_is_refused_with_a_reason :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world()
	defer free(w)
	cols, rows, ok := map_size(w, 0)
	testing.expect(t, ok && cols == 5 && rows == 4 && map_count(w) == 1)
	tw, th := tile_size(w)
	testing.expect(t, tw == 4 && th == 4 && palette(w)^ == cm.default_palette() && character_count(w) == 2)
	_, _, ok = map_size(w, 3)
	testing.expect(t, !ok)
	before := cm.world_to_json(w)
	err := load(w, transmute([]u8)string("not json"))
	testing.expect(t, err != "")
	testing.expect_value(t, cm.world_to_json(w), before) // untouched
	err = load(w, transmute([]u8)string(`{"tile_width": 0}`))
	testing.expect(t, err != "")
	// A fresh empty world has nothing.
	e := new_world()
	defer free(e)
	testing.expect(t, map_count(e) == 0 && character_count(e) == 0)
	_, has_player := player(e)
	testing.expect(t, !has_player)
	reset_world(w)
	testing.expect_value(t, map_count(w), 0)
}

@(test)
test_names_become_indexes_and_missing_tags_are_reported :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world()
	defer free(w)
	solid, ok := find_tag(w, "solid")
	testing.expect(t, ok && solid == TAG_SOLID)
	_, ok = find_tag(w, "spawn")
	testing.expect(t, ok)
	_, ok = find_tag(w, "lava")
	testing.expect(t, !ok)
	mi, found := find_map(w, "room")
	testing.expect(t, found && mi == 0)
	_, found = find_map(w, "nowhere")
	testing.expect(t, !found)
	missing := missing_tags(w, {"solid", "thing", "lava", "spawn", "ghost"})
	testing.expect(t, len(missing) == 2 && missing[0] == "lava" && missing[1] == "ghost")
	testing.expect_value(t, len(missing_tags(w, {})), 0)
	testing.expect_value(t, len(missing_tags(w, {"solid", "spawn", "thing"})), 0)
}

@(test)
test_cells_have_terrain_and_effective_tags :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world()
	defer free(w)
	spawn, _ := find_tag(w, "spawn")
	wall := terrain_at(w, 0, 2, 0)
	floor := terrain_at(w, 0, 2, 2)
	testing.expect(t, wall != nil && floor != nil && cm.name_str(&wall.name) == "wall" && cm.name_str(&floor.name) == "floor")
	testing.expect(t, terrain_at(w, 0, 5, 0) == nil && terrain_at(w, 0, 0, -1) == nil && terrain_at(w, 4, 0, 0) == nil)
	testing.expect(t, terrain_image(w, floor) != nil)
	testing.expect(t, cell_is_solid(w, 0, 2, 0) && !cell_is_solid(w, 0, 2, 2))
	testing.expect(t, cell_has_tag(w, 0, 2, 2, spawn) && !cell_has_tag(w, 0, 2, 0, spawn))
	// Outside a map counts as solid; so does a map that does not exist.
	testing.expect(t, cell_is_solid(w, 0, -1, 1) && cell_is_solid(w, 0, 5, 1) && cell_is_solid(w, 0, 1, 4) && cell_is_solid(w, 3, 0, 0))
	// A cell can say otherwise: a doorway through the wall, and a solid pillar on the floor.
	cm.world_cycle_cell_tag(w, 0, 2, 0, TAG_SOLID) // set
	cm.world_cycle_cell_tag(w, 0, 2, 0, TAG_SOLID) // cleared
	cm.world_cycle_cell_tag(w, 0, 1, 2, TAG_SOLID) // set
	testing.expect(t, !cell_is_solid(w, 0, 2, 0) && cell_is_solid(w, 0, 1, 2))
	// Spawn cells, row by row, left to right: the floor, minus none of them solid here.
	cells := cells_with_tag(w, 0, spawn)
	testing.expectf(t, len(cells) == 15, "%d spawn cells", len(cells)) // 5 x 3 floor cells
	testing.expect(t, cells[0] == [2]int{0, 1} && cells[len(cells) - 1] == [2]int{4, 3})
	testing.expect_value(t, len(cells_with_tag(w, 7, spawn)), 0)
}

@(test)
test_characters_have_types_sprites_images_and_inherited_tags :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world()
	defer free(w)
	thing, _ := find_tag(w, "thing")
	hero, star := index_of_character(w, "Hero"), index_of_character(w, "Star")
	pi, has := player(w)
	testing.expect(t, has && pi == hero)
	testing.expect(t, cm.name_str(&character_type(w, hero).name) == "player" && cm.name_str(&character_type(w, star).name) == "thing")
	testing.expect(t, character_type(w, 9) == nil && character_sprite(w, 9) == nil && character_image(w, -1) == nil)
	hs, ss := character_sprite(w, hero), character_sprite(w, star)
	testing.expect(t, hs != nil && ss != nil && hs.transparent == 0 && ss.transparent == cm.SPRITE_NO_TRANSPARENT)
	testing.expect(t, character_image(w, hero) != nil && character_image(w, star) != nil && character_image(w, hero) != character_image(w, star))
	testing.expect(t, character_has_tag(w, star, thing) && !character_has_tag(w, hero, thing))
	// A character's own setting wins over its type's.
	cm.world_cycle_character_tag(w, star, thing) // set
	cm.world_cycle_character_tag(w, star, thing) // cleared
	cm.world_cycle_character_tag(w, hero, thing) // set
	testing.expect(t, !character_has_tag(w, star, thing) && character_has_tag(w, hero, thing))
	mi, x, y, ok := authored_location(w, hero)
	testing.expect(t, ok && mi == 0 && x == 1 && y == 1)
	mi, x, y, ok = authored_location(w, star)
	testing.expect(t, ok && x == 3 && y == 2)
	_, _, _, ok = authored_location(w, 9)
	testing.expect(t, !ok)
}

@(test)
test_a_play_state_starts_as_the_authored_world_and_is_separate_from_it :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world()
	defer free(w)
	hero, star := index_of_character(w, "Hero"), index_of_character(w, "Star")
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	testing.expect(t, ps.count == 2 && play_position(ps, hero) == Position{0, 1, 1, true} && play_position(ps, star) == Position{0, 3, 2, true})
	testing.expect(t, play_character_at(ps, 0, 1, 1) == hero && play_character_at(ps, 0, 3, 2) == star && play_character_at(ps, 0, 0, 0) == -1)
	testing.expect(t, play_character_at(ps, 1, 1, 1) == -1) // another map
	in_map := play_characters_in_map(ps, 0)
	testing.expect(t, len(in_map) == 2 && in_map[0] == 0 && in_map[1] == 1)
	testing.expect_value(t, play_position(ps, 9), Position{})
	// Playing changes the Play_State and nothing else.
	before := cm.world_to_json(w)
	play_step(ps, w, hero, 1, 0)
	play_step(ps, w, hero, 0, 1)
	play_unplace(ps, star)
	testing.expect_value(t, cm.world_to_json(w), before)
	_, x, y, _ := authored_location(w, hero)
	testing.expect(t, x == 1 && y == 1)
	// A copy is independent; play_init starts over.
	copy := ps^
	play_step(ps, w, hero, -1, 0)
	testing.expect(t, play_position(&copy, hero).x == 2 && play_position(ps, hero).x == 1)
	play_init(ps, w)
	testing.expect(t, play_position(ps, hero) == Position{0, 1, 1, true} && play_position(ps, star).placed)
}

@(test)
test_stepping_is_blocked_by_edges_solid_cells_and_characters :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world()
	defer free(w)
	hero, star := index_of_character(w, "Hero"), index_of_character(w, "Star")
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	// The hero is at 1,1 under the wall row.
	testing.expect_value(t, play_step(ps, w, hero, 0, -1), Move_Result.Solid)
	testing.expect_value(t, play_position(ps, hero).y, 1)
	testing.expect_value(t, play_step(ps, w, hero, -1, 0), Move_Result.Moved)
	testing.expect_value(t, play_step(ps, w, hero, -1, 0), Move_Result.Outside)
	testing.expect_value(t, play_position(ps, hero).x, 0)
	r, tx, ty := play_can_step(ps, w, hero, 0, -1)
	testing.expect(t, r == .Solid && tx == 0 && ty == 0 && play_position(ps, hero).y == 1) // asking moves nothing
	// Walk to the star: it blocks like any character until it is taken off.
	play_step(ps, w, hero, 1, 0)
	play_step(ps, w, hero, 1, 0)
	play_step(ps, w, hero, 0, 1)
	hp := play_position(ps, hero)
	testing.expect(t, hp.x == 2 && hp.y == 2)
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Occupied)
	// The game's pickup: the thing leaves, then the step succeeds.
	testing.expect(t, play_character_at(ps, 0, 3, 2) == star && play_unplace(ps, star))
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Moved)
	testing.expect_value(t, play_step(ps, w, star, 1, 0), Move_Result.Not_Placed)
	testing.expect_value(t, play_step(ps, w, 9, 0, 1), Move_Result.Not_Placed)
	// A cell that clears solid is a doorway; one that sets it is a wall.
	cm.world_cycle_cell_tag(w, 0, 3, 3, TAG_SOLID) // set: a pillar below the hero
	testing.expect_value(t, play_step(ps, w, hero, 0, 1), Move_Result.Solid)
	cm.world_cycle_cell_tag(w, 0, 3, 3, TAG_SOLID) // cleared
	testing.expect_value(t, play_step(ps, w, hero, 0, 1), Move_Result.Moved)
	testing.expect_value(t, play_step(ps, w, hero, 0, 1), Move_Result.Outside) // the bottom edge
	cm.world_cycle_cell_tag(w, 0, 3, 2, TAG_SOLID)
	cm.world_cycle_cell_tag(w, 0, 3, 2, TAG_SOLID) // cleared on a floor cell: still fine
	testing.expect_value(t, play_step(ps, w, hero, 0, -1), Move_Result.Moved)
}

@(test)
test_placing_taking_off_and_the_pickup_and_respawn_loop :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world()
	defer free(w)
	hero, star := index_of_character(w, "Hero"), index_of_character(w, "Star")
	spawn, _ := find_tag(w, "spawn")
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	testing.expect_value(t, play_place(ps, w, star, 0, 1, 1), cm.Place_Result.Taken) // the hero is there
	testing.expect_value(t, play_place(ps, w, star, 0, 9, 1), cm.Place_Result.Outside)
	testing.expect_value(t, play_place(ps, w, star, 3, 0, 0), cm.Place_Result.Unknown)
	testing.expect_value(t, play_place(ps, w, 7, 0, 0, 1), cm.Place_Result.Unknown)
	testing.expect_value(t, play_place(ps, w, star, 0, 3, 2), cm.Place_Result.Placed) // where it already is
	testing.expect_value(t, play_position(ps, star).x, 3)
	// One round of the game, by hand: walk onto the star, score, respawn it on a free spawn cell.
	score := 0
	for _ in 0 ..< 2 {
		play_step(ps, w, hero, 1, 0)
	}
	play_step(ps, w, hero, 0, 1)
	if at := play_character_at(ps, 0, 3, 2); at == star {
		play_unplace(ps, star)
		play_step(ps, w, hero, 1, 0)
		score += 1
		for c in cells_with_tag(w, 0, spawn) {
			if !cell_is_solid(w, 0, c.x, c.y) && play_character_at(ps, 0, c.x, c.y) < 0 {
				play_place(ps, w, star, 0, c.x, c.y)
				break
			}
		}
	}
	testing.expect(t, score == 1 && play_position(ps, star).placed && play_position(ps, star).y == 1) // the first free spawn cell
	hp, sp := play_position(ps, hero), play_position(ps, star)
	testing.expect(t, !(hp.x == sp.x && hp.y == sp.y))
	// Taking a character off and back on, and a second map.
	testing.expect(t, play_unplace(ps, star) && !play_unplace(ps, star))
	testing.expect_value(t, len(play_characters_in_map(ps, 0)), 1)
	play_init(ps, w)
	testing.expect_value(t, len(play_characters_in_map(ps, 0)), 2)
}

@(test)
test_a_full_world_plays_without_overflow :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	cm.world_set_tile_size(w, 2, 2)
	ts := cm.world_add_tileset(w, "t")
	cm.tileset_insert_blank(&w.tilesets[ts], 0, "i")
	si := cm.world_add_terrain_set(w, "s")
	sp := cm.world_add_sprite_set(w, "p")
	spr := cm.world_add_sprite(w, sp)
	_ = spr
	ct := cm.world_add_char_type(w, "c")
	for _ in 0 ..< cm.WORLD_MAX_MAPS {
		mi := cm.world_add_map(w, si)
		cm.world_map_set_size(w, mi, cm.MAP_MAX, cm.MAP_MAX)
	}
	for k in 0 ..< cm.WORLD_MAX_CHARACTERS {
		ci := cm.world_add_character(w, ct)
		w.maps[k % cm.WORLD_MAX_MAPS].characters[(k / 16) % 64][k / 64 % 64] = w.characters[ci].uuid // (placing one by one would scan every cell each time)
	}
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	testing.expect_value(t, ps.count, cm.WORLD_MAX_CHARACTERS)
	placed := 0
	for ci in 0 ..< ps.count {
		if play_position(ps, ci).placed {
			placed += 1
		}
	}
	testing.expect_value(t, placed, cm.WORLD_MAX_CHARACTERS)
	p := play_position(ps, 1000)
	testing.expect_value(t, play_character_at(ps, p.map_index, p.x, p.y), 1000)
	// The same world through the file and back keeps everyone in place.
	text := cm.world_to_json(w)
	back := new_world()
	defer free(back)
	testing.expect_value(t, load(back, transmute([]u8)text), "")
	ps2 := new(Play_State)
	defer free(ps2)
	play_init(ps2, back)
	testing.expect(t, ps2.count == ps.count && play_position(ps2, 1000) == p)
}

Draw_Log :: struct {
	rects:  [dynamic]cm.Rect,
	colors: [dynamic]cm.Color,
}

draw_renderer :: proc(l: ^Draw_Log) -> cm.Renderer {
	return cm.Renderer {
		data = l,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^Draw_Log)(d)
			append(&k.rects, cm.Rect{x, y, w, h})
			append(&k.colors, c)
		},
		present = proc(d: rawptr) {},
	}
}

@(test)
test_a_game_draws_the_map_and_where_its_characters_are_now :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world()
	defer free(w)
	hero := index_of_character(w, "Hero")
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	log: Draw_Log
	defer delete(log.rects)
	defer delete(log.colors)
	r := draw_renderer(&log)
	// A 5 x 4 room at zoom 3 with its corner at pixel (20, 10): 12 x 12 pixel cells.
	d := zoom_window(w, 0, 0, 0, 5, 4, 20, 10, 3)
	testing.expect(t, d.cell_w == 12 && d.cell_h == 12)
	draw_terrain(&r, w, d)
	room := cm.Rect{20, 10, 60, 48}
	area := 0
	for rc in log.rects {
		testing.expect(t, rc.x >= room.x && rc.y >= room.y && rc.x + rc.w <= room.x + room.w && rc.y + rc.h <= room.y + room.h)
		area += rc.w * rc.h
	}
	testing.expect_value(t, area, 60 * 48)
	// The hero (picture colour 3, a dot on transparent 0) is drawn at its cell now, and moves with it.
	d.mark_player = true
	d.player_mark = cm.Color{200, 100, 50}
	clear(&log.rects)
	clear(&log.colors)
	draw_characters(&r, w, ps, d)
	cell := cm.world_cell_rect(d, 1, 1)
	for rc in log.rects {
		testing.expect(t, rc.x >= cell.x && rc.y >= cell.y && rc.x + rc.w <= cell.x + cell.w || rc.x >= cm.world_cell_rect(d, 3, 2).x) // the hero's or the star's cell
	}
	marks := 0
	for c, i in log.colors {
		if c == (cm.Color{200, 100, 50}) {
			marks += 1
			testing.expect(t, log.rects[i].x == cell.x && log.rects[i].y == cell.y)
		}
	}
	testing.expect_value(t, marks, 1)
	play_step(ps, w, hero, 1, 0)
	clear(&log.rects)
	clear(&log.colors)
	draw_characters(&r, w, ps, d)
	moved := cm.world_cell_rect(d, 2, 1)
	for c, i in log.colors {
		if c == (cm.Color{200, 100, 50}) {
			testing.expect(t, log.rects[i].x == moved.x && log.rects[i].y == moved.y)
		}
	}
	// A character that is off the map is not drawn; a window that excludes a cell leaves its character out.
	play_unplace(ps, hero)
	clear(&log.rects)
	clear(&log.colors)
	draw_characters(&r, w, ps, d)
	testing.expect_value(t, len(log.rects) > 0, true) // the star is still there
	d2 := zoom_window(w, 0, 0, 0, 3, 4, 20, 10, 3) // columns 0..2: the star is in column 3
	clear(&log.rects)
	clear(&log.colors)
	draw_characters(&r, w, ps, d2)
	testing.expect_value(t, len(log.rects), 0)
	// A click on the screen is a cell of the map.
	x, y, ok := cell_at_pixel(w, d, 20 + 12 * 4 + 5, 10 + 12 * 3 + 5)
	testing.expect(t, ok && x == 4 && y == 3)
	_, _, ok = cell_at_pixel(w, d, 10, 10)
	testing.expect(t, !ok)
	// Hanging off the surface is clipped.
	clear(&log.rects)
	clear(&log.colors)
	draw_terrain(&r, w, zoom_window(w, 0, 0, 0, 5, 4, -30, -20, 3))
	for rc in log.rects {
		testing.expect(t, rc.x >= 0 && rc.y >= 0 && rc.x + rc.w <= cm.SCREEN_W && rc.y + rc.h <= cm.SCREEN_H)
	}
}
