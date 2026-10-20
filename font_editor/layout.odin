package font_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.
// Left: either the 16 x 16 character grid or (while editing a glyph) the pixel canvas. Right: a
// panel that is the same in every mode.

Rect :: cm.Rect

rect_contains :: cm.rect_contains
intersect :: cm.rect_intersect

// The character grid: 9 px pitch, each cell 8 x 8 (the gap holds the selection frame). A glyph is
// shown at 1:1 clipped to its cell.
GRID_X :: 6
GRID_Y :: 6
GRID_PITCH :: 9
GRID_CELL :: 8
GRID_SIDE :: 16

CANVAS :: Rect{8, 8, 140, 140} // the pixel canvas for the glyph being edited

BANNER :: Rect{156, 5, 160, 11}
INFO_X :: 156
INFO_Y :: 19 // "CODE 65  $41  A"

// Setting rows: width (this glyph), height (whole font), present (this glyph). The marker ">"
// sits left of the label while Setup is the active mode.
ROW_MARKER_X :: 151
ROW_LABEL_X :: 156
ROW_VALUE_X :: 216
WIDTH_MINUS :: Rect{186, 28, 12, 10}
WIDTH_PLUS :: Rect{200, 28, 12, 10}
HEIGHT_MINUS :: Rect{186, 40, 12, 10}
HEIGHT_PLUS :: Rect{200, 40, 12, 10}
PRESENT_BUTTON :: Rect{186, 52, 32, 10}

// Glyph actions, on the same line as PRESENT: copy this glyph, paste the copy here, delete this glyph.
COPY_BUTTON :: Rect{222, 52, 28, 10}
PASTE_BUTTON :: Rect{252, 52, 32, 10}
DELETE_BUTTON :: Rect{286, 52, 28, 10}

// Flip the selected glyph: mirror left-right / top-bottom (also the last two Setup rows). They sit
// to the right of the width and height values.
FLIP_H_BUTTON :: Rect{236, 28, 36, 10}
FLIP_V_BUTTON :: Rect{236, 40, 36, 10}

// The selected glyph, scaled to fit, and how much of the printable range (32..127) is covered.
GLYPH_FRAME :: Rect{156, 66, 48, 48}
GLYPH_INNER :: Rect{157, 67, 46, 46}
COVER_X :: 210
COVER_Y :: 68 // three coverage lines, then the clipboard line at COVER_Y + 24
CLIP_Y :: COVER_Y + 24

// Sample text in the font being edited.
SAMPLE_FRAME :: Rect{156, 116, 160, 23}
SAMPLE_INNER :: Rect{157, 117, 158, 21}
SAMPLE_TEXT :: "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG 0123456789"

SAVE_BUTTON :: Rect{156, 141, 36, 9}
LOAD_BUTTON :: Rect{194, 141, 36, 9}
EDIT_BUTTON :: Rect{232, 141, 36, 9} // "EDIT" from the grid, "GRID" while editing
MENU_BUTTON :: Rect{270, 141, 36, 9}

HELP_Y :: 152
MAX_HELP_LINES :: 4

grid_cell_rect :: proc(code: int) -> Rect {
	return Rect{GRID_X + (code % GRID_SIDE) * GRID_PITCH, GRID_Y + (code / GRID_SIDE) * GRID_PITCH, GRID_CELL, GRID_CELL}
}

// The character under a logical position (the gap between cells counts as the cell before it).
grid_cell_at :: proc(px, py: int) -> (code: int, ok: bool) {
	x, y := px - GRID_X, py - GRID_Y
	if x < 0 || y < 0 {
		return 0, false
	}
	col, row := x / GRID_PITCH, y / GRID_PITCH
	if col >= GRID_SIDE || row >= GRID_SIDE {
		return 0, false
	}
	return row * GRID_SIDE + col, true
}

// Canvas geometry for the glyph being edited.
cell_at :: proc(width, height, px, py: int) -> (x, y: int, ok: bool) {
	return cm.canvas_cell_at(CANVAS, width, height, px, py)
}

cell_rect :: proc(width, height, x, y: int) -> Rect {
	return cm.canvas_cell_rect(CANVAS, width, height, x, y)
}
