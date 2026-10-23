package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Items and inventories (coxswain task #1 of project anvil). An item type has a sprite, tags, a max
// stack and numeric properties; an inventory holds entries {type, count, property overrides} and
// belongs to one owner: a character (`character` = its id), a feature (`feature` = its id) or a map
// cell (`map`, `x`, `y`). Entries are numbered from 0 in the order the inventory holds them.

item_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{"item_type_list", "List the item types: name, sprite, tags, max_stack (1 = unique items that never stack, more = counted ones like gold) and numeric properties with their defaults.", `{"type":"object","properties":{}}`, tool_item_type_list},
		{
			"item_type_new",
			"Add an item type (up to 128). max_stack defaults to 1. sprite_set and sprite name the picture (both or neither); tags lists the tags every item of the type has. Add properties with item_prop_set.",
			`{"type":"object","properties":{"name":{"type":"string"},"max_stack":{"type":"integer"},"sprite_set":{"type":"string"},"sprite":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["name"]}`,
			tool_item_type_new,
		},
		{
			"item_type_edit",
			"Change an item type; only the fields given change. Entries of the type follow a rename. max_stack is refused while an entry holds more than the new size.",
			`{"type":"object","properties":{"name":{"type":"string"},"new_name":{"type":"string"},"max_stack":{"type":"integer"},"sprite_set":{"type":"string"},"sprite":{"type":"string"},"tags":{"type":"array","items":{"type":"string"}}},"required":["name"]}`,
			tool_item_type_edit,
		},
		{"item_type_delete", "Delete an item type unless an inventory entry has it.", NAME_ARG, tool_item_type_delete},
		{
			"item_prop_set",
			"Give an item type a numeric property (up to 16, whole numbers that fit in 32 bits) or change its default value; new_name renames it. Entries without their own value follow the default.",
			`{"type":"object","properties":{"type":{"type":"string"},"name":{"type":"string"},"value":{"type":"integer"},"new_name":{"type":"string"}},"required":["type","name"]}`,
			tool_item_prop_set,
		},
		{
			"item_prop_delete",
			"Remove a property from an item type; entries lose their value for it.",
			`{"type":"object","properties":{"type":{"type":"string"},"name":{"type":"string"}},"required":["type","name"]}`,
			tool_item_prop_delete,
		},
		{
			"inventory_list",
			"List the inventories (all, or the cell inventories on map): owner and entries. Each entry has its number, item type, count and the value of every property of the type.",
			`{"type":"object","properties":{"map":{"type":"string"}}}`,
			tool_inventory_list,
		},
		{"inventory_get", "Show one owner's inventory (entries: [] when it has none). Give exactly one of character (id), feature (id) or map with x and y.", OWNER_SCHEMA, tool_inventory_get},
		{
			"inventory_add",
			"Put count items (default 1) of a type into an owner's inventory, made if there is none. Items fill matching stacks first (same type and same property values), and a stack never exceeds the type's max_stack; props is an object of property name to value for this stack. Up to 256 entries per inventory and 8192 in the world; what does not fit is reported.",
			`{"type":"object","properties":{"character":{"type":"string"},"feature":{"type":"string"},"map":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"type":{"type":"string"},"count":{"type":"integer"},"props":{"type":"object"}},"required":["type"]}`,
			tool_inventory_add,
		},
		{
			"inventory_remove",
			"Take count items (default: the whole entry) out of entry number `entry`. An emptied entry goes, and an inventory with nothing left goes with it.",
			`{"type":"object","properties":{"character":{"type":"string"},"feature":{"type":"string"},"map":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"entry":{"type":"integer"},"count":{"type":"integer"}},"required":["entry"]}`,
			tool_inventory_remove,
		},
		{
			"inventory_set",
			"Change entry number `entry`: count (1..the type's max_stack) and/or props (property name to value; a value equal to the type's default clears the entry's own value).",
			`{"type":"object","properties":{"character":{"type":"string"},"feature":{"type":"string"},"map":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"entry":{"type":"integer"},"count":{"type":"integer"},"props":{"type":"object"}},"required":["entry"]}`,
			tool_inventory_set,
		},
		{"inventory_clear", "Throw away an owner's whole inventory.", OWNER_SCHEMA, tool_inventory_clear},
	}
	return table[:]
}

OWNER_SCHEMA :: `{"type":"object","properties":{"character":{"type":"string"},"feature":{"type":"string"},"map":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"}}}`

// --- Finding -----------------------------------------------------------------------------------

find_item_type_arg :: proc(s: ^Server, args: json.Object, key := "name") -> (ti: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	i := cm.world_find_item_type(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no item type named %s", name)), false
	}
	return i, {}, true
}

// Exactly one of character, feature, or map with x and y.
find_owner_arg :: proc(s: ^Server, args: json.Object) -> (o: cm.Inventory_Owner, res: Tool_Result, ok: bool) {
	w := s.world
	_, has_c := arg_string(args, "character")
	_, has_f := arg_string(args, "feature")
	_, has_m := arg_string(args, "map")
	if int(has_c ? 1 : 0) + int(has_f ? 1 : 0) + int(has_m ? 1 : 0) != 1 {
		return {}, fail("name the owner with exactly one of character (id), feature (id) or map with x and y"), false
	}
	switch {
	case has_c:
		ci, r, found := find_character_arg(s, args, "character")
		if !found {
			return {}, r, false
		}
		return cm.owner_character(w.characters[ci].uuid), {}, true
	case has_f:
		fi, r, found := find_feature_arg(s, args, "feature")
		if !found {
			return {}, r, false
		}
		return cm.owner_feature(w.features[fi].uuid), {}, true
	}
	mi, r, found := find_map_arg(s, args, "map")
	if !found {
		return {}, r, false
	}
	x, g1 := arg_int(args, "x")
	y, g2 := arg_int(args, "y")
	if !g1 || !g2 {
		return {}, fail("a map cell needs x and y"), false
	}
	if x < 0 || y < 0 || x >= w.maps[mi].width || y >= w.maps[mi].height {
		return {}, fail("that cell is outside the map"), false
	}
	return cm.owner_cell(mi, x, y), {}, true
}

// A JSON number with no fraction (the parser may hand whole numbers over as floats).
whole_number :: proc(v: json.Value) -> (n: i64, ok: bool) {
	#partial switch x in v {
	case json.Integer:
		return i64(x), true
	case json.Float:
		if x == f64(i64(x)) {
			return i64(x), true
		}
	}
	return 0, false
}

// The "props" argument: an object of property name to whole number, for `set`'s properties.
arg_prop_values :: proc(args: json.Object, set: ^cm.Prop_Set) -> (o: cm.Prop_Overrides, present: bool, msg: string) {
	v, has := args["props"]
	if !has {
		return {}, false, ""
	}
	obj, is_obj := v.(json.Object)
	if !is_obj {
		return {}, true, "props must be an object of property name to whole number"
	}
	for key, val in obj {
		i := cm.prop_set_find(set, key)
		if i < 0 {
			return {}, true, fmt.tprintf("the item type has no property named %s", key)
		}
		n, is_int := whole_number(val)
		if !is_int || n < i64(min(i32)) || n > i64(max(i32)) {
			return {}, true, fmt.tprintf("property %s must be a whole number that fits in 32 bits", key)
		}
		cm.prop_override_set(set, &o, i, i32(n))
	}
	return o, true, ""
}

// --- Writing -----------------------------------------------------------------------------------

write_owner :: proc(b: ^strings.Builder, w: ^cm.World, o: cm.Inventory_Owner) {
	switch o.kind {
	case .Cell:
		fmt.sbprintf(b, `{{"kind":"cell","map":%s,"x":%d,"y":%d}}`, quote(cm.name_str(&w.maps[o.map_index].name)), o.x, o.y)
	case .Character:
		fmt.sbprintf(b, `{{"kind":"character","id":%s,"name":%s}}`, quote(cm.uuid_to_string(o.uuid)), quote(cm.name_str(&w.characters[cm.world_find_character(w, o.uuid)].name)))
	case .Feature:
		fmt.sbprintf(b, `{{"kind":"feature","id":%s,"name":%s}}`, quote(cm.uuid_to_string(o.uuid)), quote(cm.name_str(&w.features[cm.world_find_feature(w, o.uuid)].name)))
	}
}

// [ {entry, type, count, props: {every property of the type: its value for this entry}} ]
write_entries :: proc(b: ^strings.Builder, w: ^cm.World, u: cm.Uuid) {
	strings.write_string(b, "[")
	n := 0
	for e in 0 ..< w.entry_count {
		en := &w.entries[e]
		if en.inventory != u {
			continue
		}
		fmt.sbprintf(b, `%s{{"entry":%d,"type":%s,"count":%d,"props":{{`, n > 0 ? "," : "", n, quote(cm.name_str(&en.type)), en.count)
		if ti := cm.world_find_item_type(w, cm.name_str(&en.type)); ti >= 0 {
			ps := &w.item_types[ti].props
			for p in 0 ..< ps.count {
				fmt.sbprintf(b, `%s%s:%d`, p > 0 ? "," : "", quote(cm.name_str(&ps.names[p])), cm.prop_value(ps, &en.overrides, p))
			}
		}
		strings.write_string(b, "}}")
		n += 1
	}
	strings.write_string(b, "]")
}

write_inventory :: proc(b: ^strings.Builder, w: ^cm.World, u: cm.Uuid) {
	strings.write_string(b, `{"owner":`)
	if o, ok := cm.world_inventory_owner(w, u); ok {
		write_owner(b, w, o)
	} else {
		strings.write_string(b, "null")
	}
	strings.write_string(b, `,"entries":`)
	write_entries(b, w, u)
	strings.write_string(b, "}")
}

// --- Item types --------------------------------------------------------------------------------

tool_item_type_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"item_types":[`)
	for i in 0 ..< w.item_type_count {
		it := &w.item_types[i]
		fmt.sbprintf(&b, `%s{{"name":%s,"sprite_set":%s,"sprite":%s,"max_stack":%d,"tags":`, i > 0 ? "," : "", quote(cm.name_str(&it.name)), quote(cm.name_str(&it.sprite_set)), quote(cm.name_str(&it.sprite)), it.max_stack)
		write_strings(&b, tag_names_in(w, it.tags))
		strings.write_string(&b, `,"props":[`)
		for p in 0 ..< it.props.count {
			fmt.sbprintf(&b, `%s{{"name":%s,"value":%d}}`, p > 0 ? "," : "", quote(cm.name_str(&it.props.names[p])), it.props.values[p])
		}
		strings.write_string(&b, "]}")
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_item_type_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	if p := cm.world_check_item_type_name(w, -1, name); p != .None {
		return fail(problem_text(p))
	}
	max_stack := 1
	if _, has := args["max_stack"]; has {
		n, good := arg_int(args, "max_stack")
		if !good || n < 1 || n > cm.ITEM_MAX_STACK {
			return fail(fmt.tprintf("max_stack must be a whole number from 1 to %d", cm.ITEM_MAX_STACK))
		}
		max_stack = n
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
	i := cm.world_add_item_type(w, name)
	if i < 0 {
		return fail("the world already has 128 item types")
	}
	it := &w.item_types[i]
	it.max_stack = max_stack
	if given {
		cm.name_assign(&it.sprite_set, set)
		cm.name_assign(&it.sprite, sprite)
	}
	it.tags = mask
	return changed(s, fmt.tprintf("added item type %s", cm.name_str(&it.name)))
}

tool_item_type_edit :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	i, r1, ok1 := find_item_type_arg(s, args)
	if !ok1 {
		return r1
	}
	it := &w.item_types[i]
	new_name, has_new := arg_string(args, "new_name")
	if has_new {
		if p := cm.world_check_item_type_name(w, i, new_name); p != .None {
			return fail(problem_text(p))
		}
	}
	max_stack, has_max := it.max_stack, false
	if _, has := args["max_stack"]; has {
		n, good := arg_int(args, "max_stack")
		if !good || n < 1 || n > cm.ITEM_MAX_STACK {
			return fail(fmt.tprintf("max_stack must be a whole number from 1 to %d", cm.ITEM_MAX_STACK))
		}
		max_stack, has_max = n, true
	}
	set, sprite, given := sprite_args(args, cm.name_str(&it.sprite_set), cm.name_str(&it.sprite))
	if given {
		if msg := check_sprite_ref(w, set, sprite); msg != "" {
			return fail(msg)
		}
	}
	mask := it.tags
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
	if has_max {
		if too_big := cm.world_set_item_type_max_stack(w, i, max_stack); too_big > 0 {
			return fail(fmt.tprintf("%d entries hold more than %d: remove or split them first", too_big, max_stack))
		}
	}
	if given {
		cm.name_assign(&it.sprite_set, set)
		cm.name_assign(&it.sprite, sprite)
	}
	it.tags = mask
	if has_new {
		cm.world_rename_item_type(w, i, new_name)
	}
	return changed(s, "item type updated")
}

tool_item_type_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, r1, ok1 := find_item_type_arg(s, args)
	if !ok1 {
		return r1
	}
	if uses := cm.world_delete_item_type(s.world, i); uses > 0 {
		return fail(fmt.tprintf("%d inventory entries have this type", uses))
	}
	return changed(s, "deleted the item type")
}

tool_item_prop_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	ti, r1, ok1 := find_item_type_arg(s, args, "type")
	if !ok1 {
		return r1
	}
	name, r2, ok2 := need_string(args, "name")
	if !ok2 {
		return r2
	}
	ps := &w.item_types[ti].props
	value, has_value := i32(0), false
	if _, has := args["value"]; has {
		n, good := arg_int(args, "value")
		if !good || n < int(min(i32)) || n > int(max(i32)) {
			return fail("value must be a whole number that fits in 32 bits")
		}
		value, has_value = i32(n), true
	}
	new_name, has_new := arg_string(args, "new_name")
	p := cm.prop_set_find(ps, name)
	if p < 0 {
		if has_new {
			return fail(fmt.tprintf("no property named %s: new_name renames an existing one", name))
		}
		if pr := cm.prop_set_check_name(ps, -1, name); pr != .None {
			return fail(problem_text(pr))
		}
		if cm.prop_set_add(ps, name, value) < 0 {
			return fail("an item type has at most 16 properties")
		}
		return changed(s, fmt.tprintf("added property %s", name))
	}
	if has_new {
		if pr := cm.prop_set_rename(ps, p, new_name); pr != .None {
			return fail(problem_text(pr))
		}
	}
	if has_value {
		ps.values[p] = value
	}
	return changed(s, "property updated")
}

tool_item_prop_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	ti, r1, ok1 := find_item_type_arg(s, args, "type")
	if !ok1 {
		return r1
	}
	name, r2, ok2 := need_string(args, "name")
	if !ok2 {
		return r2
	}
	p := cm.prop_set_find(&w.item_types[ti].props, name)
	if p < 0 {
		return fail(fmt.tprintf("the item type has no property named %s", name))
	}
	cm.world_item_type_delete_prop(w, ti, p)
	return changed(s, "deleted the property")
}

// --- Inventories -------------------------------------------------------------------------------

tool_inventory_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
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
	strings.write_string(&b, `{"inventories":[`)
	first := true
	for i in 0 ..< w.inventory_count {
		u := w.inventories[i].uuid
		if only >= 0 {
			if o, found := cm.world_inventory_owner(w, u); !found || o.kind != .Cell || o.map_index != only {
				continue
			}
		}
		strings.write_string(&b, first ? "" : ",")
		first = false
		write_inventory(&b, w, u)
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_inventory_get :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	o, r, ok := find_owner_arg(s, args)
	if !ok {
		return r
	}
	b := strings.builder_make(context.temp_allocator)
	if u := cm.world_owner_inventory(w, o); !cm.uuid_is_none(u) {
		write_inventory(&b, w, u)
	} else {
		strings.write_string(&b, `{"owner":`)
		write_owner(&b, w, o)
		strings.write_string(&b, `,"entries":[]}`)
	}
	return ok_result(strings.to_string(b))
}

tool_inventory_add :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	o, r1, ok1 := find_owner_arg(s, args)
	if !ok1 {
		return r1
	}
	ti, r2, ok2 := find_item_type_arg(s, args, "type")
	if !ok2 {
		return r2
	}
	count := 1
	if _, has := args["count"]; has {
		n, good := arg_int(args, "count")
		if !good || n < 1 {
			return fail("count must be a whole number of at least 1")
		}
		count = n
	}
	overrides, _, msg := arg_prop_values(args, &w.item_types[ti].props)
	if msg != "" {
		return fail(msg)
	}
	left, result := cm.world_owner_add(w, o, ti, count, overrides)
	switch result {
	case .Added:
		return changed(s, fmt.tprintf("added %d", count))
	case .Partly:
		return changed(s, fmt.tprintf("added %d; %d did not fit (an inventory holds 256 entries, the world 8192)", count - left, left))
	case .None_Fit:
		return fail("nothing fits: the inventory has 256 entries, or the world 8192 entries or 1024 inventories")
	case .No_Owner:
		return fail("no such owner")
	case .Unknown_Type:
		return fail("no such item type")
	case .Bad_Count:
		return fail("count must be a whole number of at least 1")
	}
	return fail("nothing added")
}

// The entry argument against the owner's inventory.
find_entry_arg :: proc(s: ^Server, args: json.Object, o: cm.Inventory_Owner) -> (e: ^cm.Entry, res: Tool_Result, ok: bool) {
	n, good := arg_int(args, "entry")
	if !good {
		return nil, fail("entry is a required whole number (the first entry is 0)"), false
	}
	en := cm.world_owner_entry(s.world, o, n)
	if en == nil {
		return nil, fail(fmt.tprintf("there is no entry %d in that inventory (it has %d)", n, cm.world_owner_entry_count(s.world, o))), false
	}
	return en, {}, true
}

tool_inventory_remove :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	o, r1, ok1 := find_owner_arg(s, args)
	if !ok1 {
		return r1
	}
	en, r2, ok2 := find_entry_arg(s, args, o)
	if !ok2 {
		return r2
	}
	count := en.count
	if _, has := args["count"]; has {
		n, good := arg_int(args, "count")
		if !good || n < 1 {
			return fail("count must be a whole number of at least 1")
		}
		count = n
	}
	n, _ := arg_int(args, "entry")
	taken := cm.world_owner_remove(w, o, n, count)
	return changed(s, fmt.tprintf("took %d", taken))
}

tool_inventory_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	o, r1, ok1 := find_owner_arg(s, args)
	if !ok1 {
		return r1
	}
	en, r2, ok2 := find_entry_arg(s, args, o)
	if !ok2 {
		return r2
	}
	ti := cm.world_find_item_type(w, cm.name_str(&en.type))
	if ti < 0 {
		return fail("the entry's item type is missing")
	}
	it := &w.item_types[ti]
	count, has_count := en.count, false
	if _, has := args["count"]; has {
		n, good := arg_int(args, "count")
		if !good || n < 1 || n > it.max_stack {
			return fail(fmt.tprintf("count must be a whole number from 1 to the type's max_stack (%d); use inventory_remove to take items out", it.max_stack))
		}
		count, has_count = n, true
	}
	values, has_props, msg := arg_prop_values(args, &it.props)
	if msg != "" {
		return fail(msg)
	}
	if !has_count && !has_props {
		return fail("give count and/or props")
	}
	if has_count {
		en.count = count
	}
	if has_props {
		for p in 0 ..< it.props.count {
			if _, named := args["props"].(json.Object)[cm.name_str(&it.props.names[p])]; named {
				cm.prop_override_set(&it.props, &en.overrides, p, cm.prop_value(&it.props, &values, p))
			}
		}
	}
	return changed(s, "entry updated")
}

tool_inventory_clear :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	o, r, ok := find_owner_arg(s, args)
	if !ok {
		return r
	}
	if !cm.world_owner_clear_inventory(s.world, o) {
		return ok_result("it had no inventory")
	}
	return changed(s, "cleared the inventory")
}
