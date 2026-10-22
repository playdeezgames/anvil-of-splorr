#+build !js
package mcp_server

import "core:strings"
import "core:testing"

@(test)
test_features_are_made_placed_and_block_the_walk :: proc(t: ^testing.T) {
	dir := temp_dir("features")
	s := new_server(dir)
	defer free_server(s)
	base_world(t, s)
	good(t, s, "map_new", `{"name":"room","set":"outdoors","width":5,"height":3}`)
	good(t, s, "tag_new", `{"name":"door"}`)
	good(t, s, "char_type_new", `{"name":"player","sprite_set":"people","sprite":"hero"}`)
	hero := id_of(t, good(t, s, "character_new", `{"name":"me","type":"player"}`))
	good(t, s, "player_set", strings.concatenate({`{"id":"`, hero, `"}`}, context.temp_allocator))
	good(t, s, "character_place", strings.concatenate({`{"id":"`, hero, `","map":"room","x":1,"y":1}`}, context.temp_allocator))
	// Types.
	refused(t, s, "feature_type_new", `{"name":"x","sprite_set":"people","sprite":"nope"}`)
	refused(t, s, "feature_type_new", `{"name":"x","tags":["nope"]}`)
	good(t, s, "feature_type_new", `{"name":"gate","sprite_set":"people","sprite":"hero","tags":["door"]}`)
	refused(t, s, "feature_type_new", `{"name":"gate"}`)
	text := good(t, s, "feature_type_list", "{}")
	testing.expect(t, strings.contains(text, `"name":"gate"`) && strings.contains(text, `"tags":["door"]`), text)
	// Features.
	refused(t, s, "feature_new", `{"name":"g","type":"nope"}`)
	gate := id_of(t, good(t, s, "feature_new", `{"name":"North gate","type":"gate"}`))
	testing.expect_value(t, len(gate), 36)
	quoted :: proc(id: string, rest: string) -> string {
		return strings.concatenate({`{"id":"`, id, `",`, rest, `}`}, context.temp_allocator)
	}
	refused(t, s, "feature_place", quoted(gate, `"map":"room","x":9,"y":1`))
	refused(t, s, "feature_place", quoted(gate, `"map":"room","x":1,"y":1`)) // the hero stands there
	good(t, s, "feature_place", quoted(gate, `"map":"room","x":2,"y":1`))
	other := id_of(t, good(t, s, "feature_new", `{"name":"Oak","type":"gate"}`))
	refused(t, s, "feature_place", quoted(other, `"map":"room","x":2,"y":1`)) // taken
	refused(t, s, "character_place", quoted(hero, `"map":"room","x":2,"y":1`)) // a feature blocks
	// The window, the list and the render know about it.
	text = good(t, s, "map_get", `{"name":"room"}`)
	testing.expect(t, strings.contains(text, `"features":[{"id":"`) && strings.contains(text, `"name":"North gate"`), text)
	text = good(t, s, "feature_list", `{"map":"room"}`)
	testing.expect(t, strings.contains(text, `"x":2,"y":1`) && !strings.contains(text, `"name":"Oak"`), text)
	testing.expect(t, strings.contains(good(t, s, "map_list", "{}"), `"features":1`))
	testing.expect(t, strings.contains(good(t, s, "world_summary", "{}"), `"feature_types":["gate"]`))
	// Walking into it reports "feature".
	text = good(t, s, "play_walk", `{"moves":"rr"}`)
	testing.expect(t, strings.contains(text, `"results":["feature","feature"]`) && strings.contains(text, `"end":{"x":1,"y":1}`), text)
	// Edits, abbreviations, shrinking and deleting.
	good(t, s, "feature_edit", quoted(gate[:8], `"name":"Gate","tags_set":["solid"]`))
	refused(t, s, "feature_edit", quoted(gate, `"type":"nope"`))
	refused(t, s, "map_resize", `{"name":"room","width":2,"height":3}`) // would cut it off
	refused(t, s, "feature_type_delete", `{"name":"gate"}`)
	good(t, s, "feature_unplace", quoted(gate, ""))
	good(t, s, "map_resize", `{"name":"room","width":2,"height":3}`)
	text = good(t, s, "play_walk", `{"moves":"d"}`)
	testing.expect(t, strings.contains(text, `"results":["moved"]`), text)
	good(t, s, "feature_place", quoted(gate, `"map":"room","x":0,"y":0`))
	// It all survives a save and open.
	good(t, s, "world_save", `{"path":"f.json"}`)
	s2 := new_server(dir)
	defer free_server(s2)
	good(t, s2, "world_open", `{"path":"f.json"}`)
	text = good(t, s2, "feature_list", "{}")
	testing.expect(t, strings.contains(text, `"name":"Gate"`) && strings.contains(text, `"tags_set":["solid"]`) && strings.contains(text, `"x":0,"y":0`), text)
	good(t, s2, "feature_delete", quoted(gate, ""))
	good(t, s2, "feature_delete", quoted(other, ""))
	good(t, s2, "feature_type_edit", `{"name":"gate","new_name":"door","tags":[]}`)
	good(t, s2, "feature_type_delete", `{"name":"door"}`)
	testing.expect(t, strings.contains(good(t, s2, "feature_list", "{}"), `"features":[]`))
}
