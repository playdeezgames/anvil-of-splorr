package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// File format (JSON), one object per palette entry in order:
//   { "colors": [ {"r": 0, "g": 0, "b": 0}, ... 16 entries ... ] }
// Loading requires exactly PALETTE_SIZE entries, each with integer r, g and b in 0..255.
// Unknown extra fields are ignored.

palette_to_json :: proc(p: Palette, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "{\n  \"colors\": [\n")
	for c, i in p {
		fmt.sbprintf(&b, "    {{\"r\": %d, \"g\": %d, \"b\": %d}}%s\n", c.r, c.g, c.b, i + 1 < PALETTE_SIZE ? "," : "")
	}
	strings.write_string(&b, "  ]\n}\n")
	return strings.to_string(b)
}

// Returns ok=false (and a zero palette) for anything that is not a valid palette file.
palette_from_json :: proc(data: []u8) -> (p: Palette, ok: bool) {
	val, err := json.parse(data, .JSON, true, context.temp_allocator)
	if err != .None {
		return {}, false
	}
	defer json.destroy_value(val, context.temp_allocator)

	root, is_obj := val.(json.Object)
	if !is_obj {
		return {}, false
	}
	colors, is_arr := root["colors"].(json.Array)
	if !is_arr || len(colors) != PALETTE_SIZE {
		return {}, false
	}
	for entry, i in colors {
		obj, is_entry := entry.(json.Object)
		if !is_entry {
			return {}, false
		}
		for ch in Channel {
			v, got := channel_value(obj[channel_keys[ch]])
			if !got {
				return {}, false
			}
			p[i][ch] = v
		}
	}
	return p, true
}

@(private = "file")
channel_keys := [Channel]string {
	.R = "r",
	.G = "g",
	.B = "b",
}

@(private = "file")
channel_value :: proc(v: json.Value) -> (u8, bool) {
	n: i64
	#partial switch x in v {
	case json.Integer:
		n = x
	case json.Float:
		if x != f64(i64(x)) { 	// 5.0 is fine, 5.5 is not
			return 0, false
		}
		n = i64(x)
	case:
		return 0, false
	}
	if n < 0 || n > 255 {
		return 0, false
	}
	return u8(n), true
}
