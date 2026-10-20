package image_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains
intersect :: cm.rect_intersect

CANVAS :: Rect{8, 8, 140, 140} // the area the image is scaled into, top-left aligned

BANNER :: Rect{154, 5, 162, 11}
INFO_X :: 154
INFO_Y :: 19 // "CURSOR: 3,4  PIXEL 7"

// Setup rows, top to bottom: drawing colour, width, height. The marker ">" sits left of the row's
// label while Setup is the active mode.
ROW_MARKER_X :: 149
ROW_LABEL_X :: 154
ROW_VALUE_X :: 214
COLOR_CHIP :: Rect{182, 28, 26, 8}
WIDTH_MINUS :: Rect{182, 40, 12, 10}
WIDTH_PLUS :: Rect{196, 40, 12, 10}
HEIGHT_MINUS :: Rect{182, 52, 12, 10}
HEIGHT_PLUS :: Rect{196, 52, 12, 10}

// The palette, one row of 16 swatches: click one to draw with it.
SWATCH_W :: 10
PALETTE_X :: 154
PALETTE_Y :: 68

// 3 x 3 tiled preview: scaled by a whole number to fit the inner area, anything that does not fit
// is clipped (and flagged).
PREVIEW_FRAME :: Rect{154, 84, 64, 64}
PREVIEW_INNER :: Rect{155, 85, 62, 62}
CLIPPED_X :: 222 // under the file buttons, left of the transform column
CLIPPED_Y :: 136

// Buttons, in three columns beside the preview: file, whole-image transforms, rectangles. The
// transforms and rectangles are also the last Setup rows (green runs them).
SAVE_BUTTON :: Rect{222, 84, 28, 10}
LOAD_BUTTON :: Rect{222, 96, 28, 10}
MENU_BUTTON :: Rect{222, 108, 28, 10}
FLIP_H_BUTTON :: Rect{252, 84, 30, 10}
FLIP_V_BUTTON :: Rect{252, 96, 30, 10}
ROT_L_BUTTON :: Rect{252, 108, 30, 10}
ROT_R_BUTTON :: Rect{252, 120, 30, 10}
ROT_180_BUTTON :: Rect{252, 132, 30, 10}
FRAME_BUTTON :: Rect{284, 84, 30, 10} // arms the frame tool: then drag corner to corner on the canvas
FILL_BUTTON :: Rect{284, 96, 30, 10}
FLOOD_BUTTON :: Rect{284, 108, 30, 10} // arms flood fill: the next click on the canvas fills from that pixel
REPLACE_BUTTON :: Rect{284, 120, 30, 10} // arms replace colour: the next click picks the colour to replace
CLEAR_BUTTON :: Rect{284, 132, 30, 10} // sets the whole image to the drawing colour at once

HELP_Y :: 152 // up to four lines at the font's pitch
MAX_HELP_LINES :: 4

TILES :: 3

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

// Canvas geometry: the shared code in common/canvas.odin applied to CANVAS.
cell_size :: proc(width, height: int) -> int {
	return cm.canvas_cell_size(CANVAS, width, height)
}

cell_at :: proc(width, height, px, py: int) -> (x, y: int, ok: bool) {
	return cm.canvas_cell_at(CANVAS, width, height, px, py)
}

cell_rect :: proc(width, height, x, y: int) -> Rect {
	return cm.canvas_cell_rect(CANVAS, width, height, x, y)
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
