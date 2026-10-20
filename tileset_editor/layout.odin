package tileset_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.
// Left: a scrolling grid of thumbnails. Right: a panel with the selected image's name, the tile
// size, a preview and the buttons. (Editing an image uses the image editor's own screen.)

Rect :: cm.Rect

rect_contains :: cm.rect_contains

GRID_X :: 8
GRID_Y :: 8
GRID_PITCH :: 17 // a 16 x 16 thumbnail plus a 1 px gap that holds the selection frame
THUMB :: 16
GRID_COLS :: 8
GRID_ROWS :: 8 // visible rows; the grid scrolls by whole rows

BANNER :: Rect{156, 5, 160, 11}
INFO_X :: 156
INFO_Y :: 19 // "IMAGE 3 OF 12 *"
NAME_Y :: 27

// Setting rows: the tile size of the whole tileset. The marker ">" sits left of the label while
// Setup is the active mode (also for the action rows, whose buttons light up instead).
ROW_MARKER_X :: 148
ROW_LABEL_X :: 156
ROW_VALUE_X :: 216
WIDTH_MINUS :: Rect{186, 38, 12, 10}
WIDTH_PLUS :: Rect{200, 38, 12, 10}
HEIGHT_MINUS :: Rect{186, 50, 12, 10}
HEIGHT_PLUS :: Rect{200, 50, 12, 10}

PREVIEW_FRAME :: Rect{260, 38, 54, 54}
PREVIEW_INNER :: Rect{261, 39, 52, 52}

CLIP_X :: 156
CLIP_Y :: 96 // "CLIP: name"

// Twelve buttons in four columns and three rows.
BUTTON_W :: 38
BUTTON_H :: 10
BUTTON_X := [4]int{156, 196, 236, 276}
BUTTON_Y := [3]int{108, 120, 132}

button_rect :: proc(col, row: int) -> Rect {
	return Rect{BUTTON_X[col], BUTTON_Y[row], BUTTON_W, BUTTON_H}
}

RENAME_BUTTON :: Rect{156, 108, BUTTON_W, BUTTON_H}
NEW_BUTTON :: Rect{196, 108, BUTTON_W, BUTTON_H}
DUPLICATE_BUTTON :: Rect{236, 108, BUTTON_W, BUTTON_H}
DELETE_BUTTON :: Rect{276, 108, BUTTON_W, BUTTON_H}
COPY_BUTTON :: Rect{156, 120, BUTTON_W, BUTTON_H}
PASTE_BUTTON :: Rect{196, 120, BUTTON_W, BUTTON_H}
MOVE_LEFT_BUTTON :: Rect{236, 120, BUTTON_W, BUTTON_H}
MOVE_RIGHT_BUTTON :: Rect{276, 120, BUTTON_W, BUTTON_H}
SAVE_BUTTON :: Rect{156, 132, BUTTON_W, BUTTON_H}
LOAD_BUTTON :: Rect{196, 132, BUTTON_W, BUTTON_H}
EDIT_BUTTON :: Rect{236, 132, BUTTON_W, BUTTON_H}
MENU_BUTTON :: Rect{276, 132, BUTTON_W, BUTTON_H}

HELP_Y :: 152
MAX_HELP_LINES :: 4

grid_cell_rect :: proc(col, row: int) -> Rect {
	return Rect{GRID_X + col * GRID_PITCH, GRID_Y + row * GRID_PITCH, THUMB, THUMB}
}

// The grid cell (column, row within the visible window) under a logical position. The gap after a
// cell belongs to it.
grid_cell_at :: proc(px, py: int) -> (col, row: int, ok: bool) {
	x, y := px - GRID_X, py - GRID_Y
	if x < 0 || y < 0 {
		return 0, 0, false
	}
	col, row = x / GRID_PITCH, y / GRID_PITCH
	return col, row, col < GRID_COLS && row < GRID_ROWS
}

// How many grid rows a tileset of `count` images needs.
grid_total_rows :: proc(count: int) -> int {
	return (count + GRID_COLS - 1) / GRID_COLS
}
