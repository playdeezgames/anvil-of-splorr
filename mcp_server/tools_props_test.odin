#+build !js
package mcp_server

import "core:strings"
import "core:testing"

@(test)
test_character_and_feature_properties_through_tools :: proc(t: ^testing.T) {
	dir := temp_dir("props")
	s := new_server(dir)
	defer free_server(s)
	base_world(t, s)
	good(t, s, "map_new", `{"name":"room","set":"outdoors","width":5,"height":3}`)
	good(t, s, "char_type_new", `{"name":"player","sprite_set":"people","sprite":"hero"}`)
	good(t, s, "char_type_new", `{"name":"slime","sprite_set":"people","sprite":"hero"}`)
	// Character type properties.
	refused(t, s, "char_type_prop_set", `{"type":"nope","name":"health"}`)
	good(t, s, "char_type_prop_set", `{"type":"player","name":"health","value":10}`)
	good(t, s, "char_type_prop_set", `{"type":"player","name":"speed","value":3}`)
	good(t, s, "char_type_prop_set", `{"type":"player","name":"health","value":12}`) // changes the default
	refused(t, s, "char_type_prop_set", `{"type":"player","name":"mana","new_name":"x"}`) // nothing to rename
	refused(t, s, "char_type_prop_set", `{"type":"player","name":"speed","new_name":"health"}`) // taken
	refused(t, s, "char_type_prop_set", `{"type":"player","name":"mana","value":1.5}`)
	text := good(t, s, "char_type_list", "{}")
	testing.expect(t, strings.contains(text, `"props":[{"name":"health","value":12},{"name":"speed","value":3}]`), text)
	testing.expect(t, strings.contains(text, `"name":"slime"`) && strings.contains(text, `"props":[]`), text)
	// Characters: values at creation, in the list, by edit; refusals change nothing.
	refused(t, s, "character_new", `{"name":"me","type":"player","props":{"mana":1}}`)
	refused(t, s, "character_new", `{"name":"me","type":"player","props":{"health":"lots"}}`)
	refused(t, s, "character_new", `{"name":"me","type":"player","props":[1]}`)
	testing.expect(t, strings.contains(good(t, s, "character_list", "{}"), `"characters":[]`))
	hero := id_of(t, good(t, s, "character_new", `{"name":"me","type":"player","props":{"health":7}}`))
	other := id_of(t, good(t, s, "character_new", `{"name":"pip","type":"player"}`))
	quoted :: proc(id: string, rest: string) -> string {
		return strings.concatenate({`{"id":"`, id, `",`, rest, `}`}, context.temp_allocator)
	}
	text = good(t, s, "character_list", "{}")
	testing.expect(t, strings.contains(text, `"props":{"health":7,"speed":3}`) && strings.contains(text, `"props":{"health":12,"speed":3}`), text)
	good(t, s, "character_edit", quoted(hero, `"props":{"speed":9,"health":12}`))
	text = good(t, s, "character_list", "{}")
	testing.expect(t, strings.contains(text, `"props":{"health":12,"speed":9}`), text)
	refused(t, s, "character_edit", quoted(hero, `"props":{"mana":1}`))
	// A new type forgets the values; props in the same call use the new type.
	good(t, s, "char_type_prop_set", `{"type":"slime","name":"goo","value":5}`)
	good(t, s, "character_edit", quoted(hero, `"type":"slime","props":{"goo":8}`))
	text = good(t, s, "character_list", "{}")
	testing.expect(t, strings.contains(text, `"type":"slime"`) && strings.contains(text, `"props":{"goo":8}`), text)
	refused(t, s, "character_edit", quoted(hero, `"type":"player","props":{"goo":1}`)) // goo is the old type's
	// Deleting a property shifts the values.
	good(t, s, "character_edit", quoted(other, `"props":{"speed":4}`))
	refused(t, s, "char_type_prop_delete", `{"type":"player","name":"mana"}`)
	good(t, s, "char_type_prop_delete", `{"type":"player","name":"health"}`)
	text = good(t, s, "character_list", "{}")
	testing.expect(t, strings.contains(text, `"props":{"speed":4}`), text)
	// Features.
	good(t, s, "feature_type_new", `{"name":"gate","sprite_set":"people","sprite":"hero"}`)
	good(t, s, "feature_type_prop_set", `{"type":"gate","name":"locked","value":1}`)
	refused(t, s, "feature_type_prop_set", `{"type":"nope","name":"locked"}`)
	refused(t, s, "feature_new", `{"name":"g","type":"gate","props":{"open":1}}`)
	gate := id_of(t, good(t, s, "feature_new", `{"name":"North gate","type":"gate","props":{"locked":0}}`))
	text = good(t, s, "feature_list", "{}")
	testing.expect(t, strings.contains(text, `"props":{"locked":0}`), text)
	testing.expect(t, strings.contains(good(t, s, "feature_type_list", "{}"), `"props":[{"name":"locked","value":1}]`))
	good(t, s, "feature_edit", quoted(gate, `"props":{"locked":1}`))
	testing.expect(t, strings.contains(good(t, s, "feature_list", "{}"), `"props":{"locked":1}`))
	refused(t, s, "feature_edit", quoted(gate, `"props":{"locked":1.5}`))
	// Everything survives a save and open.
	good(t, s, "world_save", `{"path":"p.json"}`)
	s2 := new_server(dir)
	defer free_server(s2)
	good(t, s2, "world_open", `{"path":"p.json"}`)
	text = good(t, s2, "character_list", "{}")
	testing.expect(t, strings.contains(text, `"props":{"speed":4}`) && strings.contains(text, `"props":{"goo":8}`), text)
	testing.expect(t, strings.contains(good(t, s2, "feature_list", "{}"), `"props":{"locked":1}`))
	good(t, s2, "feature_type_prop_delete", `{"type":"gate","name":"locked"}`)
	refused(t, s2, "feature_type_prop_delete", `{"type":"gate","name":"locked"}`)
	testing.expect(t, !strings.contains(good(t, s2, "feature_list", "{}"), `"props"`))
}
