package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// A world: one tile size, one palette, up to 16 named tilesets (all at the world's tile size), up to
// 16 named terrain sets (each up to 256 named terrains, with a default one) and up to 64 named maps.
// A terrain names a tileset and an image in it (both empty = not set yet) and is solid or not. A map
// names the terrain set it uses; its cells hold indexes into that set's terrains.
//
// A World is about 17 MB (the tilesets). Never copy or return one by value: use a global or new()
// and the in-place procs below.

WORLD_MAX_TILESETS :: 16
WORLD_MAX_TERRAIN_SETS :: 16
WORLD_MAX_MAPS :: 64
WORLD_MAX_SPRITE_SETS :: 16
SPRITE_MAX :: 256
WORLD_MAX_CHARACTER_TYPES :: 64
WORLD_MAX_CHARACTERS :: 1024
SPRITE_NO_TRANSPARENT :: -1 // a sprite whose every colour is drawn
TERRAIN_MAX :: 256
MAP_MAX :: 64
MAP_DEFAULT_SIZE :: 32
NAME_MAX :: TILESET_NAME_MAX

Name :: struct {
	len:  int,
	text: [NAME_MAX]u8,
}

name_str :: proc(n: ^Name) -> string {
	return string(n.text[:n.len])
}

name_assign :: proc(n: ^Name, s: string) {
	n^ = {}
	k := min(len(s), NAME_MAX)
	copy(n.text[:], s[:k])
	n.len = k
}

// Empty, too long or a character other than printable ASCII; None says the text itself is fine.
name_text_problem :: proc(s: string) -> Name_Problem {
	if len(s) == 0 {
		return .Empty
	}
	if len(s) > NAME_MAX {
		return .Too_Long
	}
	for i in 0 ..< len(s) {
		if s[i] < 32 || s[i] > 126 {
			return .Bad_Character
		}
	}
	return .None
}

// base itself, else base_2, base_3 ... (cut short to fit), avoiding every name in `taken`.
unique_among :: proc(base: string, taken: []string) -> string {
	b := base
	if len(b) == 0 {
		b = "item"
	}
	if len(b) > NAME_MAX {
		b = b[:NAME_MAX]
	}
	is_taken :: proc(taken: []string, s: string) -> bool {
		for t in taken {
			if t == s {
				return true
			}
		}
		return false
	}
	if !is_taken(taken, b) {
		return strings.clone(b, context.temp_allocator)
	}
	for n in 2 ..= len(taken) + 2 {
		suffix := fmt.tprintf("_%d", n)
		candidate := fmt.tprintf("%s%s", b[:min(len(b), NAME_MAX - len(suffix))], suffix)
		if !is_taken(taken, candidate) {
			return candidate
		}
	}
	return strings.clone(b, context.temp_allocator)
}

Terrain :: struct {
	name:    Name,
	tags:    Tag_Mask, // the tags this terrain has (bit i = world tag i)
	tileset: Name, // empty = not set
	image:   Name, // the image's name within that tileset; empty = not set
}

Terrain_Set :: struct {
	name:     Name,
	count:    int, // 1..TERRAIN_MAX: a set always has at least one terrain
	default:  int, // the terrain new map cells get
	terrains: [TERRAIN_MAX]Terrain,
}

// A sprite is a tile of a tileset drawn without one colour (its transparent index, or none).
Sprite :: struct {
	name:        Name,
	tileset:     Name, // empty = not set
	image:       Name, // empty = not set
	transparent: int, // a palette index 0..15 that is not drawn, or SPRITE_NO_TRANSPARENT
}

Sprite_Set :: struct {
	name:    Name,
	count:   int, // 0..SPRITE_MAX: unlike a terrain set, a sprite set may be empty
	sprites: [SPRITE_MAX]Sprite,
}

World_Map :: struct {
	name:          Name,
	set:           Name, // the terrain set whose terrains the cells index
	width, height: int, // columns and rows, 1..MAP_MAX
	cells:         [MAP_MAX][MAP_MAX]u8, // [row][column]: a terrain index in the set; only the visible region counts
	characters:    [MAP_MAX][MAP_MAX]Uuid, // [row][column]: the character standing there (a uuid of the world's table) or none
	features:      [MAP_MAX][MAP_MAX]Uuid, // [row][column]: the feature standing there (a uuid of the features table) or none; never together with a character
	cell_tags:     [MAP_MAX][MAP_MAX]Cell_Tags, // [row][column]: a cell's own tag settings (else its terrain's)
	inventories:   [MAP_MAX][MAP_MAX]Uuid, // [row][column]: the inventory lying there (a uuid of the inventories table) or none; never blocks
}

World :: struct {
	tile_w, tile_h: int,
	palette:        Palette,
	tileset_count:  int,
	tileset_names:  [WORLD_MAX_TILESETS]Name,
	tilesets:       [WORLD_MAX_TILESETS]Tileset,
	set_count:      int,
	sets:           [WORLD_MAX_TERRAIN_SETS]Terrain_Set,
	map_count:      int,
	maps:           [WORLD_MAX_MAPS]World_Map,
	sprite_set_count: int,
	sprite_sets:    [WORLD_MAX_SPRITE_SETS]Sprite_Set,
	char_type_count: int,
	char_types:     [WORLD_MAX_CHARACTER_TYPES]Character_Type,
	character_count: int,
	characters:     [WORLD_MAX_CHARACTERS]Character, // the table every map cell and the player refer into, by uuid
	feature_type_count: int,
	feature_types:  [WORLD_MAX_FEATURE_TYPES]Feature_Type,
	feature_count:  int,
	features:       [WORLD_MAX_FEATURES]Feature, // like the characters table: map cells refer into it by uuid
	item_type_count: int,
	item_types:     [WORLD_MAX_ITEM_TYPES]Item_Type,
	inventory_count: int,
	inventories:    [WORLD_MAX_INVENTORIES]Inventory, // held by a character, a feature or a map cell (world_items.odin)
	entry_count:    int,
	entries:        [WORLD_MAX_ENTRIES]Entry, // every inventory's entries, in order, in one pool
	player:         Uuid, // the player's character, or none
	uuid_state:     u64, // the generator for new uuids (see world_new_uuid)
	tag_count:      int,
	tags:           [WORLD_MAX_TAGS]Name, // tag 0 is always "solid"
	param_count:    int,
	params:         [WORLD_MAX_PARAMS]Param, // game parameters: named numbers and short texts
	sound_count:    int,
	sounds:         [WORLD_MAX_SOUNDS]Sound, // PLAY-style tunes and effects (world_sounds.odin)
}

world_reset :: proc(w: ^World) {
	w^ = {}
	w.tile_w, w.tile_h = TILESET_DEFAULT_SIZE, TILESET_DEFAULT_SIZE
	w.palette = default_palette()
	w.uuid_state = 0x9E3779B97F4A7C15
	w.tag_count = 1
	name_assign(&w.tags[TAG_SOLID], TAG_SOLID_NAME)
}

// --- Finding -----------------------------------------------------------------------------------

world_find_tileset :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.tileset_count {
		if i != except && name_str(&w.tileset_names[i]) == name {
			return i
		}
	}
	return -1
}

world_find_set :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.set_count {
		if i != except && name_str(&w.sets[i].name) == name {
			return i
		}
	}
	return -1
}

world_find_map :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.map_count {
		if i != except && name_str(&w.maps[i].name) == name {
			return i
		}
	}
	return -1
}

set_find_terrain :: proc(s: ^Terrain_Set, name: string, except := -1) -> int {
	for i in 0 ..< s.count {
		if i != except && name_str(&s.terrains[i].name) == name {
			return i
		}
	}
	return -1
}

// The terrain set a map uses, or nil if its name matches none.
world_map_set :: proc(w: ^World, mi: int) -> ^Terrain_Set {
	if mi < 0 || mi >= w.map_count {
		return nil
	}
	si := world_find_set(w, name_str(&w.maps[mi].set))
	return si >= 0 ? &w.sets[si] : nil
}

// The image a terrain draws, or nil while it is not set (or points at nothing).
world_terrain_image :: proc(w: ^World, t: ^Terrain) -> ^Image4 {
	ti := world_find_tileset(w, name_str(&t.tileset))
	if ti < 0 {
		return nil
	}
	ii := tileset_find(&w.tilesets[ti], name_str(&t.image))
	return ii >= 0 ? &w.tilesets[ti].images[ii] : nil
}

// --- Names -------------------------------------------------------------------------------------

world_check_tileset_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_tileset(w, name, index) >= 0 ? .In_Use : .None
}

world_check_set_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_set(w, name, index) >= 0 ? .In_Use : .None
}

world_check_map_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_map(w, name, index) >= 0 ? .In_Use : .None
}

terrain_check_name :: proc(s: ^Terrain_Set, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return set_find_terrain(s, name, index) >= 0 ? .In_Use : .None
}

@(private = "file")
tileset_name_list :: proc(w: ^World) -> []string {
	out := make([]string, w.tileset_count, context.temp_allocator)
	for i in 0 ..< w.tileset_count {
		out[i] = name_str(&w.tileset_names[i])
	}
	return out
}

@(private = "file")
set_name_list :: proc(w: ^World) -> []string {
	out := make([]string, w.set_count, context.temp_allocator)
	for i in 0 ..< w.set_count {
		out[i] = name_str(&w.sets[i].name)
	}
	return out
}

@(private = "file")
map_name_list :: proc(w: ^World) -> []string {
	out := make([]string, w.map_count, context.temp_allocator)
	for i in 0 ..< w.map_count {
		out[i] = name_str(&w.maps[i].name)
	}
	return out
}

@(private = "file")
terrain_name_list :: proc(s: ^Terrain_Set) -> []string {
	out := make([]string, s.count, context.temp_allocator)
	for i in 0 ..< s.count {
		out[i] = name_str(&s.terrains[i].name)
	}
	return out
}

// --- Tile size and palette ---------------------------------------------------------------------

// Changes the world's tile size (clamped) and every tileset's with it (hidden pixels survive).
world_set_tile_size :: proc(w: ^World, width, height: int) -> bool {
	tw, th := clamp(width, IMAGE_MIN, IMAGE_MAX), clamp(height, IMAGE_MIN, IMAGE_MAX)
	if tw == w.tile_w && th == w.tile_h {
		return false
	}
	w.tile_w, w.tile_h = tw, th
	for i in 0 ..< w.tileset_count {
		tileset_set_size(&w.tilesets[i], tw, th)
	}
	return true
}

// --- Tilesets ----------------------------------------------------------------------------------

// Adds an empty tileset at the world's tile size. Returns its index, or -1 if the world is full.
world_add_tileset :: proc(w: ^World, base := "tileset") -> int {
	if w.tileset_count >= WORLD_MAX_TILESETS {
		return -1
	}
	i := w.tileset_count
	name := unique_among(base, tileset_name_list(w))
	tileset_reset(&w.tilesets[i], w.tile_w, w.tile_h)
	name_assign(&w.tileset_names[i], name)
	w.tileset_count += 1
	return i
}

// Adds a copy of an outside tileset (already checked to have the world's tile size) under a unique
// name. Returns the index, -1 if the world is full, -2 if the tile size differs.
world_add_tileset_copy :: proc(w: ^World, src: ^Tileset, base: string) -> int {
	if src.width != w.tile_w || src.height != w.tile_h {
		return -2
	}
	i := world_add_tileset(w, base)
	if i >= 0 {
		w.tilesets[i] = src^
	}
	return i
}

// Copies tileset i right after itself as "<name>_copy". Returns the new index or -1 if full.
world_duplicate_tileset :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.tileset_count || w.tileset_count >= WORLD_MAX_TILESETS {
		return -1
	}
	at := i + 1
	for k := w.tileset_count; k > at; k -= 1 {
		w.tilesets[k] = w.tilesets[k - 1]
		w.tileset_names[k] = w.tileset_names[k - 1]
	}
	name := unique_among(fmt.tprintf("%s_copy", name_str(&w.tileset_names[i])), tileset_name_list(w))
	w.tilesets[at] = w.tilesets[i]
	name_assign(&w.tileset_names[at], name)
	w.tileset_count += 1
	return at
}

// How many terrains and sprites (in any set) use this tileset.
world_tileset_uses :: proc(w: ^World, tileset: string) -> (n: int) {
	n = world_tileset_sprite_uses(w, tileset)
	for si in 0 ..< w.set_count {
		s := &w.sets[si]
		for ti in 0 ..< s.count {
			if name_str(&s.terrains[ti].tileset) == tileset {
				n += 1
			}
		}
	}
	return
}

// How many terrains and sprites use this image of this tileset.
world_image_uses :: proc(w: ^World, tileset, image: string) -> (n: int) {
	n = world_image_sprite_uses(w, tileset, image)
	for si in 0 ..< w.set_count {
		s := &w.sets[si]
		for ti in 0 ..< s.count {
			t := &s.terrains[ti]
			if name_str(&t.tileset) == tileset && name_str(&t.image) == image {
				n += 1
			}
		}
	}
	return
}

// Deletes tileset i unless a terrain uses it. Returns the number of terrains in the way (0 = done).
world_delete_tileset :: proc(w: ^World, i: int) -> (uses: int) {
	if i < 0 || i >= w.tileset_count {
		return 0
	}
	if uses = world_tileset_uses(w, name_str(&w.tileset_names[i])); uses > 0 {
		return
	}
	for k in i ..< w.tileset_count - 1 {
		w.tilesets[k] = w.tilesets[k + 1]
		w.tileset_names[k] = w.tileset_names[k + 1]
	}
	last := w.tileset_count - 1
	w.tilesets[last] = {}
	w.tileset_names[last] = {}
	w.tileset_count -= 1
	return 0
}

// Renames tileset i; every terrain that used the old name follows.
world_rename_tileset :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.tileset_count {
		return .Empty
	}
	if p := world_check_tileset_name(w, i, name); p != .None {
		return p
	}
	old := strings.clone(name_str(&w.tileset_names[i]), context.temp_allocator)
	for si in 0 ..< w.set_count {
		for ti in 0 ..< w.sets[si].count {
			t := &w.sets[si].terrains[ti]
			if name_str(&t.tileset) == old {
				name_assign(&t.tileset, name)
			}
		}
	}
	sprites_follow_tileset(w, old, name)
	name_assign(&w.tileset_names[i], name)
	return .None
}

// An image of a tileset was renamed: every terrain and sprite that used it follows.
world_rename_image :: proc(w: ^World, tileset, old, new: string) {
	sprites_follow_image(w, tileset, old, new)
	for si in 0 ..< w.set_count {
		for ti in 0 ..< w.sets[si].count {
			t := &w.sets[si].terrains[ti]
			if name_str(&t.tileset) == tileset && name_str(&t.image) == old {
				name_assign(&t.image, new)
			}
		}
	}
}

// --- Terrain sets and terrains -----------------------------------------------------------------

// Points a terrain at the first image of the first tileset that has one; not set if there is none.
world_point_at_first_image :: proc(w: ^World, t: ^Terrain) {
	t.tileset, t.image = {}, {}
	for i in 0 ..< w.tileset_count {
		if w.tilesets[i].count > 0 {
			t.tileset = w.tileset_names[i]
			name_assign(&t.image, tileset_name(&w.tilesets[i], 0))
			return
		}
	}
}

@(private = "file")
fill_new_terrain :: proc(w: ^World, s: ^Terrain_Set, i: int, base: string) {
	s.terrains[i] = {}
	name_assign(&s.terrains[i].name, unique_among(base, terrain_name_list(s)))
	world_point_at_first_image(w, &s.terrains[i])
}

// Adds a terrain set holding one terrain ("terrain", the default). Returns its index or -1 if full.
world_add_terrain_set :: proc(w: ^World, base := "terrains") -> int {
	if w.set_count >= WORLD_MAX_TERRAIN_SETS {
		return -1
	}
	i := w.set_count
	w.sets[i] = {}
	name_assign(&w.sets[i].name, unique_among(base, set_name_list(w)))
	fill_new_terrain(w, &w.sets[i], 0, "terrain")
	w.sets[i].count = 1
	w.set_count += 1
	return i
}

world_duplicate_terrain_set :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.set_count || w.set_count >= WORLD_MAX_TERRAIN_SETS {
		return -1
	}
	at := i + 1
	for k := w.set_count; k > at; k -= 1 {
		w.sets[k] = w.sets[k - 1]
	}
	// the maps list is not shifted: maps name their sets, so nothing else moves
	copy_ := w.sets[i]
	w.sets[at] = copy_
	name_assign(&w.sets[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.sets[i].name)), set_name_list(w)))
	w.set_count += 1
	return at
}

// How many maps use this terrain set.
world_set_uses :: proc(w: ^World, set: string) -> (n: int) {
	for mi in 0 ..< w.map_count {
		if name_str(&w.maps[mi].set) == set {
			n += 1
		}
	}
	return
}

// Deletes set i unless a map uses it. Returns the number of maps in the way (0 = done).
world_delete_terrain_set :: proc(w: ^World, i: int) -> (uses: int) {
	if i < 0 || i >= w.set_count {
		return 0
	}
	if uses = world_set_uses(w, name_str(&w.sets[i].name)); uses > 0 {
		return
	}
	for k in i ..< w.set_count - 1 {
		w.sets[k] = w.sets[k + 1]
	}
	w.sets[w.set_count - 1] = {}
	w.set_count -= 1
	return 0
}

// Renames set i; every map that used the old name follows.
world_rename_terrain_set :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.set_count {
		return .Empty
	}
	if p := world_check_set_name(w, i, name); p != .None {
		return p
	}
	old := strings.clone(name_str(&w.sets[i].name), context.temp_allocator)
	for mi in 0 ..< w.map_count {
		if name_str(&w.maps[mi].set) == old {
			name_assign(&w.maps[mi].set, name)
		}
	}
	name_assign(&w.sets[i].name, name)
	return .None
}

// Adds a terrain to set si ("terrain", pointing at the first image if there is one). Returns its
// index or -1 if the set is full.
world_add_terrain :: proc(w: ^World, si: int) -> int {
	if si < 0 || si >= w.set_count || w.sets[si].count >= TERRAIN_MAX {
		return -1
	}
	s := &w.sets[si]
	i := s.count
	fill_new_terrain(w, s, i, "terrain")
	s.count += 1
	return i
}

world_duplicate_terrain :: proc(w: ^World, si, ti: int) -> int {
	if si < 0 || si >= w.set_count {
		return -1
	}
	s := &w.sets[si]
	if ti < 0 || ti >= s.count || s.count >= TERRAIN_MAX {
		return -1
	}
	// A new terrain goes at the end so that no map cell has to be renumbered.
	i := s.count
	s.terrains[i] = s.terrains[ti]
	name_assign(&s.terrains[i].name, unique_among(fmt.tprintf("%s_copy", name_str(&s.terrains[ti].name)), terrain_name_list(s)))
	s.count += 1
	return i
}

// How many cells of maps that use set si hold terrain ti.
world_terrain_uses :: proc(w: ^World, si, ti: int) -> (n: int) {
	if si < 0 || si >= w.set_count {
		return 0
	}
	set_name := name_str(&w.sets[si].name)
	for mi in 0 ..< w.map_count {
		m := &w.maps[mi]
		if name_str(&m.set) != set_name {
			continue
		}
		for y in 0 ..< m.height {
			for x in 0 ..< m.width {
				if int(m.cells[y][x]) == ti {
					n += 1
				}
			}
		}
	}
	return
}

Terrain_Delete :: enum {
	Deleted,
	Last_One, // a set keeps at least one terrain
	Is_Default, // make another terrain the default first
	In_Use, // map cells use it
}

// Deletes terrain ti of set si, closing the gap and renumbering the cells of maps that use the set.
world_delete_terrain :: proc(w: ^World, si, ti: int) -> (result: Terrain_Delete, uses: int) {
	if si < 0 || si >= w.set_count || ti < 0 || ti >= w.sets[si].count {
		return .Deleted, 0
	}
	s := &w.sets[si]
	if s.count <= 1 {
		return .Last_One, 0
	}
	if s.default == ti {
		return .Is_Default, 0
	}
	if uses = world_terrain_uses(w, si, ti); uses > 0 {
		return .In_Use, uses
	}
	set_name := name_str(&s.name)
	for mi in 0 ..< w.map_count {
		m := &w.maps[mi]
		if name_str(&m.set) != set_name {
			continue
		}
		for y in 0 ..< MAP_MAX {
			for x in 0 ..< MAP_MAX {
				if int(m.cells[y][x]) > ti {
					m.cells[y][x] -= 1
				}
			}
		}
	}
	for k in ti ..< s.count - 1 {
		s.terrains[k] = s.terrains[k + 1]
	}
	s.terrains[s.count - 1] = {}
	s.count -= 1
	if s.default > ti {
		s.default -= 1
	}
	return .Deleted, 0
}

// --- Maps --------------------------------------------------------------------------------------

@(private = "file")
fill_cells :: proc(m: ^World_Map, value: u8) {
	for y in 0 ..< MAP_MAX {
		for x in 0 ..< MAP_MAX {
			m.cells[y][x] = value
		}
	}
}

// Adds a map using terrain set `si`, MAP_DEFAULT_SIZE square, every cell the set's default. Returns
// its index, or -1 if the world has 64 maps or the set does not exist.
world_add_map :: proc(w: ^World, si: int, base := "map") -> int {
	if w.map_count >= WORLD_MAX_MAPS || si < 0 || si >= w.set_count {
		return -1
	}
	i := w.map_count
	m := &w.maps[i]
	m^ = {}
	name_assign(&m.name, unique_among(base, map_name_list(w)))
	m.set = w.sets[si].name
	m.width, m.height = MAP_DEFAULT_SIZE, MAP_DEFAULT_SIZE
	fill_cells(m, u8(w.sets[si].default))
	w.map_count += 1
	return i
}

world_duplicate_map :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.map_count || w.map_count >= WORLD_MAX_MAPS {
		return -1
	}
	at := i + 1
	for k := w.map_count; k > at; k -= 1 {
		w.maps[k] = w.maps[k - 1]
	}
	w.maps[at] = w.maps[i]
	w.maps[at].characters = {} // a character or feature stands in one cell of the world: the copy has none
	w.maps[at].features = {}
	w.maps[at].inventories = {}
	name_assign(&w.maps[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.maps[i].name)), map_name_list(w)))
	w.map_count += 1
	return at
}

world_delete_map :: proc(w: ^World, i: int) -> bool {
	if i < 0 || i >= w.map_count {
		return false
	}
	world_map_clear_inventories(w, i) // what lay on its cells goes with it
	for k in i ..< w.map_count - 1 {
		w.maps[k] = w.maps[k + 1]
	}
	w.maps[w.map_count - 1] = {}
	w.map_count -= 1
	return true
}

world_rename_map :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.map_count {
		return .Empty
	}
	if p := world_check_map_name(w, i, name); p != .None {
		return p
	}
	name_assign(&w.maps[i].name, name)
	return .None
}

// Resizes map mi (sizes clamped to 1..MAP_MAX). Cells that appear take the set's default terrain;
// cells cut off are forgotten. Refused (false) while a character stands in the part that would be
// cut off (see world_map_shrink_blocked). Returns true if the size changed.
world_map_set_size :: proc(w: ^World, mi, width, height: int) -> bool {
	if mi < 0 || mi >= w.map_count {
		return false
	}
	m := &w.maps[mi]
	nw, nh := clamp(width, 1, MAP_MAX), clamp(height, 1, MAP_MAX)
	if nw == m.width && nh == m.height {
		return false
	}
	if world_map_shrink_blocked(w, mi, nw, nh) > 0 {
		return false // a character would be cut off: move it first
	}
	default := u8(0)
	if s := world_map_set(w, mi); s != nil {
		default = u8(s.default)
	}
	for y in 0 ..< MAP_MAX {
		for x in 0 ..< MAP_MAX {
			if x >= nw || y >= nh || x >= m.width || y >= m.height {
				m.cells[y][x] = default // cut off, or newly shown
				m.cell_tags[y][x] = {}
			}
		}
	}
	m.width, m.height = nw, nh
	return true
}

// Moves map mi to another terrain set, keeping each cell's terrain by name. Refused (nothing
// changes, `missing` is the first name the new set lacks) unless every visible cell's terrain exists
// in the new set. Returns ok and, if refused, how many cells are in the way.
world_map_change_set :: proc(w: ^World, mi, new_si: int) -> (ok: bool, missing: string, cells: int) {
	if mi < 0 || mi >= w.map_count || new_si < 0 || new_si >= w.set_count {
		return false, "", 0
	}
	m := &w.maps[mi]
	old := world_map_set(w, mi)
	dst := &w.sets[new_si]
	if old == dst {
		return true, "", 0
	}
	mapping: [TERRAIN_MAX]int // old index -> new index, -1 = the new set has no such terrain
	for i in 0 ..< TERRAIN_MAX {
		mapping[i] = -1
	}
	if old != nil {
		for i in 0 ..< old.count {
			mapping[i] = set_find_terrain(dst, name_str(&old.terrains[i].name))
		}
	}
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if mapping[m.cells[y][x]] < 0 {
				if cells == 0 && old != nil {
					missing = name_str(&old.terrains[m.cells[y][x]].name)
				}
				cells += 1
			}
		}
	}
	if cells > 0 {
		return false, missing, cells
	}
	for y in 0 ..< MAP_MAX {
		for x in 0 ..< MAP_MAX {
			if y < m.height && x < m.width {
				m.cells[y][x] = u8(mapping[m.cells[y][x]])
			} else {
				m.cells[y][x] = u8(dst.default)
			}
		}
	}
	m.set = dst.name
	return true, "", 0
}

// --- File format -------------------------------------------------------------------------------
//
//   { "tile_width": 16, "tile_height": 16,
//     "palette": [ {"r":0,"g":0,"b":0}, ... 16 ... ],
//     "tilesets": [ { "name": "ground", "tileset": { ...the tileset file format... } } ],
//     "terrain_sets": [ { "name": "outdoors", "default": "grass",
//                         "terrains": [ { "name": "grass", "solid": false, "tileset": "ground", "image": "g1" } ] } ],
//     "maps": [ { "name": "start", "terrain_set": "outdoors", "columns": 3, "rows": 2,
//                 "terrains": ["grass", "rock"],       // the names the cells use, in order
//                 "cells": [ 0, 1, 0,                  // one number per cell (an index into the
//                            1, 0, 0 ] } ] }           // "terrains" list), row by row
// "tileset" and "image" of a terrain may be "" (not set), otherwise they must name something that
// exists. Names follow the usual rules (printable ASCII, 1..32, unique within their own list).

world_to_json :: proc(w: ^World, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n  \"tile_width\": %d,\n  \"tile_height\": %d,\n  \"palette\": [\n", w.tile_w, w.tile_h)
	for c, i in w.palette {
		fmt.sbprintf(&b, "    {{\"r\": %d, \"g\": %d, \"b\": %d}}%s\n", c.r, c.g, c.b, i + 1 < PALETTE_SIZE ? "," : "")
	}
	strings.write_string(&b, "  ],\n  \"tags\": [")
	for i in 0 ..< w.tag_count {
		fmt.sbprintf(&b, "%s\"%s\"", i == 0 ? "" : ", ", escape_name(name_str(&w.tags[i])))
	}
	strings.write_string(&b, "],\n  \"tilesets\": [")
	for i in 0 ..< w.tileset_count {
		strings.write_string(&b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(&b, "    {{\"name\": \"%s\", \"tileset\": %s}}", escape_name(name_str(&w.tileset_names[i])), strings.trim_space(tileset_to_json(&w.tilesets[i])))
	}
	strings.write_string(&b, w.tileset_count == 0 ? "],\n" : "\n  ],\n")
	strings.write_string(&b, "  \"terrain_sets\": [")
	for si in 0 ..< w.set_count {
		s := &w.sets[si]
		strings.write_string(&b, si == 0 ? "\n" : ",\n")
		fmt.sbprintf(
			&b,
			"    {{\"name\": \"%s\", \"default\": \"%s\", \"terrains\": [",
			escape_name(name_str(&s.name)),
			escape_name(name_str(&s.terrains[s.default].name)),
		)
		for ti in 0 ..< s.count {
			t := &s.terrains[ti]
			strings.write_string(&b, ti == 0 ? "\n" : ",\n")
			fmt.sbprintf(&b, "      {{\"name\": \"%s\", \"tags\": ", escape_name(name_str(&t.name)))
			write_tag_list(&b, w, t.tags)
			fmt.sbprintf(&b, ", \"tileset\": \"%s\", \"image\": \"%s\"}}", escape_name(name_str(&t.tileset)), escape_name(name_str(&t.image)))
		}
		strings.write_string(&b, "\n    ]}")
	}
	strings.write_string(&b, w.set_count == 0 ? "],\n" : "\n  ],\n")
	strings.write_string(&b, "  \"maps\": [")
	for mi in 0 ..< w.map_count {
		m := &w.maps[mi]
		strings.write_string(&b, mi == 0 ? "\n" : ",\n")
		fmt.sbprintf(
			&b,
			"    {{\"name\": \"%s\", \"terrain_set\": \"%s\", \"columns\": %d, \"rows\": %d,\n      \"terrains\": [",
			escape_name(name_str(&m.name)),
			escape_name(name_str(&m.set)),
			m.width,
			m.height,
		)
		set := world_map_set(w, mi)
		// The names the cells use, in order of first use.
		table: [TERRAIN_MAX]int // terrain index -> position in the list, -1 = unused
		for i in 0 ..< TERRAIN_MAX {
			table[i] = -1
		}
		used := 0
		order := make([dynamic]int, context.temp_allocator)
		for y in 0 ..< m.height {
			for x in 0 ..< m.width {
				c := int(m.cells[y][x])
				if table[c] < 0 {
					table[c] = used
					used += 1
					append(&order, c)
				}
			}
		}
		for c, k in order {
			nm := set != nil && c < set.count ? name_str(&set.terrains[c].name) : ""
			fmt.sbprintf(&b, "%s\"%s\"", k == 0 ? "" : ", ", escape_name(nm))
		}
		strings.write_string(&b, "],\n      \"cells\": [")
		for y in 0 ..< m.height {
			strings.write_string(&b, y == 0 ? "\n        " : ",\n        ")
			for x in 0 ..< m.width {
				fmt.sbprintf(&b, "%s%d", x == 0 ? "" : ", ", table[m.cells[y][x]])
			}
		}
		strings.write_string(&b, "\n      ],\n      \"characters\": [")
		first := true
		for y in 0 ..< m.height {
			for x in 0 ..< m.width {
				if !uuid_is_none(m.characters[y][x]) {
					fmt.sbprintf(&b, "%s{{\"x\": %d, \"y\": %d, \"character\": \"%s\"}}", first ? "" : ", ", x, y, uuid_to_string(m.characters[y][x]))
					first = false
				}
			}
		}
		strings.write_string(&b, "],\n      \"features\": [")
		write_map_features(&b, m)
		strings.write_string(&b, "],\n      \"cell_tags\": [")
		first_tags := true
		for y in 0 ..< m.height {
			for x in 0 ..< m.width {
				ct := m.cell_tags[y][x]
				if ct.set != 0 || ct.cleared != 0 {
					fmt.sbprintf(&b, "%s{{\"x\": %d, \"y\": %d, \"tags\": ", first_tags ? "" : ", ", x, y)
					write_tag_list(&b, w, ct.set)
					strings.write_string(&b, ", \"tags_cleared\": ")
					write_tag_list(&b, w, ct.cleared)
					strings.write_string(&b, "}")
					first_tags = false
				}
			}
		}
		strings.write_string(&b, "]}")
	}
	strings.write_string(&b, w.map_count == 0 ? "],\n" : "\n  ],\n")
	write_sprite_sets(&b, w)
	write_params(&b, w)
	write_sounds(&b, w)
	write_features(&b, w)
	write_items(&b, w)
	write_characters(&b, w)
	strings.write_string(&b, "}\n")
	return strings.to_string(b)
}

// Replaces dst only if the whole file is valid. err == "" means success. Error text is on the temp
// allocator; use or copy it right away.
world_from_json :: proc(data: []u8, dst: ^World) -> (err: string) {
	val, perr := json.parse(data, .JSON, true, context.temp_allocator)
	if perr != .None {
		return "not valid JSON"
	}
	defer json.destroy_value(val, context.temp_allocator)
	root, is_obj := val.(json.Object)
	if !is_obj {
		return "the top level must be an object"
	}
	tw, tw_ok := root["tile_width"].(json.Integer)
	th, th_ok := root["tile_height"].(json.Integer)
	if !tw_ok || !th_ok {
		return `"tile_width" and "tile_height" must be whole numbers`
	}
	if tw < IMAGE_MIN || tw > IMAGE_MAX || th < IMAGE_MIN || th > IMAGE_MAX {
		return fmt.tprintf("tile size %d x %d is out of range (%d to %d)", tw, th, IMAGE_MIN, IMAGE_MAX)
	}
	tmp := new(World, context.temp_allocator) // built aside so a bad file changes nothing
	world_reset(tmp)
	tmp.tile_w, tmp.tile_h = int(tw), int(th)

	pal, is_pal := root["palette"].(json.Array)
	if !is_pal || len(pal) != PALETTE_SIZE {
		return fmt.tprintf(`"palette" must be a list of exactly %d colours`, PALETTE_SIZE)
	}
	for entry, i in pal {
		obj, is_entry := entry.(json.Object)
		if !is_entry {
			return fmt.tprintf("palette colour %d must be an object", i)
		}
		for ch in Channel {
			n, ok := obj[channel_keys[ch]].(json.Integer)
			if !ok || n < 0 || n > 255 {
				return fmt.tprintf(`palette colour %d: "%s" must be a whole number from 0 to 255`, i, channel_keys[ch])
			}
			tmp.palette[i][ch] = u8(n)
		}
	}

	if msg := read_tags(root, tmp); msg != "" {
		return msg
	}

	tilesets, _ := list_of(root, "tilesets")
	if len(tilesets) > WORLD_MAX_TILESETS {
		return fmt.tprintf("%d tilesets is more than the %d allowed", len(tilesets), WORLD_MAX_TILESETS)
	}
	for item, i in tilesets {
		obj, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("tileset %d must be an object", i)
		}
		name, name_ok := obj["name"].(json.String)
		if !name_ok {
			return fmt.tprintf(`tileset %d: "name" must be text`, i)
		}
		if p := world_check_tileset_name(tmp, -1, name); p != .None {
			return fmt.tprintf(`tileset %d: the name "%s" is %v`, i, name, name_problem_text(p))
		}
		inner, inner_ok := obj["tileset"].(json.Object)
		if !inner_ok {
			return fmt.tprintf(`tileset %d ("%s"): needs a "tileset" object`, i, name)
		}
		if msg := tileset_from_object(inner, &tmp.tilesets[i]); msg != "" {
			return fmt.tprintf(`tileset %d ("%s"): %s`, i, name, msg)
		}
		if tmp.tilesets[i].width != tmp.tile_w || tmp.tilesets[i].height != tmp.tile_h {
			return fmt.tprintf(
				`tileset %d ("%s") is %d x %d but the world's tiles are %d x %d`,
				i,
				name,
				tmp.tilesets[i].width,
				tmp.tilesets[i].height,
				tmp.tile_w,
				tmp.tile_h,
			)
		}
		name_assign(&tmp.tileset_names[i], name)
		tmp.tileset_count += 1
	}

	sets, _ := list_of(root, "terrain_sets")
	if len(sets) > WORLD_MAX_TERRAIN_SETS {
		return fmt.tprintf("%d terrain sets is more than the %d allowed", len(sets), WORLD_MAX_TERRAIN_SETS)
	}
	for item, si in sets {
		obj, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("terrain set %d must be an object", si)
		}
		name, name_ok := obj["name"].(json.String)
		if !name_ok {
			return fmt.tprintf(`terrain set %d: "name" must be text`, si)
		}
		if p := world_check_set_name(tmp, -1, name); p != .None {
			return fmt.tprintf(`terrain set %d: the name "%s" is %v`, si, name, name_problem_text(p))
		}
		s := &tmp.sets[si]
		name_assign(&s.name, name)
		terrains, _ := list_of(obj, "terrains")
		if len(terrains) < 1 || len(terrains) > TERRAIN_MAX {
			return fmt.tprintf(`terrain set "%s": needs 1 to %d terrains`, name, TERRAIN_MAX)
		}
		for titem, ti in terrains {
			tobj, tok := titem.(json.Object)
			if !tok {
				return fmt.tprintf(`terrain set "%s": terrain %d must be an object`, name, ti)
			}
			tname, tname_ok := tobj["name"].(json.String)
			if !tname_ok {
				return fmt.tprintf(`terrain set "%s": terrain %d needs a "name"`, name, ti)
			}
			s.count = ti // so that uniqueness is checked against the earlier terrains only
			if p := terrain_check_name(s, -1, tname); p != .None {
				return fmt.tprintf(`terrain set "%s": the terrain name "%s" is %v`, name, tname, name_problem_text(p))
			}
			t := &s.terrains[ti]
			name_assign(&t.name, tname)
			tag_mask, tag_err := read_tag_mask(tobj, "tags", tmp, fmt.tprintf(`terrain "%s"`, tname))
			if tag_err != "" {
				return tag_err
			}
			if old_solid, has_old := tobj["solid"]; has_old { 	// files from before tags
				flag, flag_ok := old_solid.(json.Boolean)
				if !flag_ok {
					return fmt.tprintf(`terrain "%s": "solid" must be true or false`, tname)
				}
				if bool(flag) {
					tag_mask |= tag_bit(TAG_SOLID)
				}
			}
			t.tags = tag_mask
			ts_name, ts_ok := tobj["tileset"].(json.String)
			img_name, img_ok := tobj["image"].(json.String)
			if !ts_ok || !img_ok {
				return fmt.tprintf(`terrain "%s": "tileset" and "image" must be text ("" for not set)`, tname)
			}
			if (len(ts_name) == 0) != (len(img_name) == 0) {
				return fmt.tprintf(`terrain "%s": "tileset" and "image" must both be set or both be ""`, tname)
			}
			if len(ts_name) > 0 {
				k := world_find_tileset(tmp, ts_name)
				if k < 0 {
					return fmt.tprintf(`terrain "%s": there is no tileset "%s"`, tname, ts_name)
				}
				if tileset_find(&tmp.tilesets[k], img_name) < 0 {
					return fmt.tprintf(`terrain "%s": tileset "%s" has no image "%s"`, tname, ts_name, img_name)
				}
				name_assign(&t.tileset, ts_name)
				name_assign(&t.image, img_name)
			}
		}
		s.count = len(terrains)
		def, def_ok := obj["default"].(json.String)
		if !def_ok {
			return fmt.tprintf(`terrain set "%s": "default" must be the name of a terrain`, name)
		}
		d := set_find_terrain(s, def)
		if d < 0 {
			return fmt.tprintf(`terrain set "%s": the default "%s" is not one of its terrains`, name, def)
		}
		s.default = d
		tmp.set_count += 1
	}

	maps, _ := list_of(root, "maps")
	if len(maps) > WORLD_MAX_MAPS {
		return fmt.tprintf("%d maps is more than the %d allowed", len(maps), WORLD_MAX_MAPS)
	}
	for item, mi in maps {
		obj, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("map %d must be an object", mi)
		}
		name, name_ok := obj["name"].(json.String)
		if !name_ok {
			return fmt.tprintf(`map %d: "name" must be text`, mi)
		}
		if p := world_check_map_name(tmp, -1, name); p != .None {
			return fmt.tprintf(`map %d: the name "%s" is %v`, mi, name, name_problem_text(p))
		}
		set_name, set_ok := obj["terrain_set"].(json.String)
		si := set_ok ? world_find_set(tmp, set_name) : -1
		if si < 0 {
			return fmt.tprintf(`map "%s": "terrain_set" must name an existing terrain set`, name)
		}
		cols, cols_ok := obj["columns"].(json.Integer)
		rows, rows_ok := obj["rows"].(json.Integer)
		if !cols_ok || !rows_ok || cols < 1 || cols > MAP_MAX || rows < 1 || rows > MAP_MAX {
			return fmt.tprintf(`map "%s": "columns" and "rows" must be whole numbers from 1 to %d`, name, MAP_MAX)
		}
		table_list, _ := list_of(obj, "terrains")
		table := make([]int, len(table_list), context.temp_allocator)
		for entry, k in table_list {
			tn, tn_ok := entry.(json.String)
			idx := tn_ok ? set_find_terrain(&tmp.sets[si], tn) : -1
			if idx < 0 {
				return fmt.tprintf(`map "%s": terrain list entry %d is not a terrain of "%s"`, name, k, set_name)
			}
			table[k] = idx
		}
		cells, cells_ok := obj["cells"].(json.Array)
		if !cells_ok || len(cells) != int(cols * rows) {
			return fmt.tprintf(`map "%s": "cells" must have %d entries (columns x rows)`, name, cols * rows)
		}
		m := &tmp.maps[mi]
		name_assign(&m.name, name)
		m.set = tmp.sets[si].name
		m.width, m.height = int(cols), int(rows)
		fill_cells(m, u8(tmp.sets[si].default))
		for entry, k in cells {
			n, n_ok := entry.(json.Integer)
			if !n_ok || n < 0 || int(n) >= len(table) {
				return fmt.tprintf(`map "%s": cell %d is not a position in its "terrains" list`, name, k)
			}
			m.cells[k / int(cols)][k % int(cols)] = u8(table[n])
		}
		if msg := read_cell_tags(obj, m, tmp); msg != "" {
			return msg
		}
		tmp.map_count += 1
	}
	if msg := read_sprite_sets(root, tmp); msg != "" {
		return msg
	}
	if msg := read_params(root, tmp); msg != "" {
		return msg
	}
	if msg := read_sounds(root, tmp); msg != "" {
		return msg
	}
	if msg := read_characters(root, tmp); msg != "" {
		return msg
	}
	if msg := read_features(root, tmp); msg != "" {
		return msg
	}
	if msg := read_items(root, tmp); msg != "" {
		return msg
	}
	tmp.uuid_state = dst.uuid_state // new uuids keep coming from the running generator
	dst^ = tmp^
	return ""
}

name_problem_text :: proc(p: Name_Problem) -> string {
	switch p {
	case .None:
		return "fine"
	case .Empty:
		return "empty"
	case .Too_Long:
		return "too long"
	case .Bad_Character:
		return "using a character other than printable ASCII"
	case .In_Use:
		return "used more than once"
	}
	return ""
}

@(private = "file")
list_of :: proc(obj: json.Object, key: string) -> (json.Array, bool) {
	arr, ok := obj[key].(json.Array)
	return arr, ok
}

@(private = "file")
channel_keys := [Channel]string {
	.R = "r",
	.G = "g",
	.B = "b",
}
