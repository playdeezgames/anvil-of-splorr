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

// True if both bitmaps have the same size and the same visible pixels (hidden bits are ignored).
bitmap_visible_equal :: proc(a, b: ^Bitmap) -> bool {
	if a.width != b.width || a.height != b.height {
		return false
	}
	for y in 0 ..< a.height {
		for x in 0 ..< a.width {
			if a.bits[y][x] != b.bits[y][x] {
				return false
			}
		}
	}
	return true
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

// --- Packed form ---
//
// One bit per pixel, a pixel row at a time. Every row is padded to a whole number of bytes (widths
// 1..8 take 1 byte per row, 9..16 take 2, and so on). Within a row the leftmost pixel is the top
// bit (0x80) of the first byte and the padding bits at the right of the last byte are 0. Rows
// follow each other top to bottom, so a bitmap is height * bitmap_row_bytes(width) bytes.

bitmap_row_bytes :: proc(width: int) -> int {
	return (width + 7) / 8
}

bitmap_packed_size :: proc(width, height: int) -> int {
	return bitmap_row_bytes(width) * height
}

// The visible pixels in packed form.
bitmap_pack :: proc(g: ^Bitmap, allocator := context.temp_allocator) -> []u8 {
	rb := bitmap_row_bytes(g.width)
	out := make([]u8, rb * g.height, allocator)
	for y in 0 ..< g.height {
		for x in 0 ..< g.width {
			if g.bits[y][x] {
				out[y * rb + x / 8] |= 0x80 >> uint(x % 8)
			}
		}
	}
	return out
}

// Replaces the visible pixels of g (whose size is already set) from packed bytes. Padding bits are
// ignored. Returns false, changing nothing, if bytes is not exactly the packed size.
bitmap_unpack :: proc(g: ^Bitmap, bytes: []u8) -> bool {
	rb := bitmap_row_bytes(g.width)
	if len(bytes) != rb * g.height {
		return false
	}
	for y in 0 ..< g.height {
		for x in 0 ..< g.width {
			g.bits[y][x] = bytes[y * rb + x / 8] & (0x80 >> uint(x % 8)) != 0
		}
	}
	return true
}

// Writes the packed bytes as a JSON list body, one pixel row per line at `indent`, bytes separated
// by ", " and rows by ",". No newline after the last row.
bitmap_write_bytes :: proc(b: ^strings.Builder, g: ^Bitmap, indent: string) {
	packed := bitmap_pack(g)
	rb := bitmap_row_bytes(g.width)
	for y in 0 ..< g.height {
		strings.write_string(b, indent)
		for i in 0 ..< rb {
			if i > 0 {
				strings.write_string(b, ", ")
			}
			fmt.sbprintf(b, "%d", packed[y * rb + i])
		}
		if y + 1 < g.height {
			strings.write_string(b, ",\n")
		}
	}
}

// Legacy: fills g (sized width x height, cleared) from rows of "#" and "." characters. Only used
// to read files written before the packed form existed. Returns an error message, or "".
bitmap_read_rows :: proc(g: ^Bitmap, rows: json.Array, width, height: int) -> string {
	if len(rows) != height {
		return fmt.tprintf(`"rows" has %d entries but the height is %d`, len(rows), height)
	}
	for row, y in rows {
		text, is_str := row.(json.String)
		if !is_str {
			return fmt.tprintf("row %d is not a string", y)
		}
		if len(text) != width {
			return fmt.tprintf("row %d has %d characters but the width is %d", y, len(text), width)
		}
		for i in 0 ..< len(text) {
			switch text[i] {
			case '#':
				g.bits[y][i] = true
			case '.':
			case:
				return fmt.tprintf(`row %d: only "#" and "." are allowed`, y)
			}
		}
	}
	return ""
}

// Fills g (sized width x height, cleared) from a JSON object holding "bytes" (the packed form, a
// list of whole numbers 0..255) or, for old files, "rows". Returns an error message, or "".
// Error text is on the temp allocator.
bitmap_read_pixels :: proc(g: ^Bitmap, obj: json.Object, width, height: int) -> string {
	if list, ok := obj["bytes"].(json.Array); ok {
		packed := make([]u8, len(list), context.temp_allocator)
		for item, i in list {
			n, is_int := item.(json.Integer)
			if !is_int || n < 0 || n > 255 {
				return fmt.tprintf(`"bytes" entry %d is not a whole number from 0 to 255`, i)
			}
			packed[i] = u8(n)
		}
		if !bitmap_unpack(g, packed) {
			return fmt.tprintf(
				`"bytes" has %d entries but a %d x %d image needs %d (%d per row)`,
				len(list),
				width,
				height,
				bitmap_packed_size(width, height),
				bitmap_row_bytes(width),
			)
		}
		return ""
	}
	if _, present := obj["bytes"]; present {
		return `"bytes" must be a list of whole numbers from 0 to 255`
	}
	if rows, ok := obj["rows"].(json.Array); ok {
		return bitmap_read_rows(g, rows, width, height)
	}
	return `needs "bytes" (a list of whole numbers from 0 to 255)`
}

// File format (JSON), pixels in the packed form described above, one pixel row per line:
//   { "width": 3, "height": 2, "bytes": [ 160, 64 ] }   // "#.#" is 10100000b = 160, ".#." is 64
//   { "width": 10, "height": 1, "bytes": [ 255, 192 ] } // ten set pixels: 11111111b, 11000000b
// Loading requires sizes within BITMAP_MIN..BITMAP_MAX and exactly height * ceil(width / 8) bytes;
// padding bits are ignored. Unknown extra fields are ignored. Files from before this format, with
// "rows" of "#" and "." strings instead of "bytes", can still be read but are never written.
bitmap_to_json :: proc(g: ^Bitmap, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n  \"width\": %d,\n  \"height\": %d,\n  \"bytes\": [\n", g.width, g.height)
	bitmap_write_bytes(&b, g, "    ")
	strings.write_string(&b, "\n  ]\n}\n")
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
	g = bitmap_make(int(w), int(h))
	if e := bitmap_read_pixels(&g, root, int(w), int(h)); e != "" {
		return {}, e
	}
	return g, ""
}
