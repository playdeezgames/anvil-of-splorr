package glyph_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: struct {
	x, y, w, h: int,
}

CANVAS :: Rect{8, 8, 140, 140} // the area the bitmap is scaled into, top-left aligned

BANNER :: Rect{154, 5, 162, 11}
INFO_X :: 154
INFO_Y :: 22 // "CURSOR: 3,4" then "PIXEL: ON"

// Mouse size controls: "W - + 8" and "H - + 8".
WIDTH_MINUS :: Rect{182, 42, 12, 10}
WIDTH_PLUS :: Rect{196, 42, 12, 10}
HEIGHT_MINUS :: Rect{182, 56, 12, 10}
HEIGHT_PLUS :: Rect{196, 56, 12, 10}
SIZE_LABEL_X :: 154 // "HEIGHT" is 23 px wide and must end before the buttons
SIZE_VALUE_X :: 214

// Actual-size preview, in a 66 x 66 frame (the largest bitmap plus a 1 px border).
PREVIEW_FRAME :: Rect{154, 80, 66, 66}

SAVE_BUTTON :: Rect{240, 84, 36, 12}
LOAD_BUTTON :: Rect{240, 100, 36, 12}
MENU_BUTTON :: Rect{240, 116, 36, 12}

HELP_Y :: 152 // up to four lines at the font's pitch
MAX_HELP_LINES :: 4

rect_contains :: proc(r: Rect, x, y: int) -> bool {
	return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
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
