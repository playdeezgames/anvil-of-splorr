package character_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains

BANNER :: Rect{8, 5, 304, 11}
INFO_X :: 8
INFO_Y :: 19

// The list of characters: one per line, scrolling.
LIST_X :: 8
LIST_Y :: 28
LIST_PITCH :: 10
LIST_ROWS :: 11
LIST_W :: 196

// The right panel: the character's picture, its id, its type (with - and + buttons), and actions.
PANEL_X :: 214
PREVIEW_FRAME :: Rect{214, 28, 34, 34}
PREVIEW_INNER :: Rect{215, 29, 32, 32}
ID_X :: 254
ID_Y :: 30
STATUS_X :: 254
STATUS_Y :: 42
TYPE_LABEL_Y :: 70
TYPE_MINUS :: Rect{244, 68, 12, 10}
TYPE_PLUS :: Rect{258, 68, 12, 10}
TYPE_NAME_Y :: 82
VALUE_CHARS :: 22

BUTTON_W :: 48
BUTTON_H :: 10
RENAME_BUTTON :: Rect{214, 98, BUTTON_W, BUTTON_H}
NEW_BUTTON :: Rect{266, 98, BUTTON_W, BUTTON_H}
DUPLICATE_BUTTON :: Rect{214, 110, BUTTON_W, BUTTON_H}
DELETE_BUTTON :: Rect{266, 110, BUTTON_W, BUTTON_H}
PLAYER_BUTTON :: Rect{214, 122, BUTTON_W, BUTTON_H}
UNPLACE_BUTTON :: Rect{266, 122, BUTTON_W, BUTTON_H}
TAGS_BUTTON :: Rect{214, 138, BUTTON_W, BUTTON_H}
BACK_BUTTON :: Rect{266, 138, BUTTON_W, BUTTON_H}
TAGS_Y :: 90 // "2 TAGS" under the type's name

HELP_Y :: 152
MAX_HELP_LINES :: 4

list_row_rect :: proc(row: int) -> Rect {
	return Rect{LIST_X, LIST_Y + row * LIST_PITCH, LIST_W, LIST_PITCH}
}

// The list row under a point, if any.
list_row_at :: proc(x, y: int) -> (row: int, ok: bool) {
	if x < LIST_X || x >= LIST_X + LIST_W || y < LIST_Y {
		return 0, false
	}
	row = (y - LIST_Y) / LIST_PITCH
	return row, row < LIST_ROWS
}
