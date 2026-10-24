#+build !js
package mcp_server

import "core:strings"
import "core:testing"

@(test)
test_triggers_are_made_placed_attached_and_heard_in_a_walk :: proc(t: ^testing.T) {
	dir := temp_dir("triggers")
	s := new_server(dir)
	defer free_server(s)
	base_world(t, s)
	good(t, s, "map_new", `{"name":"room","set":"outdoors","width":5,"height":3}`)
	good(t, s, "tag_new", `{"name":"trap"}`)
	good(t, s, "char_type_new", `{"name":"player","sprite_set":"people","sprite":"hero"}`)
	hero := id_of(t, good(t, s, "character_new", `{"name":"me","type":"player"}`))
	good(t, s, "player_set", strings.concatenate({`{"id":"`, hero, `"}`}, context.temp_allocator))
	good(t, s, "character_place", strings.concatenate({`{"id":"`, hero, `","map":"room","x":0,"y":1}`}, context.temp_allocator))
	good(t, s, "feature_type_new", `{"name":"door","sprite_set":"people","sprite":"hero"}`)
	door := id_of(t, good(t, s, "feature_new", `{"name":"Door","type":"door"}`))
	quoted :: proc(id: string, rest: string) -> string {
		return strings.concatenate({`{"id":"`, id, `",`, rest, `}`}, context.temp_allocator)
	}
	good(t, s, "feature_place", quoted(door, `"map":"room","x":3,"y":1`))
	// Types and their properties.
	refused(t, s, "trigger_type_new", `{"name":"x","sprite_set":"people","sprite":"nope"}`)
	refused(t, s, "trigger_type_new", `{"name":"x","tags":["nope"]}`)
	good(t, s, "trigger_type_new", `{"name":"spikes","sprite_set":"people","sprite":"hero","tags":["trap"]}`)
	good(t, s, "trigger_type_new", `{"name":"lock"}`)
	refused(t, s, "trigger_type_new", `{"name":"lock"}`)
	good(t, s, "trigger_type_prop_set", `{"type":"spikes","name":"damage","value":5}`)
	refused(t, s, "trigger_type_prop_set", `{"type":"nope","name":"damage"}`)
	text := good(t, s, "trigger_type_list", "{}")
	testing.expect(t, strings.contains(text, `"name":"spikes","sprite_set":"people","sprite":"hero","tags":["trap"],"props":[{"name":"damage","value":5}]`), text)
	// Triggers.
	refused(t, s, "trigger_new", `{"name":"t","type":"nope"}`)
	refused(t, s, "trigger_new", `{"name":"t","type":"spikes","props":{"mana":1}}`)
	trap := id_of(t, good(t, s, "trigger_new", `{"name":"Hall trap","type":"spikes","props":{"damage":8}}`))
	testing.expect_value(t, len(trap), 36)
	other := id_of(t, good(t, s, "trigger_new", `{"name":"Second","type":"spikes"}`))
	latch := id_of(t, good(t, s, "trigger_new", `{"name":"Latch","type":"lock"}`))
	good(t, s, "trigger_place", quoted(trap, `"map":"room","x":1,"y":1`))
	good(t, s, "trigger_place", quoted(other, `"map":"room","x":1,"y":1`)) // two in one cell
	refused(t, s, "trigger_place", quoted(trap, `"map":"room","x":9,"y":1`))
	refused(t, s, "trigger_place", quoted(trap, `"map":"nope","x":1,"y":1`))
	good(t, s, "trigger_attach", quoted(latch, strings.concatenate({`"feature":"`, door, `"`}, context.temp_allocator)))
	refused(t, s, "trigger_attach", quoted(latch, `"feature":"ffffffff-ffff-4fff-bfff-ffffffffffff"`))
	text = good(t, s, "trigger_list", "{}")
	testing.expect(t, strings.contains(text, `"name":"Hall trap","type":"spikes","map":"room","x":1,"y":1`) && strings.contains(text, `"props":{"damage":8}`), text)
	testing.expect(t, strings.contains(text, `"feature":{"id":"`) && strings.contains(text, `"name":"Door"}`), text)
	text = good(t, s, "trigger_list", `{"map":"room"}`)
	testing.expect(t, !strings.contains(text, `"name":"Latch"`) && strings.contains(text, `"name":"Second"`), text)
	text = good(t, s, "trigger_list", strings.concatenate({`{"feature":"`, door, `"}`}, context.temp_allocator))
	testing.expect(t, strings.contains(text, `"name":"Latch"`) && !strings.contains(text, `"name":"Second"`), text)
	// The window, the list, the summary and the picture know about them.
	text = good(t, s, "map_get", `{"name":"room"}`)
	testing.expect(t, strings.contains(text, `"triggers":[{"id":"`) && strings.contains(text, `"name":"Hall trap"`), text)
	testing.expect(t, strings.contains(good(t, s, "map_list", "{}"), `"triggers":2`))
	text = good(t, s, "world_summary", "{}")
	testing.expect(t, strings.contains(text, `"trigger_types":["spikes","lock"]`) && strings.contains(text, `"triggers":3`), text)
	call_picture(t, s, "render_map", `{"name":"room","zoom":2}`)
	call_picture(t, s, "render_map", `{"name":"room","zoom":2,"triggers":false}`)
	// A walk: right onto the traps, on to the door (refused), where the latch hears the bump.
	text = good(t, s, "play_walk", `{"moves":"rrr"}`)
	testing.expect(t, strings.contains(text, `"results":["moved","moved","feature"]`), text)
	testing.expect(t, strings.contains(text, `"trigger":"Hall trap","id":"`) && strings.contains(text, `"kind":"entered","reason":"","x":1,"y":1}`), text)
	testing.expect(t, strings.contains(text, `"trigger":"Latch"`) && strings.contains(text, `"kind":"bumped","reason":"feature","x":3,"y":1}`), text)
	testing.expect(t, strings.contains(text, `"step":0`) && strings.contains(text, `"step":2`), text)
	// Edits: values, type change forgets them, tags, unplacing.
	good(t, s, "trigger_edit", quoted(trap, `"name":"Hall spikes","props":{"damage":9},"tags_set":["trap"]`))
	refused(t, s, "trigger_edit", quoted(trap, `"props":{"mana":1}`))
	refused(t, s, "trigger_edit", quoted(trap, `"type":"nope"`))
	good(t, s, "trigger_edit", quoted(trap, `"type":"lock"`))
	testing.expect(t, !strings.contains(good(t, s, "trigger_list", `{"map":"room"}`), `"damage":9`))
	good(t, s, "trigger_unplace", quoted(other, ""))
	testing.expect(t, strings.contains(good(t, s, "trigger_unplace", quoted(other, "")), "no place"))
	refused(t, s, "trigger_type_delete", `{"name":"spikes"}`)
	refused(t, s, "map_resize", `{"name":"room","width":1,"height":3}`) // the trigger at x=1 would be cut off
	// Saving, opening, deleting.
	good(t, s, "world_save", `{"path":"t.json"}`)
	s2 := new_server(dir)
	defer free_server(s2)
	good(t, s2, "world_open", `{"path":"t.json"}`)
	text = good(t, s2, "trigger_list", "{}")
	testing.expect(t, strings.contains(text, `"name":"Hall spikes"`) && strings.contains(text, `"name":"Latch"`) && strings.contains(text, `"feature":{"id":"`), text)
	good(t, s2, "feature_delete", quoted(door, "")) // the latch stays, on nothing
	text = good(t, s2, "trigger_list", `{}`)
	testing.expect(t, strings.contains(text, `"name":"Latch"`) && !strings.contains(text, `"feature":{`), text)
	good(t, s2, "trigger_delete", quoted(latch, ""))
	good(t, s2, "trigger_delete", quoted(trap, ""))
	good(t, s2, "trigger_delete", quoted(other, ""))
	good(t, s2, "trigger_type_edit", `{"name":"spikes","new_name":"thorns","tags":[]}`)
	good(t, s2, "trigger_type_prop_delete", `{"type":"thorns","name":"damage"}`)
	good(t, s2, "trigger_type_delete", `{"name":"thorns"}`)
	good(t, s2, "trigger_type_delete", `{"name":"lock"}`)
	testing.expect(t, strings.contains(good(t, s2, "trigger_list", "{}"), `"triggers":[]`))
}
