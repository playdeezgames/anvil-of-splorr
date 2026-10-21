// The game-side API of the Anvil of SPLORR!!: load a `world.json` and ask it questions, without any
// of the editors. A game imports this package (and `../common` for the Renderer and the drawing
// helpers) and keeps its own mutable state in a `Play_State` (play.odin); the loaded world is never
// changed by playing.
//
// A `World` is about 21 MB: make it a global or `new()` it, never copy or return one by value. The
// package builds for native and `js_wasm32` and has no platform code. (The name is not `runtime`
// because Odin reserves that for its own package.)
package anvil_runtime

import cm "../common"

// Re-exports, so a game can name the types it gets back without importing common for them.
World :: cm.World
Terrain :: cm.Terrain
Sprite :: cm.Sprite
Character :: cm.Character
Character_Type :: cm.Character_Type
Image4 :: cm.Image4
Palette :: cm.Palette

// The tag every world has (index 0), which blocks movement.
TAG_SOLID :: cm.TAG_SOLID

// A new empty world on the heap (16 x 16 tiles, the default palette, only the "solid" tag). The
// caller frees it with `free`.
new_world :: proc() -> ^World {
	w := new(World)
	cm.world_reset(w)
	return w
}

// Empties a world you already have (a global, say) in place.
reset_world :: proc(w: ^World) {
	cm.world_reset(w)
}

// Replaces `w` with the world in `bytes` (the text of a world.json). If the file is not valid, `w`
// is left alone and the returned text says what is wrong; "" means success. The text is on the temp
// allocator, so use or copy it before the next free_all.
load :: proc(w: ^World, bytes: []u8) -> (err: string) {
	return cm.world_from_json(bytes, w)
}

// --- Names to indexes --------------------------------------------------------------------------

// The index of a tag by name ("solid" is always TAG_SOLID).
find_tag :: proc(w: ^World, name: string) -> (tag: int, ok: bool) {
	i := cm.world_find_tag(w, name)
	return i, i >= 0
}

find_map :: proc(w: ^World, name: string) -> (index: int, ok: bool) {
	i := cm.world_find_map(w, name)
	return i, i >= 0
}

// Which of `required` tag names the world lacks, in the order given (empty if it has them all).
missing_tags :: proc(w: ^World, required: []string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	for name in required {
		if cm.world_find_tag(w, name) < 0 {
			append(&out, name)
		}
	}
	return out[:]
}

// --- The world's basics ------------------------------------------------------------------------

palette :: proc(w: ^World) -> ^Palette {
	return &w.palette
}

// The size of every tile in pixels.
tile_size :: proc(w: ^World) -> (width, height: int) {
	return w.tile_w, w.tile_h
}

map_count :: proc(w: ^World) -> int {
	return w.map_count
}

// The columns and rows of a map; ok is false for no such map.
map_size :: proc(w: ^World, mi: int) -> (columns, rows: int, ok: bool) {
	if mi < 0 || mi >= w.map_count {
		return 0, 0, false
	}
	return w.maps[mi].width, w.maps[mi].height, true
}

// --- Cells -------------------------------------------------------------------------------------

// The terrain in a cell, or nil for a cell outside the map (or a map whose terrain set is missing).
terrain_at :: proc(w: ^World, mi, x, y: int) -> ^Terrain {
	if mi < 0 || mi >= w.map_count {
		return nil
	}
	m := &w.maps[mi]
	set := cm.world_map_set(w, mi)
	if set == nil || x < 0 || y < 0 || x >= m.width || y >= m.height {
		return nil
	}
	i := int(m.cells[y][x])
	return i < set.count ? &set.terrains[i] : nil
}

// The tile image a terrain draws, or nil while it has none.
terrain_image :: proc(w: ^World, t: ^Terrain) -> ^Image4 {
	return cm.world_terrain_image(w, t)
}

// Whether a cell has a tag: the cell's own setting if it has one, else its terrain's. False outside
// the map.
cell_has_tag :: proc(w: ^World, mi, x, y, tag: int) -> bool {
	return cm.world_cell_has_tag(w, mi, x, y, tag)
}

// Whether a cell blocks movement: the effective "solid" tag. Outside the map counts as solid, so a
// game that steps into it is stopped.
cell_is_solid :: proc(w: ^World, mi, x, y: int) -> bool {
	if columns, rows, ok := map_size(w, mi); !ok || x < 0 || y < 0 || x >= columns || y >= rows {
		return true
	}
	return cm.world_cell_has_tag(w, mi, x, y, TAG_SOLID)
}

// Every cell of a map that has the tag, row by row, left to right (for choosing spawn cells). On
// the temp allocator unless another is given.
cells_with_tag :: proc(w: ^World, mi, tag: int, allocator := context.temp_allocator) -> [][2]int {
	out := make([dynamic][2]int, allocator)
	columns, rows, ok := map_size(w, mi)
	if !ok {
		return out[:]
	}
	for y in 0 ..< rows {
		for x in 0 ..< columns {
			if cm.world_cell_has_tag(w, mi, x, y, tag) {
				append(&out, [2]int{x, y})
			}
		}
	}
	return out[:]
}

// --- Characters (as authored) -------------------------------------------------------------------

character_count :: proc(w: ^World) -> int {
	return w.character_count
}

// The player's index in the character table, if the world names one.
player :: proc(w: ^World) -> (ci: int, ok: bool) {
	i := cm.world_find_character(w, w.player)
	return i, i >= 0
}

character_type :: proc(w: ^World, ci: int) -> ^Character_Type {
	if ci < 0 || ci >= w.character_count {
		return nil
	}
	ti := cm.world_find_char_type(w, cm.name_str(&w.characters[ci].type))
	return ti >= 0 ? &w.char_types[ti] : nil
}

// The sprite a character draws (through its type), or nil.
character_sprite :: proc(w: ^World, ci: int) -> ^Sprite {
	ct := character_type(w, ci)
	return ct == nil ? nil : cm.world_char_type_sprite(w, ct)
}

// The tile image of a character's sprite, or nil. Draw it without the sprite's `transparent` colour
// (see `character_sprite(...).transparent`; -1 means none).
character_image :: proc(w: ^World, ci: int) -> ^Image4 {
	sp := character_sprite(w, ci)
	return sp == nil ? nil : cm.world_sprite_image(w, sp)
}

// Whether a character has a tag: its own setting if it has one, else its type's.
character_has_tag :: proc(w: ^World, ci, tag: int) -> bool {
	return cm.world_character_has_tag(w, ci, tag)
}

// Where the world's authors put a character: its map and cell. For where it is now, ask the
// Play_State.
authored_location :: proc(w: ^World, ci: int) -> (mi, x, y: int, ok: bool) {
	if ci < 0 || ci >= w.character_count {
		return 0, 0, 0, false
	}
	return cm.world_character_location(w, w.characters[ci].uuid)
}

// --- Tags a game needs --------------------------------------------------------------------------

// The tags a game requires, from its `game_tags.json` (see common/game_tags.odin for the format).
// About 8 KB: a plain value is fine on the stack.
Game_Tags :: cm.Game_Tags

// Reads a game_tags.json into `g` (untouched on failure). "" means success; the error text is on
// the temp allocator.
parse_game_tags :: proc(bytes: []u8, g: ^Game_Tags) -> (err: string) {
	return cm.game_tags_from_json(bytes, g)
}

// The required tags the world lacks, in the file's order (empty if it has them all): check this
// once at start-up and stop with a clear message instead of failing later. On the temp allocator.
required_missing :: proc(w: ^World, g: ^Game_Tags) -> []string {
	return cm.game_tags_missing(w, g)
}

// --- Game parameters ----------------------------------------------------------------------------

// A named whole number from the world (a round length, points per pickup), or `default` if the
// world has no such parameter or it is a text. The value fits 32 bits.
param_number :: proc(w: ^World, name: string, default: int) -> int {
	return cm.world_param_number(w, name, default)
}

// A named short text from the world, or `default` if the world has no such parameter or it is a
// number. The text is valid as long as the world is unchanged: copy it to keep it.
param_text :: proc(w: ^World, name: string, default: string) -> string {
	return cm.world_param_text(w, name, default)
}

// How many parameters the world holds.
param_count :: proc(w: ^World) -> int {
	return w.param_count
}
