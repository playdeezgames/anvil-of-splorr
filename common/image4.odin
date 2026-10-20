package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// A 4 bit per pixel image: every pixel is an index 0..15 into a Palette (palette.odin), so the
// colours live in the palette, not in the image. The image editor edits one.
//
// Like Bitmap, `pixels` is a fixed IMAGE_MAX x IMAGE_MAX store of which only the top-left
// width x height region is the image; shrinking keeps the hidden pixels so growing back restores
// them. Files hold only the visible region.

IMAGE_MIN :: 1
IMAGE_MAX :: 64
IMAGE_COLORS :: PALETTE_SIZE // 16

Image4 :: struct {
	width, height: int,
	pixels:        [IMAGE_MAX][IMAGE_MAX]u8, // [y][x], each 0..15
}

image4_make :: proc(width, height: int) -> (img: Image4) {
	img.width = clamp(width, IMAGE_MIN, IMAGE_MAX)
	img.height = clamp(height, IMAGE_MIN, IMAGE_MAX)
	return
}

// Pixels outside the visible region read as colour 0.
image4_get :: proc(img: ^Image4, x, y: int) -> u8 {
	if x < 0 || y < 0 || x >= img.width || y >= img.height {
		return 0
	}
	return img.pixels[y][x]
}

// The colour is clamped to 0..15. Returns true if the pixel changed; out-of-range coordinates
// change nothing.
image4_set :: proc(img: ^Image4, x, y: int, color: int) -> bool {
	if x < 0 || y < 0 || x >= img.width || y >= img.height {
		return false
	}
	c := u8(clamp(color, 0, IMAGE_COLORS - 1))
	if img.pixels[y][x] == c {
		return false
	}
	img.pixels[y][x] = c
	return true
}

// Sizes are clamped to IMAGE_MIN..IMAGE_MAX. Returns true if the size changed.
image4_resize :: proc(img: ^Image4, width, height: int) -> bool {
	w, h := clamp(width, IMAGE_MIN, IMAGE_MAX), clamp(height, IMAGE_MIN, IMAGE_MAX)
	if w == img.width && h == img.height {
		return false
	}
	img.width, img.height = w, h
	return true
}

// True if both images have the same size and the same visible pixels (hidden pixels are ignored).
image4_visible_equal :: proc(a, b: ^Image4) -> bool {
	if a.width != b.width || a.height != b.height {
		return false
	}
	for y in 0 ..< a.height {
		for x in 0 ..< a.width {
			if a.pixels[y][x] != b.pixels[y][x] {
				return false
			}
		}
	}
	return true
}

// Mirrors the visible pixels left to right. Hidden pixels are untouched. Returns true if anything
// changed (a symmetric image flips to itself).
image4_flip_horizontal :: proc(img: ^Image4) -> (changed: bool) {
	for y in 0 ..< img.height {
		for x in 0 ..< img.width / 2 {
			a, b := &img.pixels[y][x], &img.pixels[y][img.width - 1 - x]
			if a^ != b^ {
				a^, b^ = b^, a^
				changed = true
			}
		}
	}
	return
}

// Mirrors the visible pixels top to bottom. Hidden pixels are untouched. Returns true if anything
// changed.
image4_flip_vertical :: proc(img: ^Image4) -> (changed: bool) {
	for y in 0 ..< img.height / 2 {
		for x in 0 ..< img.width {
			a, b := &img.pixels[y][x], &img.pixels[img.height - 1 - y][x]
			if a^ != b^ {
				a^, b^ = b^, a^
				changed = true
			}
		}
	}
	return
}

// Quarter turns of the visible pixels. The width and height swap (both stay within 1..IMAGE_MAX,
// so a turn always fits). Every pixel of the new visible area is rewritten, so hidden pixels that
// happened to sit there are replaced; pixels outside it are untouched. Return true if the picture
// changed (a square, symmetric one can turn into itself).

// Clockwise: the top row becomes the right column.
image4_rotate_right :: proc(img: ^Image4) -> bool {
	old := img^
	img.width, img.height = old.height, old.width
	for ny in 0 ..< img.height {
		for nx in 0 ..< img.width {
			img.pixels[ny][nx] = old.pixels[old.height - 1 - nx][ny]
		}
	}
	return !image4_visible_equal(&old, img)
}

// Counter-clockwise: the top row becomes the left column.
image4_rotate_left :: proc(img: ^Image4) -> bool {
	old := img^
	img.width, img.height = old.height, old.width
	for ny in 0 ..< img.height {
		for nx in 0 ..< img.width {
			img.pixels[ny][nx] = old.pixels[nx][old.width - 1 - ny]
		}
	}
	return !image4_visible_equal(&old, img)
}

// Half a turn: same size, every pixel moves to the opposite corner position.
image4_rotate_180 :: proc(img: ^Image4) -> bool {
	old := img^
	image4_flip_horizontal(img)
	image4_flip_vertical(img)
	return !image4_visible_equal(&old, img)
}

// Sets every visible pixel to `color` (clamped to 0..15). Returns true if any pixel changed.
image4_clear :: proc(img: ^Image4, color: int) -> (changed: bool) {
	c := u8(clamp(color, 0, IMAGE_COLORS - 1))
	for y in 0 ..< img.height {
		for x in 0 ..< img.width {
			if img.pixels[y][x] != c {
				img.pixels[y][x] = c
				changed = true
			}
		}
	}
	return
}

// Changes every visible pixel of colour `from` to colour `to`. Returns true if any pixel changed.
image4_replace_color :: proc(img: ^Image4, from, to: int) -> (changed: bool) {
	f, t := u8(clamp(from, 0, IMAGE_COLORS - 1)), u8(clamp(to, 0, IMAGE_COLORS - 1))
	if f == t {
		return false
	}
	for y in 0 ..< img.height {
		for x in 0 ..< img.width {
			if img.pixels[y][x] == f {
				img.pixels[y][x] = t
				changed = true
			}
		}
	}
	return
}

// Paints the connected region of same-coloured pixels around (x, y) with `color`. Pixels connect
// along rows and columns, not diagonally. Returns true if anything changed (not if the region is
// already that colour, or (x, y) is outside the image).
image4_flood_fill :: proc(img: ^Image4, x, y: int, color: int) -> bool {
	if x < 0 || y < 0 || x >= img.width || y >= img.height {
		return false
	}
	c := u8(clamp(color, 0, IMAGE_COLORS - 1))
	target := img.pixels[y][x]
	if target == c {
		return false
	}
	// Each pixel is recoloured when it is pushed, so it is pushed at most once: the stack never
	// needs more than one entry per pixel.
	stack: [IMAGE_MAX * IMAGE_MAX][2]u8
	n := 0
	img.pixels[y][x] = c
	stack[n] = {u8(x), u8(y)}
	n += 1
	for n > 0 {
		n -= 1
		px, py := int(stack[n][0]), int(stack[n][1])
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			nx, ny := px + d.x, py + d.y
			if nx >= 0 && ny >= 0 && nx < img.width && ny < img.height && img.pixels[ny][nx] == target {
				img.pixels[ny][nx] = c
				stack[n] = {u8(nx), u8(ny)}
				n += 1
			}
		}
	}
	return true
}

// --- Packed form ---
//
// Two pixels per byte, a pixel row at a time. Every row is padded to a whole number of bytes
// (widths 1..2 take 1 byte per row, 3..4 take 2, and so on). Within a row the left pixel of each
// pair is the high nibble and the right pixel the low nibble; for an odd width the last byte's low
// nibble is padding, 0 on write and ignored on read. Rows follow each other top to bottom, so an
// image is height * image4_row_bytes(width) bytes.

image4_row_bytes :: proc(width: int) -> int {
	return (width + 1) / 2
}

image4_packed_size :: proc(width, height: int) -> int {
	return image4_row_bytes(width) * height
}

image4_pack :: proc(img: ^Image4, allocator := context.temp_allocator) -> []u8 {
	rb := image4_row_bytes(img.width)
	out := make([]u8, rb * img.height, allocator)
	for y in 0 ..< img.height {
		for x in 0 ..< img.width {
			shift: uint = x % 2 == 0 ? 4 : 0
			out[y * rb + x / 2] |= (img.pixels[y][x] & 0x0F) << shift
		}
	}
	return out
}

// Replaces the visible pixels of img (whose size is already set) from packed bytes. Returns false,
// changing nothing, if bytes is not exactly the packed size.
image4_unpack :: proc(img: ^Image4, bytes: []u8) -> bool {
	rb := image4_row_bytes(img.width)
	if len(bytes) != rb * img.height {
		return false
	}
	for y in 0 ..< img.height {
		for x in 0 ..< img.width {
			shift: uint = x % 2 == 0 ? 4 : 0
			img.pixels[y][x] = (bytes[y * rb + x / 2] >> shift) & 0x0F
		}
	}
	return true
}

// File format (JSON), pixels in the packed form above, one pixel row per line:
//   { "width": 3, "height": 2, "bytes": [ 18, 48,    // row 0: pixels 1 2 3 -> 0x12, 0x30
//                                         0, 240 ] } // row 1: pixels 0 0 15 -> 0x00, 0xF0
// Loading requires sizes within IMAGE_MIN..IMAGE_MAX and exactly height * ceil(width / 2) bytes
// (each 0..255); padding nibbles are ignored. Unknown extra fields are ignored. The palette is
// not part of the file: the colours come from whichever palette the image is used with.
image4_to_json :: proc(img: ^Image4, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n  \"width\": %d,\n  \"height\": %d,\n  \"bytes\": [\n", img.width, img.height)
	packed := image4_pack(img)
	rb := image4_row_bytes(img.width)
	for y in 0 ..< img.height {
		strings.write_string(&b, "    ")
		for i in 0 ..< rb {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			fmt.sbprintf(&b, "%d", packed[y * rb + i])
		}
		if y + 1 < img.height {
			strings.write_string(&b, ",\n")
		}
	}
	strings.write_string(&b, "\n  ]\n}\n")
	return strings.to_string(b)
}

// err == "" means success. Error text is on the temp allocator; use or copy it right away.
image4_from_json :: proc(data: []u8) -> (img: Image4, err: string) {
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
	if w < IMAGE_MIN || w > IMAGE_MAX || h < IMAGE_MIN || h > IMAGE_MAX {
		return {}, fmt.tprintf("size %d x %d is out of range (%d to %d)", w, h, IMAGE_MIN, IMAGE_MAX)
	}
	list, list_ok := root["bytes"].(json.Array)
	if !list_ok {
		return {}, `needs "bytes" (a list of whole numbers from 0 to 255)`
	}
	packed := make([]u8, len(list), context.temp_allocator)
	for item, i in list {
		n, is_int := item.(json.Integer)
		if !is_int || n < 0 || n > 255 {
			return {}, fmt.tprintf(`"bytes" entry %d is not a whole number from 0 to 255`, i)
		}
		packed[i] = u8(n)
	}
	img = image4_make(int(w), int(h))
	if !image4_unpack(&img, packed) {
		return {}, fmt.tprintf(
			`"bytes" has %d entries but a %d x %d image needs %d (%d per row)`,
			len(list),
			w,
			h,
			image4_packed_size(int(w), int(h)),
			image4_row_bytes(int(w)),
		)
	}
	return img, ""
}
