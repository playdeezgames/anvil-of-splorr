package map_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains

CANVAS :: Rect{8, 8, 140, 140} // the area the map is scaled into, top-left aligned

BANNER :: Rect{154, 5, 162, 11}
INFO_X :: 154
INFO_Y :: 19 // "CURSOR: 3,4  grass"

// Setting rows, top to bottom: terrain, columns, rows, terrain set. The marker ">" sits left of the
// row's label while Setup is the active mode. Each has - and + buttons; the value is text.
ROW_MARKER_X :: 149
ROW_LABEL_X :: 154
ROW_VALUE_X :: 226
VALUE_CHARS :: 22 // the most characters of a name shown in a value (the rest is cut off)
TERRAIN_MINUS :: Rect{194, 28, 12, 10}
TERRAIN_PLUS :: Rect{208, 28, 12, 10}
COLUMNS_MINUS :: Rect{194, 40, 12, 10}
COLUMNS_PLUS :: Rect{208, 40, 12, 10}
ROWS_MINUS :: Rect{194, 52, 12, 10}
ROWS_PLUS :: Rect{208, 52, 12, 10}
SET_MINUS :: Rect{194, 64, 12, 10}
SET_PLUS :: Rect{208, 64, 12, 10}

// The terrain picker: 16 terrains at a time (the page holding the current one), thumbnails.
PICKER_COLS :: 8
PICKER_ROWS :: 2
PICKER_PAGE :: PICKER_COLS * PICKER_ROWS
PICKER_X :: 154
PICKER_Y :: 78
PICKER_PITCH :: 17
PICKER_THUMB :: 16

// Buttons: four columns of 38 x 10, three rows.
BUTTON_X := [4]int{154, 194, 234, 274}
BUTTON_Y := [3]int{115, 126, 137}
BUTTON_W :: 38
BUTTON_H :: 10

button_rect :: proc(col, row: int) -> Rect {
	return Rect{BUTTON_X[col], BUTTON_Y[row], BUTTON_W, BUTTON_H}
}

FLIP_H_BUTTON :: Rect{154, 115, BUTTON_W, BUTTON_H}
FLIP_V_BUTTON :: Rect{194, 115, BUTTON_W, BUTTON_H}
ROT_L_BUTTON :: Rect{234, 115, BUTTON_W, BUTTON_H}
ROT_R_BUTTON :: Rect{274, 115, BUTTON_W, BUTTON_H}
ROT_180_BUTTON :: Rect{154, 126, BUTTON_W, BUTTON_H}
FRAME_BUTTON :: Rect{194, 126, BUTTON_W, BUTTON_H} // arms the frame tool: then drag corner to corner on the map
FILL_BUTTON :: Rect{234, 126, BUTTON_W, BUTTON_H}
FLOOD_BUTTON :: Rect{274, 126, BUTTON_W, BUTTON_H} // arms flood fill: the next click fills from that cell
REPLACE_BUTTON :: Rect{154, 137, BUTTON_W, BUTTON_H} // arms replace: the next click picks the terrain to replace
CLEAR_BUTTON :: Rect{194, 137, BUTTON_W, BUTTON_H} // sets the whole map to the current terrain at once
BACK_BUTTON :: Rect{234, 137, BUTTON_W, BUTTON_H}

HELP_Y :: 150 // up to four lines at the font's pitch
MAX_HELP_LINES :: 4

picker_rect :: proc(slot: int) -> Rect {
	return Rect{PICKER_X + (slot % PICKER_COLS) * PICKER_PITCH, PICKER_Y + (slot / PICKER_COLS) * PICKER_PITCH, PICKER_THUMB, PICKER_THUMB}
}

// The picker slot (0..PICKER_PAGE-1) under a position, if any. The gap after a thumbnail counts as
// part of it.
picker_slot_at :: proc(x, y: int) -> (slot: int, ok: bool) {
	cx, cy := x - PICKER_X, y - PICKER_Y
	if cx < 0 || cy < 0 {
		return 0, false
	}
	col, row := cx / PICKER_PITCH, cy / PICKER_PITCH
	if col >= PICKER_COLS || row >= PICKER_ROWS {
		return 0, false
	}
	return row * PICKER_COLS + col, true
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
