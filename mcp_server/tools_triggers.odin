package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Triggers (design in coxswain task #64 of project `anvil`): things in a map cell, or on a feature,
// that never block and that a game hears about when a character enters the cell or is refused entry.
// The tools mirror the feature ones; a trigger's id is a uuid (an 8-digit prefix works if unique).

trigger_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{"trigger_type_list", "List the trigger types: name, sprite, tags and numeric properties with their defaults.", `{"type":"object","properties":{}}`, tool_trigger_type_list},
		{
			"trigger_type_new",
			"Add a trigger type (up to 64). sprite_set and sprite name the picture (both or neither); tags lists the tags every trigger of the type has. Add properties with trigger_type_prop_set.",
			`{"type":"object","properties":{"name":{"type":"string"},"sprite_set":{"type":"string"},"sprite":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["name"]}`,
			tool_trigger_type_new,
		},
		{
			"trigger_type_edit",
			"Change a trigger type; only the fields given change. Triggers of the type follow a rename.",
			`{"type":"object","properties":{"name":{"type":"string"},"new_name":{"type":"string"},"sprite_set":{"type":"string"},"sprite":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["name"]}`,
			tool_trigger_type_edit,
		},
		{"trigger_type_delete", "Delete a trigger type unless a trigger has it.", NAME_ARG, tool_trigger_type_delete},
		{
			"trigger_type_prop_set",
			"Give a trigger type a numeric property (up to 16, whole numbers that fit in 32 bits) or change its default value; new_name renames it. Triggers without their own value follow the default.",
			`{"type":"object","properties":{"type":{"type":"string"},"name":{"type":"string"},"value":{"type":"integer"},"new_name":{"type":"string"}},"required":["type","name"]}`,
			tool_trigger_type_prop_set,
		},
		{
			"trigger_type_prop_delete",
			"Remove a property from a trigger type; its triggers lose their value for it.",
			`{"type":"object","properties":{"type":{"type":"string"},"name":{"type":"string"}},"required":["type","name"]}`,
			tool_trigger_type_prop_delete,
		},
		{
			"trigger_list",
			"List triggers (all, or those in cells of map, or those on one feature): id, name, type, where (a cell, or the feature it is on), its own tag settings and its values of its type's properties. A trigger never blocks, any number can share a cell or a feature.",
			`{"type":"object","properties":{"map":{"type":"string"},"feature":{"type":"string"}}}`,
			tool_trigger_list,
		},
		{
			"trigger_new",
			"Add a trigger of a type (up to 2048), in no place. Returns its id. tags_set / tags_cleared are its own tag settings; props is an object of property name (of the type) to its value for this trigger. Put it somewhere with trigger_place or trigger_attach.",
			`{"type":"object","properties":{"name":{"type":"string"},"type":{"type":"string"},"tags_set":{"type":"array","items":{"type":"string"}},"tags_cleared":{"type":"array","items":{"type":"string"}},"props":{"type":"object"}},"required":["name","type"]}`,
			tool_trigger_new,
		},
		{
			"trigger_edit",
			"Change a trigger by id; only the fields given change (name, type, tags_set, tags_cleared, props). A new type makes it forget its property values; props sets values of its (new) type's properties.",
			`{"type":"object","properties":{"id":{"type":"string"},"name":{"type":"string"},"type":{"type":"string"},"tags_set":{"type":"array","items":{"type":"string"}},"tags_cleared":{"type":"array","items":{"type":"string"}},"props":{"type":"object"}},"required":["id"]}`,
			tool_trigger_edit,
		},
		{"trigger_delete", "Delete a trigger.", `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`, tool_trigger_delete},
		{
			"trigger_place",
			"Put a trigger in a map cell (taking it from its cell or feature). Nothing in the cell stops it: triggers, characters, features and items may all be there.",
			`{"type":"object","properties":{"id":{"type":"string"},"map":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"}},"required":["id","map","x","y"]}`,
			tool_trigger_place,
		},
		{
			"trigger_attach",
			"Put a trigger on a feature (taking it from its cell): it has no cell of its own and goes wherever the feature goes. It fires when the feature refuses a step.",
			`{"type":"object","properties":{"id":{"type":"string"},"feature":{"type":"string"}},"required":["id","feature"]}`,
			tool_trigger_attach,
		},
		{"trigger_unplace", "Take a trigger out of its cell or off its feature.", `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`, tool_trigger_unplace},
	}
	return table[:]
}

// --- Finding -----------------------------------------------------------------------------------

find_trigger_type :: proc(s: ^Server, args: json.Object, key := "name") -> (tt: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	i := cm.world_find_trigger_type(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no trigger type named %s", name)), false
	}
	return i, {}, true
}

find_trigger_arg :: proc(s: ^Server, args: json.Object, key := "id") -> (ti: int, res: Tool_Result, ok: bool) {
	text, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	w := s.world
	if u, is_uuid := cm.uuid_from_string(text); is_uuid {
		i := cm.world_find_trigger(w, u)
		if i < 0 {
			return 0, fail(fmt.tprintf("no trigger with id %s", text)), false
		}
		return i, {}, true
	}
	found := -1
	for i in 0 ..< w.trigger_count {
		if len(text) >= 4 && strings.has_prefix(cm.uuid_to_string(w.triggers[i].uuid), strings.to_lower(text, context.temp_allocator)) {
			if found >= 0 {
				return 0, fail(fmt.tprintf("%s matches more than one trigger: use the full id", text)), false
			}
			found = i
		}
	}
	if found < 0 {
		return 0, fail(fmt.tprintf("no trigger with id %s", text)), false
	}
	return found, {}, true
}

// --- Trigger types -----------------------------------------------------------------------------

tool_trigger_type_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"trigger_types":[`)
	for i in 0 ..< w.trigger_type_count {
		tt := &w.trigger_types[i]
		fmt.sbprintf(&b, `%s{{"name":%s,"sprite_set":%s,"sprite":%s,"tags":`, i > 0 ? "," : "", quote(cm.name_str(&tt.name)), quote(cm.name_str(&tt.sprite_set)), quote(cm.name_str(&tt.sprite)))
		write_strings(&b, tag_names_in(w, tt.tags))
		strings.write_string(&b, `,"props":`)
		write_prop_defaults(&b, &tt.props)
		strings.write_string(&b, "}")
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_trigger_type_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	if p := cm.world_check_trigger_type_name(w, -1, name); p != .None {
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
	i := cm.world_add_trigger_type(w, name)
	if i < 0 {
		return fail("the world already has 64 trigger types")
	}
	tt := &w.trigger_types[i]
	if given {
		cm.name_assign(&tt.sprite_set, set)
		cm.name_assign(&tt.sprite, sprite)
	}
	tt.tags = mask
	return changed(s, fmt.tprintf("added trigger type %s", cm.name_str(&tt.name)))
}

tool_trigger_type_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	i, r1, ok1 := find_trigger_type(s, args)
	if !ok1 {
		return r1
	}
	tt := &w.trigger_types[i]
	new_name, has_new := arg_string(args, "new_name")
	if has_new {
		if p := cm.world_check_trigger_type_name(w, i, new_name); p != .None {
			return fail(problem_text(p))
		}
	}
	set, sprite, given := sprite_args(args, cm.name_str(&tt.sprite_set), cm.name_str(&tt.sprite))
	if given {
		if msg := check_sprite_ref(w, set, sprite); msg != "" {
			return fail(msg)
		}
	}
	mask := tt.tags
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
		cm.name_assign(&tt.sprite_set, set)
		cm.name_assign(&tt.sprite, sprite)
	}
	tt.tags = mask
	if has_new {
		cm.world_rename_trigger_type(w, i, new_name)
	}
	return changed(s, "trigger type updated")
}

tool_trigger_type_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, r1, ok1 := find_trigger_type(s, args)
	if !ok1 {
		return r1
	}
	if uses := cm.world_delete_trigger_type(s.world, i); uses > 0 {
		return fail(fmt.tprintf("%d triggers have this type", uses))
	}
	return changed(s, "deleted the trigger type")
}

tool_trigger_type_prop_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	tt, r, ok := find_trigger_type(s, args, "type")
	if !ok {
		return r
	}
	return set_prop_tool(s, args, &s.world.trigger_types[tt].props, "a trigger type")
}

tool_trigger_type_prop_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	tt, r, ok := find_trigger_type(s, args, "type")
	if !ok {
		return r
	}
	name, r2, ok2 := need_string(args, "name")
	if !ok2 {
		return r2
	}
	p := cm.prop_set_find(&s.world.trigger_types[tt].props, name)
	if p < 0 {
		return fail(fmt.tprintf("the trigger type has no property named %s", name))
	}
	cm.world_trigger_type_delete_prop(s.world, tt, p)
	return changed(s, "deleted the property")
}

// --- Triggers ----------------------------------------------------------------------------------

write_trigger :: proc(b: ^strings.Builder, w: ^cm.World, ti: int) {
	t := &w.triggers[ti]
	fmt.sbprintf(b, `{{"id":%s,"name":%s,"type":%s`, quote(cm.uuid_to_string(t.uuid)), quote(cm.name_str(&t.name)), quote(cm.name_str(&t.type)))
	switch t.place {
	case .None:
	case .Cell:
		fmt.sbprintf(b, `,"map":%s,"x":%d,"y":%d`, quote(cm.name_str(&t.map_name)), t.x, t.y)
	case .Feature:
		if fi := cm.world_find_feature(w, t.feature); fi >= 0 {
			fmt.sbprintf(b, `,"feature":{{"id":%s,"name":%s}}`, quote(cm.uuid_to_string(t.feature)), quote(cm.name_str(&w.features[fi].name)))
		}
	}
	strings.write_string(b, `,"tags_set":`)
	write_strings(b, tag_names_in(w, t.tags_set))
	strings.write_string(b, `,"tags_cleared":`)
	write_strings(b, tag_names_in(w, t.tags_cleared))
	if tt := cm.world_find_trigger_type(w, cm.name_str(&t.type)); tt >= 0 && w.trigger_types[tt].props.count > 0 {
		strings.write_string(b, `,"props":`)
		write_prop_values(b, &w.trigger_types[tt].props, &t.overrides)
	}
	strings.write_string(b, "}")
}

tool_trigger_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	only_map, only_feature := -1, -1
	if _, has := arg_string(args, "map"); has {
		mi, r, ok := find_map_arg(s, args, "map")
		if !ok {
			return r
		}
		only_map = mi
	}
	if _, has := arg_string(args, "feature"); has {
		fi, r, ok := find_feature_arg(s, args, "feature")
		if !ok {
			return r
		}
		only_feature = fi
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"triggers":[`)
	first := true
	for ti in 0 ..< w.trigger_count {
		t := &w.triggers[ti]
		if only_map >= 0 && !(t.place == .Cell && cm.name_str(&t.map_name) == cm.name_str(&w.maps[only_map].name)) {
			continue
		}
		if only_feature >= 0 && !(t.place == .Feature && t.feature == w.features[only_feature].uuid) {
			continue
		}
		strings.write_string(&b, first ? "" : ",")
		first = false
		write_trigger(&b, w, ti)
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_trigger_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
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
	tt, r2, ok2 := find_trigger_type(s, args, "type")
	if !ok2 {
		return r2
	}
	set, cleared, r3, ok3 := tag_setting_args(w, args, 0, 0)
	if !ok3 {
		return r3
	}
	values, _, pmsg := parse_props_arg(args, &w.trigger_types[tt].props)
	if pmsg != "" {
		return fail(pmsg)
	}
	ti := cm.world_add_trigger(w, tt, name)
	if ti < 0 {
		return fail("the world already has 2048 triggers")
	}
	w.triggers[ti].tags_set, w.triggers[ti].tags_cleared = set, cleared
	for v in values {
		cm.world_trigger_set_value(w, ti, v.index, v.value)
	}
	return changed(s, fmt.tprintf(`{{"id":%s}}`, quote(cm.uuid_to_string(w.triggers[ti].uuid))))
}

tool_trigger_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	ti, r1, ok1 := find_trigger_arg(s, args)
	if !ok1 {
		return r1
	}
	t := &w.triggers[ti]
	name, has_name := arg_string(args, "name")
	if has_name {
		if p := cm.name_text_problem(name); p != .None {
			return fail(problem_text(p))
		}
	}
	tt := -1
	if _, has := arg_string(args, "type"); has {
		i, r, found := find_trigger_type(s, args, "type")
		if !found {
			return r
		}
		tt = i
	}
	set, cleared, r2, ok2 := tag_setting_args(w, args, t.tags_set, t.tags_cleared)
	if !ok2 {
		return r2
	}
	target_type := tt >= 0 ? tt : cm.world_find_trigger_type(w, cm.name_str(&t.type))
	values: []Prop_Arg
	if target_type >= 0 {
		pmsg: string
		values, _, pmsg = parse_props_arg(args, &w.trigger_types[target_type].props)
		if pmsg != "" {
			return fail(pmsg)
		}
	}
	if has_name {
		cm.world_rename_trigger(w, ti, name)
	}
	if tt >= 0 {
		cm.world_set_trigger_type(w, ti, tt) // (its values belonged to the old type)
	}
	t.tags_set, t.tags_cleared = set, cleared
	for v in values {
		cm.world_trigger_set_value(w, ti, v.index, v.value)
	}
	return changed(s, "trigger updated")
}

tool_trigger_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	ti, r1, ok1 := find_trigger_arg(s, args)
	if !ok1 {
		return r1
	}
	cm.world_delete_trigger(s.world, ti)
	return changed(s, "deleted the trigger")
}

tool_trigger_place :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	ti, r1, ok1 := find_trigger_arg(s, args)
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
	switch cm.world_place_trigger(w, w.triggers[ti].uuid, mi, x, y) {
	case .Placed:
		return changed(s, "placed")
	case .Outside:
		return fail("that cell is outside the map")
	case .Unknown:
		return fail("no such map or trigger")
	}
	return fail("not placed")
}

tool_trigger_attach :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	ti, r1, ok1 := find_trigger_arg(s, args)
	if !ok1 {
		return r1
	}
	fi, r2, ok2 := find_feature_arg(s, args, "feature")
	if !ok2 {
		return r2
	}
	if !cm.world_attach_trigger(w, w.triggers[ti].uuid, w.features[fi].uuid) {
		return fail("could not attach it")
	}
	return changed(s, "attached")
}

tool_trigger_unplace :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	ti, r1, ok1 := find_trigger_arg(s, args)
	if !ok1 {
		return r1
	}
	if !cm.world_unplace_trigger(s.world, s.world.triggers[ti].uuid) {
		return ok_result("it was in no place")
	}
	return changed(s, "taken out of its place")
}
