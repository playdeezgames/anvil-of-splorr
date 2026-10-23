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
	copy := new(Play_State)
	defer free(copy)
	copy^ = ps^
	play_step(ps, w, hero, -1, 0)
	testing.expect(t, play_position(copy, hero).x == 2 && play_position(ps, hero).x == 1)
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

@(test)
test_a_game_checks_its_tags_file_against_the_world_at_start_up :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world() // has solid, spawn and thing
	defer free(w)
	g: Game_Tags
	testing.expect_value(t, parse_game_tags(transmute([]u8)string(`{"tags": ["solid", {"name": "thing", "note": "pickup"}, "spawn"]}`), &g), "")
	testing.expect_value(t, len(required_missing(w, &g)), 0)
	testing.expect_value(t, parse_game_tags(transmute([]u8)string(`{"tags": ["solid", "thing", "spawn", "exit", "key"]}`), &g), "")
	missing := required_missing(w, &g)
	testing.expect(t, len(missing) == 2 && missing[0] == "exit" && missing[1] == "key")
	// A bad file is an error and leaves what was read.
	testing.expect(t, parse_game_tags(transmute([]u8)string(`{"tags": ["a", "a"]}`), &g) != "")
	testing.expect_value(t, g.count, 5)
}

@(test)
test_a_game_reads_parameters_by_name_with_defaults :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	source := build_world()
	n := cm.world_add_param(source, "round_seconds")
	cm.world_set_param_number(source, n, 45)
	s := cm.world_add_param(source, "title")
	cm.world_set_param_text(source, s, "Go Get the Thing!")
	text := cm.world_to_json(source)
	free(source)
	w := new_world()
	defer free(w)
	testing.expect_value(t, load(w, transmute([]u8)text), "")
	testing.expect_value(t, param_count(w), 2)
	testing.expect_value(t, param_number(w, "round_seconds", 30), 45)
	testing.expect_value(t, param_number(w, "points_per_pickup", 1), 1) // absent: the default
	testing.expect_value(t, param_number(w, "title", 9), 9) // a text is not a number
	testing.expect_value(t, param_text(w, "title", "?"), "Go Get the Thing!")
	testing.expect_value(t, param_text(w, "subtitle", "none"), "none")
	testing.expect_value(t, param_text(w, "round_seconds", "none"), "none")
	// A world from before parameters has none: every read gives its default.
	old := loaded_world()
	defer free(old)
	testing.expect(t, param_count(old) == 0 && param_number(old, "round_seconds", 30) == 30)
}

// The documented way to ship a world in a game: compile the file in with #load.
EMBEDDED_WORLD :: #load("testdata/demo_world.json")

@(test)
test_an_embedded_world_file_loads_like_any_other :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	testing.expect(t, len(EMBEDDED_WORLD) > 1000)
	err := load(w, EMBEDDED_WORLD)
	testing.expect_value(t, err, "")
	cols, rows, ok := map_size(w, 0)
	testing.expect(t, ok && cols == 20 && rows == 10)
	pi, has := player(w)
	testing.expect(t, has && cm.name_str(&w.characters[pi].name) == "Hero")
	_, x, y, placed := authored_location(w, pi)
	testing.expect(t, placed && x == 3 && y == 4)
	testing.expect(t, cell_is_solid(w, 0, 0, 0) && !cell_is_solid(w, 0, 1, 1) && cell_is_solid(w, 0, 9, 4)) // the room's walls
	testing.expect(t, character_image(w, pi) != nil)
	// It plays: the hero walks right until the interior wall at column 9.
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	steps := 0
	for play_step(ps, w, pi, 1, 0) == .Moved {
		steps += 1
	}
	testing.expect_value(t, steps, 5) // from column 3 to column 8
	testing.expect_value(t, play_step(ps, w, pi, 1, 0), Move_Result.Solid)
}

// --- Sounds ------------------------------------------------------------------------------------

sound_world :: proc() -> ^World {
	w := new_world()
	i := cm.world_add_sound(w, "pickup")
	cm.world_set_sound_text(w, i, "T240 L16 C E G")
	j := cm.world_add_sound(w, "theme")
	cm.world_set_sound_text(w, j, "L8 CDEFGAB>C")
	cm.world_set_sound_loop(w, j, true)
	k := cm.world_add_sound(w, "broken")
	cm.world_set_sound_text(w, k, "C X")
	cm.world_add_sound(w, "silent") // no text
	return w
}

@(test)
test_a_game_finds_and_checks_its_sounds :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sound_world()
	defer free(w)
	testing.expect_value(t, sound_count(w), 4)
	i, ok := find_sound(w, "theme")
	testing.expect(t, ok && i == 1 && sound_loops(w, i) && !sound_loops(w, 0) && !sound_loops(w, 9))
	_, ok = find_sound(w, "nope")
	testing.expect(t, !ok)
	testing.expect_value(t, len(missing_sounds(w, {"pickup", "theme"})), 0)
	missing := missing_sounds(w, {"pickup", "gameover", "start"})
	testing.expect(t, len(missing) == 2 && missing[0] == "gameover" && missing[1] == "start")
	broken := broken_sounds(w)
	testing.expect(t, len(broken) == 1 && broken[0] == "broken") // an empty text is not broken
	testing.expect(t, sound_seconds(w, 0) > 0.18 && sound_seconds(w, 0) < 0.19) // three sixteenths at T240: 0.1875
	testing.expect(t, sound_seconds(w, 2) == 0 && sound_seconds(w, 3) == 0 && sound_seconds(w, -1) == 0)
}

@(test)
test_a_game_gets_audio_requests_for_its_sounds :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sound_world()
	defer free(w)
	req, ok := sound_play(w, "pickup", 2)
	testing.expect(t, ok && req.action == .Play && req.channel == 2 && !req.loop && req.rate == cm.SOUND_RATE && len(req.samples) > 0)
	notes, _, _ := cm.play_parse("T240 L16 C E G")
	testing.expect_value(t, len(req.samples), len(cm.play_render(notes)))
	req, ok = sound_play(w, "theme", 0)
	testing.expect(t, ok && req.loop)
	// Unknown, broken, silent sounds and bad channels give nothing.
	for name in ([]string{"nope", "broken", "silent"}) {
		_, ok = sound_play(w, name, 0)
		testing.expectf(t, !ok, "%s", name)
	}
	_, ok = sound_play(w, "pickup", AUDIO_CHANNELS)
	testing.expect(t, !ok)
	_, ok = sound_play(w, "pickup", -1)
	testing.expect(t, !ok)
	// Stopping, and mixing what a game asked for.
	m: cm.Mixer
	defer cm.mixer_free(&m)
	a, _ := sound_play(w, "pickup", 0)
	b, _ := sound_play(w, "theme", 1)
	cm.mixer_apply(&m, a)
	cm.mixer_apply(&m, b)
	testing.expect_value(t, cm.mixer_active(&m), 2)
	cm.mixer_apply(&m, sound_stop(1))
	testing.expect_value(t, cm.mixer_active(&m), 1)
	cm.mixer_apply(&m, sound_stop_all())
	testing.expect_value(t, cm.mixer_active(&m), 0)
	// pcm for one sound, and a copy on a longer-lived allocator.
	samples, found := sound_pcm(w, 0, context.allocator)
	testing.expect(t, found && len(samples) > 0)
	delete(samples)
	_, found = sound_pcm(w, 2)
	testing.expect(t, !found)
	_, found = sound_pcm(w, 77)
	testing.expect(t, !found)
}

@(test)
test_sounds_come_through_a_world_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sound_world()
	defer free(w)
	text := cm.world_to_json(w)
	loaded := new_world()
	defer free(loaded)
	testing.expect_value(t, load(loaded, transmute([]u8)text), "")
	req, ok := sound_play(loaded, "pickup", 0)
	testing.expect(t, ok && len(req.samples) > 0)
	testing.expect(t, sound_loops(loaded, 1))
}

// The room plus a feature type "tree" (sprite star, tag "thing"), Tree at 2,2 and Stump off the map.
loaded_world_with_features :: proc() -> ^World {
	w := build_world()
	defer free(w)
	ft := cm.world_add_feature_type(w, "tree")
	cm.name_assign(&w.feature_types[ft].sprite_set, "actors")
	cm.name_assign(&w.feature_types[ft].sprite, "star")
	w.feature_types[ft].tags = cm.tag_bit(2) // "thing"
	tree := cm.world_add_feature(w, ft)
	cm.name_assign(&w.features[tree].name, "Tree")
	stump := cm.world_add_feature(w, ft)
	cm.name_assign(&w.features[stump].name, "Stump")
	cm.world_place_feature(w, 0, 2, 2, w.features[tree].uuid)
	out := new_world()
	err := load(out, transmute([]u8)cm.world_to_json(w))
	assert(err == "", err)
	return out
}

@(test)
test_features_are_queried_as_authored_and_block_stepping_in_play :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world_with_features()
	defer free(w)
	hero := index_of_character(w, "Hero")
	testing.expect_value(t, feature_count(w), 2)
	testing.expect(t, feature_type(w, 0) != nil && feature_sprite(w, 0) != nil && feature_image(w, 0) != nil)
	testing.expect(t, feature_type(w, 5) == nil && feature_sprite(w, -1) == nil)
	thing, _ := find_tag(w, "thing")
	testing.expect(t, feature_has_tag(w, 0, thing) && feature_has_tag(w, 1, thing))
	testing.expect_value(t, len(features_with_tag(w, thing)), 2)
	testing.expect_value(t, feature_at(w, 0, 2, 2), 0)
	testing.expect_value(t, feature_at(w, 0, 0, 1), -1)
	mi, x, y, ok := authored_feature_location(w, 0)
	testing.expect(t, ok && mi == 0 && x == 2 && y == 2)
	_, _, _, ok = authored_feature_location(w, 1)
	testing.expect(t, !ok)

	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	testing.expect_value(t, play_feature_position(ps, 0), Position{0, 2, 2, true})
	testing.expect(t, !play_feature_position(ps, 1).placed && !play_feature_position(ps, 9).placed)
	testing.expect_value(t, play_feature_at(ps, 0, 2, 2), 0)
	testing.expect_value(t, len(play_features_in_map(ps, 0)), 1)
	// The hero goes down to 1,2; the tree is to its right and always blocks.
	testing.expect_value(t, play_step(ps, w, hero, 0, 1), Move_Result.Moved)
	r, tx, ty := play_can_step(ps, w, hero, 1, 0)
	testing.expect(t, r == .Feature && tx == 2 && ty == 2)
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Feature)
	// Cutting the tree down clears the way; the world is untouched.
	testing.expect(t, play_unplace_feature(ps, 0) && !play_unplace_feature(ps, 0))
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Moved)
	testing.expect_value(t, cm.world_feature_at(w, 0, 2, 2), 0)
	// Placing: the hero's cell and other features refuse; a free cell takes it.
	testing.expect_value(t, play_place_feature(ps, w, 0, 0, 2, 2), cm.Place_Result.Character_There)
	testing.expect_value(t, play_place_feature(ps, w, 0, 0, 4, 3), cm.Place_Result.Placed)
	testing.expect_value(t, play_place_feature(ps, w, 1, 0, 4, 3), cm.Place_Result.Taken)
	testing.expect_value(t, play_place_feature(ps, w, 1, 0, 9, 3), cm.Place_Result.Outside)
	testing.expect_value(t, play_place_feature(ps, w, 7, 0, 0, 1), cm.Place_Result.Unknown)
	testing.expect_value(t, play_place_feature(ps, w, 0, 0, 4, 3), cm.Place_Result.Placed) // already there
	// A character cannot be put on a feature either.
	testing.expect_value(t, play_place(ps, w, hero, 0, 4, 3), cm.Place_Result.Feature_There)
	testing.expect_value(t, play_position(ps, hero), Position{0, 2, 2, true})
}

@(test)
test_a_game_draws_the_features_where_they_are_now :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world_with_features()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	log: Draw_Log
	defer delete(log.rects)
	defer delete(log.colors)
	r := draw_renderer(&log)
	d := zoom_window(w, 0, 0, 0, 5, 4, 20, 10, 3)
	draw_features(&r, w, ps, d)
	cell := cm.world_cell_rect(d, 2, 2)
	testing.expect(t, len(log.rects) > 0)
	for rc in log.rects {
		testing.expect(t, rc.x >= cell.x && rc.y >= cell.y && rc.x + rc.w <= cell.x + cell.w && rc.y + rc.h <= cell.y + cell.h)
	}
	play_unplace_feature(ps, 0)
	clear(&log.rects)
	clear(&log.colors)
	draw_features(&r, w, ps, d)
	testing.expect_value(t, len(log.rects), 0)
	play_place_feature(ps, w, 0, 0, 0, 1)
	draw_features(&r, w, ps, zoom_window(w, 0, 1, 0, 4, 4, 20, 10, 3)) // column 0 is outside this window
	testing.expect_value(t, len(log.rects), 0)
}

@(test)
test_running_into_a_character_or_a_feature_queues_a_collision :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := loaded_world_with_features()
	defer free(w)
	hero, star := index_of_character(w, "Hero"), index_of_character(w, "Star")
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	_, ok := play_take_collision(ps)
	testing.expect(t, !ok)
	// Walls, edges and asking do not count.
	play_step(ps, w, hero, 0, -1) // the wall row
	play_can_step(ps, w, hero, 0, 1)
	play_step(ps, w, hero, 0, 1) // to 1,2
	_, ok = play_take_collision(ps)
	testing.expect(t, !ok)
	// Into the tree at 2,2.
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Feature)
	c: Collision
	c, ok = play_take_collision(ps)
	testing.expect(t, ok && c == Collision{hero, .Feature, 0, 0, 2, 2, 1, 0})
	_, ok = play_take_collision(ps)
	testing.expect(t, !ok)
	// Into the star at 3,2, from above (1,2 -> 1,1 -> 3,1 -> down).
	play_step(ps, w, hero, 0, -1)
	play_step(ps, w, hero, 1, 0)
	play_step(ps, w, hero, 1, 0)
	testing.expect_value(t, play_step(ps, w, hero, 0, 1), Move_Result.Occupied)
	c, ok = play_take_collision(ps)
	testing.expect(t, ok && c == Collision{hero, .Character, star, 0, 3, 2, 0, 1})
	// A non-player character bumping works the same, and events come out oldest first.
	play_step(ps, w, star, -1, 0) // the tree is to its left
	c, ok = play_take_collision(ps)
	testing.expect(t, ok && c.mover == star && c.kind == .Feature && c.dx == -1)
	// The queue is bounded: the oldest are dropped and counted.
	play_clear_collisions(ps)
	play_place(ps, w, star, 0, 3, 2) // next to the tree again
	for _ in 0 ..< MAX_COLLISIONS + 5 {
		play_step(ps, w, star, -1, 0)
	}
	testing.expect_value(t, ps.collision_count, MAX_COLLISIONS)
	testing.expect_value(t, ps.collisions_lost, 5)
	n := 0
	for _, ok2 := play_take_collision(ps); ok2; _, ok2 = play_take_collision(ps) {
		n += 1
	}
	testing.expect_value(t, n, MAX_COLLISIONS)
	// Starting over empties the queue.
	play_step(ps, w, star, -1, 0)
	play_init(ps, w)
	_, ok = play_take_collision(ps)
	testing.expect(t, !ok)
}
