package terrain_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains

// The grid of thumbnails (of terrains in Pick mode, of images in Image mode), 8 x 8 visible.
GRID_COLS :: 8
GRID_ROWS :: 8
GRID_PITCH :: 17
THUMB :: 16
GRID_X :: 8
GRID_Y :: 8

BANNER :: Rect{154, 5, 162, 11}
INFO_X :: 154
INFO_Y :: 19 // "TERRAIN 3 OF 7 *"
NAME_Y :: 28 // the selected terrain's name

// Setting rows with - and + buttons: tileset, image; a readout of the tags; then the default row.
ROW_MARKER_X :: 149
ROW_LABEL_X :: 154
ROW_VALUE_X :: 226
VALUE_CHARS :: 22
TILESET_MINUS :: Rect{194, 38, 12, 10}
TILESET_PLUS :: Rect{208, 38, 12, 10}
IMAGE_MINUS :: Rect{194, 50, 12, 10}
IMAGE_PLUS :: Rect{208, 50, 12, 10}
TAGS_ROW_Y :: 62 // the readout of the terrain's tags (the TAGS button opens the list)
DEFAULT_SWITCH :: Rect{194, 74, 26, 10}

PREVIEW_FRAME :: Rect{154, 88, 24, 24}
PREVIEW_INNER :: Rect{155, 89, 22, 22}

BUTTON_X := [4]int{154, 194, 234, 274}
BUTTON_Y := [3]int{115, 126, 137}
BUTTON_W :: 38
BUTTON_H :: 10

RENAME_BUTTON :: Rect{154, 115, BUTTON_W, BUTTON_H}
NEW_BUTTON :: Rect{194, 115, BUTTON_W, BUTTON_H}
DUPLICATE_BUTTON :: Rect{234, 115, BUTTON_W, BUTTON_H}
DELETE_BUTTON :: Rect{274, 115, BUTTON_W, BUTTON_H}
PICK_BUTTON :: Rect{154, 126, BUTTON_W, BUTTON_H} // choose the image from a grid
DEFAULT_BUTTON :: Rect{194, 126, BUTTON_W, BUTTON_H}
TAGS_BUTTON :: Rect{234, 126, BUTTON_W, BUTTON_H}
BACK_BUTTON :: Rect{274, 137, BUTTON_W, BUTTON_H}

HELP_Y :: 150
MAX_HELP_LINES :: 4

grid_cell_rect :: proc(col, row: int) -> Rect {
	return Rect{GRID_X + col * GRID_PITCH, GRID_Y + row * GRID_PITCH, THUMB, THUMB}
}

// The grid position under a point (the gap after a thumbnail belongs to it).
grid_cell_at :: proc(x, y: int) -> (col, row: int, ok: bool) {
	cx, cy := x - GRID_X, y - GRID_Y
	if cx < 0 || cy < 0 {
		return 0, 0, false
	}
	col, row = cx / GRID_PITCH, cy / GRID_PITCH
	return col, row, col < GRID_COLS && row < GRID_ROWS
}

grid_total_rows :: proc(count: int) -> int {
	return (count + GRID_COLS - 1) / GRID_COLS
}
