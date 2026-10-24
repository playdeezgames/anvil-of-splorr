package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Features (FEATURES.md): things that stand still and always block, one per map cell. The tools
// mirror the character ones; a feature's id is a uuid (an 8-digit prefix works if unique).

feature_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{"feature_type_list", "List the feature types: name, sprite, tags and numeric properties with their defaults.", `{"type":"object","properties":{}}`, tool_feature_type_list},
		{
			"feature_type_new",
			"Add a feature type (up to 64). sprite_set and sprite name the picture (both or neither); tags lists the tags every feature of the type has.",
			`{"type":"object","properties":{"name":{"type":"string"},"sprite_set":{"type":"string"},"sprite":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["name"]}`,
			tool_feature_type_new,
		},
		{
			"feature_type_edit",
			"Change a feature type; only the fields given change. Features of the type follow a rename.",
			`{"type":"object","properties":{"name":{"type":"string"},"new_name":{"type":"string"},"sprite_set":{"type":"string"},"sprite":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["name"]}`,
			tool_feature_type_edit,
		},
		{"feature_type_delete", "Delete a feature type unless a feature has it.", NAME_ARG, tool_feature_type_delete},
		{
			"feature_type_prop_set",
			"Give a feature type a numeric property (up to 16, whole numbers that fit in 32 bits) or change its default value; new_name renames it. Features without their own value follow the default.",
			`{"type":"object","properties":{"type":{"type":"string"},"name":{"type":"string"},"value":{"type":"integer"},"new_name":{"type":"string"}},"required":["type","name"]}`,
			tool_feature_type_prop_set,
		},
		{
			"feature_type_prop_delete",
			"Remove a property from a feature type; its features lose their value for it.",
			`{"type":"object","properties":{"type":{"type":"string"},"name":{"type":"string"}},"required":["type","name"]}`,
			tool_feature_type_prop_delete,
		},
		{
			"feature_list",
			"List features (all, or those standing on map): id, name, type, where, its own tag settings and its values of its type's properties. A feature always blocks: no character can share its cell.",
			`{"type":"object","properties":{"map":{"type":"string"}}}`,
			tool_feature_list,
		},
		{
			"feature_new",
			"Add a feature of a type (up to 2048), standing nowhere. Returns its id. tags_set / tags_cleared are its own tag settings; props is an object of property name (of the type) to its value for this feature.",
			`{"type":"object","properties":{"name":{"type":"string"},"type":{"type":"string"},"tags_set":{"type":"array","items":{"type":"string"}},"tags_cleared":{"type":"array","items":{"type":"string"}},"props":{"type":"object"}},"required":["name","type"]}`,
			tool_feature_new,
		},
		{
			"feature_edit",
			"Change a feature by id; only the fields given change (name, type, tags_set, tags_cleared, props). A new type makes it forget its property values; props sets values of its (new) type's properties.",
			`{"type":"object","properties":{"id":{"type":"string"},"name":{"type":"string"},"type":{"type":"string"},"tags_set":{"type":"array","items":{"type":"string"}},"tags_cleared":{"type":"array","items":{"type":"string"}},"props":{"type":"object"}},"required":["id"]}`,
			tool_feature_edit,
		},
		{"feature_delete", "Delete a feature; it leaves its map and what it held is gone.", `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`, tool_feature_delete},
		{
			"feature_place",
			"Stand a feature in a map cell (moving it if it stood elsewhere). Refused if another feature or a character is in the cell.",
			`{"type":"object","properties":{"id":{"type":"string"},"map":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"}},"required":["id","map","x","y"]}`,
			tool_feature_place,
		},
		{"feature_unplace", "Take a feature off its map.", `{"type":"object","properties":{"id":{"type":"string"}},"required":["id"]}`, tool_feature_unplace},
	}
	return table[:]
}

find_feature_type :: proc(s: ^Server, args: json.Object, key := "name") -> (ft: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	i := cm.world_find_feature_type(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no feature type named %s", name)), false
	}
	return i, {}, true
}

find_feature_arg :: proc(s: ^Server, args: json.Object, key := "id") -> (fi: int, res: Tool_Result, ok: bool) {
	text, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	w := s.world
	if u, is_uuid := cm.uuid_from_string(text); is_uuid {
		i := cm.world_find_feature(w, u)
		if i < 0 {
			return 0, fail(fmt.tprintf("no feature with id %s", text)), false
		}
		return i, {}, true
	}
	found := -1
	for i in 0 ..< w.feature_count {
		if len(text) >= 4 && strings.has_prefix(cm.uuid_to_string(w.features[i].uuid), strings.to_lower(text, context.temp_allocator)) {
			if found >= 0 {
				return 0, fail(fmt.tprintf("%s matches more than one feature: use the full id", text)), false
			}
			found = i
		}
	}
	if found < 0 {
		return 0, fail(fmt.tprintf("no feature with id %s", text)), false
	}
	return found, {}, true
}

// --- Feature types -----------------------------------------------------------------------------

tool_feature_type_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"feature_types":[`)
	for i in 0 ..< w.feature_type_count {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		ft := &w.feature_types[i]
		fmt.sbprintf(&b, `{{"name":%s,"sprite_set":%s,"sprite":%s,"tags":`, quote(cm.name_str(&ft.name)), quote(cm.name_str(&ft.sprite_set)), quote(cm.name_str(&ft.sprite)))
		write_strings(&b, tag_names_in(w, ft.tags))
		strings.write_string(&b, `,"props":`)
		write_prop_defaults(&b, &ft.props)
		strings.write_string(&b, "}")
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_feature_type_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	if p := cm.world_check_feature_type_name(w, -1, name); p != .None {
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
	i := cm.world_add_feature_type(w, name)
	if i < 0 {
		return fail("the world already has 64 feature types")
	}
	ft := &w.feature_types[i]
	if given {
		cm.name_assign(&ft.sprite_set, set)
		cm.name_assign(&ft.sprite, sprite)
	}
	ft.tags = mask
	return changed(s, fmt.tprintf("added feature type %s", cm.name_str(&ft.name)))
}

tool_feature_type_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	i, r1, ok1 := find_feature_type(s, args)
	if !ok1 {
		return r1
	}
	ft := &w.feature_types[i]
	new_name, has_new := arg_string(args, "new_name")
	if has_new {
		if p := cm.world_check_feature_type_name(w, i, new_name); p != .None {
			return fail(problem_text(p))
		}
	}
	set, sprite, given := sprite_args(args, cm.name_str(&ft.sprite_set), cm.name_str(&ft.sprite))
	if given {
		if msg := check_sprite_ref(w, set, sprite); msg != "" {
			return fail(msg)
		}
	}
	mask := ft.tags
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
		cm.name_assign(&ft.sprite_set, set)
		cm.name_assign(&ft.sprite, sprite)
	}
	ft.tags = mask
	if has_new {
		cm.world_rename_feature_type(w, i, new_name)
	}
	return changed(s, "feature type updated")
}

tool_feature_type_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, r1, ok1 := find_feature_type(s, args)
	if !ok1 {
		return r1
	}
	if uses := cm.world_delete_feature_type(s.world, i); uses > 0 {
		return fail(fmt.tprintf("%d features have this type", uses))
	}
	return changed(s, "deleted the feature type")
}

tool_feature_type_prop_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	ft, r, ok := find_feature_type(s, args, "type")
	if !ok {
		return r
	}
	return set_prop_tool(s, args, &s.world.feature_types[ft].props, "a feature type")
}

tool_feature_type_prop_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	ft, r, ok := find_feature_type(s, args, "type")
	if !ok {
		return r
	}
	name, r2, ok2 := need_string(args, "name")
	if !ok2 {
		return r2
	}
	p := cm.prop_set_find(&s.world.feature_types[ft].props, name)
	if p < 0 {
		return fail(fmt.tprintf("the feature type has no property named %s", name))
	}
	cm.world_feature_type_delete_prop(s.world, ft, p)
	return changed(s, "deleted the property")
}

// --- Features ----------------------------------------------------------------------------------

write_feature :: proc(b: ^strings.Builder, w: ^cm.World, fi: int) {
	f := &w.features[fi]
	fmt.sbprintf(b, `{{"id":%s,"name":%s,"type":%s`, quote(cm.uuid_to_string(f.uuid)), quote(cm.name_str(&f.name)), quote(cm.name_str(&f.type)))
	if mi, x, y, placed := cm.world_feature_location(w, f.uuid); placed {
		fmt.sbprintf(b, `,"map":%s,"x":%d,"y":%d`, quote(cm.name_str(&w.maps[mi].name)), x, y)
	}
	strings.write_string(b, `,"tags_set":`)
	write_strings(b, tag_names_in(w, f.tags_set))
	strings.write_string(b, `,"tags_cleared":`)
	write_strings(b, tag_names_in(w, f.tags_cleared))
	if ti := cm.world_find_feature_type(w, cm.name_str(&f.type)); ti >= 0 && w.feature_types[ti].props.count > 0 {
		strings.write_string(b, `,"props":`)
		write_prop_values(b, &w.feature_types[ti].props, &f.overrides)
	}
	strings.write_string(b, "}")
}

tool_feature_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	only := -1
	if _, has := arg_string(args, "map"); has {
		mi, r, ok := find_map_arg(s, args, "map")
		if !ok {
			return r
		}
		only = mi
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"features":[`)
	first := true
	for fi in 0 ..< w.feature_count {
		if only >= 0 {
			if mi, _, _, placed := cm.world_feature_location(w, w.features[fi].uuid); !placed || mi != only {
				continue
			}
		}
		strings.write_string(&b, first ? "" : ",")
		first = false
		write_feature(&b, w, fi)
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_feature_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
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
	ft, r2, ok2 := find_feature_type(s, args, "type")
	if !ok2 {
		return r2
	}
	set, cleared, r3, ok3 := tag_setting_args(w, args, 0, 0)
	if !ok3 {
		return r3
	}
	values, _, pmsg := parse_props_arg(args, &w.feature_types[ft].props)
	if pmsg != "" {
		return fail(pmsg)
	}
	fi := cm.world_add_feature(w, ft, name)
	if fi < 0 {
		return fail("the world already has 2048 features")
	}
	w.features[fi].tags_set, w.features[fi].tags_cleared = set, cleared
	for v in values {
		cm.world_feature_set_value(w, fi, v.index, v.value)
	}
	return changed(s, fmt.tprintf(`{{"id":%s}}`, quote(cm.uuid_to_string(w.features[fi].uuid))))
}

tool_feature_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	fi, r1, ok1 := find_feature_arg(s, args)
	if !ok1 {
		return r1
	}
	f := &w.features[fi]
	name, has_name := arg_string(args, "name")
	if has_name {
		if p := cm.name_text_problem(name); p != .None {
			return fail(problem_text(p))
		}
	}
	ft := -1
	if _, has := arg_string(args, "type"); has {
		i, r, found := find_feature_type(s, args, "type")
		if !found {
			return r
		}
		ft = i
	}
	set, cleared, r2, ok2 := tag_setting_args(w, args, f.tags_set, f.tags_cleared)
	if !ok2 {
		return r2
	}
	target_type := ft >= 0 ? ft : cm.world_find_feature_type(w, cm.name_str(&f.type))
	values: []Prop_Arg
	if target_type >= 0 {
		pmsg: string
		values, _, pmsg = parse_props_arg(args, &w.feature_types[target_type].props)
		if pmsg != "" {
			return fail(pmsg)
		}
	}
	if has_name {
		cm.world_rename_feature(w, fi, name)
	}
	if ft >= 0 {
		cm.world_set_feature_type(w, fi, ft) // (its values belonged to the old type)
	}
	f.tags_set, f.tags_cleared = set, cleared
	for v in values {
		cm.world_feature_set_value(w, fi, v.index, v.value)
	}
	return changed(s, "feature updated")
}

tool_feature_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	fi, r1, ok1 := find_feature_arg(s, args)
	if !ok1 {
		return r1
	}
	cm.world_delete_feature(s.world, fi)
	return changed(s, "deleted the feature")
}

tool_feature_place :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	fi, r1, ok1 := find_feature_arg(s, args)
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
	switch cm.world_place_feature(w, mi, x, y, w.features[fi].uuid) {
	case .Placed:
		return changed(s, "placed")
	case .Taken:
		return fail("another feature stands in that cell")
	case .Character_There:
		return fail("a character stands in that cell: features always block")
	case .Outside:
		return fail("that cell is outside the map")
	case .Unknown, .Feature_There:
		return fail("no such map or feature")
	}
	return fail("not placed")
}

tool_feature_unplace :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	fi, r1, ok1 := find_feature_arg(s, args)
	if !ok1 {
		return r1
	}
	if !cm.world_unplace_feature(s.world, s.world.features[fi].uuid) {
		return ok_result("it was not standing anywhere")
	}
	return changed(s, "taken off its map")
}
