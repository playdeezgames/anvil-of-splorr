package feature_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains

BANNER :: Rect{8, 5, 304, 11}
INFO_X :: 8
INFO_Y :: 19

// The list of features: one per line, scrolling.
LIST_X :: 8
LIST_Y :: 28
LIST_PITCH :: 10
LIST_ROWS :: 11
LIST_W :: 196

// The right panel: the feature's picture, its id, its type (with - and + buttons), and actions.
PANEL_X :: 214
PREVIEW_FRAME :: Rect{214, 28, 34, 34}
PREVIEW_INNER :: Rect{215, 29, 32, 32}
ID_X :: 254
ID_Y :: 30
TYPE_LABEL_Y :: 70
TYPE_MINUS :: Rect{244, 68, 12, 10}
TYPE_PLUS :: Rect{258, 68, 12, 10}
TYPE_NAME_Y :: 82
VALUE_CHARS :: 22

BUTTON_W :: 48
BUTTON_H :: 10
RENAME_BUTTON :: Rect{214, 98, BUTTON_W, BUTTON_H}
NEW_BUTTON :: Rect{266, 98, BUTTON_W, BUTTON_H}
DUPLICATE_BUTTON :: Rect{214, 109, BUTTON_W, BUTTON_H}
DELETE_BUTTON :: Rect{266, 109, BUTTON_W, BUTTON_H}
UNPLACE_BUTTON :: Rect{214, 120, BUTTON_W, BUTTON_H}
ITEMS_BUTTON :: Rect{266, 120, BUTTON_W, BUTTON_H} // the feature's inventory (opened by the host)
TAGS_BUTTON :: Rect{214, 131, BUTTON_W, BUTTON_H}
PROPS_BUTTON :: Rect{266, 131, BUTTON_W, BUTTON_H} // the feature's values of its type's properties
BACK_BUTTON :: Rect{266, 142, BUTTON_W, BUTTON_H}
TAGS_Y :: 90 // "2 TAGS" under the type's name
TRIGGERS_X :: PANEL_X + 46 // "3 TRIG": how many triggers are on the feature, right of the tag count

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

// The Props screen: the selected feature's type's properties with its values, buttons beside them.
PROP_LIST_X :: 8
PROP_LIST_Y :: 22
PROP_ROW_H :: 8
PROP_LIST_W :: 196
PROP_VALUE_X :: 100 // where a value starts, inside a row
PROP_INFO_X :: 214 // whose properties these are: right of the list (the info line would overprint its first rows)
PROP_INFO_Y :: 56
PROP_VALUE_BUTTON :: Rect{214, 28, BUTTON_W, BUTTON_H}
PROP_DEFAULT_BUTTON :: Rect{266, 28, BUTTON_W, BUTTON_H}
PROP_MINUS :: Rect{214, 40, 22, BUTTON_H}
PROP_PLUS :: Rect{238, 40, 22, BUTTON_H}

prop_row_rect :: proc(i: int) -> Rect {
	return Rect{PROP_LIST_X, PROP_LIST_Y + i * PROP_ROW_H, PROP_LIST_W, PROP_ROW_H}
}

// The row of the property list under a point, or -1.
prop_row_at :: proc(x, y: int) -> int {
	if x < PROP_LIST_X || x >= PROP_LIST_X + PROP_LIST_W || y < PROP_LIST_Y {
		return -1
	}
	return (y - PROP_LIST_Y) / PROP_ROW_H
}
