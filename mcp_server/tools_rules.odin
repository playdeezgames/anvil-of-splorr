package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

rules_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{"tag_list", "List the world's tags with how many things set or clear each (tag 0, solid, is built in).", `{"type":"object","properties":{}}`, tool_tag_list},
		{"tag_new", "Add a tag (up to 64 in the world).", `{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}`, tool_tag_new},
		{"tag_rename", "Rename a tag. The built-in solid tag cannot be renamed.", `{"type":"object","properties":{"name":{"type":"string"},"new_name":{"type":"string"}},"required":["name","new_name"]}`, tool_tag_rename},
		{
			"tag_delete",
			"Delete a tag and clear it everywhere. If anything uses it, confirm must be true. The solid tag cannot be deleted.",
			`{"type":"object","properties":{"name":{"type":"string"},"confirm":{"type":"boolean"}},"required":["name"]}`,
			tool_tag_delete,
		},
		{"param_list", "List the game parameters (named whole numbers or short texts).", `{"type":"object","properties":{}}`, tool_param_list},
		{
			"param_set",
			"Create or change a game parameter. Give number (a whole number, 32-bit) or text (up to 32 printable ASCII characters), not both.",
			`{"type":"object","properties":{"name":{"type":"string"},"number":{"type":"integer"},"text":{"type":"string"}},"required":["name"]}`,
			tool_param_set,
		},
		{"param_rename", "Rename a game parameter.", `{"type":"object","properties":{"name":{"type":"string"},"new_name":{"type":"string"}},"required":["name","new_name"]}`, tool_param_rename},
		{"param_delete", "Delete a game parameter.", `{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}`, tool_param_delete},
	}
	return table[:]
}

tool_tag_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"tags":[`)
	for i in 0 ..< w.tag_count {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		fmt.sbprintf(&b, `{{"name":%s,"used_by":%d}}`, quote(cm.name_str(&w.tags[i])), cm.world_tag_uses(w, i))
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_tag_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, res, ok := need_string(args, "name")
	if !ok {
		return res
	}
	if p := cm.world_check_tag_name(s.world, -1, name); p != .None {
		return fail(problem_text(p))
	}
	if cm.world_add_tag(s.world, name) < 0 {
		return fail("the world already has 64 tags")
	}
	return changed(s, fmt.tprintf("added tag %s", name))
}

find_tag_or_fail :: proc(s: ^Server, args: json.Object, key: string) -> (name: string, index: int, res: Tool_Result, ok: bool) {
	n, r, got := need_string(args, key)
	if !got {
		return "", 0, r, false
	}
	i := cm.world_find_tag(s.world, n)
	if i < 0 {
		return n, 0, fail(fmt.tprintf("no tag named %s", n)), false
	}
	return n, i, {}, true
}

tool_tag_rename :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	_, i, res, ok := find_tag_or_fail(s, args, "name")
	if !ok {
		return res
	}
	new_name, r2, ok2 := need_string(args, "new_name")
	if !ok2 {
		return r2
	}
	if cm.tag_is_reserved(i) {
		return fail("the solid tag cannot be renamed")
	}
	if p := cm.world_rename_tag(s.world, i, new_name); p != .None {
		return fail(problem_text(p))
	}
	return changed(s, fmt.tprintf("renamed to %s", new_name))
}

tool_tag_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, i, res, ok := find_tag_or_fail(s, args, "name")
	if !ok {
		return res
	}
	if cm.tag_is_reserved(i) {
		return fail("the solid tag cannot be deleted")
	}
	if uses := cm.world_tag_uses(s.world, i); uses > 0 && !arg_bool(args, "confirm") {
		return fail(fmt.tprintf("%d things use the tag %s: pass confirm true to clear it everywhere and delete it", uses, name))
	}
	cm.world_delete_tag(s.world, i)
	return changed(s, fmt.tprintf("deleted tag %s", name))
}

find_param :: proc(s: ^Server, args: json.Object, key: string) -> (name: string, index: int, res: Tool_Result, ok: bool) {
	n, r, got := need_string(args, key)
	if !got {
		return "", 0, r, false
	}
	i := cm.world_find_param(s.world, n)
	if i < 0 {
		return n, 0, fail(fmt.tprintf("no parameter named %s", n)), false
	}
	return n, i, {}, true
}

tool_param_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"params":[`)
	for i in 0 ..< w.param_count {
		if i > 0 {
			strings.write_string(&b, ",")
		}
		p := &w.params[i]
		if p.kind == .Number {
			fmt.sbprintf(&b, `{{"name":%s,"number":%d}}`, quote(cm.name_str(&p.name)), p.number)
		} else {
			fmt.sbprintf(&b, `{{"name":%s,"text":%s}}`, quote(cm.name_str(&p.name)), quote(cm.name_str(&p.text)))
		}
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_param_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, res, ok := need_string(args, "name")
	if !ok {
		return res
	}
	number, has_number := arg_int(args, "number")
	text, has_text := arg_string(args, "text")
	if has_number == has_text {
		return fail("give exactly one of number or text")
	}
	w := s.world
	i := cm.world_find_param(w, name)
	if i < 0 {
		if p := cm.world_check_param_name(w, -1, name); p != .None {
			return fail(problem_text(p))
		}
		if has_text && len(text) > cm.PARAM_TEXT_MAX {
			return fail("the text is longer than 32 characters")
		}
		i = cm.world_add_param(w, name)
		if i < 0 {
			return fail("the world already has 64 parameters")
		}
	}
	if has_number {
		cm.world_set_param_number(w, i, number)
		return changed(s, fmt.tprintf("%s = %d", name, w.params[i].number))
	}
	if p := cm.world_set_param_text(w, i, text); p != .None {
		return fail(problem_text(p))
	}
	return changed(s, fmt.tprintf("%s = %s", name, text))
}

tool_param_rename :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	_, i, res, ok := find_param(s, args, "name")
	if !ok {
		return res
	}
	new_name, r2, ok2 := need_string(args, "new_name")
	if !ok2 {
		return r2
	}
	if p := cm.world_rename_param(s.world, i, new_name); p != .None {
		return fail(problem_text(p))
	}
	return changed(s, fmt.tprintf("renamed to %s", new_name))
}

tool_param_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	name, i, res, ok := find_param(s, args, "name")
	if !ok {
		return res
	}
	cm.world_delete_param(s.world, i)
	return changed(s, fmt.tprintf("deleted parameter %s", name))
}
