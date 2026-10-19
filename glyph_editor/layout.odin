package glyph_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: struct {
	x, y, w, h: int,
}

CANVAS :: Rect{8, 8, 140, 140} // the area the bitmap is scaled into, top-left aligned

BANNER :: Rect{154, 5, 162, 11}
INFO_X :: 154
INFO_Y :: 19 // "CURSOR: 3,4 ON *"

// Setup rows, top to bottom: width, height, foreground, background. The marker ">" sits left of
// the row's label while Setup is the active mode.
ROW_MARKER_X :: 149
ROW_LABEL_X :: 154
ROW_VALUE_X :: 214
WIDTH_MINUS :: Rect{182, 28, 12, 10}
WIDTH_PLUS :: Rect{196, 28, 12, 10}
HEIGHT_MINUS :: Rect{182, 40, 12, 10}
HEIGHT_PLUS :: Rect{196, 40, 12, 10}
FG_CHIP :: Rect{182, 52, 26, 8}
BG_CHIP :: Rect{182, 64, 26, 8}

// The palette, one row of 16 swatches: left click = foreground, right click = background.
SWATCH_W :: 10
PALETTE_X :: 154
PALETTE_Y :: 74

// 3 x 3 tiled preview. The frame holds an inner area; tiles are scaled by a whole number to fit
// and anything that does not fit is clipped (and flagged).
PREVIEW_FRAME :: Rect{154, 86, 64, 64}
PREVIEW_INNER :: Rect{155, 87, 62, 62}
CLIPPED_X :: 222
CLIPPED_Y :: 138

SAVE_BUTTON :: Rect{240, 86, 36, 12}
LOAD_BUTTON :: Rect{240, 102, 36, 12}
MENU_BUTTON :: Rect{240, 118, 36, 12}

HELP_Y :: 152 // up to four lines at the font's pitch
MAX_HELP_LINES :: 4

TILES :: 3

rect_contains :: proc(r: Rect, x, y: int) -> bool {
	return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

swatch_rect :: proc(i: int) -> Rect {
	return Rect{PALETTE_X + i * SWATCH_W, PALETTE_Y, SWATCH_W, SWATCH_W}
}

swatch_at :: proc(x, y: int) -> (i: int, ok: bool) {
	for i in 0 ..< cm.PALETTE_SIZE {
		if rect_contains(swatch_rect(i), x, y) {
			return i, true
		}
	}
	return 0, false
}

// Pixels per bitmap pixel so the whole bitmap fits in CANVAS (at least 1).
cell_size :: proc(width, height: int) -> int {
	return max(1, min(CANVAS.w / width, CANVAS.h / height))
}

// The bitmap pixel under a logical position, if any.
cell_at :: proc(width, height, px, py: int) -> (x, y: int, ok: bool) {
	c := cell_size(width, height)
	cx, cy := px - CANVAS.x, py - CANVAS.y
	if cx < 0 || cy < 0 {
		return 0, 0, false
	}
	x, y = cx / c, cy / c
	return x, y, x < width && y < height
}

cell_rect :: proc(width, height, x, y: int) -> Rect {
	c := cell_size(width, height)
	return Rect{CANVAS.x + x * c, CANVAS.y + y * c, c, c}
}

// Whole-number scale for the 3 x 3 preview, at least 1.
preview_scale :: proc(width, height: int) -> int {
	return max(1, min(PREVIEW_INNER.w / (TILES * width), PREVIEW_INNER.h / (TILES * height)))
}

// True if the 3 x 3 tiling does not fit the preview area at its scale.
preview_clipped :: proc(width, height: int) -> bool {
	s := preview_scale(width, height)
	return TILES * width * s > PREVIEW_INNER.w || TILES * height * s > PREVIEW_INNER.h
}

intersect :: proc(a, b: Rect) -> (r: Rect, ok: bool) {
	x0, y0 := max(a.x, b.x), max(a.y, b.y)
	x1, y1 := min(a.x + a.w, b.x + b.w), min(a.y + a.h, b.y + b.h)
	if x1 <= x0 || y1 <= y0 {
		return {}, false
	}
	return Rect{x0, y0, x1 - x0, y1 - y0}, true
}
