package mcp_server

import cm "../common"
import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:sync"

// The whole tool table, in the order tools/list shows it.
tools :: proc() -> []Tool {
	@(static) all: [dynamic]Tool
	@(static) once: sync.Once // (tests run servers on several threads)
	sync.once_do(&once, proc() {
		all.allocator = runtime.default_allocator() // (not a test's tracking allocator: this outlives the test)
		append(&all, ..world_tools())
		append(&all, ..rules_tools())
		append(&all, ..look_tools())
		append(&all, ..actor_tools())
		append(&all, ..feature_tools())
		append(&all, ..render_tools())
		append(&all, ..sound_tools())
	})
	return all[:]
}

// --- Helpers shared by the tool files ----------------------------------------------------------

// Every editing tool starts here: the world must be open.
need_world :: proc(s: ^Server) -> (res: Tool_Result, ok: bool) {
	if !s.open {
		return fail(NOT_OPEN), false
	}
	return {}, true
}

// An editing tool's success: the world now has unsaved changes.
changed :: proc(s: ^Server, text: string) -> Tool_Result {
	s.dirty = true
	return ok_result(text)
}

problem_text :: proc(p: cm.Name_Problem) -> string {
	switch p {
	case .None:
		return ""
	case .Empty:
		return "the name is empty"
	case .Too_Long:
		return "the name is longer than 32 characters"
	case .Bad_Character:
		return "names use printable ASCII only"
	case .In_Use:
		return "that name is already taken"
	}
	return ""
}

arg_int :: proc(args: json.Object, key: string) -> (value: int, ok: bool) {
	#partial switch x in args[key] {
	case json.Integer:
		return int(x), true
	case json.Float:
		if f64(i64(x)) == f64(x) {
			return int(x), true
		}
	}
	return 0, false
}

// A required string argument, or the failure naming it.
need_string :: proc(args: json.Object, key: string) -> (value: string, res: Tool_Result, ok: bool) {
	v, has := arg_string(args, key)
	if !has {
		return "", fail(fmt.tprintf("%s is required (a string)", key)), false
	}
	return v, {}, true
}

// An array of strings argument. present says whether the key was given; ok is false if it is not an
// array of strings.
arg_strings :: proc(args: json.Object, key: string) -> (values: []string, present, ok: bool) {
	raw, has := args[key]
	if !has {
		return nil, false, true
	}
	arr, is_arr := raw.(json.Array)
	if !is_arr {
		return nil, true, false
	}
	out := make([]string, len(arr), context.temp_allocator)
	for item, i in arr {
		str, is_str := item.(json.String)
		if !is_str {
			return nil, true, false
		}
		out[i] = str
	}
	return out, true, true
}

// "#RRGGBB" (or "RRGGBB") to a colour.
parse_hex_color :: proc(text: string) -> (c: cm.Color, ok: bool) {
	t := strings.trim_prefix(text, "#")
	if len(t) != 6 {
		return {}, false
	}
	for i in 0 ..< 3 {
		hi, ok1 := hex_digit(t[i * 2])
		lo, ok2 := hex_digit(t[i * 2 + 1])
		if !ok1 || !ok2 {
			return {}, false
		}
		c[i] = u8(hi * 16 + lo)
	}
	return c, true
}

hex_digit :: proc(ch: u8) -> (int, bool) {
	switch ch {
	case '0' ..= '9':
		return int(ch - '0'), true
	case 'a' ..= 'f':
		return int(ch - 'a') + 10, true
	case 'A' ..= 'F':
		return int(ch - 'A') + 10, true
	}
	return 0, false
}

color_text :: proc(c: cm.Color) -> string {
	return fmt.tprintf("#%02X%02X%02X", c.r, c.g, c.b)
}

// Writes a JSON array of strings.
write_strings :: proc(b: ^strings.Builder, items: []string) {
	strings.write_string(b, "[")
	for item, i in items {
		if i > 0 {
			strings.write_string(b, ",")
		}
		strings.write_string(b, quote(item))
	}
	strings.write_string(b, "]")
}

// The names of the tags set in a mask, in tag order.
tag_names_in :: proc(w: ^cm.World, mask: cm.Tag_Mask) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for i in 0 ..< w.tag_count {
		if mask & cm.tag_bit(i) != 0 {
			append(&out, cm.name_str(&w.tags[i]))
		}
	}
	return out[:]
}

// A mask from tag names; names the world lacks fail with the name in the text.
mask_from_names :: proc(w: ^cm.World, names: []string) -> (mask: cm.Tag_Mask, bad: string, ok: bool) {
	for name in names {
		i := cm.world_find_tag(w, name)
		if i < 0 {
			return 0, name, false
		}
		mask |= cm.tag_bit(i)
	}
	return mask, "", true
}
