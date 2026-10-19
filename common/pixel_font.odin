package common

import "core:encoding/json"
import "core:fmt"
import "core:strconv"
import "core:strings"

// A bitmap font: up to 256 glyphs (character codes 0..255), every glyph the same height and each
// with its own width. Glyphs are optional; codes 32..127 are the ones general text needs.
//
// A Pixel_Font is about 1 MB. Never return or copy one by value on the stack: create it with
// new() or as a global, and use the in-place procs below.

PIXEL_FONT_CHARS :: 256
PRINTABLE_FIRST :: 32
PRINTABLE_LAST :: 127
PRINTABLE_COUNT :: PRINTABLE_LAST - PRINTABLE_FIRST + 1
DEFAULT_FONT_HEIGHT :: 8
DEFAULT_GLYPH_WIDTH :: 8

Pixel_Font :: struct {
	height:  int,
	present: [PIXEL_FONT_CHARS]bool,
	// glyphs[c].height always equals height. A glyph that is not present keeps its (blank or
	// hidden) pixels and width, so removing and re-adding one restores it.
	glyphs:  [PIXEL_FONT_CHARS]Bitmap,
}

// Empties the font in place: no glyphs present, every width DEFAULT_GLYPH_WIDTH.
pixel_font_reset :: proc(f: ^Pixel_Font, height := DEFAULT_FONT_HEIGHT) {
	f^ = {}
	f.height = clamp(height, BITMAP_MIN, BITMAP_MAX)
	for &g in f.glyphs {
		g.width = DEFAULT_GLYPH_WIDTH
		g.height = f.height
	}
}

// nil for a code outside 0..255.
pixel_font_glyph :: proc(f: ^Pixel_Font, code: int) -> ^Bitmap {
	if code < 0 || code >= PIXEL_FONT_CHARS {
		return nil
	}
	return &f.glyphs[code]
}

// Changes the height of every glyph. Clamped to BITMAP_MIN..BITMAP_MAX; returns true if it changed.
// Rows beyond a smaller height are kept hidden, so growing back restores them.
pixel_font_set_height :: proc(f: ^Pixel_Font, height: int) -> bool {
	h := clamp(height, BITMAP_MIN, BITMAP_MAX)
	if h == f.height {
		return false
	}
	f.height = h
	for &g in f.glyphs {
		bitmap_resize(&g, g.width, h)
	}
	return true
}

// Returns true if the glyph's presence changed.
pixel_font_set_present :: proc(f: ^Pixel_Font, code: int, present: bool) -> bool {
	if code < 0 || code >= PIXEL_FONT_CHARS || f.present[code] == present {
		return false
	}
	f.present[code] = present
	return true
}

// Returns true if the width changed (clamped to BITMAP_MIN..BITMAP_MAX).
pixel_font_set_width :: proc(f: ^Pixel_Font, code, width: int) -> bool {
	g := pixel_font_glyph(f, code)
	return g != nil && bitmap_resize(g, width, f.height)
}

// Removes a glyph for good: not present, every pixel cleared (including hidden ones) and the width
// back to the default. Unlike pixel_font_set_present(false), nothing is kept. Returns true if
// the glyph was present.
pixel_font_delete :: proc(f: ^Pixel_Font, code: int) -> bool {
	g := pixel_font_glyph(f, code)
	if g == nil {
		return false
	}
	was := f.present[code]
	g^ = {}
	g.width, g.height = DEFAULT_GLYPH_WIDTH, f.height
	f.present[code] = false
	return was
}

// Copies a present glyph into dst. Returns false (leaving dst alone) if there is no such glyph.
pixel_font_copy_glyph :: proc(f: ^Pixel_Font, code: int, dst: ^Bitmap) -> bool {
	if code < 0 || code >= PIXEL_FONT_CHARS || !f.present[code] {
		return false
	}
	dst^ = f.glyphs[code]
	return true
}

// Makes `code` a copy of src (creating it if absent). src may come from a time when the font was
// a different height: it is fitted to the current height first. Returns true if anything visible
// changed (presence, width or pixels).
pixel_font_paste_glyph :: proc(f: ^Pixel_Font, code: int, src: ^Bitmap) -> bool {
	if code < 0 || code >= PIXEL_FONT_CHARS {
		return false
	}
	fitted := src^
	bitmap_resize(&fitted, fitted.width, f.height)
	changed := !f.present[code] || !bitmap_visible_equal(&f.glyphs[code], &fitted)
	f.glyphs[code] = fitted
	f.present[code] = true
	return changed
}

// How many of the printable characters (32..127) are defined, out of PRINTABLE_COUNT.
pixel_font_coverage :: proc(f: ^Pixel_Font) -> (defined, total: int) {
	for c in PRINTABLE_FIRST ..= PRINTABLE_LAST {
		if f.present[c] {
			defined += 1
		}
	}
	return defined, PRINTABLE_COUNT
}

// Width in pixels of text drawn with the font. Characters without a glyph take no space.
pixel_font_text_width :: proc(f: ^Pixel_Font, text: string) -> (w: int) {
	for i in 0 ..< len(text) {
		c := int(text[i])
		if f.present[c] {
			w += f.glyphs[c].width
		}
	}
	return
}

// File format (JSON). Only present glyphs are listed, keyed by character code:
//   { "height": 8, "glyphs": { "65": { "width": 3, "rows": [ "...", ... ] }, ... } }
// Rows follow the Bitmap file format ('#' set, '.' clear). Loading requires a height of
// BITMAP_MIN..BITMAP_MAX, codes 0..255, widths in the same range, and exactly `height` rows of
// `width` characters per glyph. Unknown extra fields are ignored.
pixel_font_to_json :: proc(f: ^Pixel_Font, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\n  \"height\": %d,\n  \"glyphs\": {{", f.height)
	first := true
	for c in 0 ..< PIXEL_FONT_CHARS {
		if !f.present[c] {
			continue
		}
		g := &f.glyphs[c]
		strings.write_string(&b, first ? "\n" : ",\n")
		first = false
		fmt.sbprintf(&b, "    \"%d\": {{\n      \"width\": %d,\n      \"rows\": [\n", c, g.width)
		bitmap_write_rows(&b, g, "        ")
		strings.write_string(&b, "\n      ]\n    }")
	}
	strings.write_string(&b, first ? "}\n}\n" : "\n  }\n}\n")
	return strings.to_string(b)
}

// Replaces dst only if the whole file is valid. err == "" means success. Error text is on the
// temp allocator; use or copy it right away.
pixel_font_from_json :: proc(data: []u8, dst: ^Pixel_Font) -> (err: string) {
	val, perr := json.parse(data, .JSON, true, context.temp_allocator)
	if perr != .None {
		return "not valid JSON"
	}
	defer json.destroy_value(val, context.temp_allocator)
	root, is_obj := val.(json.Object)
	if !is_obj {
		return "the top level must be an object"
	}
	h, h_ok := root["height"].(json.Integer)
	if !h_ok || h < BITMAP_MIN || h > BITMAP_MAX {
		return fmt.tprintf(`"height" must be a whole number from %d to %d`, BITMAP_MIN, BITMAP_MAX)
	}
	glyphs, g_ok := root["glyphs"].(json.Object)
	if !g_ok {
		if _, missing := root["glyphs"]; missing {
			return `"glyphs" must be an object`
		}
	}

	tmp := new(Pixel_Font, context.temp_allocator) // built aside so a bad file changes nothing
	pixel_font_reset(tmp, int(h))
	for key, entry in glyphs {
		code, code_ok := strconv.parse_int(key)
		if !code_ok || code < 0 || code >= PIXEL_FONT_CHARS {
			return fmt.tprintf(`glyph key "%s" is not a character code from 0 to 255`, key)
		}
		obj, is_glyph := entry.(json.Object)
		if !is_glyph {
			return fmt.tprintf("glyph %d must be an object", code)
		}
		w, w_ok := obj["width"].(json.Integer)
		if !w_ok || w < BITMAP_MIN || w > BITMAP_MAX {
			return fmt.tprintf(`glyph %d: "width" must be a whole number from %d to %d`, code, BITMAP_MIN, BITMAP_MAX)
		}
		rows, rows_ok := obj["rows"].(json.Array)
		if !rows_ok {
			return fmt.tprintf(`glyph %d: "rows" must be a list of strings`, code)
		}
		tmp.glyphs[code] = bitmap_make(int(w), int(h))
		if e := bitmap_read_rows(&tmp.glyphs[code], rows, int(w), int(h)); e != "" {
			return fmt.tprintf("glyph %d: %s", code, e)
		}
		tmp.present[code] = true
	}
	dst^ = tmp^
	return ""
}
