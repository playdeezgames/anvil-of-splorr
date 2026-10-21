package world_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains

BANNER :: Rect{8, 5, 304, 11}
INFO_X :: 8
INFO_Y :: 19

// Hub: one row per part of the world.
HUB_X :: 24
HUB_VALUE_X :: 130
HUB_Y :: 26
HUB_PITCH :: 9
HUB_MARKER_X :: 12
WIDTH_MINUS :: Rect{230, 35, 12, 10} // the tile width row (hub row 1)
WIDTH_PLUS :: Rect{244, 35, 12, 10}
HEIGHT_MINUS :: Rect{230, 45, 12, 10} // the tile height row (hub row 2)
HEIGHT_PLUS :: Rect{244, 45, 12, 10}

// The three file buttons under the hub rows.
SAVE_BUTTON :: Rect{24, 130, 40, 10}
LOAD_BUTTON :: Rect{68, 130, 40, 10}
MENU_BUTTON :: Rect{112, 130, 40, 10}
PLAY_BUTTON :: Rect{156, 130, 40, 10} // try the world: walk the player around (YELLOW in the hub)

// Lists: the named things of one kind, one per line, with the action buttons on the right.
LIST_X :: 8
LIST_Y :: 28
LIST_PITCH :: 10
LIST_ROWS :: 11
LIST_W :: 200

BUTTON_X :: 218
BUTTON_W :: 44
BUTTON_H :: 10
BUTTON_PITCH :: 12
OPEN_BUTTON :: Rect{BUTTON_X, 28, BUTTON_W, BUTTON_H}
RENAME_BUTTON :: Rect{BUTTON_X, 40, BUTTON_W, BUTTON_H}
NEW_BUTTON :: Rect{BUTTON_X, 52, BUTTON_W, BUTTON_H}
DUPLICATE_BUTTON :: Rect{BUTTON_X, 64, BUTTON_W, BUTTON_H}
DELETE_BUTTON :: Rect{BUTTON_X, 76, BUTTON_W, BUTTON_H}
IMPORT_BUTTON :: Rect{BUTTON_X, 88, BUTTON_W, BUTTON_H} // tilesets only
BACK_BUTTON :: Rect{BUTTON_X, 112, BUTTON_W, BUTTON_H}

// The value screen of a parameter.
VALUE_X :: 24
VALUE_MINUS10 :: Rect{24, 92, 34, 12}
VALUE_MINUS1 :: Rect{62, 92, 34, 12}
VALUE_PLUS1 :: Rect{100, 92, 34, 12}
VALUE_PLUS10 :: Rect{138, 92, 34, 12}
VALUE_EDIT :: Rect{190, 92, 44, 12}
VALUE_KIND :: Rect{238, 92, 44, 12}
VALUE_BACK :: Rect{260, 130, 44, 10}

HELP_Y :: 150
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

hub_row_rect :: proc(row: int) -> Rect {
	return Rect{HUB_MARKER_X, HUB_Y + row * HUB_PITCH - 2, 280, HUB_PITCH}
}

hub_row_at :: proc(x, y: int) -> (row: int, ok: bool) {
	if x < HUB_MARKER_X || x >= HUB_MARKER_X + 280 || y < HUB_Y - 2 {
		return 0, false
	}
	row = (y - (HUB_Y - 2)) / HUB_PITCH
	return row, row < HUB_ROWS
}
