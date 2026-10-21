package common

import "core:hash"

// A minimal PNG writer for pictures that are mostly flat colour (maps, tiles, palettes): no
// compression (stored deflate blocks), so the size is about one byte per pixel when the picture has
// at most 256 colours (written as an indexed image) and three otherwise. Nothing here is platform
// specific.

PNG_SIGNATURE :: [8]u8{0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A}

// `rgb` is width * height * 3 bytes, rows top to bottom. Returns the file's bytes, or nil for an
// empty picture or a buffer of the wrong size.
png_encode_rgb :: proc(rgb: []u8, width, height: int, allocator := context.temp_allocator) -> []u8 {
	if width < 1 || height < 1 || len(rgb) != width * height * 3 {
		return nil
	}
	// At most 256 distinct colours: an indexed image.
	index_of := make(map[u32]u8, 256, context.temp_allocator)
	colors := make([dynamic]u32, context.temp_allocator)
	indexed := true
	for i in 0 ..< width * height {
		key := u32(rgb[i * 3]) << 16 | u32(rgb[i * 3 + 1]) << 8 | u32(rgb[i * 3 + 2])
		if key not_in index_of {
			if len(colors) == 256 {
				indexed = false
				break
			}
			index_of[key] = u8(len(colors))
			append(&colors, key)
		}
	}
	bpp := indexed ? 1 : 3
	raw := make([]u8, height * (1 + width * bpp), context.temp_allocator)
	for y in 0 ..< height {
		row := y * (1 + width * bpp)
		raw[row] = 0 // filter: none
		for x in 0 ..< width {
			p := (y * width + x) * 3
			if indexed {
				raw[row + 1 + x] = index_of[u32(rgb[p]) << 16 | u32(rgb[p + 1]) << 8 | u32(rgb[p + 2])]
			} else {
				copy(raw[row + 1 + x * 3:row + 4 + x * 3], rgb[p:p + 3])
			}
		}
	}
	out := make([dynamic]u8, allocator)
	sig := PNG_SIGNATURE
	append(&out, ..sig[:])
	ihdr: [13]u8
	put_u32(ihdr[0:4], u32(width))
	put_u32(ihdr[4:8], u32(height))
	ihdr[8] = 8 // bit depth
	ihdr[9] = indexed ? 3 : 2 // colour type: indexed / truecolour
	png_chunk(&out, "IHDR", ihdr[:])
	if indexed {
		plte := make([]u8, len(colors) * 3, context.temp_allocator)
		for c, i in colors {
			plte[i * 3], plte[i * 3 + 1], plte[i * 3 + 2] = u8(c >> 16), u8(c >> 8), u8(c)
		}
		png_chunk(&out, "PLTE", plte)
	}
	// zlib: header, stored blocks of at most 65535 bytes, Adler-32 of the data.
	z := make([dynamic]u8, context.temp_allocator)
	append(&z, 0x78, 0x01)
	for start := 0; start < len(raw); start += 65535 {
		n := min(65535, len(raw) - start)
		final: u8 = start + n >= len(raw) ? 1 : 0
		append(&z, final, u8(n), u8(n >> 8), u8(~n), u8((~n) >> 8))
		append(&z, ..raw[start:start + n])
	}
	sum: [4]u8
	put_u32(sum[:], hash.adler32(raw))
	append(&z, ..sum[:])
	png_chunk(&out, "IDAT", z[:])
	png_chunk(&out, "IEND", nil)
	return out[:]
}

@(private = "file")
put_u32 :: proc(dst: []u8, v: u32) {
	dst[0], dst[1], dst[2], dst[3] = u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v)
}

@(private = "file")
png_chunk :: proc(out: ^[dynamic]u8, kind: string, data: []u8) {
	head: [4]u8
	put_u32(head[:], u32(len(data)))
	append(out, ..head[:])
	body := make([]u8, 4 + len(data), context.temp_allocator)
	copy(body[0:4], kind)
	copy(body[4:], data)
	append(out, ..body)
	put_u32(head[:], hash.crc32(body))
	append(out, ..head[:])
}
