package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

NOT_OPEN :: "no world is open: use world_new or world_open first"

// The world file tools.
world_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{
			"world_new",
			"Start a new, empty world (16x16 tiles, the default palette, only the solid tag). Refuses while the open world has unsaved changes unless discard is true.",
			`{"type":"object","properties":{"discard":{"type":"boolean","description":"throw away unsaved changes"}}}`,
			tool_world_new,
		},
		{
			"world_open",
			"Open a world.json from the server's folder. The path is relative (no '..'), ends in .json. Refuses while the open world has unsaved changes unless discard is true. A file that is not a valid world leaves the open world alone.",
			`{"type":"object","properties":{"path":{"type":"string"},"discard":{"type":"boolean"}},"required":["path"]}`,
			tool_world_open,
		},
		{
			"world_save",
			"Write the open world to a file in the server's folder. Without a path it saves to the file it was opened from or last saved to. Saving over a different existing file needs overwrite true.",
			`{"type":"object","properties":{"path":{"type":"string"},"overwrite":{"type":"boolean"}}}`,
			tool_world_save,
		},
		{
			"world_summary",
			"Describe the open world: file, unsaved changes, tile size, and the names of its tilesets, terrain sets, sprite sets, character types, maps, tags and parameters.",
			`{"type":"object","properties":{}}`,
			tool_world_summary,
		},
		{
			"world_check_game_tags",
			"Check the open world against the tags a game needs. Give either the text of a game_tags.json or a path to one in the server's folder. Lists the needed tags the world lacks.",
			`{"type":"object","properties":{"text":{"type":"string","description":"the contents of a game_tags.json"},"path":{"type":"string"}}}`,
			tool_world_check_game_tags,
		},
	}
	return table[:]
}

// A file name inside the server's folder: relative, no '..' or backslashes, ending in .json.
resolve_path :: proc(s: ^Server, name: string) -> (path: string, err: string) {
	switch {
	case name == "":
		return "", "the path is empty"
	case strings.has_prefix(name, "/") || strings.contains(name, ":") || strings.contains(name, "\\"):
		return "", "the path must be relative to the server's folder"
	case strings.contains(name, ".."):
		return "", "the path may not contain '..'"
	case !strings.has_suffix(name, ".json"):
		return "", "the path must end in .json"
	}
	if s.dir == "" {
		return name, ""
	}
	return fmt.tprintf("%s/%s", strings.trim_right(s.dir, "/"), name), ""
}

unsaved_refusal :: proc(s: ^Server, args: json.Object) -> (refused: bool, res: Tool_Result) {
	if s.open && s.dirty && !arg_bool(args, "discard") {
		return true, fail("the open world has unsaved changes: save it first, or pass discard true")
	}
	return false, {}
}

set_file :: proc(s: ^Server, name: string) {
	delete(s.file)
	s.file = strings.clone(name)
}

tool_world_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if refused, res := unsaved_refusal(s, args); refused {
		return res
	}
	cm.world_reset(s.world)
	s.open, s.dirty = true, true
	set_file(s, "")
	return ok_result("a new empty world is open (unsaved)")
}

tool_world_open :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	name, has := arg_string(args, "path")
	if !has {
		return fail("world_open needs a path")
	}
	path, perr := resolve_path(s, name)
	if perr != "" {
		return fail(perr)
	}
	if refused, res := unsaved_refusal(s, args); refused {
		return res
	}
	data, rerr := os.read_entire_file(path, context.temp_allocator)
	if rerr != nil {
		return fail(fmt.tprintf("cannot read %s", name))
	}
	if err := cm.world_from_json(data, s.world); err != "" {
		return fail(fmt.tprintf("%s is not a valid world: %s", name, err))
	}
	s.open, s.dirty = true, false
	set_file(s, name)
	return ok_result(fmt.tprintf("opened %s", name))
}

tool_world_save :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if !s.open {
		return fail(NOT_OPEN)
	}
	name, has := arg_string(args, "path")
	if !has {
		if s.file == "" {
			return fail("this world has no file yet: give a path")
		}
		name = s.file
	}
	path, perr := resolve_path(s, name)
	if perr != "" {
		return fail(perr)
	}
	if name != s.file && os.exists(path) && !arg_bool(args, "overwrite") {
		return fail(fmt.tprintf("%s already exists: pass overwrite true to replace it", name))
	}
	text := cm.world_to_json(s.world)
	if err := os.write_entire_file(path, transmute([]u8)text); err != nil {
		return fail(fmt.tprintf("cannot write %s", name))
	}
	s.dirty = false
	set_file(s, name)
	return ok_result(fmt.tprintf("saved %s (%d bytes)", name, len(text)))
}

write_name_list :: proc(b: ^strings.Builder, key: string, count: int, name_at: proc(w: ^cm.World, i: int) -> string, w: ^cm.World) {
	fmt.sbprintf(b, `,%s:[`, quote(key))
	for i in 0 ..< count {
		if i > 0 {
			strings.write_string(b, ",")
		}
		strings.write_string(b, quote(name_at(w, i)))
	}
	strings.write_string(b, "]")
}

tool_world_summary :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if !s.open {
		return fail(NOT_OPEN)
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"file":%s,"unsaved_changes":%v,"tile_width":%d,"tile_height":%d`, quote(s.file), s.dirty, w.tile_w, w.tile_h)
	write_name_list(&b, "tilesets", w.tileset_count, proc(w: ^cm.World, i: int) -> string {return cm.name_str(&w.tileset_names[i])}, w)
	write_name_list(&b, "terrain_sets", w.set_count, proc(w: ^cm.World, i: int) -> string {return cm.name_str(&w.sets[i].name)}, w)
	write_name_list(&b, "sprite_sets", w.sprite_set_count, proc(w: ^cm.World, i: int) -> string {return cm.name_str(&w.sprite_sets[i].name)}, w)
	write_name_list(&b, "character_types", w.char_type_count, proc(w: ^cm.World, i: int) -> string {return cm.name_str(&w.char_types[i].name)}, w)
	write_name_list(&b, "maps", w.map_count, proc(w: ^cm.World, i: int) -> string {return cm.name_str(&w.maps[i].name)}, w)
	write_name_list(&b, "tags", w.tag_count, proc(w: ^cm.World, i: int) -> string {return cm.name_str(&w.tags[i])}, w)
	write_name_list(&b, "params", w.param_count, proc(w: ^cm.World, i: int) -> string {return cm.name_str(&w.params[i].name)}, w)
	fmt.sbprintf(&b, `,"characters":%d,"has_player":%v}}`, w.character_count, w.player != cm.Uuid{})
	return ok_result(strings.to_string(b))
}

tool_world_check_game_tags :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if !s.open {
		return fail(NOT_OPEN)
	}
	data: []u8
	if text, has := arg_string(args, "text"); has {
		data = transmute([]u8)text
	} else if name, has_path := arg_string(args, "path"); has_path {
		path, perr := resolve_path(s, name)
		if perr != "" {
			return fail(perr)
		}
		read, rerr := os.read_entire_file(path, context.temp_allocator)
		if rerr != nil {
			return fail(fmt.tprintf("cannot read %s", name))
		}
		data = read
	} else {
		return fail("give either text or path")
	}
	g := new(cm.Game_Tags, context.temp_allocator)
	if err := cm.game_tags_from_json(data, g); err != "" {
		return fail(fmt.tprintf("not a valid game_tags.json: %s", err))
	}
	missing := cm.game_tags_missing(s.world, g)
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"needed":%d,"missing":[`, g.count)
	for name, i in missing {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		strings.write_string(&b, quote(name))
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}
