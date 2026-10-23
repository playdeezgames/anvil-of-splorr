#+build !js
package mcp_server

import "core:strings"
import "core:testing"

@(test)
test_item_types_inventories_and_entries_through_tools :: proc(t: ^testing.T) {
	dir := temp_dir("items")
	s := new_server(dir)
	defer free_server(s)
	base_world(t, s)
	good(t, s, "map_new", `{"name":"room","set":"outdoors","width":5,"height":3}`)
	good(t, s, "tag_new", `{"name":"weapon"}`)
	good(t, s, "char_type_new", `{"name":"player","sprite_set":"people","sprite":"hero"}`)
	hero := id_of(t, good(t, s, "character_new", `{"name":"me","type":"player"}`))
	good(t, s, "player_set", strings.concatenate({`{"id":"`, hero, `"}`}, context.temp_allocator))
	good(t, s, "character_place", strings.concatenate({`{"id":"`, hero, `","map":"room","x":1,"y":1}`}, context.temp_allocator))
	// Item types and their properties.
	refused(t, s, "item_type_new", `{"name":"x","sprite_set":"people","sprite":"nope"}`)
	refused(t, s, "item_type_new", `{"name":"x","tags":["nope"]}`)
	refused(t, s, "item_type_new", `{"name":"x","max_stack":0}`)
	good(t, s, "item_type_new", `{"name":"sword","sprite_set":"people","sprite":"hero","tags":["weapon"]}`)
	good(t, s, "image_new", `{"tileset":"ground","name":"coin"}`)
	good(t, s, "image_set", `{"tileset":"ground","name":"coin","rows":["5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555","5555555555555555"]}`)
	good(t, s, "sprite_new", `{"set":"people","name":"coin","tileset":"ground","image":"coin"}`)
	good(t, s, "item_type_new", `{"name":"gold","max_stack":100,"sprite_set":"people","sprite":"coin"}`)
	refused(t, s, "item_type_new", `{"name":"gold"}`)
	good(t, s, "item_prop_set", `{"type":"sword","name":"damage","value":5}`)
	good(t, s, "item_prop_set", `{"type":"sword","name":"durability","value":100}`)
	good(t, s, "item_prop_set", `{"type":"sword","name":"damage","value":6}`) // changes the default
	refused(t, s, "item_prop_set", `{"type":"sword","name":"new","new_name":"damage"}`) // nothing to rename
	refused(t, s, "item_prop_set", `{"type":"sword","name":"damage","new_name":"durability"}`) // taken
	refused(t, s, "item_prop_set", `{"type":"nope","name":"damage"}`)
	text := good(t, s, "item_type_list", "{}")
	testing.expect(t, strings.contains(text, `"name":"sword","sprite_set":"people","sprite":"hero","max_stack":1,"tags":["weapon"],"props":[{"name":"damage","value":6},{"name":"durability","value":100}]`), text)
	testing.expect(t, strings.contains(text, `"name":"gold"`) && strings.contains(text, `"max_stack":100`), text)
	// Owners: exactly one of character, feature, cell.
	refused(t, s, "inventory_add", `{"type":"gold"}`)
	refused(t, s, "inventory_add", `{"type":"gold","map":"room","x":0,"y":0,"character":"abcd1234"}`)
	refused(t, s, "inventory_add", `{"type":"gold","map":"room","x":9,"y":0}`)
	refused(t, s, "inventory_add", `{"type":"gold","map":"room"}`)
	refused(t, s, "inventory_add", `{"type":"nope","map":"room","x":0,"y":0}`)
	refused(t, s, "inventory_add", `{"type":"gold","count":0,"map":"room","x":0,"y":0}`)
	refused(t, s, "inventory_add", `{"type":"sword","props":{"colour":1},"map":"room","x":0,"y":0}`)
	refused(t, s, "inventory_add", `{"type":"sword","props":{"damage":1.5},"map":"room","x":0,"y":0}`)
	testing.expect(t, strings.contains(good(t, s, "inventory_list", "{}"), `"inventories":[]`)) // refusals left nothing behind
	// Adding.
	carrier := strings.concatenate({`"character":"`, hero, `"`}, context.temp_allocator)
	with :: proc(owner, rest: string) -> string {
		return strings.concatenate({"{", owner, ",", rest, "}"}, context.temp_allocator)
	}
	good(t, s, "inventory_add", with(carrier, `"type":"sword","props":{"durability":40}`))
	text = good(t, s, "inventory_add", with(carrier, `"type":"gold","count":250`))
	text = good(t, s, "inventory_get", strings.concatenate({"{", carrier, "}"}, context.temp_allocator))
	testing.expect(t, strings.contains(text, `{"entry":0,"type":"sword","count":1,"props":{"damage":6,"durability":40}}`), text)
	testing.expect(t, strings.contains(text, `{"entry":3,"type":"gold","count":50,"props":{}}`), text)
	testing.expect(t, strings.contains(text, `"owner":{"kind":"character"`), text)
	good(t, s, "inventory_add", `{"type":"gold","count":7,"map":"room","x":2,"y":1}`)
	// The window, the list, the summary and the walk know about the cell.
	text = good(t, s, "map_get", `{"name":"room"}`)
	testing.expect(t, strings.contains(text, `"inventories":[{"x":2,"y":1,"entries":[{"entry":0,"type":"gold","count":7`), text)
	testing.expect(t, strings.contains(good(t, s, "map_list", "{}"), `"inventories":1`))
	text = good(t, s, "world_summary", "{}")
	testing.expect(t, strings.contains(text, `"item_types":["sword","gold"]`) && strings.contains(text, `"inventories":2`), text)
	text = good(t, s, "inventory_list", `{"map":"room"}`)
	testing.expect(t, strings.contains(text, `"kind":"cell"`) && !strings.contains(text, `"kind":"character"`), text)
	text = good(t, s, "play_walk", `{"moves":"rr"}`)
	testing.expect(t, strings.contains(text, `"results":["moved","moved"]`) && strings.contains(text, `"items_at":[{"step":0,"x":2,"y":1}]`), text)
	_, with_items := call_picture(t, s, "render_map", `{"name":"room","zoom":2}`)
	_, without_items := call_picture(t, s, "render_map", `{"name":"room","zoom":2,"items":false}`)
	if with_items != nil && without_items != nil {
		cw, ch := with_items.width / 5, with_items.height / 3
		differs := false
		for py in ch ..< 2 * ch {
			for px in 2 * cw ..< 3 * cw {
				differs ||= pixel(with_items, px, py) != pixel(without_items, px, py)
			}
		}
		testing.expect(t, differs, "the item shows in its cell")
		testing.expect_value(t, pixel(with_items, 0, 0), pixel(without_items, 0, 0)) // and only there
	}
	// Editing an entry.
	refused(t, s, "inventory_set", with(carrier, `"entry":9,"count":1`))
	refused(t, s, "inventory_set", with(carrier, `"entry":0,"count":2`)) // swords never stack
	refused(t, s, "inventory_set", with(carrier, `"entry":0`))
	good(t, s, "inventory_set", with(carrier, `"entry":0,"props":{"durability":10,"damage":6}`))
	text = good(t, s, "inventory_get", strings.concatenate({"{", carrier, "}"}, context.temp_allocator))
	testing.expect(t, strings.contains(text, `"props":{"damage":6,"durability":10}`), text)
	good(t, s, "inventory_set", with(carrier, `"entry":3,"count":60`))
	// Max stack and deleting.
	refused(t, s, "item_type_edit", `{"name":"gold","max_stack":10}`)
	refused(t, s, "item_type_delete", `{"name":"gold"}`)
	refused(t, s, "inventory_remove", with(carrier, `"entry":9`))
	text = good(t, s, "inventory_remove", with(carrier, `"entry":3,"count":100`))
	testing.expect(t, strings.contains(text, "took 60"), text)
	good(t, s, "inventory_remove", with(carrier, `"entry":1`))
	good(t, s, "inventory_remove", with(carrier, `"entry":1`))
	refused(t, s, "map_resize", `{"name":"room","width":2,"height":3}`) // the cell inventory at x=2 would be cut off
	good(t, s, "inventory_clear", `{"map":"room","x":2,"y":1}`)
	good(t, s, "map_resize", `{"name":"room","width":2,"height":3}`)
	testing.expect(t, strings.contains(good(t, s, "inventory_clear", `{"map":"room","x":0,"y":0}`), "no inventory"))
	// Survives a save and open; deleting the carrier takes the inventory.
	good(t, s, "world_save", `{"path":"i.json"}`)
	s2 := new_server(dir)
	defer free_server(s2)
	good(t, s2, "world_open", `{"path":"i.json"}`)
	text = good(t, s2, "inventory_get", strings.concatenate({"{", carrier, "}"}, context.temp_allocator))
	testing.expect(t, strings.contains(text, `"type":"sword"`) && strings.contains(text, `"durability":10`), text)
	good(t, s2, "item_prop_delete", `{"type":"sword","name":"durability"}`)
	refused(t, s2, "item_prop_delete", `{"type":"sword","name":"durability"}`)
	good(t, s2, "character_delete", strings.concatenate({`{"id":"`, hero, `"}`}, context.temp_allocator))
	testing.expect(t, strings.contains(good(t, s2, "inventory_list", "{}"), `"inventories":[]`))
	good(t, s2, "item_type_edit", `{"name":"sword","new_name":"blade","max_stack":1,"tags":[]}`)
	good(t, s2, "item_type_delete", `{"name":"blade"}`)
	good(t, s2, "item_type_delete", `{"name":"gold"}`)
}
