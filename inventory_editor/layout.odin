package inventory_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains

BANNER :: Rect{8, 5, 304, 11}
INFO_X :: 8
INFO_Y :: 19

// The list (entries and a NEW row in List mode, one property per row in Props mode, item types in
// Types mode): one per line, scrolling.
LIST_X :: 8
LIST_Y :: 28
LIST_PITCH :: 8
LIST_ROWS :: 15
LIST_W :: 196
ICON :: 7 // an item's picture at the start of a row
NAME_X :: 10 // where the name starts, inside a row
NAME_CHARS :: 14
VALUE_X :: 100 // where the count or value starts, inside a row

// The right panel.
PANEL_X :: 214
BUTTON_W :: 48
BUTTON_H :: 10
MINUS :: Rect{214, 28, 22, BUTTON_H}
PLUS :: Rect{238, 28, 22, BUTTON_H}
COUNT_BUTTON :: Rect{214, 40, BUTTON_W, BUTTON_H} // types the count (List) or the value (Props)
PROPS_BUTTON :: Rect{266, 40, BUTTON_W, BUTTON_H} // the entry's properties (List), reset to default (Props)
NEW_BUTTON :: Rect{214, 52, BUTTON_W, BUTTON_H} // add an item (List), use this type (Types)
DELETE_BUTTON :: Rect{266, 52, BUTTON_W, BUTTON_H}
BACK_BUTTON :: Rect{266, 142, BUTTON_W, BUTTON_H}
PREVIEW_FRAME :: Rect{214, 70, 34, 34}
PREVIEW_INNER :: Rect{215, 71, 32, 32}

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
