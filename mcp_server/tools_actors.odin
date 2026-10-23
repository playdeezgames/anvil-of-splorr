package mcp_server

import rt "../anvil_runtime"
import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

// The characters a map's rows are written with: one per terrain index of its set (the first 90).
TERRAIN_SYMBOLS :: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-./:;<=>?@[]^_{|}~"

symbols: string = TERRAIN_SYMBOLS // (a variable, so it can be indexed)

actor_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{"map_list", "List the maps: name, terrain set, size, characters, features and cell inventories on it.", `{"type":"object","properties":{}}`, tool_map_list},
		{
			"map_new",
			"Add a map (up to 64) using a terrain set; every cell takes the set's default terrain. width and height default to 32 (1..64).",
			`{"type":"object","properties":{"name":{"type":"string"},"set":{"type":"string"},"width":{"type":"integer"},"height":{"type":"integer"}},"required":["name","set"]}`,
			tool_map_new,
		},
		{"map_rename", "Rename a map.", RENAME_ARG, tool_map_rename},
		{"map_delete", "Delete a map; characters and features on it stay in the table, standing nowhere, but the inventories lying in its cells go.", NAME_ARG, tool_map_delete},
		{
			"map_resize",
			"Resize a map (1..64). New cells take the set's default terrain. Refused while a character, a feature or a cell inventory is in the part that would be cut off.",
			`{"type":"object","properties":{"name":{"type":"string"},"width":{"type":"integer"},"height":{"type":"integer"}},"required":["name","width","height"]}`,
			tool_map_resize,
		},
		{
			"map_set_terrain_set",
			"Move a map to another terrain set. Refused unless every cell's terrain exists by name in the new set.",
			`{"type":"object","properties":{"name":{"type":"string"},"set":{"type":"string"}},"required":["name","set"]}`,
			tool_map_set_terrain_set,
		},
		{
			"map_get",
			"Read a window of a map (default all): rows of symbols, a legend of symbol to terrain (the first 90 terrains of the set), and the characters, features and cell inventories (with their entries) in the window.",
			`{"type":"object","properties":{"name":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"width":{"type":"integer"},"height":{"type":"integer"}},"required":["name"]}`,
			tool_map_get,
		},
		{
			"map_set_rows",
			"Write rows of symbols (see map_get's legend) with their top-left cell at (x, y), default 0,0. Nothing changes unless every row fits and every symbol is in the legend.",
			`{"type":"object","properties":{"name":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"rows":{"type":"array","items":{"type":"string"}}},"required":["name","rows"]}`,
			tool_map_set_rows,
		},
		{
			"map_paint",
			"Paint single cells: cells is a list of {x, y, terrain}.",
			`{"type":"object","properties":{"name":{"type":"string"},"cells":{"type":"array","items":{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"},"terrain":{"type":"string"}},"required":["x","y","terrain"]}}},"required":["name","cells"]}`,
			tool_map_paint,
		},
		{
			"map_fill_rect",
			"Fill a rectangle (x, y, width, height; clamped to the map) with a terrain, or just its outline with frame true.",
			`{"type":"object","properties":{"name":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"width":{"type":"integer"},"height":{"type":"integer"},"terrain":{"type":"string"},"frame":{"type":"boolean"}},"required":["name","x","y","width","height","terrain"]}`,
			tool_map_fill_rect,
		},
		{
			"map_flood_fill",
			"Replace the connected region (not diagonal) of equal terrain around (x, y) with another terrain.",
			`{"type":"object","properties":{"name":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"terrain":{"type":"string"}},"required":["name","x","y","terrain"]}`,
			tool_map_flood_fill,
		},
		{
			"map_replace_terrain",
			"Replace every cell of one terrain with another.",
			`{"type":"object","properties":{"name":{"type":"string"},"from":{"type":"string"},"to":{"type":"string"}},"required":["name","from","to"]}`,
			tool_map_replace_terrain,
		},
		{
			"map_cell_tags",
			"Set one cell's own tag settings (the rest is inherited from its terrain): tags_set lists tags it has regardless, tags_cleared lists tags it lacks regardless. A list replaces that setting; give [] to go back to inheriting. Returns the cell's effective tags.",
			`{"type":"object","properties":{"name":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"tags_set":{"type":"array","items":{"type":"string"}},"tags_cleared":{"type":"array","items":{"type":"string"}}},"required":["name","x","y"]}`,
			tool_map_cell_tags,
		},
		{"char_type_list", "List the character types: name, sprite, tags.", `{"type":"object","properties":{}}`, tool_char_type_list},
		{
			"char_type_new",
			"Add a character type (up to 64). sprite_set and sprite name the picture (both or neither); tags lists the tags every character of the type has.",
			`{"type":"object","properties":{"name":{"type":"string"},"sprite_set":{"type":"string"},"sprite":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["name"]}`,
			tool_char_type_new,
		},
		{
			"char_type_edit",
			"Change a character type; only the fields given change. Characters of the type follow a rename.",
			`{"type":"object","properties":{"name":{"type":"string"},"new_name":{"type":"string"},"sprite_set":{"type":"string"},"sprite":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["name"]}`,
			tool_char_type_edit,
		},
		{"char_type_delete", "Delete a character type unless a character has it.", NAME_ARG, tool_char_type_delete},
		{
			"character_list",
			"List characters (all, or those standing on map): id, name, type, where, whether it is the player, and its own tag settings. Ids are uuids; the first 8 hex digits identify one in later calls if unique.",
			`{"type":"object","properties":{"map":{"type":"string"}}}`,
			tool_character_list,
		},
		{
			"character_new",
			"Add a character of a type (up to 1024), standing nowhere. Returns its id. tags_set / tags_cleared are its own tag settings.",
			`{"type":"object","properties":{"name":{"type":"string"},"type":{"type":"string"},"tags_set":{"type":"array","items":{"type":"string"}},"tags_cleared":{"type":"array","items":{"type":"string"}}},"required":["name","type"]}`,
			tool_character_new,
		},
		{
			"character_edit",
			"Change a character by id; only the fields given change (name, type, tags_set, tags_cleared).",
			`{"type":"object","properties":{"id":{"type":"string"},"name":{"type":"string"},"type":{"type":"string"},"tags_set":{"type":"array","items":{"type":"string"}},"tags_cleared":{"type":"array","items":{"type":"string"}}},"required":["id"]}`,
			tool_character_edit,
		},
		{"character_delete", "Delete a character; it leaves its map, the player becomes nobody if it was the player, and what it carried is gone.", `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`, tool_character_delete},
		{
			"character_place",
			"Stand a character in a map cell (moving it if it stood elsewhere). Refused if another character is in the cell.",
			`{"type":"object","properties":{"id":{"type":"string"},"map":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"}},"required":["id","map","x","y"]}`,
			tool_character_place,
		},
		{"character_unplace", "Take a character off its map.", `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`, tool_character_unplace},
		{"player_set", "Make a character the world's player; an empty or missing id means nobody.", `{"type":"object","properties":{"id":{"type":"string"}}}`, tool_player_set},
		{
			"play_walk",
			"Try a layout: walk a character (default the player) from where it stands. moves is a string of u, d, l, r or a list of up/down/left/right. Reports each step (moved, solid, outside, occupied, feature) and where it ends, and items_at: the steps that ended on a cell holding an inventory (a step onto one is never refused); the world is not changed.",
			`{"type":"object","properties":{"moves":{"type":["string","array"],"items":{"type":"string"}},"id":{"type":"string"}},"required":["moves"]}`,
			tool_play_walk,
		},
	}
	return table[:]
}

// --- Finding things ----------------------------------------------------------------------------

find_map_arg :: proc(s: ^Server, args: json.Object, key := "name") -> (mi: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	i := cm.world_find_map(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no map named %s", name)), false
	}
	return i, {}, true
}

// A terrain of the map's own set, by name.
map_terrain :: proc(s: ^Server, mi: int, name: string) -> (index: int, res: Tool_Result, ok: bool) {
	set := cm.world_map_set(s.world, mi)
	if set == nil {
		return 0, fail("the map's terrain set is missing"), false
	}
	i := cm.set_find_terrain(set, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("terrain set %s has no terrain named %s", cm.name_str(&set.name), name)), false
	}
	return i, {}, true
}

terrain_arg :: proc(s: ^Server, mi: int, args: json.Object, key: string) -> (index: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	return map_terrain(s, mi, name)
}

// A character by its uuid, or by the first 8 hex digits when only one matches.
find_character_arg :: proc(s: ^Server, args: json.Object, key := "id") -> (ci: int, res: Tool_Result, ok: bool) {
	text, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	w := s.world
	if u, is_uuid := cm.uuid_from_string(text); is_uuid {
		i := cm.world_find_character(w, u)
		if i < 0 {
			return 0, fail(fmt.tprintf("no character with id %s", text)), false
		}
		return i, {}, true
	}
	found := -1
	for i in 0 ..< w.character_count {
		if len(text) >= 4 && strings.has_prefix(cm.uuid_to_string(w.characters[i].uuid), strings.to_lower(text, context.temp_allocator)) {
			if found >= 0 {
				return 0, fail(fmt.tprintf("%s matches more than one character: use the full id", text)), false
			}
			found = i
		}
	}
	if found < 0 {
		return 0, fail(fmt.tprintf("no character with id %s", text)), false
	}
	return found, {}, true
}

// tags_set / tags_cleared arguments (each optional) as masks; a given list replaces `set`/`cleared`.
tag_setting_args :: proc(w: ^cm.World, args: json.Object, set, cleared: cm.Tag_Mask) -> (new_set, new_cleared: cm.Tag_Mask, res: Tool_Result, ok: bool) {
	new_set, new_cleared = set, cleared
	for key in ([2]string{"tags_set", "tags_cleared"}) {
		names, present, good := arg_strings(args, key)
		if !present {
			continue
		}
		if !good {
			return 0, 0, fail(fmt.tprintf("%s must be a list of tag names", key)), false
		}
		mask, bad, found := mask_from_names(w, names)
		if !found {
			return 0, 0, fail(fmt.tprintf("no tag named %s", bad)), false
		}
		if key == "tags_set" {
			new_set = mask
		} else {
			new_cleared = mask
		}
	}
	if new_set & new_cleared != 0 {
		return 0, 0, fail("a tag cannot be both set and cleared"), false
	}
	return new_set, new_cleared, {}, true
}

// --- Maps --------------------------------------------------------------------------------------

tool_map_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"maps":[`)
	for i in 0 ..< w.map_count {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		m := &w.maps[i]
		fmt.sbprintf(&b, `{{"name":%s,"set":%s,"width":%d,"height":%d,"characters":%d,"features":%d,"inventories":%d}}`, quote(cm.name_str(&m.name)), quote(cm.name_str(&m.set)), m.width, m.height, cm.world_map_character_count(w, i), cm.world_map_feature_count(w, i), cm.world_map_inventory_count(w, i))
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_map_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	si, r2, ok2 := find_set(s, args, "set")
	if !ok2 {
		return r2
	}
	if p := cm.world_check_map_name(w, -1, name); p != .None {
		return fail(problem_text(p))
	}
	width, height := cm.MAP_DEFAULT_SIZE, cm.MAP_DEFAULT_SIZE
	if v, has := arg_int(args, "width"); has {
		width = v
	}
	if v, has := arg_int(args, "height"); has {
		height = v
	}
	if width < 1 || width > cm.MAP_MAX || height < 1 || height > cm.MAP_MAX {
		return fail("width and height are whole numbers 1..64")
	}
	mi := cm.world_add_map(w, si, name)
	if mi < 0 {
		return fail("the world already has 64 maps")
	}
	cm.world_map_set_size(w, mi, width, height)
	return changed(s, fmt.tprintf("added map %s (%dx%d)", name, width, height))
}

tool_map_rename :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	new_name, r2, ok2 := need_string(args, "new_name")
	if !ok2 {
		return r2
	}
	if p := cm.world_rename_map(s.world, mi, new_name); p != .None {
		return fail(problem_text(p))
	}
	return changed(s, fmt.tprintf("renamed to %s", new_name))
}

tool_map_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	cm.world_delete_map(s.world, mi)
	return changed(s, "deleted the map")
}

tool_map_resize :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	width, g1 := arg_int(args, "width")
	height, g2 := arg_int(args, "height")
	if !g1 || !g2 || width < 1 || width > cm.MAP_MAX || height < 1 || height > cm.MAP_MAX {
		return fail("width and height are whole numbers 1..64")
	}
	m := &s.world.maps[mi]
	if width == m.width && height == m.height {
		return ok_result("the map is already that size")
	}
	if n := cm.world_map_shrink_blocked(s.world, mi, width, height); n > 0 {
		return fail(fmt.tprintf("%d characters stand in the part that would be cut off: move them first", n))
	}
	cm.world_map_set_size(s.world, mi, width, height)
	return changed(s, fmt.tprintf("the map is now %dx%d", width, height))
}

tool_map_set_terrain_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	si, r2, ok2 := find_set(s, args, "set")
	if !ok2 {
		return r2
	}
	done, missing, cells := cm.world_map_change_set(s.world, mi, si)
	if !done {
		return fail(fmt.tprintf("%d cells use terrain %s, which the new set lacks", cells, missing))
	}
	return changed(s, "the map uses the new terrain set")
}

tool_map_get :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	m := &w.maps[mi]
	x0, y0 := 0, 0
	if v, has := arg_int(args, "x"); has {
		x0 = v
	}
	if v, has := arg_int(args, "y"); has {
		y0 = v
	}
	cols, rows := m.width - x0, m.height - y0
	if v, has := arg_int(args, "width"); has {
		cols = v
	}
	if v, has := arg_int(args, "height"); has {
		rows = v
	}
	if x0 < 0 || y0 < 0 || x0 >= m.width || y0 >= m.height || cols < 1 || rows < 1 {
		return fail("the window is outside the map")
	}
	cols, rows = min(cols, m.width - x0), min(rows, m.height - y0)
	set := cm.world_map_set(w, mi)
	lines := make([]string, rows, context.temp_allocator)
	for y in 0 ..< rows {
		row := make([]u8, cols, context.temp_allocator)
		for x in 0 ..< cols {
			t := int(m.cells[y0 + y][x0 + x])
			row[x] = t < len(symbols) ? symbols[t] : '?'
		}
		lines[y] = string(row)
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"width":%d,"height":%d,"x":%d,"y":%d,"rows":`, m.width, m.height, x0, y0)
	write_strings(&b, lines)
	strings.write_string(&b, `,"legend":[`)
	if set != nil {
		for t in 0 ..< min(set.count, len(TERRAIN_SYMBOLS)) {
			if t > 0 {
				strings.write_string(&b, ",")
			}
			fmt.sbprintf(&b, `{{"symbol":%s,"terrain":%s}}`, quote(symbols[t:t + 1]), quote(cm.name_str(&set.terrains[t].name)))
		}
	}
	strings.write_string(&b, `],"characters":[`)
	first := true
	for y in y0 ..< y0 + rows {
		for x in x0 ..< x0 + cols {
			if ci := cm.world_find_character(w, m.characters[y][x]); ci >= 0 {
				strings.write_string(&b, first ? "" : ",")
				first = false
				c := &w.characters[ci]
				fmt.sbprintf(&b, `{{"id":%s,"name":%s,"type":%s,"x":%d,"y":%d}}`, quote(cm.uuid_to_string(c.uuid)), quote(cm.name_str(&c.name)), quote(cm.name_str(&c.type)), x, y)
			}
		}
	}
	strings.write_string(&b, `],"features":[`)
	first = true
	for y in y0 ..< y0 + rows {
		for x in x0 ..< x0 + cols {
			if fi := cm.world_find_feature(w, m.features[y][x]); fi >= 0 {
				strings.write_string(&b, first ? "" : ",")
				first = false
				f := &w.features[fi]
				fmt.sbprintf(&b, `{{"id":%s,"name":%s,"type":%s,"x":%d,"y":%d}}`, quote(cm.uuid_to_string(f.uuid)), quote(cm.name_str(&f.name)), quote(cm.name_str(&f.type)), x, y)
			}
		}
	}
	strings.write_string(&b, `],"inventories":[`)
	first = true
	for y in y0 ..< y0 + rows {
		for x in x0 ..< x0 + cols {
			if u := m.inventories[y][x]; !cm.uuid_is_none(u) {
				fmt.sbprintf(&b, `%s{{"x":%d,"y":%d,"entries":`, first ? "" : ",", x, y)
				write_entries(&b, w, u)
				strings.write_string(&b, "}")
				first = false
			}
		}
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_map_set_rows :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	m := &s.world.maps[mi]
	set := cm.world_map_set(s.world, mi)
	x0, _ := arg_int(args, "x")
	y0, _ := arg_int(args, "y")
	rows, present, good := arg_strings(args, "rows")
	if !present || !good || len(rows) == 0 {
		return fail("rows must be a non-empty list of strings")
	}
	if set == nil || x0 < 0 || y0 < 0 || y0 + len(rows) > m.height {
		return fail("the rows do not fit in the map")
	}
	cells := make([][]u8, len(rows), context.temp_allocator)
	for row, y in rows {
		if x0 + len(row) > m.width || len(row) == 0 {
			return fail(fmt.tprintf("row %d does not fit in the map", y))
		}
		cells[y] = make([]u8, len(row), context.temp_allocator)
		for x in 0 ..< len(row) {
			t := strings.index_byte(TERRAIN_SYMBOLS, row[x])
			if t < 0 || t >= set.count {
				return fail(fmt.tprintf("row %d column %d: %c is not in the legend", y, x, row[x]))
			}
			cells[y][x] = u8(t)
		}
	}
	for line, y in cells {
		for t, x in line {
			m.cells[y0 + y][x0 + x] = t
		}
	}
	return changed(s, fmt.tprintf("wrote %d rows", len(rows)))
}

arg_objects :: proc(args: json.Object, key: string) -> (items: []json.Object, ok: bool) {
	arr, is_arr := args[key].(json.Array)
	if !is_arr {
		return nil, false
	}
	out := make([]json.Object, len(arr), context.temp_allocator)
	for item, i in arr {
		obj, is_obj := item.(json.Object)
		if !is_obj {
			return nil, false
		}
		out[i] = obj
	}
	return out, true
}

tool_map_paint :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	cells, good := arg_objects(args, "cells")
	if !good || len(cells) == 0 {
		return fail("cells must be a non-empty list of {x, y, terrain}")
	}
	m := &s.world.maps[mi]
	Paint :: struct {
		x, y, terrain: int,
	}
	plan := make([]Paint, len(cells), context.temp_allocator)
	for c, i in cells {
		x, gx := arg_int(c, "x")
		y, gy := arg_int(c, "y")
		if !gx || !gy || x < 0 || y < 0 || x >= m.width || y >= m.height {
			return fail(fmt.tprintf("cell %d is outside the map", i))
		}
		t, r, found := terrain_arg(s, mi, c, "terrain")
		if !found {
			return r
		}
		plan[i] = {x, y, t}
	}
	for p in plan {
		cm.map_set(m, p.x, p.y, p.terrain)
	}
	return changed(s, fmt.tprintf("painted %d cells", len(plan)))
}

tool_map_fill_rect :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	t, r2, ok2 := terrain_arg(s, mi, args, "terrain")
	if !ok2 {
		return r2
	}
	x, g1 := arg_int(args, "x")
	y, g2 := arg_int(args, "y")
	width, g3 := arg_int(args, "width")
	height, g4 := arg_int(args, "height")
	if !g1 || !g2 || !g3 || !g4 || width < 1 || height < 1 {
		return fail("x, y, width and height are whole numbers (width and height at least 1)")
	}
	shape := arg_bool(args, "frame") ? cm.Shape.Frame : cm.Shape.Fill
	cm.map_draw_shape(&s.world.maps[mi], shape, x, y, x + width - 1, y + height - 1, t)
	return changed(s, "rectangle drawn")
}

tool_map_flood_fill :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	t, r2, ok2 := terrain_arg(s, mi, args, "terrain")
	if !ok2 {
		return r2
	}
	x, g1 := arg_int(args, "x")
	y, g2 := arg_int(args, "y")
	m := &s.world.maps[mi]
	if !g1 || !g2 || x < 0 || y < 0 || x >= m.width || y >= m.height {
		return fail("(x, y) is outside the map")
	}
	cm.map_flood_fill(m, x, y, t)
	return changed(s, "filled")
}

tool_map_replace_terrain :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	from, r2, ok2 := terrain_arg(s, mi, args, "from")
	if !ok2 {
		return r2
	}
	to, r3, ok3 := terrain_arg(s, mi, args, "to")
	if !ok3 {
		return r3
	}
	cm.map_replace(&s.world.maps[mi], from, to)
	return changed(s, "replaced")
}

tool_map_cell_tags :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	x, g1 := arg_int(args, "x")
	y, g2 := arg_int(args, "y")
	m := &w.maps[mi]
	if !g1 || !g2 || x < 0 || y < 0 || x >= m.width || y >= m.height {
		return fail("(x, y) is outside the map")
	}
	cell := &m.cell_tags[y][x]
	set, cleared, res, ok := tag_setting_args(w, args, cell.set, cell.cleared)
	if !ok {
		return res
	}
	cell.set, cell.cleared = set, cleared
	effective: cm.Tag_Mask
	for t in 0 ..< w.tag_count {
		if cm.world_cell_has_tag(w, mi, x, y, t) {
			effective |= cm.tag_bit(t)
		}
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"tags_set":`)
	write_strings(&b, tag_names_in(w, set))
	strings.write_string(&b, `,"tags_cleared":`)
	write_strings(&b, tag_names_in(w, cleared))
	strings.write_string(&b, `,"effective":`)
	write_strings(&b, tag_names_in(w, effective))
	strings.write_string(&b, "}")
	return changed(s, strings.to_string(b))
}

// --- Character types ---------------------------------------------------------------------------

check_sprite_ref :: proc(w: ^cm.World, set, sprite: string) -> string {
	if set == "" && sprite == "" {
		return ""
	}
	si := cm.world_find_sprite_set(w, set)
	if si < 0 {
		return fmt.tprintf("no sprite set named %s", set)
	}
	if cm.sprite_set_find(&w.sprite_sets[si], sprite) < 0 {
		return fmt.tprintf("sprite set %s has no sprite named %s", set, sprite)
	}
	return ""
}

find_char_type :: proc(s: ^Server, args: json.Object, key := "name") -> (ct: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	i := cm.world_find_char_type(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no character type named %s", name)), false
	}
	return i, {}, true
}

tool_char_type_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"character_types":[`)
	for i in 0 ..< w.char_type_count {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		ct := &w.char_types[i]
		fmt.sbprintf(&b, `{{"name":%s,"sprite_set":%s,"sprite":%s,"tags":`, quote(cm.name_str(&ct.name)), quote(cm.name_str(&ct.sprite_set)), quote(cm.name_str(&ct.sprite)))
		write_strings(&b, tag_names_in(w, ct.tags))
		strings.write_string(&b, "}")
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

// The sprite_set / sprite arguments, over `current`.
sprite_args :: proc(args: json.Object, current_set, current_sprite: string) -> (set, sprite: string, given: bool) {
	a, has_a := arg_string(args, "sprite_set")
	b, has_b := arg_string(args, "sprite")
	set, sprite = current_set, current_sprite
	if has_a {
		set = a
	}
	if has_b {
		sprite = b
	}
	return set, sprite, has_a || has_b
}

tool_char_type_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	if p := cm.world_check_char_type_name(w, -1, name); p != .None {
		return fail(problem_text(p))
	}
	set, sprite, given := sprite_args(args, "", "")
	if given {
		if msg := check_sprite_ref(w, set, sprite); msg != "" {
			return fail(msg)
		}
	}
	mask: cm.Tag_Mask
	if names, present, good := arg_strings(args, "tags"); present {
		bad: string
		if !good {
			return fail("tags must be a list of tag names")
		}
		mask, bad, good = mask_from_names(w, names)
		if !good {
			return fail(fmt.tprintf("no tag named %s", bad))
		}
	}
	i := cm.world_add_char_type(w, name)
	if i < 0 {
		return fail("the world already has 64 character types")
	}
	ct := &w.char_types[i]
	if given {
		cm.name_assign(&ct.sprite_set, set)
		cm.name_assign(&ct.sprite, sprite)
	}
	ct.tags = mask
	return changed(s, fmt.tprintf("added character type %s", name))
}

tool_char_type_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	i, r1, ok1 := find_char_type(s, args)
	if !ok1 {
		return r1
	}
	ct := &w.char_types[i]
	new_name, has_new := arg_string(args, "new_name")
	if has_new {
		if p := cm.world_check_char_type_name(w, i, new_name); p != .None {
			return fail(problem_text(p))
		}
	}
	set, sprite, given := sprite_args(args, cm.name_str(&ct.sprite_set), cm.name_str(&ct.sprite))
	if given {
		if msg := check_sprite_ref(w, set, sprite); msg != "" {
			return fail(msg)
		}
	}
	mask := ct.tags
	if names, present, good := arg_strings(args, "tags"); present {
		bad: string
		if !good {
			return fail("tags must be a list of tag names")
		}
		mask, bad, good = mask_from_names(w, names)
		if !good {
			return fail(fmt.tprintf("no tag named %s", bad))
		}
	}
	if given {
		cm.name_assign(&ct.sprite_set, set)
		cm.name_assign(&ct.sprite, sprite)
	}
	ct.tags = mask
	if has_new {
		cm.world_rename_char_type(w, i, new_name)
	}
	return changed(s, "character type updated")
}

tool_char_type_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, r1, ok1 := find_char_type(s, args)
	if !ok1 {
		return r1
	}
	if uses := cm.world_delete_char_type(s.world, i); uses > 0 {
		return fail(fmt.tprintf("%d characters have this type", uses))
	}
	return changed(s, "deleted the character type")
}

// --- Characters --------------------------------------------------------------------------------

write_character :: proc(b: ^strings.Builder, w: ^cm.World, ci: int) {
	c := &w.characters[ci]
	fmt.sbprintf(b, `{{"id":%s,"name":%s,"type":%s,"player":%v`, quote(cm.uuid_to_string(c.uuid)), quote(cm.name_str(&c.name)), quote(cm.name_str(&c.type)), c.uuid == w.player)
	if mi, x, y, placed := cm.world_character_location(w, c.uuid); placed {
		fmt.sbprintf(b, `,"map":%s,"x":%d,"y":%d`, quote(cm.name_str(&w.maps[mi].name)), x, y)
	}
	strings.write_string(b, `,"tags_set":`)
	write_strings(b, tag_names_in(w, c.tags_set))
	strings.write_string(b, `,"tags_cleared":`)
	write_strings(b, tag_names_in(w, c.tags_cleared))
	strings.write_string(b, "}")
}

tool_character_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	only := -1
	if _, has := arg_string(args, "map"); has {
		mi, r, ok := find_map_arg(s, args, "map")
		if !ok {
			return r
		}
		only = mi
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"characters":[`)
	first := true
	for ci in 0 ..< w.character_count {
		if only >= 0 {
			if mi, _, _, placed := cm.world_character_location(w, w.characters[ci].uuid); !placed || mi != only {
				continue
			}
		}
		strings.write_string(&b, first ? "" : ",")
		first = false
		write_character(&b, w, ci)
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_character_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	if p := cm.name_text_problem(name); p != .None {
		return fail(problem_text(p))
	}
	ct, r2, ok2 := find_char_type(s, args, "type")
	if !ok2 {
		return r2
	}
	set, cleared, r3, ok3 := tag_setting_args(w, args, 0, 0)
	if !ok3 {
		return r3
	}
	ci := cm.world_add_character(w, ct, name)
	if ci < 0 {
		return fail("the world already has 1024 characters")
	}
	w.characters[ci].tags_set, w.characters[ci].tags_cleared = set, cleared
	return changed(s, fmt.tprintf(`{{"id":%s}}`, quote(cm.uuid_to_string(w.characters[ci].uuid))))
}

tool_character_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	ci, r1, ok1 := find_character_arg(s, args)
	if !ok1 {
		return r1
	}
	c := &w.characters[ci]
	name, has_name := arg_string(args, "name")
	if has_name {
		if p := cm.name_text_problem(name); p != .None {
			return fail(problem_text(p))
		}
	}
	ct := -1
	if _, has := arg_string(args, "type"); has {
		i, r, found := find_char_type(s, args, "type")
		if !found {
			return r
		}
		ct = i
	}
	set, cleared, r2, ok2 := tag_setting_args(w, args, c.tags_set, c.tags_cleared)
	if !ok2 {
		return r2
	}
	if has_name {
		cm.world_rename_character(w, ci, name)
	}
	if ct >= 0 {
		cm.world_set_character_type(w, ci, ct)
	}
	c.tags_set, c.tags_cleared = set, cleared
	return changed(s, "character updated")
}

tool_character_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	ci, r1, ok1 := find_character_arg(s, args)
	if !ok1 {
		return r1
	}
	cm.world_delete_character(s.world, ci)
	return changed(s, "deleted the character")
}

tool_character_place :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	ci, r1, ok1 := find_character_arg(s, args)
	if !ok1 {
		return r1
	}
	mi, r2, ok2 := find_map_arg(s, args, "map")
	if !ok2 {
		return r2
	}
	x, g1 := arg_int(args, "x")
	y, g2 := arg_int(args, "y")
	if !g1 || !g2 {
		return fail("x and y are required whole numbers")
	}
	switch cm.world_place_character(w, mi, x, y, w.characters[ci].uuid) {
	case .Placed:
		return changed(s, "placed")
	case .Taken:
		return fail("another character stands in that cell")
	case .Feature_There:
		return fail("a feature stands in that cell: features always block")
	case .Outside:
		return fail("that cell is outside the map")
	case .Unknown, .Character_There:
		return fail("no such map or character")
	}
	return fail("not placed")
}

tool_character_unplace :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	ci, r1, ok1 := find_character_arg(s, args)
	if !ok1 {
		return r1
	}
	if !cm.world_unplace_character(s.world, s.world.characters[ci].uuid) {
		return ok_result("it was not standing anywhere")
	}
	return changed(s, "taken off its map")
}

tool_player_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	if id, has := arg_string(args, "id"); !has || id == "" {
		w.player = cm.UUID_NONE
		return changed(s, "the world has no player now")
	}
	ci, r1, ok1 := find_character_arg(s, args)
	if !ok1 {
		return r1
	}
	cm.world_set_player(w, w.characters[ci].uuid)
	return changed(s, fmt.tprintf("%s is the player", cm.name_str(&w.characters[ci].name)))
}

// --- Trying a layout ---------------------------------------------------------------------------

tool_play_walk :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	steps: [dynamic][2]int
	steps.allocator = context.temp_allocator
	add_move :: proc(steps: ^[dynamic][2]int, name: string) -> bool {
		switch name {
		case "up", "u":
			append(steps, [2]int{0, -1})
		case "down", "d":
			append(steps, [2]int{0, 1})
		case "left", "l":
			append(steps, [2]int{-1, 0})
		case "right", "r":
			append(steps, [2]int{1, 0})
		case:
			return false
		}
		return true
	}
	#partial switch moves in args["moves"] {
	case json.String:
		for ch in transmute([]u8)string(moves) {
			if !add_move(&steps, strings.to_lower(string([]u8{ch}), context.temp_allocator)) {
				return fail("a moves string uses only u, d, l and r")
			}
		}
	case json.Array:
		for item in moves {
			name, is_str := item.(json.String)
			if !is_str || !add_move(&steps, string(name)) {
				return fail("moves are up, down, left or right")
			}
		}
	case:
		return fail("moves is required: a string of u d l r, or a list of directions")
	}
	if len(steps) == 0 || len(steps) > 10000 {
		return fail("give between 1 and 10000 moves")
	}
	ci: int
	if _, has := arg_string(args, "id"); has {
		i, r, found := find_character_arg(s, args)
		if !found {
			return r
		}
		ci = i
	} else {
		i, has_player := rt.player(w)
		if !has_player {
			return fail("the world has no player: use player_set or give an id")
		}
		ci = i
	}
	ps := new(rt.Play_State, context.temp_allocator)
	rt.play_init(ps, w)
	start := rt.play_position(ps, ci)
	if !start.placed {
		return fail("that character is not standing on a map: use character_place")
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"map":%s,"start":{{"x":%d,"y":%d}},"results":[`, quote(cm.name_str(&w.maps[start.map_index].name)), start.x, start.y)
	blocked := 0
	touched := strings.builder_make(context.temp_allocator)
	for d, i in steps {
		result := rt.play_step(ps, w, ci, d.x, d.y)
		if result != .Moved {
			blocked += 1
		}
		fmt.sbprintf(&b, `%s%s`, i > 0 ? "," : "", quote(move_text(result)))
		for {
			c, got := rt.play_take_contact(ps)
			if !got {
				break
			}
			fmt.sbprintf(&touched, `%s{{"step":%d,"x":%d,"y":%d}}`, strings.builder_len(touched) > 0 ? "," : "", i, c.x, c.y)
		}
	}
	end := rt.play_position(ps, ci)
	fmt.sbprintf(&b, `],"end":{{"x":%d,"y":%d}},"blocked":%d,"items_at":[%s]}}`, end.x, end.y, blocked, strings.to_string(touched))
	return ok_result(strings.to_string(b))
}

move_text :: proc(r: rt.Move_Result) -> string {
	switch r {
	case .Moved:
		return "moved"
	case .Not_Placed:
		return "not_placed"
	case .Outside:
		return "outside"
	case .Solid:
		return "solid"
	case .Occupied:
		return "occupied"
	case .Feature:
		return "feature"
	}
	return "?"
}
