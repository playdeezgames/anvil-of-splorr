package feature_type_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains

// The grid of thumbnails (of feature types in Pick mode, of the sprites of a set in Sprite mode).
GRID_COLS :: 8
GRID_ROWS :: 8
GRID_PITCH :: 17
THUMB :: 16
GRID_X :: 8
GRID_Y :: 8

BANNER :: Rect{154, 5, 162, 11}
INFO_X :: 154
INFO_Y :: 19 // "TYPE 3 OF 7 *"
NAME_Y :: 28 // the selected type's name

// Setting rows with - and + buttons: sprite set, sprite, background set, background terrain. The
// background is only for looking: it is not saved.
ROW_MARKER_X :: 149
ROW_LABEL_X :: 154
ROW_VALUE_X :: 226
VALUE_CHARS :: 22
SET_MINUS :: Rect{194, 38, 12, 10}
SET_PLUS :: Rect{208, 38, 12, 10}
SPRITE_MINUS :: Rect{194, 49, 12, 10}
SPRITE_PLUS :: Rect{208, 49, 12, 10}
BG_SET_MINUS :: Rect{194, 60, 12, 10}
BG_SET_PLUS :: Rect{208, 60, 12, 10}
BG_TERRAIN_MINUS :: Rect{194, 71, 12, 10}
BG_TERRAIN_PLUS :: Rect{208, 71, 12, 10}

USES_Y :: 84 // "USED BY 3 FEATURES"

PREVIEW_FRAME :: Rect{154, 94, 24, 24}
PREVIEW_INNER :: Rect{155, 95, 22, 22}

BUTTON_W :: 38
BUTTON_H :: 10
RENAME_BUTTON :: Rect{154, 119, BUTTON_W, BUTTON_H}
NEW_BUTTON :: Rect{194, 119, BUTTON_W, BUTTON_H}
DUPLICATE_BUTTON :: Rect{234, 119, BUTTON_W, BUTTON_H}
DELETE_BUTTON :: Rect{274, 119, BUTTON_W, BUTTON_H}
PICK_BUTTON :: Rect{154, 130, BUTTON_W, BUTTON_H} // choose the sprite from a grid
TAGS_BUTTON :: Rect{194, 130, BUTTON_W, BUTTON_H}
BACK_BUTTON :: Rect{274, 141, BUTTON_W, BUTTON_H}

HELP_Y :: 152
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
