package anvil_runtime

import cm "../common"

// The state of a game being played, kept apart from the world: where every character is now. It
// starts as a copy of the authored placements (`play_init`) and a game changes only this, so the
// loaded world stays exactly as the editors wrote it. About 1.1 MB (the inventories' entries and the property values are most
// of it): a global or `new()`, copy it only when you mean to, and `play_init` it again to start over.
//
// Characters are the world's table, by index (see `player`, `character_type`); a character is in
// at most one cell, or on no map.

Position :: struct {
	map_index: int,
	x, y:      int,
	placed:    bool, // false: not on any map
}

Play_State :: struct {
	count:     int, // the number of characters when the state was made
	positions: [cm.WORLD_MAX_CHARACTERS]Position,
	// Features are the world's table too, by index; they stand still, but a game may remove or
	// place them (open a door, cut a tree).
	feature_count:     int,
	feature_positions: [cm.WORLD_MAX_FEATURES]Position,
	// Collisions `play_step` noticed and the game has not taken yet (see `play_take_collision`).
	collisions:        [MAX_COLLISIONS]Collision,
	collision_head:    int,
	collision_count:   int,
	collisions_lost:   int, // events dropped because the queue was full (the oldest go first)
	// Items (items.odin): the inventories as they are now, and the contacts `play_step` noticed.
	inventories:       [cm.WORLD_MAX_INVENTORIES]Play_Inventory,
	entry_count:       int,
	entries:           [cm.WORLD_MAX_ENTRIES]Play_Entry,
	contacts:          [MAX_COLLISIONS]Contact,
	contact_head:      int,
	contact_count:     int,
	contacts_lost:     int,
	// Numeric properties (props.odin): each character's and feature's own values, as the game has changed them.
	character_values:  [cm.WORLD_MAX_CHARACTERS]Prop_Overrides,
	feature_values:    [cm.WORLD_MAX_FEATURES]Prop_Overrides,
}

MAX_COLLISIONS :: 64

// What a character ran into.
Collision_Kind :: enum {
	Character, // another character
	Feature,
}

// A character's step was refused because another character or a feature stands in the cell it
// tried to enter. `other` is an index into the world's character or feature table, per `kind`; the
// cell is the one that was entered for (x, y) on `map_index`; (dx, dy) is the step. A game decides
// what it means from the two parties' tags (a door, an enemy, a pickup).
Collision :: struct {
	mover:     int, // character index
	kind:      Collision_Kind,
	other:     int,
	map_index: int,
	x, y:      int,
	dx, dy:    int,
}

// Starts (or restarts) a game: every character where the world authors put it. If the world has
// changed since, call this again.
play_init :: proc(ps: ^Play_State, w: ^World) {
	ps^ = {}
	ps.count = w.character_count
	ps.feature_count = w.feature_count
	play_init_items(ps, w)
	play_init_values(ps, w)
	for mi in 0 ..< w.map_count {
		m := &w.maps[mi]
		for y in 0 ..< m.height {
			for x in 0 ..< m.width {
				if ci := cm.world_find_character(w, m.characters[y][x]); ci >= 0 {
					ps.positions[ci] = Position{mi, x, y, true}
				}
				if fi := cm.world_find_feature(w, m.features[y][x]); fi >= 0 {
					ps.feature_positions[fi] = Position{mi, x, y, true}
				}
			}
		}
	}
}

// The next collision since the last call (oldest first), or ok = false when there is none. A game
// drains these once a frame after its steps.
play_take_collision :: proc(ps: ^Play_State) -> (c: Collision, ok: bool) {
	if ps.collision_count == 0 {
		return {}, false
	}
	c = ps.collisions[ps.collision_head]
	ps.collision_head = (ps.collision_head + 1) % MAX_COLLISIONS
	ps.collision_count -= 1
	return c, true
}

// Forgets the collisions not yet taken (and the lost count).
play_clear_collisions :: proc(ps: ^Play_State) {
	ps.collision_head, ps.collision_count, ps.collisions_lost = 0, 0, 0
}

@(private = "file")
push_collision :: proc(ps: ^Play_State, c: Collision) {
	if ps.collision_count == MAX_COLLISIONS {
		ps.collision_head = (ps.collision_head + 1) % MAX_COLLISIONS
		ps.collision_count -= 1
		ps.collisions_lost += 1
	}
	ps.collisions[(ps.collision_head + ps.collision_count) % MAX_COLLISIONS] = c
	ps.collision_count += 1
}

// Where a character is now (placed is false for no such character or one off the map).
play_position :: proc(ps: ^Play_State, ci: int) -> Position {
	if ci < 0 || ci >= ps.count {
		return {}
	}
	return ps.positions[ci]
}

// The character standing in a cell now, or -1.
play_character_at :: proc(ps: ^Play_State, mi, x, y: int) -> int {
	for ci in 0 ..< ps.count {
		p := ps.positions[ci]
		if p.placed && p.map_index == mi && p.x == x && p.y == y {
			return ci
		}
	}
	return -1
}

// The characters on a map now, in table order. On the temp allocator unless another is given.
play_characters_in_map :: proc(ps: ^Play_State, mi: int, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for ci in 0 ..< ps.count {
		if p := ps.positions[ci]; p.placed && p.map_index == mi {
			append(&out, ci)
		}
	}
	return out[:]
}

// Where a feature is now (placed is false for no such feature or one off the map).
play_feature_position :: proc(ps: ^Play_State, fi: int) -> Position {
	if fi < 0 || fi >= ps.feature_count {
		return {}
	}
	return ps.feature_positions[fi]
}

// The feature standing in a cell now, or -1.
play_feature_at :: proc(ps: ^Play_State, mi, x, y: int) -> int {
	for fi in 0 ..< ps.feature_count {
		p := ps.feature_positions[fi]
		if p.placed && p.map_index == mi && p.x == x && p.y == y {
			return fi
		}
	}
	return -1
}

// The features on a map now, in table order. On the temp allocator unless another is given.
play_features_in_map :: proc(ps: ^Play_State, mi: int, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for fi in 0 ..< ps.feature_count {
		if p := ps.feature_positions[fi]; p.placed && p.map_index == mi {
			append(&out, fi)
		}
	}
	return out[:]
}

Move_Result :: enum {
	Moved,
	Not_Placed, // the character is on no map (or does not exist)
	Outside, // the step leaves the map
	Solid, // the cell it steps into is solid
	Occupied, // another character is in that cell
	Feature, // a feature stands in that cell (a feature always blocks)
}

// What stepping one cell (dx, dy) would do, without doing it; target is the cell it would enter.
play_can_step :: proc(ps: ^Play_State, w: ^World, ci, dx, dy: int) -> (result: Move_Result, tx, ty: int) {
	p := play_position(ps, ci)
	if !p.placed {
		return .Not_Placed, 0, 0
	}
	tx, ty = p.x + dx, p.y + dy
	columns, rows, _ := map_size(w, p.map_index)
	switch {
	case tx < 0 || ty < 0 || tx >= columns || ty >= rows:
		return .Outside, tx, ty
	case cell_is_solid(w, p.map_index, tx, ty):
		return .Solid, tx, ty
	case play_feature_at(ps, p.map_index, tx, ty) >= 0:
		return .Feature, tx, ty
	case play_character_at(ps, p.map_index, tx, ty) >= 0:
		return .Occupied, tx, ty
	}
	return .Moved, tx, ty
}

// Steps a character one cell. Nothing moves unless the result is .Moved. Solid cells, features and
// other characters block it, and running into a feature or a character queues a `Collision` for the
// game (`play_take_collision`); a game that lets the player walk onto a pickup looks at
// `play_character_at` for the target first and removes the pickup (`play_unplace`) before stepping.
play_step :: proc(ps: ^Play_State, w: ^World, ci, dx, dy: int) -> Move_Result {
	result, tx, ty := play_can_step(ps, w, ci, dx, dy)
	switch result {
	case .Moved:
		ps.positions[ci].x, ps.positions[ci].y = tx, ty
		if mi := ps.positions[ci].map_index; play_cell_has_items(ps, mi, tx, ty) {
			push_contact(ps, {ci, mi, tx, ty, dx, dy}) // never refuses: the game decides about picking up
		}
	case .Feature:
		mi := ps.positions[ci].map_index
		push_collision(ps, {ci, .Feature, play_feature_at(ps, mi, tx, ty), mi, tx, ty, dx, dy})
	case .Occupied:
		mi := ps.positions[ci].map_index
		push_collision(ps, {ci, .Character, play_character_at(ps, mi, tx, ty), mi, tx, ty, dx, dy})
	case .Not_Placed, .Outside, .Solid:
	}
	return result
}

// Puts a character in a cell (of any map), moving it from where it was. Refused (nothing changes)
// for a cell outside the map, a character or map that does not exist, a cell another character is
// in (Taken) or a cell with a feature (Feature_There). Solid is not checked here: placing is a game decision, stepping is the rule.
play_place :: proc(ps: ^Play_State, w: ^World, ci, mi, x, y: int) -> cm.Place_Result {
	if ci < 0 || ci >= ps.count || mi < 0 || mi >= w.map_count {
		return .Unknown
	}
	columns, rows, _ := map_size(w, mi)
	if x < 0 || y < 0 || x >= columns || y >= rows {
		return .Outside
	}
	if play_feature_at(ps, mi, x, y) >= 0 {
		return .Feature_There
	}
	if other := play_character_at(ps, mi, x, y); other >= 0 && other != ci {
		return .Taken
	}
	ps.positions[ci] = Position{mi, x, y, true}
	return .Placed
}

// Takes a character off its map (a picked-up thing). Returns true if it was on one.
play_unplace :: proc(ps: ^Play_State, ci: int) -> bool {
	if ci < 0 || ci >= ps.count || !ps.positions[ci].placed {
		return false
	}
	ps.positions[ci] = {}
	return true
}

// Puts a feature in a cell (of any map), moving it from where it was. Refused (nothing changes) for
// a cell outside the map, a feature or map that does not exist, a cell with another feature (Taken)
// or a character (Character_There).
play_place_feature :: proc(ps: ^Play_State, w: ^World, fi, mi, x, y: int) -> cm.Place_Result {
	if fi < 0 || fi >= ps.feature_count || mi < 0 || mi >= w.map_count {
		return .Unknown
	}
	columns, rows, _ := map_size(w, mi)
	if x < 0 || y < 0 || x >= columns || y >= rows {
		return .Outside
	}
	if other := play_feature_at(ps, mi, x, y); other >= 0 && other != fi {
		return .Taken
	}
	if play_character_at(ps, mi, x, y) >= 0 {
		return .Character_There
	}
	ps.feature_positions[fi] = Position{mi, x, y, true}
	return .Placed
}

// Takes a feature off its map (a felled tree). Returns true if it was on one.
play_unplace_feature :: proc(ps: ^Play_State, fi: int) -> bool {
	if fi < 0 || fi >= ps.feature_count || !ps.feature_positions[fi].placed {
		return false
	}
	ps.feature_positions[fi] = {}
	return true
}

// --- Drawing ------------------------------------------------------------------------------------

// The shared drawing (common/world_draw.odin), so a game never reimplements how a tile looks.
// `World_Draw` says which window of a map goes where on the 320 x 180 surface and how big a cell is.
World_Draw :: cm.World_Draw

// A window at a whole-number zoom of the tiles: cols x rows cells starting at (col, row), with that
// cell's corner at surface pixel (x, y). Cells outside the map or the surface are clipped, not errors.
zoom_window :: proc(w: ^World, map_index, col, row, cols, rows, x, y, zoom: int) -> World_Draw {
	return cm.world_zoom_draw(w, map_index, col, row, cols, rows, x, y, zoom)
}

// Draws the terrain of the window.
draw_terrain :: proc(r: ^cm.Renderer, w: ^World, d: World_Draw) {
	cm.world_draw_terrain(r, w, d)
}

// Draws the features standing on the window's map *now* (the Play_State) over the terrain, each in
// its cell. Draw them before the characters.
draw_features :: proc(r: ^cm.Renderer, w: ^World, ps: ^Play_State, d: World_Draw) {
	if d.cell_w <= 0 || d.cell_h <= 0 {
		return
	}
	for fi in 0 ..< ps.feature_count {
		p := ps.feature_positions[fi]
		if !p.placed || p.map_index != d.map_index {
			continue
		}
		if p.x < d.col || p.y < d.row || p.x >= d.col + d.cols || p.y >= d.row + d.rows {
			continue
		}
		cm.world_draw_feature(r, w, fi, cm.world_cell_rect(d, p.x, p.y), d.clip, d.missing)
	}
}

// Draws the characters standing on the window's map *now* (the Play_State, not the authored map)
// over the terrain, each in its cell, without its sprite's transparent colour. With
// `d.mark_player` the player gets a small corner mark.
draw_characters :: proc(r: ^cm.Renderer, w: ^World, ps: ^Play_State, d: World_Draw) {
	if d.cell_w <= 0 || d.cell_h <= 0 {
		return
	}
	for ci in 0 ..< ps.count {
		p := ps.positions[ci]
		if !p.placed || p.map_index != d.map_index {
			continue
		}
		if p.x < d.col || p.y < d.row || p.x >= d.col + d.cols || p.y >= d.row + d.rows {
			continue
		}
		area := cm.world_cell_rect(d, p.x, p.y)
		cm.world_draw_character(r, w, ci, area, d.clip, d.missing)
		if d.mark_player && w.characters[ci].uuid == w.player && area.w >= 4 {
			k := max(2, area.w / 4)
			cs: cm.Clip_State
			cr := cm.clipped_renderer(&cs, r, d.clip)
			cm.renderer_fill_rect(&cr, area.x, area.y, k, k, d.player_mark)
		}
	}
}

// The map cell under a surface pixel of the window (to turn a mouse click into a cell).
cell_at_pixel :: proc(w: ^World, d: World_Draw, px, py: int) -> (x, y: int, ok: bool) {
	return cm.world_cell_at(w, d, px, py)
}
