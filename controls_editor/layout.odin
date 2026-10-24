package controls_editor

import cm "../common"

// Layout in logical (cm.SCREEN_W x cm.SCREEN_H) pixels; shared by drawing and mouse hit-testing.

Rect :: cm.Rect

rect_contains :: cm.rect_contains

BANNER :: Rect{8, 5, 304, 11}
INFO_X :: 8
INFO_Y :: 19

// The table: a header, then one row per command and a last row that resets everything to the defaults.
HEADER_Y :: 31
ROW_Y :: 41
ROW_H :: 11
ROW_COUNT :: 9 // 8 commands and the defaults row
CMD_X :: 12
KEY_CELL :: Rect{64, 0, 88, ROW_H}
PAD_CELL :: Rect{154, 0, 36, ROW_H}
LABEL_CELL :: Rect{192, 0, 60, ROW_H}
TABLE_W :: 244 // from x 8: the row highlight

// The buttons down the right side.
BUTTON_X :: 258
BUTTON_W :: 54
BUTTON_H :: 10
SAVE_BUTTON :: Rect{BUTTON_X, 31, BUTTON_W, BUTTON_H}
LOAD_BUTTON :: Rect{BUTTON_X, 43, BUTTON_W, BUTTON_H}
UNBIND_BUTTON :: Rect{BUTTON_X, 55, BUTTON_W, BUTTON_H}
CANCEL_BUTTON :: Rect{BUTTON_X, 67, BUTTON_W, BUTTON_H} // while a key or button is being captured
MENU_BUTTON :: Rect{BUTTON_X, 140, BUTTON_W, BUTTON_H}

HELP_Y :: 152
MAX_HELP_LINES :: 4

Column :: enum {
	Key,
	Pad,
	Label,
}

row_rect :: proc(row: int) -> Rect {
	return Rect{8, ROW_Y + row * ROW_H, TABLE_W, ROW_H}
}

cell_rect :: proc(row: int, col: Column) -> Rect {
	base: Rect
	switch col {
	case .Key:
		base = KEY_CELL
	case .Pad:
		base = PAD_CELL
	case .Label:
		base = LABEL_CELL
	}
	base.y = ROW_Y + row * ROW_H
	return base
}

// The row and column under a point; column is only meaningful for command rows (row < 8).
cell_at :: proc(x, y: int) -> (row: int, col: Column, ok: bool) {
	if x < 8 || x >= 8 + TABLE_W || y < ROW_Y {
		return 0, .Key, false
	}
	row = (y - ROW_Y) / ROW_H
	if row >= ROW_COUNT {
		return 0, .Key, false
	}
	switch {
	case x >= LABEL_CELL.x:
		col = .Label
	case x >= PAD_CELL.x:
		col = .Pad
	case:
		col = .Key
	}
	return row, col, true
}
