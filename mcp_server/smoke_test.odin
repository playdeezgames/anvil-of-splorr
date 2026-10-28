#+build !js
package mcp_server

import rt "../anvil_runtime"
import cm "../common"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// The user's "Go Get the Thing!" world (see USER_STORIES.md), built with nothing but tool calls,
// saved, and then read back the way a game would: through anvil_runtime.
@(test)
test_a_game_world_built_only_by_tools_is_ready_for_a_game :: proc(t: ^testing.T) {
	dir := temp_dir("smoke")
	s := new_server(dir)
	defer free_server(s)
	good(t, s, "world_new", "{}")
	good(t, s, "tile_size_set", `{"width":4,"height":4}`)
	good(t, s, "palette_set", `{"colors":["#000000","#2B6B3A","#8A8A8A","#3355FF","#FFD400"]}`)
	good(t, s, "tileset_new", `{"name":"room"}`)
	for pair in ([][2]string{{"floor", "1111,1111,1111,1111"}, {"wall", "2222,2222,2222,2222"}, {"hero", "0330,3333,3333,0330"}, {"gem", "0440,4444,4444,0440"}}) {
		good(t, s, "image_new", fmt.tprintf(`{{"tileset":"room","name":"%s"}}`, pair[0]))
		rows, _ := strings.split(pair[1], ",", context.temp_allocator)
		good(t, s, "image_set", fmt.tprintf(`{{"tileset":"room","name":"%s","rows":["%s"]}}`, pair[0], strings.join(rows, `","`, context.temp_allocator)))
	}
	good(t, s, "terrain_set_new", `{"name":"room"}`)
	good(t, s, "terrain_edit", `{"set":"room","name":"terrain","new_name":"floor","tileset":"room","image":"floor"}`)
	good(t, s, "terrain_new", `{"set":"room","name":"wall","tileset":"room","image":"wall","tags":["solid"]}`)
	good(t, s, "tag_new", `{"name":"thing"}`)
	good(t, s, "tag_new", `{"name":"spawn"}`)
	good(t, s, "param_set", `{"name":"round_seconds","number":60}`)
	good(t, s, "param_set", `{"name":"points_per_thing","number":10}`)
	good(t, s, "sprite_set_new", `{"name":"actors"}`)
	good(t, s, "sprite_new", `{"set":"actors","name":"hero","tileset":"room","image":"hero","transparent":0}`)
	good(t, s, "sprite_new", `{"set":"actors","name":"gem","tileset":"room","image":"gem","transparent":0}`)
	good(t, s, "char_type_new", `{"name":"player","sprite_set":"actors","sprite":"hero"}`)
	good(t, s, "char_type_new", `{"name":"thing","sprite_set":"actors","sprite":"gem","tags":["thing"]}`)
	good(t, s, "map_new", `{"name":"room","set":"room","width":8,"height":5}`)
	good(t, s, "map_set_rows", `{"name":"room","rows":["11111111","10000001","10011001","10000001","11111111"]}`)
	good(t, s, "map_cell_tags", `{"name":"room","x":5,"y":1,"tags_set":["spawn"]}`)
	good(t, s, "map_cell_tags", `{"name":"room","x":1,"y":3,"tags_set":["spawn"]}`)
	hero := id_of(t, good(t, s, "character_new", `{"name":"you","type":"player"}`))
	gem := id_of(t, good(t, s, "character_new", `{"name":"gem","type":"thing"}`))
	good(t, s, "character_place", fmt.tprintf(`{{"id":"%s","map":"room","x":1,"y":1}}`, hero))
	good(t, s, "character_place", fmt.tprintf(`{{"id":"%s","map":"room","x":5,"y":1}}`, gem))
	good(t, s, "player_set", fmt.tprintf(`{{"id":"%s"}}`, hero))
	// A trap on the way: walking onto it sets it off, and it never blocks.
	good(t, s, "trigger_type_new", `{"name":"trap","tags":["spawn"]}`)
	good(t, s, "trigger_type_prop_set", `{"type":"trap","name":"damage","value":5}`)
	trap := id_of(t, good(t, s, "trigger_new", `{"name":"spikes","type":"trap","props":{"damage":7}}`))
	good(t, s, "trigger_place", fmt.tprintf(`{{"id":"%s","map":"room","x":3,"y":1}}`, trap))

	// The game's needs are met, and the layout can be walked.
	text := good(t, s, "world_check_game_tags", `{"text":"{\"tags\":[\"thing\",\"spawn\"]}"}`)
	testing.expect(t, strings.contains(text, `"missing":[]`), text)
	text = good(t, s, "play_walk", `{"moves":"rrrr"}`) // the fourth step meets the thing
	testing.expect(t, strings.contains(text, `"end":{"x":4,"y":1}`) && strings.contains(text, `"occupied"]`), text)
	testing.expect(t, strings.contains(text, `"triggered":[{"step":1,"trigger":"spikes"`) && strings.contains(text, `"kind":"entered"`), text)
	_, img := call_picture(t, s, "render_map", `{"name":"room","zoom":8}`)
	testing.expect(t, img != nil && img.width == 8 * 4 * 8 && img.height == 5 * 4 * 8)
	good(t, s, "world_save", `{"path":"world.json"}`)

	// Read it back as a game would.
	data, err := os.read_entire_file(fmt.tprintf("%s/world.json", dir), context.temp_allocator)
	testing.expect(t, err == nil)
	w := rt.new_world()
	defer free(w)
	testing.expect_value(t, rt.load(w, data), "")
	g := new(cm.Game_Tags, context.temp_allocator)
	testing.expect_value(t, rt.parse_game_tags(transmute([]u8)string(`{"tags":[{"name":"thing"},{"name":"spawn"}]}`), g), "")
	testing.expect_value(t, len(rt.required_missing(w, g)), 0)
	testing.expect_value(t, rt.param_number(w, "round_seconds", 0), 60)
	testing.expect_value(t, rt.param_number(w, "points_per_thing", 0), 10)
	mi, found := rt.find_map(w, "room")
	testing.expect(t, found)
	spawn, _ := rt.find_tag(w, "spawn")
	testing.expect_value(t, len(rt.cells_with_tag(w, mi, spawn)), 2)
	testing.expect_value(t, rt.trigger_count(w), 1)
	tmi, tx, ty, placed := rt.authored_trigger_cell(w, 0)
	testing.expect(t, placed && tmi == mi && tx == 3 && ty == 1)
	damage, has_damage := rt.trigger_prop_index(w, 0, "damage")
	testing.expect(t, has_damage && damage == 0)
	testing.expect_value(t, rt.trigger_prop_default(w, 0, damage), 5)
	testing.expect_value(t, rt.trigger_value(w, 0, damage), 7)
	ci, has_player := rt.player(w)
	testing.expect(t, has_player && rt.character_has_tag(w, ci, 0) == false)
	testing.expect(t, rt.cell_is_solid(w, mi, 0, 0) && !rt.cell_is_solid(w, mi, 1, 1) && rt.cell_is_solid(w, mi, 3, 2))
}

@(test)
test_the_tool_reference_file_is_up_to_date :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	data, err := os.read_entire_file("MCP_TOOLS.md", context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, string(data) == tool_reference_markdown(), "MCP_TOOLS.md is stale: run ./build.sh mcp && build/anvil_mcp --tools > MCP_TOOLS.md")
}
