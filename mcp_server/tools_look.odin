package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

@(rodata)
HEX_DIGITS := [16]u8{'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'}

NAME_ARG :: `{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}`
RENAME_ARG :: `{"type":"object","properties":{"name":{"type":"string"},"new_name":{"type":"string"}},"required":["name","new_name"]}`

look_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{"palette_get", "The 16 palette colours as #RRGGBB, index 0 first.", `{"type":"object","properties":{}}`, tool_palette_get},
		{
			"palette_set",
			"Set palette colours: colors is a list of #RRGGBB strings placed from index start (default 0).",
			`{"type":"object","properties":{"colors":{"type":"array","items":{"type":"string"}},"start":{"type":"integer"}},"required":["colors"]}`,
			tool_palette_set,
		},
		{
			"tile_size_set",
			"Set the world's tile size (1..64 each). Every tileset image is cropped or padded; pixels cut off stay hidden and return when the size grows back.",
			`{"type":"object","properties":{"width":{"type":"integer"},"height":{"type":"integer"}},"required":["width","height"]}`,
			tool_tile_size_set,
		},
		{"tileset_list", "List the tilesets and the names of the images in each.", `{"type":"object","properties":{}}`, tool_tileset_list},
		{"tileset_new", "Add an empty tileset (up to 16) at the world's tile size.", NAME_ARG, tool_tileset_new},
		{"tileset_rename", "Rename a tileset; terrains and sprites that use it follow.", RENAME_ARG, tool_tileset_rename},
		{"tileset_delete", "Delete a tileset unless a terrain or sprite uses it.", NAME_ARG, tool_tileset_delete},
		{
			"image_new",
			"Add a blank image (all colour 0) to a tileset; name is optional.",
			`{"type":"object","properties":{"tileset":{"type":"string"},"name":{"type":"string"}},"required":["tileset"]}`,
			tool_image_new,
		},
		{
			"image_rename",
			"Rename an image; terrains and sprites that use it follow.",
			`{"type":"object","properties":{"tileset":{"type":"string"},"name":{"type":"string"},"new_name":{"type":"string"}},"required":["tileset","name","new_name"]}`,
			tool_image_rename,
		},
		{
			"image_delete",
			"Delete an image unless a terrain or sprite uses it.",
			`{"type":"object","properties":{"tileset":{"type":"string"},"name":{"type":"string"}},"required":["tileset","name"]}`,
			tool_image_delete,
		},
		{
			"image_get",
			"An image's pixels as rows of hex digits (0-9, A-F = palette index), top row first.",
			`{"type":"object","properties":{"tileset":{"type":"string"},"name":{"type":"string"}},"required":["tileset","name"]}`,
			tool_image_get,
		},
		{
			"image_set",
			"Replace an image's pixels. rows has exactly tile-height strings of exactly tile-width hex digits (0-9, A-F).",
			`{"type":"object","properties":{"tileset":{"type":"string"},"name":{"type":"string"},"rows":{"type":"array","items":{"type":"string"}}},"required":["tileset","name","rows"]}`,
			tool_image_set,
		},
		{
			"terrain_list",
			"Without set: the terrain sets. With set: its terrains (name, tags, tileset, image) and default.",
			`{"type":"object","properties":{"set":{"type":"string"}}}`,
			tool_terrain_list,
		},
		{"terrain_set_new", "Add a terrain set holding one terrain named terrain (the default).", NAME_ARG, tool_terrain_set_new},
		{"terrain_set_rename", "Rename a terrain set; maps that use it follow.", RENAME_ARG, tool_terrain_set_rename},
		{"terrain_set_delete", "Delete a terrain set unless a map uses it.", NAME_ARG, tool_terrain_set_delete},
		{
			"terrain_set_default",
			"Choose the terrain new map cells get.",
			`{"type":"object","properties":{"set":{"type":"string"},"terrain":{"type":"string"}},"required":["set","terrain"]}`,
			tool_terrain_set_default,
		},
		{
			"terrain_new",
			"Add a terrain to a set (up to 256). tileset and image name the picture (both or neither; empty = not set); tags lists tag names it has.",
			`{"type":"object","properties":{"set":{"type":"string"},"name":{"type":"string"},"tileset":{"type":"string"},"image":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["set","name"]}`,
			tool_terrain_new,
		},
		{
			"terrain_edit",
			"Change a terrain; only the fields given change. tags replaces its whole tag list.",
			`{"type":"object","properties":{"set":{"type":"string"},"name":{"type":"string"},"new_name":{"type":"string"},"tileset":{"type":"string"},"image":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["set","name"]}`,
			tool_terrain_edit,
		},
		{
			"terrain_delete",
			"Delete a terrain unless it is the default, the last one, or map cells use it.",
			`{"type":"object","properties":{"set":{"type":"string"},"name":{"type":"string"}},"required":["set","name"]}`,
			tool_terrain_delete,
		},
		{
			"sprite_list",
			"Without set: the sprite sets. With set: its sprites (name, tileset, image, transparent colour or -1).",
			`{"type":"object","properties":{"set":{"type":"string"}}}`,
			tool_sprite_list,
		},
		{"sprite_set_new", "Add an empty sprite set (up to 16).", NAME_ARG, tool_sprite_set_new},
		{"sprite_set_rename", "Rename a sprite set; character types that use it follow.", RENAME_ARG, tool_sprite_set_rename},
		{"sprite_set_delete", "Delete a sprite set unless a character type draws one of its sprites.", NAME_ARG, tool_sprite_set_delete},
		{
			"sprite_new",
			"Add a sprite to a set (up to 256). transparent is the palette index 0..15 that is not drawn, or -1 for none (default 0).",
			`{"type":"object","properties":{"set":{"type":"string"},"name":{"type":"string"},"tileset":{"type":"string"},"image":{"type":"string"},"transparent":{"type":"integer"}},"required":["set","name"]}`,
			tool_sprite_new,
		},
		{
			"sprite_edit",
			"Change a sprite; only the fields given change.",
			`{"type":"object","properties":{"set":{"type":"string"},"name":{"type":"string"},"new_name":{"type":"string"},"tileset":{"type":"string"},"image":{"type":"string"},"transparent":{"type":"integer"}},"required":["set","name"]}`,
			tool_sprite_edit,
		},
		{
			"sprite_delete",
			"Delete a sprite unless a character type draws it.",
			`{"type":"object","properties":{"set":{"type":"string"},"name":{"type":"string"}},"required":["set","name"]}`,
			tool_sprite_delete,
		},
	}
	return table[:]
}

// --- Palette and tile size ---------------------------------------------------------------------

tool_palette_get :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	items := make([]string, cm.PALETTE_SIZE, context.temp_allocator)
	for c, i in s.world.palette {
		items[i] = color_text(c)
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"palette":`)
	write_strings(&b, items)
	strings.write_string(&b, "}")
	return ok_result(strings.to_string(b))
}

tool_palette_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	colors, present, ok := arg_strings(args, "colors")
	if !present || !ok || len(colors) == 0 {
		return fail("colors must be a non-empty list of #RRGGBB strings")
	}
	start, _ := arg_int(args, "start")
	if start < 0 || start + len(colors) > cm.PALETTE_SIZE {
		return fail("the colours must fit in indexes 0..15")
	}
	parsed := make([]cm.Color, len(colors), context.temp_allocator)
	for text, i in colors {
		c, good := parse_hex_color(text)
		if !good {
			return fail(fmt.tprintf("%s is not a #RRGGBB colour", text))
		}
		parsed[i] = c
	}
	for c, i in parsed {
		s.world.palette[start + i] = c
	}
	return changed(s, fmt.tprintf("set %d colours from index %d", len(parsed), start))
}

tool_tile_size_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	width, ok1 := arg_int(args, "width")
	height, ok2 := arg_int(args, "height")
	if !ok1 || !ok2 || width < cm.IMAGE_MIN || width > cm.IMAGE_MAX || height < cm.IMAGE_MIN || height > cm.IMAGE_MAX {
		return fail("width and height are whole numbers 1..64")
	}
	if !cm.world_set_tile_size(s.world, width, height) {
		return ok_result("the tile size is already that")
	}
	return changed(s, fmt.tprintf("tile size is now %dx%d", width, height))
}

// --- Tilesets and images -----------------------------------------------------------------------

find_tileset :: proc(s: ^Server, name: string) -> (index: int, res: Tool_Result, ok: bool) {
	i := cm.world_find_tileset(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no tileset named %s", name)), false
	}
	return i, {}, true
}

tool_tileset_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"tile_width":%d,"tile_height":%d,"tilesets":[`, w.tile_w, w.tile_h)
	for i in 0 ..< w.tileset_count {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		ts := &w.tilesets[i]
		names := make([]string, ts.count, context.temp_allocator)
		for k in 0 ..< ts.count {
			names[k] = cm.tileset_name(ts, k)
		}
		fmt.sbprintf(&b, `{{"name":%s,"images":`, quote(cm.name_str(&w.tileset_names[i])))
		write_strings(&b, names)
		strings.write_string(&b, "}")
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_tileset_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, res, ok := need_string(args, "name")
	if !ok {
		return res
	}
	if p := cm.world_check_tileset_name(s.world, -1, name); p != .None {
		return fail(problem_text(p))
	}
	if cm.world_add_tileset(s.world, name) < 0 {
		return fail("the world already has 16 tilesets")
	}
	return changed(s, fmt.tprintf("added tileset %s", name))
}

tool_tileset_rename :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	new_name, r2, ok2 := need_string(args, "new_name")
	if !ok2 {
		return r2
	}
	i, r3, ok3 := find_tileset(s, name)
	if !ok3 {
		return r3
	}
	if p := cm.world_rename_tileset(s.world, i, new_name); p != .None {
		return fail(problem_text(p))
	}
	return changed(s, fmt.tprintf("renamed to %s", new_name))
}

tool_tileset_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	i, r2, ok2 := find_tileset(s, name)
	if !ok2 {
		return r2
	}
	if uses := cm.world_delete_tileset(s.world, i); uses > 0 {
		return fail(fmt.tprintf("%d terrains or sprites use tileset %s", uses, name))
	}
	return changed(s, fmt.tprintf("deleted tileset %s", name))
}

// A tileset (by the "tileset" argument) and an image in it (by `key`).
find_image :: proc(s: ^Server, args: json.Object, key := "name") -> (ti, ii: int, res: Tool_Result, ok: bool) {
	tname, r1, ok1 := need_string(args, "tileset")
	if !ok1 {
		return 0, 0, r1, false
	}
	iname, r2, ok2 := need_string(args, key)
	if !ok2 {
		return 0, 0, r2, false
	}
	t, r3, ok3 := find_tileset(s, tname)
	if !ok3 {
		return 0, 0, r3, false
	}
	i := cm.tileset_find(&s.world.tilesets[t], iname)
	if i < 0 {
		return 0, 0, fail(fmt.tprintf("tileset %s has no image named %s", tname, iname)), false
	}
	return t, i, {}, true
}

tool_image_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	tname, r1, ok1 := need_string(args, "tileset")
	if !ok1 {
		return r1
	}
	t, r2, ok2 := find_tileset(s, tname)
	if !ok2 {
		return r2
	}
	ts := &s.world.tilesets[t]
	name, has := arg_string(args, "name")
	if !has {
		name = "image"
	} else if p := cm.tileset_check_name(ts, -1, name); p != .None {
		return fail(problem_text(p))
	}
	i := cm.tileset_insert_blank(ts, ts.count, name)
	if i < 0 {
		return fail("the tileset already has 256 images")
	}
	return changed(s, fmt.tprintf("added image %s to %s", cm.tileset_name(ts, i), tname))
}

tool_image_rename :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	t, i, res, ok := find_image(s, args)
	if !ok {
		return res
	}
	new_name, r2, ok2 := need_string(args, "new_name")
	if !ok2 {
		return r2
	}
	ts := &s.world.tilesets[t]
	old := strings.clone(cm.tileset_name(ts, i), context.temp_allocator)
	if p := cm.tileset_set_name(ts, i, new_name); p != .None {
		return fail(problem_text(p))
	}
	cm.world_rename_image(s.world, cm.name_str(&s.world.tileset_names[t]), old, new_name)
	return changed(s, fmt.tprintf("renamed to %s", new_name))
}

tool_image_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	t, i, res, ok := find_image(s, args)
	if !ok {
		return res
	}
	ts := &s.world.tilesets[t]
	tname, iname := cm.name_str(&s.world.tileset_names[t]), cm.tileset_name(ts, i)
	if uses := cm.world_image_uses(s.world, tname, iname); uses > 0 {
		return fail(fmt.tprintf("%d terrains or sprites use image %s", uses, iname))
	}
	name := strings.clone(iname, context.temp_allocator)
	cm.tileset_delete(ts, i)
	return changed(s, fmt.tprintf("deleted image %s", name))
}

tool_image_get :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	t, i, res, ok := find_image(s, args)
	if !ok {
		return res
	}
	img := &s.world.tilesets[t].images[i]
	rows := make([]string, img.height, context.temp_allocator)
	for y in 0 ..< img.height {
		row := make([]u8, img.width, context.temp_allocator)
		for x in 0 ..< img.width {
			row[x] = HEX_DIGITS[img.pixels[y][x] & 15]
		}
		rows[y] = string(row)
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"width":%d,"height":%d,"rows":`, img.width, img.height)
	write_strings(&b, rows)
	strings.write_string(&b, "}")
	return ok_result(strings.to_string(b))
}

tool_image_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	t, i, res, ok := find_image(s, args)
	if !ok {
		return res
	}
	rows, present, good := arg_strings(args, "rows")
	img := &s.world.tilesets[t].images[i]
	if !present || !good || len(rows) != img.height {
		return fail(fmt.tprintf("rows must be a list of %d strings", img.height))
	}
	pixels := make([]u8, img.width * img.height, context.temp_allocator)
	for row, y in rows {
		if len(row) != img.width {
			return fail(fmt.tprintf("row %d has %d characters, expected %d", y, len(row), img.width))
		}
		for x in 0 ..< img.width {
			v, is_hex := hex_digit(row[x])
			if !is_hex {
				return fail(fmt.tprintf("row %d column %d: %c is not a hex digit", y, x, row[x]))
			}
			pixels[y * img.width + x] = u8(v)
		}
	}
	for y in 0 ..< img.height {
		for x in 0 ..< img.width {
			img.pixels[y][x] = pixels[y * img.width + x]
		}
	}
	return changed(s, "image updated")
}

// --- Terrain sets and terrains -----------------------------------------------------------------

find_set :: proc(s: ^Server, args: json.Object, key: string) -> (index: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	i := cm.world_find_set(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no terrain set named %s", name)), false
	}
	return i, {}, true
}

find_terrain :: proc(s: ^Server, args: json.Object) -> (si, ti: int, res: Tool_Result, ok: bool) {
	si, res, ok = find_set(s, args, "set")
	if !ok {
		return
	}
	name, r, got := need_string(args, "name")
	if !got {
		return 0, 0, r, false
	}
	ti = cm.set_find_terrain(&s.world.sets[si], name)
	if ti < 0 {
		return 0, 0, fail(fmt.tprintf("terrain set %s has no terrain named %s", cm.name_str(&s.world.sets[si].name), name)), false
	}
	return si, ti, {}, true
}

tool_terrain_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	if _, has := arg_string(args, "set"); !has {
		strings.write_string(&b, `{"terrain_sets":[`)
		for i in 0 ..< w.set_count {
			if i > 0 {
				strings.write_string(&b, ",")
			}
			fmt.sbprintf(&b, `{{"name":%s,"terrains":%d}}`, quote(cm.name_str(&w.sets[i].name)), w.sets[i].count)
		}
		strings.write_string(&b, "]}")
		return ok_result(strings.to_string(b))
	}
	si, res, ok := find_set(s, args, "set")
	if !ok {
		return res
	}
	set := &w.sets[si]
	fmt.sbprintf(&b, `{{"default":%s,"terrains":[`, quote(cm.name_str(&set.terrains[set.default].name)))
	for i in 0 ..< set.count {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		t := &set.terrains[i]
		fmt.sbprintf(&b, `{{"name":%s,"tileset":%s,"image":%s,"tags":`, quote(cm.name_str(&t.name)), quote(cm.name_str(&t.tileset)), quote(cm.name_str(&t.image)))
		write_strings(&b, tag_names_in(w, t.tags))
		strings.write_string(&b, "}")
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_terrain_set_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, res, ok := need_string(args, "name")
	if !ok {
		return res
	}
	if p := cm.world_check_set_name(s.world, -1, name); p != .None {
		return fail(problem_text(p))
	}
	if cm.world_add_terrain_set(s.world, name) < 0 {
		return fail("the world already has 16 terrain sets")
	}
	return changed(s, fmt.tprintf("added terrain set %s with one terrain, \"terrain\"", name))
}

tool_terrain_set_rename :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, res, ok := find_set(s, args, "name")
	if !ok {
		return res
	}
	new_name, r2, ok2 := need_string(args, "new_name")
	if !ok2 {
		return r2
	}
	if p := cm.world_rename_terrain_set(s.world, i, new_name); p != .None {
		return fail(problem_text(p))
	}
	return changed(s, fmt.tprintf("renamed to %s", new_name))
}

tool_terrain_set_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, res, ok := find_set(s, args, "name")
	if !ok {
		return res
	}
	if uses := cm.world_delete_terrain_set(s.world, i); uses > 0 {
		return fail(fmt.tprintf("%d maps use this terrain set", uses))
	}
	return changed(s, "deleted the terrain set")
}

tool_terrain_set_default :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	si, res, ok := find_set(s, args, "set")
	if !ok {
		return res
	}
	name, r2, ok2 := need_string(args, "terrain")
	if !ok2 {
		return r2
	}
	ti := cm.set_find_terrain(&s.world.sets[si], name)
	if ti < 0 {
		return fail(fmt.tprintf("no terrain named %s in that set", name))
	}
	s.world.sets[si].default = ti
	return changed(s, fmt.tprintf("the default terrain is now %s", name))
}

// Checks a tileset/image pair (both empty = not set) against the world.
check_picture :: proc(w: ^cm.World, tileset, image: string) -> string {
	if tileset == "" && image == "" {
		return ""
	}
	ti := cm.world_find_tileset(w, tileset)
	if ti < 0 {
		return fmt.tprintf("no tileset named %s", tileset)
	}
	if cm.tileset_find(&w.tilesets[ti], image) < 0 {
		return fmt.tprintf("tileset %s has no image named %s", tileset, image)
	}
	return ""
}

// The tileset/image a tool call names: the call's own values where given, else `current`.
picture_args :: proc(args: json.Object, current_tileset, current_image: string) -> (tileset, image: string, given: bool) {
	t, has_t := arg_string(args, "tileset")
	i, has_i := arg_string(args, "image")
	tileset, image = current_tileset, current_image
	if has_t {
		tileset = t
	}
	if has_i {
		image = i
	}
	return tileset, image, has_t || has_i
}

tool_terrain_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	si, res, ok := find_set(s, args, "set")
	if !ok {
		return res
	}
	name, r2, ok2 := need_string(args, "name")
	if !ok2 {
		return r2
	}
	set := &w.sets[si]
	if p := cm.terrain_check_name(set, -1, name); p != .None {
		return fail(problem_text(p))
	}
	tileset, image, given := picture_args(args, "", "")
	if given {
		if msg := check_picture(w, tileset, image); msg != "" {
			return fail(msg)
		}
	}
	mask: cm.Tag_Mask
	if names, present, good := arg_strings(args, "tags"); present {
		if !good {
			return fail("tags must be a list of tag names")
		}
		bad: string
		mask, bad, good = mask_from_names(w, names)
		if !good {
			return fail(fmt.tprintf("no tag named %s", bad))
		}
	}
	ti := cm.world_add_terrain(w, si)
	if ti < 0 {
		return fail("the set already has 256 terrains")
	}
	t := &set.terrains[ti]
	cm.name_assign(&t.name, name)
	t.tags = mask
	if given {
		cm.name_assign(&t.tileset, tileset)
		cm.name_assign(&t.image, image)
	}
	return changed(s, fmt.tprintf("added terrain %s", name))
}

tool_terrain_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	si, ti, res, ok := find_terrain(s, args)
	if !ok {
		return res
	}
	t := &w.sets[si].terrains[ti]
	new_name, has_new := arg_string(args, "new_name")
	if has_new {
		if p := cm.terrain_check_name(&w.sets[si], ti, new_name); p != .None {
			return fail(problem_text(p))
		}
	}
	tileset, image, given := picture_args(args, cm.name_str(&t.tileset), cm.name_str(&t.image))
	if given {
		if msg := check_picture(w, tileset, image); msg != "" {
			return fail(msg)
		}
	}
	mask := t.tags
	if names, present, good := arg_strings(args, "tags"); present {
		if !good {
			return fail("tags must be a list of tag names")
		}
		bad: string
		mask, bad, good = mask_from_names(w, names)
		if !good {
			return fail(fmt.tprintf("no tag named %s", bad))
		}
	}
	if has_new {
		cm.name_assign(&t.name, new_name)
	}
	if given {
		cm.name_assign(&t.tileset, tileset)
		cm.name_assign(&t.image, image)
	}
	t.tags = mask
	return changed(s, "terrain updated")
}

tool_terrain_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	si, ti, res, ok := find_terrain(s, args)
	if !ok {
		return res
	}
	result, uses := cm.world_delete_terrain(s.world, si, ti)
	switch result {
	case .Deleted:
		return changed(s, "deleted the terrain")
	case .Last_One:
		return fail("a terrain set keeps at least one terrain")
	case .Is_Default:
		return fail("this is the set's default terrain: choose another default first")
	case .In_Use:
		return fail(fmt.tprintf("%d map cells use this terrain", uses))
	}
	return fail("not deleted")
}

// --- Sprite sets and sprites -------------------------------------------------------------------

find_sprite_set :: proc(s: ^Server, args: json.Object, key: string) -> (index: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	i := cm.world_find_sprite_set(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no sprite set named %s", name)), false
	}
	return i, {}, true
}

find_sprite :: proc(s: ^Server, args: json.Object) -> (si, i: int, res: Tool_Result, ok: bool) {
	si, res, ok = find_sprite_set(s, args, "set")
	if !ok {
		return
	}
	name, r, got := need_string(args, "name")
	if !got {
		return 0, 0, r, false
	}
	set := &s.world.sprite_sets[si]
	i = cm.sprite_set_find(set, name)
	if i < 0 {
		return 0, 0, fail(fmt.tprintf("sprite set %s has no sprite named %s", cm.name_str(&set.name), name)), false
	}
	return si, i, {}, true
}

tool_sprite_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	if _, has := arg_string(args, "set"); !has {
		strings.write_string(&b, `{"sprite_sets":[`)
		for i in 0 ..< w.sprite_set_count {
			if i > 0 {
				strings.write_string(&b, ",")
			}
			fmt.sbprintf(&b, `{{"name":%s,"sprites":%d}}`, quote(cm.name_str(&w.sprite_sets[i].name)), w.sprite_sets[i].count)
		}
		strings.write_string(&b, "]}")
		return ok_result(strings.to_string(b))
	}
	si, res, ok := find_sprite_set(s, args, "set")
	if !ok {
		return res
	}
	set := &w.sprite_sets[si]
	strings.write_string(&b, `{"sprites":[`)
	for i in 0 ..< set.count {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		sp := &set.sprites[i]
		fmt.sbprintf(&b, `{{"name":%s,"tileset":%s,"image":%s,"transparent":%d}}`, quote(cm.name_str(&sp.name)), quote(cm.name_str(&sp.tileset)), quote(cm.name_str(&sp.image)), sp.transparent)
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_sprite_set_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, res, ok := need_string(args, "name")
	if !ok {
		return res
	}
	if p := cm.world_check_sprite_set_name(s.world, -1, name); p != .None {
		return fail(problem_text(p))
	}
	if cm.world_add_sprite_set(s.world, name) < 0 {
		return fail("the world already has 16 sprite sets")
	}
	return changed(s, fmt.tprintf("added sprite set %s", name))
}

tool_sprite_set_rename :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, res, ok := find_sprite_set(s, args, "name")
	if !ok {
		return res
	}
	new_name, r2, ok2 := need_string(args, "new_name")
	if !ok2 {
		return r2
	}
	if p := cm.world_rename_sprite_set(s.world, i, new_name); p != .None {
		return fail(problem_text(p))
	}
	return changed(s, fmt.tprintf("renamed to %s", new_name))
}

tool_sprite_set_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, res, ok := find_sprite_set(s, args, "name")
	if !ok {
		return res
	}
	if !cm.world_delete_sprite_set(s.world, i) {
		return fail("a character type draws a sprite of this set")
	}
	return changed(s, "deleted the sprite set")
}

// The transparent argument: -1 or 0..15.
arg_transparent :: proc(args: json.Object) -> (value: int, given, ok: bool) {
	if _, has := args["transparent"]; !has {
		return 0, false, true
	}
	v, is_int := arg_int(args, "transparent")
	if !is_int || v < -1 || v >= cm.PALETTE_SIZE {
		return 0, true, false
	}
	return v, true, true
}

tool_sprite_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	si, res, ok := find_sprite_set(s, args, "set")
	if !ok {
		return res
	}
	name, r2, ok2 := need_string(args, "name")
	if !ok2 {
		return r2
	}
	set := &w.sprite_sets[si]
	if p := cm.sprite_check_name(set, -1, name); p != .None {
		return fail(problem_text(p))
	}
	tileset, image, given := picture_args(args, "", "")
	if given {
		if msg := check_picture(w, tileset, image); msg != "" {
			return fail(msg)
		}
	}
	transparent, has_t, good := arg_transparent(args)
	if !good {
		return fail("transparent is -1 (none) or a palette index 0..15")
	}
	i := cm.world_add_sprite(w, si)
	if i < 0 {
		return fail("the set already has 256 sprites")
	}
	sp := &set.sprites[i]
	cm.name_assign(&sp.name, name)
	if given {
		cm.name_assign(&sp.tileset, tileset)
		cm.name_assign(&sp.image, image)
	}
	if has_t {
		sp.transparent = transparent == -1 ? cm.SPRITE_NO_TRANSPARENT : transparent
	}
	return changed(s, fmt.tprintf("added sprite %s", name))
}

tool_sprite_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	si, i, res, ok := find_sprite(s, args)
	if !ok {
		return res
	}
	sp := &w.sprite_sets[si].sprites[i]
	new_name, has_new := arg_string(args, "new_name")
	if has_new {
		if p := cm.sprite_check_name(&w.sprite_sets[si], i, new_name); p != .None {
			return fail(problem_text(p))
		}
	}
	tileset, image, given := picture_args(args, cm.name_str(&sp.tileset), cm.name_str(&sp.image))
	if given {
		if msg := check_picture(w, tileset, image); msg != "" {
			return fail(msg)
		}
	}
	transparent, has_t, good := arg_transparent(args)
	if !good {
		return fail("transparent is -1 (none) or a palette index 0..15")
	}
	if has_new {
		cm.world_rename_sprite(w, si, i, new_name)
	}
	if given {
		cm.name_assign(&sp.tileset, tileset)
		cm.name_assign(&sp.image, image)
	}
	if has_t {
		sp.transparent = transparent == -1 ? cm.SPRITE_NO_TRANSPARENT : transparent
	}
	return changed(s, "sprite updated")
}

tool_sprite_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	si, i, res, ok := find_sprite(s, args)
	if !ok {
		return res
	}
	if !cm.world_delete_sprite(s.world, si, i) {
		return fail("a character type draws this sprite")
	}
	return changed(s, "deleted the sprite")
}
