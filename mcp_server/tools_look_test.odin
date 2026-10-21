#+build !js
package mcp_server

import "core:strings"
import "core:testing"

// Calls a tool that must succeed; returns its text.
good :: proc(t: ^testing.T, s: ^Server, name, args: string) -> string {
	text, bad := call(t, s, name, args)
	testing.expectf(t, !bad, "%s %s failed: %s", name, args, text)
	return text
}

// Calls a tool that must be refused; returns the reason.
refused :: proc(t: ^testing.T, s: ^Server, name, args: string) -> string {
	text, bad := call(t, s, name, args)
	testing.expectf(t, bad, "%s %s should have been refused", name, args)
	return text
}

@(test)
test_every_tool_needs_an_open_world_and_names_are_unique :: proc(t: ^testing.T) {
	s := new_server("")
	defer free_server(s)
	seen := map[string]bool{}
	defer delete(seen)
	for tool in tools() {
		testing.expectf(t, tool.name not_in seen, "duplicate tool %s", tool.name)
		seen[tool.name] = true
		// (these work with no world open: they look at files)
		if tool.name == "world_new" || tool.name == "world_open" || tool.name == "world_list" || tool.name == "world_read" {
			continue
		}
		text, bad := call(t, s, tool.name, `{"name":"x","set":"x","tileset":"x"}`)
		testing.expectf(t, bad && strings.contains(text, "no world is open"), "%s: %s", tool.name, text)
	}
}

@(test)
test_rules_tools :: proc(t: ^testing.T) {
	s := new_server("")
	defer free_server(s)
	good(t, s, "world_new", "{}")
	good(t, s, "tag_new", `{"name":"thing"}`)
	refused(t, s, "tag_new", `{"name":"thing"}`)
	refused(t, s, "tag_new", `{"name":""}`)
	refused(t, s, "tag_rename", `{"name":"solid","new_name":"wall"}`)
	refused(t, s, "tag_delete", `{"name":"solid"}`)
	refused(t, s, "tag_delete", `{"name":"nope"}`)
	good(t, s, "tag_rename", `{"name":"thing","new_name":"prize"}`)
	text := good(t, s, "tag_list", "{}")
	testing.expect(t, strings.contains(text, `"prize"`) && !strings.contains(text, `"thing"`))
	good(t, s, "tag_delete", `{"name":"prize"}`) // unused: no confirmation needed
	good(t, s, "param_set", `{"name":"round_seconds","number":60}`)
	good(t, s, "param_set", `{"name":"title","text":"Go Get It"}`)
	good(t, s, "param_set", `{"name":"round_seconds","number":45}`)
	refused(t, s, "param_set", `{"name":"x","number":1,"text":"a"}`)
	refused(t, s, "param_set", `{"name":"x"}`)
	refused(t, s, "param_set", `{"name":"long","text":"0123456789012345678901234567890123456789"}`)
	text = good(t, s, "param_list", "{}")
	testing.expect(t, strings.contains(text, `{"name":"round_seconds","number":45}`) && strings.contains(text, `{"name":"title","text":"Go Get It"}`))
	testing.expect_value(t, s.world.param_count, 2) // the refused ones added nothing
	good(t, s, "param_rename", `{"name":"title","new_name":"heading"}`)
	good(t, s, "param_delete", `{"name":"heading"}`)
	refused(t, s, "param_delete", `{"name":"heading"}`)
}

@(test)
test_palette_and_tile_size :: proc(t: ^testing.T) {
	s := new_server("")
	defer free_server(s)
	good(t, s, "world_new", "{}")
	good(t, s, "palette_set", `{"colors":["#FF0000","00ff00"],"start":3}`)
	testing.expect(t, s.world.palette[3] == {255, 0, 0} && s.world.palette[4] == {0, 255, 0})
	refused(t, s, "palette_set", `{"colors":["#FF0000","nope"]}`)
	refused(t, s, "palette_set", `{"colors":["#FF0000","#000000"],"start":15}`)
	text := good(t, s, "palette_get", "{}")
	testing.expect(t, strings.contains(text, `"#FF0000","#00FF00"`))
	good(t, s, "tile_size_set", `{"width":4,"height":6}`)
	testing.expect(t, s.world.tile_w == 4 && s.world.tile_h == 6)
	refused(t, s, "tile_size_set", `{"width":0,"height":6}`)
	refused(t, s, "tile_size_set", `{"width":65,"height":6}`)
}

@(test)
test_a_small_world_built_by_tools_round_trips_through_a_file :: proc(t: ^testing.T) {
	dir := temp_dir("small_world")
	s := new_server(dir)
	defer free_server(s)
	good(t, s, "world_new", "{}")
	good(t, s, "tile_size_set", `{"width":3,"height":2}`)
	good(t, s, "tileset_new", `{"name":"ground"}`)
	refused(t, s, "tileset_new", `{"name":"ground"}`)
	good(t, s, "image_new", `{"tileset":"ground","name":"grass"}`)
	good(t, s, "image_new", `{"tileset":"ground","name":"rock"}`)
	refused(t, s, "image_new", `{"tileset":"ground","name":"rock"}`)
	refused(t, s, "image_new", `{"tileset":"nope"}`)
	good(t, s, "image_set", `{"tileset":"ground","name":"grass","rows":["1A1","f00"]}`)
	refused(t, s, "image_set", `{"tileset":"ground","name":"grass","rows":["1A1"]}`)
	refused(t, s, "image_set", `{"tileset":"ground","name":"grass","rows":["1A1","12"]}`)
	refused(t, s, "image_set", `{"tileset":"ground","name":"grass","rows":["1A1","1G1"]}`)
	text := good(t, s, "image_get", `{"tileset":"ground","name":"grass"}`)
	testing.expect(t, strings.contains(text, `"rows":["1A1","F00"]`)) // the refused ones changed nothing

	good(t, s, "terrain_set_new", `{"name":"outdoors"}`)
	good(t, s, "terrain_edit", `{"set":"outdoors","name":"terrain","new_name":"floor","tileset":"ground","image":"grass"}`)
	good(t, s, "terrain_new", `{"set":"outdoors","name":"wall","tileset":"ground","image":"rock","tags":["solid"]}`)
	refused(t, s, "terrain_new", `{"set":"outdoors","name":"wall"}`)
	refused(t, s, "terrain_new", `{"set":"outdoors","name":"bad","tags":["nope"]}`)
	refused(t, s, "terrain_new", `{"set":"outdoors","name":"bad","tileset":"ground","image":"nope"}`)
	refused(t, s, "terrain_edit", `{"set":"outdoors","name":"wall","tileset":"nope","image":"x"}`)
	text = good(t, s, "terrain_list", `{"set":"outdoors"}`)
	testing.expect(t, strings.contains(text, `"default":"floor"`) && strings.contains(text, `{"name":"wall","tileset":"ground","image":"rock","tags":["solid"]}`))
	testing.expect(t, strings.contains(good(t, s, "terrain_list", "{}"), `{"name":"outdoors","terrains":2}`))

	// Things in use are protected, and the reasons say so.
	refused(t, s, "image_delete", `{"tileset":"ground","name":"rock"}`)
	refused(t, s, "tileset_delete", `{"name":"ground"}`)
	refused(t, s, "terrain_delete", `{"set":"outdoors","name":"floor"}`) // the default
	good(t, s, "terrain_set_default", `{"set":"outdoors","terrain":"wall"}`)
	good(t, s, "terrain_set_default", `{"set":"outdoors","terrain":"floor"}`)
	// Renames follow their users.
	good(t, s, "image_rename", `{"tileset":"ground","name":"rock","new_name":"stone"}`)
	good(t, s, "tileset_rename", `{"name":"ground","new_name":"land"}`)
	text = good(t, s, "terrain_list", `{"set":"outdoors"}`)
	testing.expect(t, strings.contains(text, `"tileset":"land","image":"stone"`))
	// A tag in use needs confirmation to delete.
	good(t, s, "tag_new", `{"name":"prize"}`)
	good(t, s, "terrain_edit", `{"set":"outdoors","name":"floor","tags":["prize"]}`)
	refused(t, s, "tag_delete", `{"name":"prize"}`)
	good(t, s, "tag_delete", `{"name":"prize","confirm":true}`)
	testing.expect(t, strings.contains(good(t, s, "terrain_list", `{"set":"outdoors"}`), `"name":"floor","tileset":"land","image":"grass","tags":[]`))

	good(t, s, "sprite_set_new", `{"name":"creatures"}`)
	good(t, s, "sprite_new", `{"set":"creatures","name":"bat","tileset":"land","image":"grass","transparent":-1}`)
	good(t, s, "sprite_new", `{"set":"creatures","name":"owl","tileset":"land","image":"stone"}`)
	refused(t, s, "sprite_new", `{"set":"creatures","name":"owl"}`)
	refused(t, s, "sprite_new", `{"set":"creatures","name":"x","transparent":16}`)
	good(t, s, "sprite_edit", `{"set":"creatures","name":"owl","new_name":"hawk","transparent":3}`)
	text = good(t, s, "sprite_list", `{"set":"creatures"}`)
	testing.expect(t, strings.contains(text, `"name":"bat","tileset":"land","image":"grass","transparent":-1`) && strings.contains(text, `"name":"hawk","tileset":"land","image":"stone","transparent":3`))
	good(t, s, "sprite_delete", `{"set":"creatures","name":"bat"}`)
	good(t, s, "sprite_set_rename", `{"name":"creatures","new_name":"animals"}`)
	good(t, s, "terrain_delete", `{"set":"outdoors","name":"wall"}`)

	// Save it, open it in a fresh server, and find the same things.
	good(t, s, "world_save", `{"path":"w.json"}`)
	s2 := new_server(dir)
	defer free_server(s2)
	good(t, s2, "world_open", `{"path":"w.json"}`)
	text = good(t, s2, "world_summary", "{}")
	testing.expect(t, strings.contains(text, `"tile_width":3,"tile_height":2`) && strings.contains(text, `"tilesets":["land"]`) && strings.contains(text, `"terrain_sets":["outdoors"]`) && strings.contains(text, `"sprite_sets":["animals"]`))
	testing.expect(t, strings.contains(good(t, s2, "image_get", `{"tileset":"land","name":"grass"}`), `"rows":["1A1","F00"]`))
	testing.expect(t, strings.contains(good(t, s2, "sprite_list", `{"set":"animals"}`), `"name":"hawk"`))
}
