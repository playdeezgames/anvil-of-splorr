package palette_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: struct {
	x, y, w, h: int,
}

GRID_X :: 8
GRID_Y :: 8
CELL :: 24
CELL_GAP :: 4

SLIDER_X :: 150
SLIDER_Y :: 24
SLIDER_W :: 128 // 2 values per pixel
SLIDER_H :: 12
SLIDER_PITCH :: 24

BANNER :: Rect{134, 5, 160, 11}
PREVIEW :: Rect{134, 94, 84, 28}
SAVE_BUTTON :: Rect{232, 94, 40, 12}
LOAD_BUTTON :: Rect{232, 110, 40, 12}
COPY_BUTTON :: Rect{278, 94, 36, 12}
PASTE_BUTTON :: Rect{278, 110, 36, 12}
CLIP_CHIP :: Rect{190, 125, 7, 7} // shows the copied colour next to the readout
READOUT_Y :: 126 // "05 #AA5500 *" under the preview
HELP_Y :: 136 // help block, full width, packed at the font's line pitch

rect_contains :: proc(r: Rect, x, y: int) -> bool {
	return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

swatch_rect :: proc(i: int) -> Rect {
	col, row := i % GRID_COLS, i / GRID_COLS
	return Rect {
		GRID_X + col * (CELL + CELL_GAP),
		GRID_Y + row * (CELL + CELL_GAP),
		CELL,
		CELL,
	}
}

slider_rect :: proc(ch: cm.Channel) -> Rect {
	return Rect{SLIDER_X, SLIDER_Y + int(ch) * SLIDER_PITCH, SLIDER_W, SLIDER_H}
}

swatch_at :: proc(x, y: int) -> (i: int, ok: bool) {
	for i in 0 ..< cm.PALETTE_SIZE {
		if rect_contains(swatch_rect(i), x, y) {
			return i, true
		}
	}
	return 0, false
}

// Sliders also respond a few pixels above/below the bar so they are easy to grab.
slider_at :: proc(x, y: int) -> (ch: cm.Channel, ok: bool) {
	for ch in cm.Channel {
		r := slider_rect(ch)
		r.y -= 4
		r.h += 8
		if rect_contains(r, x, y) {
			return ch, true
		}
	}
	return {}, false
}
