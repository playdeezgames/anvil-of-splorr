#+build !js
package common

import "core:strings"
import "core:testing"

new_world :: proc() -> ^World {
	w := new(World)
	world_reset(w)
	return w
}

// A world with a 4 x 4 tile size, tilesets "a" (images x, y) and "b" (image z), set "s" with
// terrains grass (default, a/x), rock (solid, a/y) and a map "m" of 3 x 2 using it.
sample_world :: proc() -> ^World {
	w := new_world()
	world_set_tile_size(w, 4, 4)
	w.palette[3] = {10, 20, 30}
	a := world_add_tileset(w, "a")
	b := world_add_tileset(w, "b")
	tileset_insert_blank(&w.tilesets[a], 0, "x")
	tileset_insert_blank(&w.tilesets[a], 1, "y")
	tileset_insert_blank(&w.tilesets[b], 0, "z")
	image4_set(&w.tilesets[a].images[1], 2, 1, 9)
	si := world_add_terrain_set(w, "s")
	name_assign(&w.sets[si].terrains[0].name, "grass")
	rock := world_add_terrain(w, si)
	name_assign(&w.sets[si].terrains[rock].name, "rock")
	w.sets[si].terrains[rock].tags = tag_bit(TAG_SOLID)
	name_assign(&w.sets[si].terrains[rock].image, "y")
	mi := world_add_map(w, si, "m")
	world_map_set_size(w, mi, 3, 2)
	w.maps[mi].cells[0][1] = 1
	w.maps[mi].cells[1][2] = 1
	return w
}

@(test)
test_a_new_world_is_empty_with_the_default_palette :: proc(t: ^testing.T) {
	w := new_world()
	defer free(w)
	testing.expect(t, w.tile_w == 16 && w.tile_h == 16 && w.palette == default_palette())
	testing.expect(t, w.tileset_count == 0 && w.set_count == 0 && w.map_count == 0)
}

@(test)
test_tilesets_follow_the_tile_size_and_have_unique_names :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	a := world_add_tileset(w)
	b := world_add_tileset(w)
	testing.expect_value(t, name_str(&w.tileset_names[a]), "tileset")
	testing.expect_value(t, name_str(&w.tileset_names[b]), "tileset_2")
	testing.expect(t, w.tilesets[a].width == 16 && w.tilesets[a].height == 16)
	tileset_insert_blank(&w.tilesets[a], 0)
	testing.expect(t, world_set_tile_size(w, 8, 5))
	testing.expect(t, w.tilesets[a].width == 8 && w.tilesets[b].height == 5 && w.tilesets[a].images[0].width == 8)
	testing.expect(t, !world_set_tile_size(w, 8, 5))
	world_set_tile_size(w, 500, 0)
	testing.expect(t, w.tile_w == 64 && w.tile_h == 1)
	testing.expect_value(t, world_check_tileset_name(w, b, "tileset"), Name_Problem.In_Use)
	testing.expect_value(t, world_check_tileset_name(w, a, "tileset"), Name_Problem.None) // its own name
	testing.expect_value(t, world_check_tileset_name(w, a, ""), Name_Problem.Empty)
	testing.expect_value(t, world_check_tileset_name(w, a, "caf\xe9"), Name_Problem.Bad_Character)
	for _ in 2 ..< WORLD_MAX_TILESETS {
		testing.expect(t, world_add_tileset(w) >= 0)
	}
	testing.expect_value(t, world_add_tileset(w), -1)
	testing.expect_value(t, world_duplicate_tileset(w, 0), -1)
}

@(test)
test_a_tileset_of_the_wrong_size_is_not_added :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	src := new(Tileset)
	defer free(src)
	tileset_reset(src, 8, 8)
	testing.expect_value(t, world_add_tileset_copy(w, src, "x"), -2)
	tileset_reset(src, 16, 16)
	tileset_insert_blank(src, 0, "img")
	i := world_add_tileset_copy(w, src, "imported")
	testing.expect(t, i == 0 && w.tilesets[0].count == 1 && name_str(&w.tileset_names[0]) == "imported")
}

@(test)
test_terrains_start_on_the_first_image_and_follow_renames :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	s := &w.sets[0]
	testing.expect(t, s.count == 2 && s.default == 0 && s.terrains[0].tags == 0 && s.terrains[1].tags == 1)
	testing.expect_value(t, name_str(&s.terrains[0].tileset), "a")
	testing.expect_value(t, name_str(&s.terrains[0].image), "x")
	testing.expect(t, world_terrain_image(w, &s.terrains[1]) == &w.tilesets[0].images[1])
	testing.expect_value(t, world_rename_tileset(w, 0, "ground"), Name_Problem.None)
	testing.expect_value(t, name_str(&s.terrains[1].tileset), "ground")
	testing.expect_value(t, world_rename_tileset(w, 0, "b"), Name_Problem.In_Use)
	testing.expect_value(t, name_str(&s.terrains[1].tileset), "ground")
	world_rename_image(w, "ground", "y", "yy")
	testing.expect_value(t, name_str(&s.terrains[1].image), "yy")
	testing.expect_value(t, name_str(&s.terrains[0].image), "x")
	testing.expect(t, world_image_uses(w, "ground", "yy") == 1 && world_image_uses(w, "ground", "x") == 1 && world_image_uses(w, "b", "z") == 0)
	// A terrain made while no tileset has an image is not set.
	e := new_world()
	defer free(e)
	world_add_terrain_set(e)
	testing.expect(t, e.sets[0].terrains[0].tileset.len == 0 && world_terrain_image(e, &e.sets[0].terrains[0]) == nil)
}

@(test)
test_a_used_tileset_cannot_be_deleted :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	testing.expect_value(t, world_delete_tileset(w, 0), 2)
	testing.expect_value(t, w.tileset_count, 2)
	testing.expect_value(t, world_delete_tileset(w, 1), 0) // "b" is unused
	testing.expect(t, w.tileset_count == 1 && name_str(&w.tileset_names[0]) == "a")
	d := world_duplicate_tileset(w, 0)
	testing.expect(t, d == 1 && name_str(&w.tileset_names[1]) == "a_copy" && w.tilesets[1].count == 2)
	testing.expect_value(t, world_tileset_uses(w, "a_copy"), 0)
}

@(test)
test_terrain_sets_and_their_maps :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	testing.expect_value(t, world_delete_terrain_set(w, 0), 1) // map "m" uses it
	testing.expect_value(t, world_rename_terrain_set(w, 0, "outdoors"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.maps[0].set), "outdoors")
	d := world_duplicate_terrain_set(w, 0)
	testing.expect(t, d == 1 && name_str(&w.sets[1].name) == "outdoors_copy" && w.sets[1].count == 2)
	testing.expect_value(t, world_rename_terrain_set(w, 1, "outdoors"), Name_Problem.In_Use)
	testing.expect_value(t, world_delete_terrain_set(w, 1), 0)
	testing.expect_value(t, w.set_count, 1)
	for _ in 1 ..< WORLD_MAX_TERRAIN_SETS {
		testing.expect(t, world_add_terrain_set(w) >= 0)
	}
	testing.expect_value(t, world_add_terrain_set(w), -1)
}

@(test)
test_terrain_deletion_renumbers_cells_and_protects_the_default :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	world_add_terrain(w, 0) // index 2
	name_assign(&w.sets[0].terrains[2].name, "sand")
	w.maps[0].cells[1][0] = 2
	testing.expect_value(t, world_terrain_uses(w, 0, 1), 2)
	r, uses := world_delete_terrain(w, 0, 1)
	testing.expect(t, r == .In_Use && uses == 2)
	r, _ = world_delete_terrain(w, 0, 0)
	testing.expect_value(t, r, Terrain_Delete.Is_Default)
	w.maps[0].cells[0][1], w.maps[0].cells[1][2] = 0, 0 // nothing uses rock now
	r, _ = world_delete_terrain(w, 0, 1)
	testing.expect_value(t, r, Terrain_Delete.Deleted)
	testing.expect(t, w.sets[0].count == 2 && name_str(&w.sets[0].terrains[1].name) == "sand")
	testing.expect_value(t, w.maps[0].cells[1][0], 1) // sand moved down one place
	// A set keeps one terrain; the default index follows deletions before it.
	w.sets[0].default = 1
	for y in 0 ..< MAP_MAX {
		for x in 0 ..< MAP_MAX {
			w.maps[0].cells[y][x] = 1
		}
	}
	r, _ = world_delete_terrain(w, 0, 0)
	testing.expect_value(t, r, Terrain_Delete.Deleted)
	testing.expect(t, w.sets[0].default == 0 && w.sets[0].count == 1)
	r, _ = world_delete_terrain(w, 0, 0)
	testing.expect_value(t, r, Terrain_Delete.Last_One)
	// Duplicating a terrain appends it (nothing to renumber) with a unique name.
	n := world_duplicate_terrain(w, 0, 0)
	testing.expect(t, n == 1 && name_str(&w.sets[0].terrains[1].name) == "sand_copy")
	for w.sets[0].count < TERRAIN_MAX {
		world_add_terrain(w, 0)
	}
	testing.expect_value(t, world_add_terrain(w, 0), -1)
	testing.expect_value(t, world_duplicate_terrain(w, 0, 0), -1)
}

@(test)
test_maps_start_filled_with_the_default_and_resize_with_it :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	w.sets[0].default = 1 // rock
	m := &w.maps[0]
	testing.expect(t, m.width == 3 && m.height == 2)
	testing.expect(t, world_map_set_size(w, 0, 4, 3))
	testing.expect_value(t, m.cells[0][1], 1) // existing cells kept
	testing.expect_value(t, m.cells[0][3], 1) // new column: the default (rock)
	testing.expect_value(t, m.cells[2][0], 1)
	w.sets[0].default = 0
	world_map_set_size(w, 0, 2, 2) // shrink forgets what was cut off...
	world_map_set_size(w, 0, 4, 3)
	testing.expect_value(t, m.cells[0][3], 0) // ...and growing back fills with the default now
	testing.expect(t, !world_map_set_size(w, 0, 4, 3))
	world_map_set_size(w, 0, 999, -4)
	testing.expect(t, m.width == MAP_MAX && m.height == 1)
	i := world_add_map(w, 0)
	testing.expect(t, i == 1 && name_str(&w.maps[1].name) == "map" && w.maps[1].width == MAP_DEFAULT_SIZE)
	testing.expect_value(t, world_add_map(w, 5), -1) // no such set
	d := world_duplicate_map(w, 0)
	testing.expect(t, d == 1 && name_str(&w.maps[1].name) == "m_copy" && w.map_count == 3)
	testing.expect_value(t, world_rename_map(w, 1, "m"), Name_Problem.In_Use)
	testing.expect(t, world_delete_map(w, 1) && w.map_count == 2)
	for w.map_count < WORLD_MAX_MAPS {
		testing.expect(t, world_add_map(w, 0) >= 0)
	}
	testing.expect_value(t, world_add_map(w, 0), -1)
	testing.expect_value(t, world_duplicate_map(w, 0), -1)
}

@(test)
test_a_map_changes_its_terrain_set_only_if_every_cell_still_exists :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	// Set 2 holds the same names in another order plus one more; set 3 lacks "rock".
	s2 := world_add_terrain_set(w, "s2")
	name_assign(&w.sets[s2].terrains[0].name, "rock")
	g := world_add_terrain(w, s2)
	name_assign(&w.sets[s2].terrains[g].name, "grass")
	extra := world_add_terrain(w, s2)
	name_assign(&w.sets[s2].terrains[extra].name, "lava")
	w.sets[s2].default = 2
	s3 := world_add_terrain_set(w, "s3")
	name_assign(&w.sets[s3].terrains[0].name, "grass")
	ok, missing, cells := world_map_change_set(w, 0, s3)
	testing.expect(t, !ok && missing == "rock" && cells == 2)
	testing.expect_value(t, name_str(&w.maps[0].set), "s") // nothing changed
	testing.expect_value(t, w.maps[0].cells[0][1], 1)
	ok, _, _ = world_map_change_set(w, 0, s2)
	testing.expect(t, ok && name_str(&w.maps[0].set) == "s2")
	testing.expect_value(t, w.maps[0].cells[0][0], 1) // grass is now index 1
	testing.expect_value(t, w.maps[0].cells[0][1], 0) // rock is now index 0
	testing.expect_value(t, w.maps[0].cells[1][2], 0)
	testing.expect_value(t, w.maps[0].cells[3][3], 2) // hidden cells get the new default (lava)
	// Cells that are not visible do not block a change.
	world_map_set_size(w, 0, 1, 1)
	ok, _, _ = world_map_change_set(w, 0, s3)
	testing.expect(t, ok) // the one visible cell is grass
}

@(test)
test_the_world_file_text_for_a_tiny_world :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	world_set_tile_size(w, 2, 1)
	ts := world_add_tileset(w, "t")
	tileset_insert_blank(&w.tilesets[ts], 0, "i")
	image4_set(&w.tilesets[ts].images[0], 0, 0, 1)
	si := world_add_terrain_set(w, "set")
	mi := world_add_map(w, si, "m")
	world_map_set_size(w, mi, 2, 1)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `"tile_width": 2`))
	testing.expect(t, strings.contains(text, `{"name": "t", "tileset": {`))
	testing.expect(t, strings.contains(text, `{"name": "terrain", "tags": [], "tileset": "t", "image": "i"}`))
	testing.expect(t, strings.contains(text, `"terrain_set": "set", "columns": 2, "rows": 1`))
	testing.expect(t, strings.contains(text, `"terrains": ["terrain"]`))
	testing.expect(t, strings.contains(text, "0, 0"))
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
}

@(test)
test_a_world_round_trips :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	text := world_to_json(w)
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect(t, back.tile_w == 4 && back.palette[3] == Color{10, 20, 30})
	testing.expect(t, back.tileset_count == 2 && back.sets[0].count == 2 && back.maps[0].width == 3)
	testing.expect(t, back.sets[0].terrains[1].tags == 1 && name_str(&back.sets[0].terrains[1].image) == "y")
	testing.expect(t, back.tilesets[0].images[1].pixels[1][2] == 9)
	testing.expect(t, back.maps[0].cells[0][1] == 1 && back.maps[0].cells[1][2] == 1 && back.maps[0].cells[0][0] == 0)
	// A map's cells are written as positions in its own list of names, so renumbering a set
	// does not disturb the file's meaning.
	w.sets[0].default = 1
	w.maps[0].cells[0][0] = 1
	text = world_to_json(w)
	testing.expect(t, strings.contains(text, `"terrains": ["rock", "grass"]`))
}

load_error :: proc(text: string) -> string {
	w := new_world()
	defer free(w)
	return world_from_json(transmute([]u8)text, w)
}

@(test)
test_bad_world_files_are_rejected_with_a_reason :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sample_world()
	defer free(w)
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	// Each variation breaks one rule; all must be refused (and say something).
	variations := [][2]string {
		{`"tile_width": 4`, `"tile_width": 0`},
		{`"tile_width": 4`, `"tile_width": 65`},
		{`"tile_height": 4`, `"tile_height": "x"`},
		{`"r": 10, "g": 20`, `"r": 300, "g": 20`},
		{`"name": "b"`, `"name": "a"`}, // duplicate tileset name
		{`"name": "grass"`, `"name": "rock"`}, // duplicate terrain name
		{`"default": "grass"`, `"default": "nothing"`},
		{`"tileset": "a", "image": "x"`, `"tileset": "nope", "image": "x"`},
		{`"tileset": "a", "image": "x"`, `"tileset": "a", "image": "nope"`},
		{`"tileset": "a", "image": "x"`, `"tileset": "a", "image": ""`},
		{`"tags": ["solid"], "tileset"`, `"tags": ["nope"], "tileset"`},
		{`"terrain_set": "s"`, `"terrain_set": "zzz"`},
		{`"columns": 3`, `"columns": 0`},
		{`"columns": 3`, `"columns": 4`}, // the cell count no longer matches
		{`"terrains": ["grass", "rock"]`, `"terrains": ["grass", "lava"]`},
		{`"terrains": ["grass", "rock"]`, `"terrains": ["grass"]`}, // a cell now points past the list
		{`"name": "m"`, `"name": ""`},
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		msg := load_error(bad)
		testing.expectf(t, msg != "", "variation %d was accepted", i)
	}
	testing.expect(t, load_error("nonsense") != "")
	testing.expect(t, load_error("[]") != "")
	// A tileset of another size than the world's.
	w2 := new_world()
	defer free(w2)
	world_add_tileset(w2)
	text2 := world_to_json(w2)
	bad2, _ := strings.replace(text2, `"tile_width": 16`, `"tile_width": 8`, 1, context.temp_allocator)
	testing.expect(t, strings.contains(load_error(bad2), "tiles are"))
	// A failed load leaves the destination alone.
	dst := sample_world()
	defer free(dst)
	before := world_to_json(dst)
	testing.expect(t, world_from_json(transmute([]u8)string("{}"), dst) != "")
	testing.expect_value(t, world_to_json(dst), before)
}

@(test)
test_a_big_world_round_trips :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := new_world()
	defer free(w)
	world_set_tile_size(w, 16, 16)
	for _ in 0 ..< 4 {
		i := world_add_tileset(w)
		for k in 0 ..< 40 {
			n := tileset_insert_blank(&w.tilesets[i], k, "t")
			image4_set(&w.tilesets[i].images[n], k % 16, k % 7, k % 16)
		}
	}
	for _ in 0 ..< 3 {
		si := world_add_terrain_set(w)
		for _ in 0 ..< 59 {
			world_add_terrain(w, si)
		}
	}
	for k in 0 ..< 10 {
		m := world_add_map(w, k % 3)
		world_map_set_size(w, m, 64, 64)
		for y in 0 ..< 64 {
			for x in 0 ..< 64 {
				w.maps[m].cells[y][x] = u8((x * 7 + y * 3 + k) % 60)
			}
		}
	}
	text := world_to_json(w)
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
}

// --- Sprites ---

// The sample world plus sprite set "creatures" holding slime (a/x, transparent 0) and bat (a/y, none).
sprite_world :: proc() -> ^World {
	w := sample_world()
	si := world_add_sprite_set(w, "creatures")
	slime := world_add_sprite(w, si)
	name_assign(&w.sprite_sets[si].sprites[slime].name, "slime")
	bat := world_add_sprite(w, si)
	name_assign(&w.sprite_sets[si].sprites[bat].name, "bat")
	name_assign(&w.sprite_sets[si].sprites[bat].image, "y")
	w.sprite_sets[si].sprites[bat].transparent = SPRITE_NO_TRANSPARENT
	return w
}

@(test)
test_sprite_sets_and_sprites_are_named_and_limited :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sprite_world()
	defer free(w)
	s := &w.sprite_sets[0]
	testing.expect(t, s.count == 2 && s.sprites[0].transparent == 0 && s.sprites[1].transparent == SPRITE_NO_TRANSPARENT)
	testing.expect_value(t, name_str(&s.sprites[0].tileset), "a")
	testing.expect_value(t, name_str(&s.sprites[0].image), "x")
	testing.expect(t, world_sprite_image(w, &s.sprites[1]) == &w.tilesets[0].images[1])
	n := world_add_sprite(w, 0)
	testing.expect_value(t, name_str(&s.sprites[n].name), "sprite")
	testing.expect_value(t, world_add_sprite(w, 3), -1)
	testing.expect_value(t, sprite_check_name(s, n, "bat"), Name_Problem.In_Use)
	testing.expect_value(t, sprite_check_name(s, n, "sprite"), Name_Problem.None)
	testing.expect_value(t, sprite_check_name(s, n, ""), Name_Problem.Empty)
	d := world_duplicate_sprite(w, 0, 0)
	testing.expect(t, d == 3 && name_str(&s.sprites[3].name) == "slime_copy" && s.sprites[3].transparent == 0)
	testing.expect(t, world_delete_sprite(w, 0, 0) && s.count == 3 && name_str(&s.sprites[0].name) == "bat")
	testing.expect(t, !world_delete_sprite(w, 0, 9))
	for s.count < SPRITE_MAX {
		world_add_sprite(w, 0)
	}
	testing.expect_value(t, world_add_sprite(w, 0), -1)
	testing.expect_value(t, world_duplicate_sprite(w, 0, 0), -1)
	// An empty world's new sprite is not set.
	e := new_world()
	defer free(e)
	es := world_add_sprite_set(e)
	ns := world_add_sprite(e, es)
	testing.expect(t, e.sprite_sets[es].sprites[ns].tileset.len == 0 && world_sprite_image(e, &e.sprite_sets[es].sprites[ns]) == nil)
	// Sets.
	for e.sprite_set_count < WORLD_MAX_SPRITE_SETS {
		testing.expect(t, world_add_sprite_set(e) >= 0)
	}
	testing.expect_value(t, world_add_sprite_set(e), -1)
	testing.expect_value(t, world_duplicate_sprite_set(e, 0), -1)
	testing.expect_value(t, world_check_sprite_set_name(e, 0, name_str(&e.sprite_sets[1].name)), Name_Problem.In_Use)
	testing.expect_value(t, world_rename_sprite_set(e, 0, "zoo"), Name_Problem.None)
	testing.expect(t, world_delete_sprite_set(e, 0) && e.sprite_set_count == 15 && !world_delete_sprite_set(e, 15))
}

@(test)
test_sprites_keep_tilesets_and_images_in_use_and_follow_renames :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sprite_world()
	defer free(w)
	// Terrains use a/x and a/y; the sprites use a/x and a/y as well.
	testing.expect_value(t, world_tileset_uses(w, "a"), 4)
	testing.expect_value(t, world_tileset_sprite_uses(w, "a"), 2)
	testing.expect_value(t, world_image_uses(w, "a", "y"), 2)
	testing.expect_value(t, world_image_sprite_uses(w, "a", "y"), 1)
	testing.expect_value(t, world_delete_tileset(w, 0), 4)
	// Point the terrains elsewhere: the sprites alone still hold the tileset.
	for ti in 0 ..< w.sets[0].count {
		w.sets[0].terrains[ti].tileset, w.sets[0].terrains[ti].image = {}, {}
	}
	testing.expect_value(t, world_delete_tileset(w, 0), 2)
	testing.expect_value(t, world_rename_tileset(w, 0, "ground"), Name_Problem.None)
	testing.expect_value(t, name_str(&w.sprite_sets[0].sprites[1].tileset), "ground")
	world_rename_image(w, "ground", "y", "yy")
	testing.expect_value(t, name_str(&w.sprite_sets[0].sprites[1].image), "yy")
	testing.expect_value(t, name_str(&w.sprite_sets[0].sprites[0].image), "x")
	w.sprite_sets[0].count = 0
	testing.expect_value(t, world_delete_tileset(w, 0), 0)
	testing.expect_value(t, uses_text(1, 0), "1 TERRAIN")
	testing.expect_value(t, uses_text(2, 0), "2 TERRAINS")
	testing.expect_value(t, uses_text(1, 1), "1 TERRAIN AND 1 SPRITE")
	testing.expect_value(t, uses_text(0, 3), "0 TERRAINS AND 3 SPRITES")
}

@(test)
test_sprite_sets_round_trip_and_old_files_still_load :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sprite_world()
	defer free(w)
	text := world_to_json(w)
	testing.expect(t, strings.contains(text, `"sprite_sets": [`))
	testing.expect(t, strings.contains(text, `{"name": "slime", "tileset": "a", "image": "x", "transparent": 0}`))
	testing.expect(t, strings.contains(text, `"transparent": null`))
	back := new_world()
	defer free(back)
	testing.expect_value(t, world_from_json(transmute([]u8)text, back), "")
	testing.expect_value(t, world_to_json(back), text)
	testing.expect(t, back.sprite_set_count == 1 && back.sprite_sets[0].count == 2 && back.sprite_sets[0].sprites[1].transparent == SPRITE_NO_TRANSPARENT)
	// A file from before sprites (no "sprite_sets") loads with none; an empty set round-trips.
	old, _ := strings.replace(text, `  "sprite_sets": [`, `  "sprite_sets_old_name": [`, 1, context.temp_allocator)
	testing.expect_value(t, world_from_json(transmute([]u8)old, back), "")
	testing.expect_value(t, back.sprite_set_count, 0)
	empty := new_world()
	defer free(empty)
	world_add_sprite_set(empty, "none")
	back2 := new_world()
	defer free(back2)
	testing.expect_value(t, world_from_json(transmute([]u8)world_to_json(empty), back2), "")
	testing.expect(t, back2.sprite_set_count == 1 && back2.sprite_sets[0].count == 0)
	// The tiny world's file is unchanged apart from the new list.
	testing.expect(t, strings.has_suffix(world_to_json(new_world()), "\"player\": null\n}\n"))
}

@(test)
test_bad_sprite_files_are_rejected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := sprite_world()
	defer free(w)
	good := world_to_json(w)
	testing.expect_value(t, load_error(good), "")
	variations := [][2]string {
		{`"name": "creatures"`, `"name": ""`},
		{`"name": "slime"`, `"name": "bat"`}, // duplicate sprite name
		{`"transparent": 0}`, `"transparent": 16}`},
		{`"transparent": 0}`, `"transparent": -2}`},
		{`"transparent": 0}`, `"transparent": "x"}`},
		{`"transparent": 0}`, `"colour": 0}`},
		{`"name": "slime", "tileset": "a"`, `"name": "slime", "tileset": "nope"`},
		{`"name": "slime", "tileset": "a", "image": "x"`, `"name": "slime", "tileset": "a", "image": "nope"`},
		{`"name": "slime", "tileset": "a", "image": "x"`, `"name": "slime", "tileset": "a", "image": ""`},
		{`"sprite_sets": [`, `"sprite_sets": {"x": [`},
	}
	for v, i in variations {
		testing.expectf(t, strings.contains(good, v[0]), "variation %d: %q is not in the sample file", i, v[0])
		bad, _ := strings.replace(good, v[0], v[1], 1, context.temp_allocator)
		testing.expectf(t, load_error(bad) != "", "variation %d was accepted", i)
	}
}
