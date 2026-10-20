package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// A tileset: a list of named 4-bit images that all share one width and height. The tileset editor
// edits one; each image is an Image4 and uses a palette (the colours are not in the file).
//
// A Tileset is about 1 MB. Never return or copy one by value on the stack: create it with new() or
// as a global, and use the in-place procs below.

TILESET_MAX_IMAGES :: 256
TILESET_NAME_MAX :: TEXT_ENTRY_MAX // 32, the most the keypad can type
TILESET_DEFAULT_SIZE :: 16

Tileset :: struct {
	width, height: int, // every image has this size, IMAGE_MIN..IMAGE_MAX
	count:         int,
	name_len:      [TILESET_MAX_IMAGES]int,
	names:         [TILESET_MAX_IMAGES][TILESET_NAME_MAX]u8,
	images:        [TILESET_MAX_IMAGES]Image4, // images[i].width/height always equal the tileset's
}

Name_Problem :: enum {
	None,
	Empty,
	Too_Long,
	Bad_Character, // only printable ASCII (32..126) is allowed
	In_Use, // another image already has this name
}

// Empties the tileset in place: no images, the given tile size (clamped to IMAGE_MIN..IMAGE_MAX).
tileset_reset :: proc(ts: ^Tileset, width := TILESET_DEFAULT_SIZE, height := TILESET_DEFAULT_SIZE) {
	ts^ = {}
	ts.width = clamp(width, IMAGE_MIN, IMAGE_MAX)
	ts.height = clamp(height, IMAGE_MIN, IMAGE_MAX)
}

// The name of image i (valid until that name changes). "" for an index out of range.
tileset_name :: proc(ts: ^Tileset, i: int) -> string {
	if i < 0 || i >= ts.count {
		return ""
	}
	return string(ts.names[i][:ts.name_len[i]])
}

// Looks for an image with exactly this name, ignoring the image at index `except` (-1 for none).
tileset_find :: proc(ts: ^Tileset, name: string, except := -1) -> int {
	for i in 0 ..< ts.count {
		if i != except && tileset_name(ts, i) == name {
			return i
		}
	}
	return -1
}

// Whether `name` could be given to image `index` (pass -1 when naming a new image).
tileset_check_name :: proc(ts: ^Tileset, index: int, name: string) -> Name_Problem {
	if len(name) == 0 {
		return .Empty
	}
	if len(name) > TILESET_NAME_MAX {
		return .Too_Long
	}
	for i in 0 ..< len(name) {
		if name[i] < 32 || name[i] > 126 {
			return .Bad_Character
		}
	}
	if tileset_find(ts, name, index) >= 0 {
		return .In_Use
	}
	return .None
}

// Renames image i. Returns the problem if the name is not allowed (nothing changes then).
tileset_set_name :: proc(ts: ^Tileset, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= ts.count {
		return .Empty
	}
	if p := tileset_check_name(ts, i, name); p != .None {
		return p
	}
	ts.names[i] = {}
	copy(ts.names[i][:], name)
	ts.name_len[i] = len(name)
	return .None
}

// A name based on `base` that no image uses: base itself, else base_2, base_3 ... The base is cut
// short as needed so the result always fits.
tileset_unique_name :: proc(ts: ^Tileset, base: string) -> string {
	b := base
	if len(b) == 0 {
		b = "image"
	}
	if len(b) > TILESET_NAME_MAX {
		b = b[:TILESET_NAME_MAX]
	}
	if tileset_find(ts, b) < 0 {
		return strings.clone(b, context.temp_allocator)
	}
	for n in 2 ..= TILESET_MAX_IMAGES + 1 {
		suffix := fmt.tprintf("_%d", n)
		room := TILESET_NAME_MAX - len(suffix)
		candidate := fmt.tprintf("%s%s", b[:min(len(b), room)], suffix)
		if tileset_find(ts, candidate) < 0 {
			return candidate
		}
	}
	return strings.clone(b, context.temp_allocator) // unreachable: at most 256 images
}

@(private = "file")
make_room_at :: proc(ts: ^Tileset, at: int) {
	for i := ts.count; i > at; i -= 1 {
		ts.images[i] = ts.images[i - 1]
		ts.names[i] = ts.names[i - 1]
		ts.name_len[i] = ts.name_len[i - 1]
	}
}

// Inserts a blank image at index `at` (0..count) named after `base` (made unique). Returns its
// index, or -1 if the tileset is full.
tileset_insert_blank :: proc(ts: ^Tileset, at: int, base := "image") -> int {
	if ts.count >= TILESET_MAX_IMAGES {
		return -1
	}
	i := clamp(at, 0, ts.count)
	name := tileset_unique_name(ts, base)
	make_room_at(ts, i)
	ts.images[i] = image4_make(ts.width, ts.height)
	ts.names[i] = {}
	copy(ts.names[i][:], name)
	ts.name_len[i] = len(name)
	ts.count += 1
	return i
}

// Inserts a copy of image i right after it, named "<name>_copy" (made unique). Returns the new
// index, or -1 if the tileset is full or i is out of range.
tileset_duplicate :: proc(ts: ^Tileset, i: int) -> int {
	if i < 0 || i >= ts.count || ts.count >= TILESET_MAX_IMAGES {
		return -1
	}
	original := ts.images[i]
	base := fmt.tprintf("%s_copy", tileset_name(ts, i))
	n := tileset_insert_blank(ts, i + 1, base)
	if n >= 0 {
		ts.images[n] = original
	}
	return n
}

// Removes image i, closing the gap. Returns false if i is out of range.
tileset_delete :: proc(ts: ^Tileset, i: int) -> bool {
	if i < 0 || i >= ts.count {
		return false
	}
	for k in i ..< ts.count - 1 {
		ts.images[k] = ts.images[k + 1]
		ts.names[k] = ts.names[k + 1]
		ts.name_len[k] = ts.name_len[k + 1]
	}
	last := ts.count - 1
	ts.images[last] = {}
	ts.names[last] = {}
	ts.name_len[last] = 0
	ts.count -= 1
	return true
}

// Swaps image i with its neighbour in direction `delta` (-1 earlier, +1 later). Returns the image's
// new index, or its old one if it is already at that end.
tileset_move :: proc(ts: ^Tileset, i, delta: int) -> int {
	j := i + delta
	if i < 0 || i >= ts.count || j < 0 || j >= ts.count || delta == 0 {
		return i
	}
	ts.images[i], ts.images[j] = ts.images[j], ts.images[i]
	ts.names[i], ts.names[j] = ts.names[j], ts.names[i]
	ts.name_len[i], ts.name_len[j] = ts.name_len[j], ts.name_len[i]
	return j
}

// Changes the tile size for every image (clamped). Pixels cut off by a smaller size stay hidden, so
// growing back restores them. Returns true if the size changed.
tileset_set_size :: proc(ts: ^Tileset, width, height: int) -> bool {
	w, h := clamp(width, IMAGE_MIN, IMAGE_MAX), clamp(height, IMAGE_MIN, IMAGE_MAX)
	if w == ts.width && h == ts.height {
		return false
	}
	ts.width, ts.height = w, h
	for i in 0 ..< ts.count {
		image4_resize(&ts.images[i], w, h)
	}
	return true
}

// File format (JSON): the tile size and the images in order, each with its name and its pixels in
// the Image4 packed form (two per byte, rows padded to a whole byte):
//   { "width": 2, "height": 2, "images": [ { "name": "grass", "bytes": [ 18, 52 ] } ] }
// Loading requires a size within IMAGE_MIN..IMAGE_MAX, at most TILESET_MAX_IMAGES images, names of
// 1..TILESET_NAME_MAX printable ASCII characters that are all different, and exactly
// height * ceil(width / 2) bytes per image. Unknown extra fields are ignored.
tileset_to_json :: proc(ts: ^Tileset, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n  \"width\": %d,\n  \"height\": %d,\n  \"images\": [", ts.width, ts.height)
	rb := image4_row_bytes(ts.width)
	for i in 0 ..< ts.count {
		strings.write_string(&b, i == 0 ? "\n" : ",\n")
		fmt.sbprintf(&b, "    {{\n      \"name\": \"%s\",\n      \"bytes\": [\n", escape_name(tileset_name(ts, i)))
		packed := image4_pack(&ts.images[i])
		for y in 0 ..< ts.height {
			strings.write_string(&b, "        ")
			for k in 0 ..< rb {
				if k > 0 {
					strings.write_string(&b, ", ")
				}
				fmt.sbprintf(&b, "%d", packed[y * rb + k])
			}
			if y + 1 < ts.height {
				strings.write_string(&b, ",\n")
			}
		}
		strings.write_string(&b, "\n      ]\n    }")
	}
	strings.write_string(&b, ts.count == 0 ? "]\n}\n" : "\n  ]\n}\n")
	return strings.to_string(b)
}

// Backslash and quote are the only printable ASCII characters JSON needs escaped.
@(private = "file")
escape_name :: proc(name: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i in 0 ..< len(name) {
		if name[i] == '"' || name[i] == '\\' {
			strings.write_byte(&b, '\\')
		}
		strings.write_byte(&b, name[i])
	}
	return strings.to_string(b)
}

// Replaces dst only if the whole file is valid. err == "" means success. Error text is on the temp
// allocator; use or copy it right away.
tileset_from_json :: proc(data: []u8, dst: ^Tileset) -> (err: string) {
	val, perr := json.parse(data, .JSON, true, context.temp_allocator)
	if perr != .None {
		return "not valid JSON"
	}
	defer json.destroy_value(val, context.temp_allocator)
	root, is_obj := val.(json.Object)
	if !is_obj {
		return "the top level must be an object"
	}
	w, w_ok := root["width"].(json.Integer)
	h, h_ok := root["height"].(json.Integer)
	if !w_ok || !h_ok {
		return `"width" and "height" must be whole numbers`
	}
	if w < IMAGE_MIN || w > IMAGE_MAX || h < IMAGE_MIN || h > IMAGE_MAX {
		return fmt.tprintf("tile size %d x %d is out of range (%d to %d)", w, h, IMAGE_MIN, IMAGE_MAX)
	}
	images: json.Array
	if v, present := root["images"]; present {
		arr, is_arr := v.(json.Array)
		if !is_arr {
			return `"images" must be a list`
		}
		images = arr
	}
	if len(images) > TILESET_MAX_IMAGES {
		return fmt.tprintf("%d images is more than the %d allowed", len(images), TILESET_MAX_IMAGES)
	}

	tmp := new(Tileset, context.temp_allocator) // built aside so a bad file changes nothing
	tileset_reset(tmp, int(w), int(h))
	rb := image4_row_bytes(int(w))
	for item, i in images {
		obj, is_item := item.(json.Object)
		if !is_item {
			return fmt.tprintf("image %d must be an object", i)
		}
		name, name_ok := obj["name"].(json.String)
		if !name_ok {
			return fmt.tprintf(`image %d: "name" must be text`, i)
		}
		switch tileset_check_name(tmp, -1, name) {
		case .Empty:
			return fmt.tprintf("image %d: the name is empty", i)
		case .Too_Long:
			return fmt.tprintf("image %d: the name is longer than %d characters", i, TILESET_NAME_MAX)
		case .Bad_Character:
			return fmt.tprintf("image %d: the name has a character other than printable ASCII", i)
		case .In_Use:
			return fmt.tprintf(`image %d: the name "%s" is used more than once`, i, name)
		case .None:
		}
		list, list_ok := obj["bytes"].(json.Array)
		if !list_ok {
			return fmt.tprintf(`image %d ("%s"): needs "bytes" (a list of whole numbers from 0 to 255)`, i, name)
		}
		packed := make([]u8, len(list), context.temp_allocator)
		for entry, k in list {
			n, is_int := entry.(json.Integer)
			if !is_int || n < 0 || n > 255 {
				return fmt.tprintf(`image %d ("%s"): "bytes" entry %d is not a whole number from 0 to 255`, i, name, k)
			}
			packed[k] = u8(n)
		}
		tmp.images[i] = image4_make(int(w), int(h))
		if !image4_unpack(&tmp.images[i], packed) {
			return fmt.tprintf(
				`image %d ("%s"): "bytes" has %d entries but a %d x %d image needs %d (%d per row)`,
				i,
				name,
				len(list),
				w,
				h,
				image4_packed_size(int(w), int(h)),
				rb,
			)
		}
		copy(tmp.names[i][:], name)
		tmp.name_len[i] = len(name)
		tmp.count += 1
	}
	dst^ = tmp^
	return ""
}
