package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// A 1 bit per pixel image (the glyph editor edits one; the font editor will hold many).
//
// `bits` is a fixed BITMAP_MAX x BITMAP_MAX store; only the top-left width x height region is the
// image. Shrinking keeps the hidden bits, so growing back restores them. Saved files contain
// only the visible region.

BITMAP_MIN :: 1
BITMAP_MAX :: 64

Bitmap :: struct {
	width, height: int,
	bits:          [BITMAP_MAX][BITMAP_MAX]bool, // [y][x]
}

bitmap_make :: proc(width, height: int) -> (g: Bitmap) {
	g.width = clamp(width, BITMAP_MIN, BITMAP_MAX)
	g.height = clamp(height, BITMAP_MIN, BITMAP_MAX)
	return
}

// Pixels outside the visible region read as off.
bitmap_get :: proc(g: ^Bitmap, x, y: int) -> bool {
	if x < 0 || y < 0 || x >= g.width || y >= g.height {
		return false
	}
	return g.bits[y][x]
}

// Returns true if the pixel changed. Out-of-range coordinates change nothing.
bitmap_set :: proc(g: ^Bitmap, x, y: int, on: bool) -> bool {
	if x < 0 || y < 0 || x >= g.width || y >= g.height || g.bits[y][x] == on {
		return false
	}
	g.bits[y][x] = on
	return true
}

// Flips a pixel and returns its new value (false if out of range).
bitmap_toggle :: proc(g: ^Bitmap, x, y: int) -> bool {
	if x < 0 || y < 0 || x >= g.width || y >= g.height {
		return false
	}
	g.bits[y][x] = !g.bits[y][x]
	return g.bits[y][x]
}

// Sizes are clamped to BITMAP_MIN..BITMAP_MAX. Returns true if the size changed.
bitmap_resize :: proc(g: ^Bitmap, width, height: int) -> bool {
	w, h := clamp(width, BITMAP_MIN, BITMAP_MAX), clamp(height, BITMAP_MIN, BITMAP_MAX)
	if w == g.width && h == g.height {
		return false
	}
	g.width, g.height = w, h
	return true
}

// File format (JSON), '#' is a set pixel and '.' a clear one, one string per row:
//   { "width": 3, "height": 2, "rows": [ "#.#", ".#." ] }
// Loading requires sizes within BITMAP_MIN..BITMAP_MAX and exactly `height` rows of `width`
// characters, nothing but '#' and '.'. Unknown extra fields are ignored.
bitmap_to_json :: proc(g: ^Bitmap, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n  \"width\": %d,\n  \"height\": %d,\n  \"rows\": [\n", g.width, g.height)
	for y in 0 ..< g.height {
		strings.write_string(&b, "    \"")
		for x in 0 ..< g.width {
			strings.write_byte(&b, g.bits[y][x] ? '#' : '.')
		}
		strings.write_string(&b, y + 1 < g.height ? "\",\n" : "\"\n")
	}
	strings.write_string(&b, "  ]\n}\n")
	return strings.to_string(b)
}

// err == "" means success. Error text is on the temp allocator; use or copy it right away.
bitmap_from_json :: proc(data: []u8) -> (g: Bitmap, err: string) {
	val, perr := json.parse(data, .JSON, true, context.temp_allocator)
	if perr != .None {
		return {}, "not valid JSON"
	}
	defer json.destroy_value(val, context.temp_allocator)
	root, is_obj := val.(json.Object)
	if !is_obj {
		return {}, "the top level must be an object"
	}
	w, w_ok := root["width"].(json.Integer)
	h, h_ok := root["height"].(json.Integer)
	if !w_ok || !h_ok {
		return {}, `"width" and "height" must be whole numbers`
	}
	if w < BITMAP_MIN || w > BITMAP_MAX || h < BITMAP_MIN || h > BITMAP_MAX {
		return {}, fmt.tprintf("size %d x %d is out of range (%d to %d)", w, h, BITMAP_MIN, BITMAP_MAX)
	}
	rows, rows_ok := root["rows"].(json.Array)
	if !rows_ok {
		return {}, `"rows" must be a list of strings`
	}
	if len(rows) != int(h) {
		return {}, fmt.tprintf(`"rows" has %d entries but "height" is %d`, len(rows), h)
	}
	g = bitmap_make(int(w), int(h))
	for row, y in rows {
		text, is_str := row.(json.String)
		if !is_str {
			return {}, fmt.tprintf("row %d is not a string", y)
		}
		if len(text) != int(w) {
			return {}, fmt.tprintf("row %d has %d characters but \"width\" is %d", y, len(text), w)
		}
		for i in 0 ..< len(text) {
			switch text[i] {
			case '#':
				g.bits[y][i] = true
			case '.':
			case:
				return {}, fmt.tprintf(`row %d: only "#" and "." are allowed`, y)
			}
		}
	}
	return g, ""
}
