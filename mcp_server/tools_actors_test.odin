#+build !js
package mcp_server

import "core:encoding/json"
import "core:strings"
import "core:testing"

// Builds a world with a tileset, an outdoors set (floor, wall[solid]) and a sprite.
base_world :: proc(t: ^testing.T, s: ^Server) {
	good(t, s, "world_new", "{}")
	good(t, s, "tileset_new", `{"name":"ground"}`)
	good(t, s, "image_new", `{"tileset":"ground","name":"a"}`)
	good(t, s, "terrain_set_new", `{"name":"outdoors"}`)
	good(t, s, "terrain_edit", `{"set":"outdoors","name":"terrain","new_name":"floor","tileset":"ground","image":"a"}`)
	good(t, s, "terrain_new", `{"set":"outdoors","name":"wall","tileset":"ground","image":"a","tags":["solid"]}`)
	good(t, s, "sprite_set_new", `{"name":"people"}`)
	good(t, s, "sprite_new", `{"set":"people","name":"hero","tileset":"ground","image":"a"}`)
}

// The id in {"id":"..."}.
id_of :: proc(t: ^testing.T, text: string) -> string {
	v, err := json.parse(transmute([]u8)text, .JSON, false, context.temp_allocator)
	testing.expect_value(t, err, json.Error.None)
	obj, _ := v.(json.Object)
	id, _ := obj["id"].(json.String)
	return string(id)
}

@(test)
test_maps_can_be_drawn_with_every_tool :: proc(t: ^testing.T) {
	s := new_server("")
	defer free_server(s)
	base_world(t, s)
	refused(t, s, "map_new", `{"name":"m","set":"nope"}`)
	refused(t, s, "map_new", `{"name":"m","set":"outdoors","width":65}`)
	good(t, s, "map_new", `{"name":"room","set":"outdoors","width":5,"height":4}`)
	refused(t, s, "map_new", `{"name":"room","set":"outdoors"}`)
	text := good(t, s, "map_get", `{"name":"room"}`)
	testing.expect(t, strings.contains(text, `"rows":["00000","00000","00000","00000"]`) && strings.contains(text, `{"symbol":"1","terrain":"wall"}`))
	good(t, s, "map_fill_rect", `{"name":"room","x":0,"y":0,"width":5,"height":4,"terrain":"wall","frame":true}`)
	text = good(t, s, "map_get", `{"name":"room"}`)
	testing.expect(t, strings.contains(text, `"rows":["11111","10001","10001","11111"]`))
	good(t, s, "map_paint", `{"name":"room","cells":[{"x":2,"y":1,"terrain":"wall"},{"x":2,"y":2,"terrain":"wall"}]}`)
	refused(t, s, "map_paint", `{"name":"room","cells":[{"x":1,"y":1,"terrain":"wall"},{"x":9,"y":1,"terrain":"wall"}]}`)
	refused(t, s, "map_paint", `{"name":"room","cells":[{"x":1,"y":1,"terrain":"nope"}]}`)
	good(t, s, "map_set_rows", `{"name":"room","x":3,"y":1,"rows":["1","1"]}`)
	refused(t, s, "map_set_rows", `{"name":"room","rows":["0000000"]}`)
	refused(t, s, "map_set_rows", `{"name":"room","rows":["0Z000"]}`) // Z is no terrain
	text = good(t, s, "map_get", `{"name":"room","x":1,"y":1,"width":4,"height":2}`)
	testing.expect(t, strings.contains(text, `"rows":["0111","0111"]`)) // the refused ones changed nothing
	good(t, s, "map_flood_fill", `{"name":"room","x":1,"y":1,"terrain":"wall"}`)
	good(t, s, "map_replace_terrain", `{"name":"room","from":"wall","to":"floor"}`)
	text = good(t, s, "map_get", `{"name":"room"}`)
	testing.expect(t, strings.contains(text, `"rows":["00000","00000","00000","00000"]`))
	// Per-cell tags: set solid on one floor cell.
	text = good(t, s, "map_cell_tags", `{"name":"room","x":1,"y":1,"tags_set":["solid"]}`)
	testing.expect(t, strings.contains(text, `"effective":["solid"]`))
	refused(t, s, "map_cell_tags", `{"name":"room","x":1,"y":1,"tags_set":["solid"],"tags_cleared":["solid"]}`)
	refused(t, s, "map_cell_tags", `{"name":"room","x":1,"y":1,"tags_set":["nope"]}`)
	// Resize and the terrain set.
	good(t, s, "map_resize", `{"name":"room","width":8,"height":3}`)
	testing.expect(t, strings.contains(good(t, s, "map_list", "{}"), `"width":8,"height":3`))
	refused(t, s, "map_resize", `{"name":"room","width":0,"height":3}`)
	good(t, s, "terrain_set_new", `{"name":"indoors"}`)
	refused(t, s, "map_set_terrain_set", `{"name":"room","set":"indoors"}`) // "floor" is not there
	refused(t, s, "terrain_set_delete", `{"name":"outdoors"}`) // a map uses it
	good(t, s, "map_rename", `{"name":"room","new_name":"hall"}`)
	good(t, s, "map_delete", `{"name":"hall"}`)
	refused(t, s, "map_delete", `{"name":"hall"}`)
	good(t, s, "terrain_set_delete", `{"name":"outdoors"}`)
}

@(test)
test_characters_are_placed_and_walked :: proc(t: ^testing.T) {
	dir := temp_dir("characters")
	s := new_server(dir)
	defer free_server(s)
	base_world(t, s)
	good(t, s, "map_new", `{"name":"room","set":"outdoors","width":5,"height":3}`)
	good(t, s, "map_fill_rect", `{"name":"room","x":0,"y":0,"width":5,"height":3,"terrain":"wall","frame":true}`)
	good(t, s, "tag_new", `{"name":"thing"}`)
	good(t, s, "char_type_new", `{"name":"player","sprite_set":"people","sprite":"hero"}`)
	good(t, s, "char_type_new", `{"name":"prize","sprite_set":"people","sprite":"hero","tags":["thing"]}`)
	refused(t, s, "char_type_new", `{"name":"x","sprite_set":"people","sprite":"nope"}`)
	refused(t, s, "char_type_new", `{"name":"x","tags":["nope"]}`)
	refused(t, s, "character_new", `{"name":"me","type":"nope"}`)
	hero := id_of(t, good(t, s, "character_new", `{"name":"me","type":"player"}`))
	prize := id_of(t, good(t, s, "character_new", `{"name":"gold","type":"prize"}`))
	testing.expect_value(t, len(hero), 36)
	// A walk needs the player to stand on a map.
	refused(t, s, "play_walk", `{"moves":"r"}`)
	text, bad := call(t, s, "player_set", `{"id":"nope"}`)
	testing.expect(t, bad, text)
	good(t, s, "player_set", strings.concatenate({`{"id":"`, hero, `"}`}, context.temp_allocator))
	refused(t, s, "play_walk", `{"moves":"r"}`)
	good(t, s, "character_place", strings.concatenate({`{"id":"`, hero, `","map":"room","x":1,"y":1}`}, context.temp_allocator))
	refused(t, s, "character_place", strings.concatenate({`{"id":"`, prize, `","map":"room","x":1,"y":1}`}, context.temp_allocator)) // taken
	refused(t, s, "character_place", strings.concatenate({`{"id":"`, prize, `","map":"room","x":9,"y":1}`}, context.temp_allocator))
	good(t, s, "character_place", strings.concatenate({`{"id":"`, prize, `","map":"room","x":3,"y":1}`}, context.temp_allocator))
	// Walk right: moves, moves... then the prize blocks, a further step hits the wall.
	text = good(t, s, "play_walk", `{"moves":"rrru"}`)
	testing.expect(t, strings.contains(text, `"results":["moved","occupied","occupied","solid"]`) && strings.contains(text, `"end":{"x":2,"y":1}`) && strings.contains(text, `"blocked":3`), text)
	text = good(t, s, "play_walk", `{"moves":["left","left","down"]}`)
	testing.expect(t, strings.contains(text, `"results":["solid","solid","solid"]`), text)
	refused(t, s, "play_walk", `{"moves":"x"}`)
	// The walk did not move anybody; ids may be abbreviated.
	text = good(t, s, "character_list", `{"map":"room"}`)
	testing.expect(t, strings.contains(text, `"x":1,"y":1`) && strings.contains(text, `"player":true`))
	good(t, s, "character_edit", strings.concatenate({`{"id":"`, hero[:8], `","name":"hero","tags_cleared":["solid"]}`}, context.temp_allocator))
	text = good(t, s, "map_get", `{"name":"room"}`)
	testing.expect(t, strings.contains(text, `"name":"hero"`))
	// A shrink that would cut a character off is refused; a type in use cannot be deleted.
	refused(t, s, "map_resize", `{"name":"room","width":3,"height":3}`)
	refused(t, s, "char_type_delete", `{"name":"prize"}`)
	good(t, s, "character_unplace", strings.concatenate({`{"id":"`, prize, `"}`}, context.temp_allocator))
	good(t, s, "map_resize", `{"name":"room","width":3,"height":3}`)
	good(t, s, "character_delete", strings.concatenate({`{"id":"`, prize, `"}`}, context.temp_allocator))
	good(t, s, "char_type_edit", `{"name":"prize","new_name":"treasure","tags":[]}`)
	good(t, s, "char_type_delete", `{"name":"treasure"}`)
	// It all survives a save and open.
	good(t, s, "world_save", `{"path":"c.json"}`)
	s2 := new_server(dir)
	defer free_server(s2)
	good(t, s2, "world_open", `{"path":"c.json"}`)
	text = good(t, s2, "play_walk", `{"moves":"r"}`)
	testing.expect(t, strings.contains(text, `"results":["moved"]`) && strings.contains(text, `"end":{"x":2,"y":1}`), text)
	good(t, s2, "player_set", "{}")
	refused(t, s2, "play_walk", `{"moves":"r"}`)
}
