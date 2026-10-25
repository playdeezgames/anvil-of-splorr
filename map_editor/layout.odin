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
COLUMNS_MINUS :: Rect{194, 39, 12, 10}
COLUMNS_PLUS :: Rect{208, 39, 12, 10}
ROWS_MINUS :: Rect{194, 50, 12, 10}
ROWS_PLUS :: Rect{208, 50, 12, 10}
SET_MINUS :: Rect{194, 61, 12, 10}
SET_PLUS :: Rect{208, 61, 12, 10}
ZOOM_MINUS :: Rect{194, 72, 12, 10} // zoom out (towards FIT)
ZOOM_PLUS :: Rect{208, 72, 12, 10}
TAGS_BUTTON :: Rect{268, 72, 38, 10} // the tags of the cell under the cursor, or of the current character

// Cell sizes in screen pixels for the zoom levels; level 0 is FIT (the whole map in the canvas).
ZOOM_SIZES :: [?]int{0, 4, 6, 8, 12, 16, 24, 32}

// Scroll bars beside the canvas, shown when the map is larger than the view.
VBAR :: Rect{150, 8, 3, 140}
HBAR :: Rect{8, 150, 140, 3}

// The terrain picker: 16 terrains at a time (the page holding the current one), thumbnails.
PICKER_COLS :: 8
PICKER_ROWS :: 2
PICKER_PAGE :: PICKER_COLS * PICKER_ROWS
PICKER_X :: 154
PICKER_Y :: 84
PICKER_PITCH :: 17
PICKER_THUMB :: 16

// Buttons: four columns of 38 x 10, three rows.
BUTTON_X := [4]int{154, 194, 234, 274}
BUTTON_Y := [3]int{119, 130, 141}
BUTTON_W :: 38
BUTTON_H :: 10

button_rect :: proc(col, row: int) -> Rect {
	return Rect{BUTTON_X[col], BUTTON_Y[row], BUTTON_W, BUTTON_H}
}

FLIP_H_BUTTON :: Rect{154, 119, BUTTON_W, BUTTON_H}
FLIP_V_BUTTON :: Rect{194, 119, BUTTON_W, BUTTON_H}
ROT_L_BUTTON :: Rect{234, 119, BUTTON_W, BUTTON_H}
ROT_R_BUTTON :: Rect{274, 119, BUTTON_W, BUTTON_H}
ROT_180_BUTTON :: Rect{154, 130, BUTTON_W, BUTTON_H}
FRAME_BUTTON :: Rect{194, 130, BUTTON_W, BUTTON_H} // arms the frame tool: then drag corner to corner on the map
FILL_BUTTON :: Rect{234, 130, BUTTON_W, BUTTON_H}
FLOOD_BUTTON :: Rect{274, 130, BUTTON_W, BUTTON_H} // arms flood fill: the next click fills from that cell
REPLACE_BUTTON :: Rect{154, 141, BUTTON_W, BUTTON_H} // arms replace: the next click picks the terrain to replace
CLEAR_BUTTON :: Rect{194, 141, BUTTON_W, BUTTON_H} // sets the whole map to the current terrain at once
BACK_BUTTON :: Rect{234, 141, BUTTON_W, BUTTON_H}
LAYER_BUTTON :: Rect{274, 141, BUTTON_W, BUTTON_H} // terrain painting <-> characters

// The Characters layer's buttons (the same places as the terrain layer's first row and a bit more).
CHAR_NEW_BUTTON :: Rect{154, 119, BUTTON_W, BUTTON_H}
CHAR_UNPLACE_BUTTON :: Rect{194, 119, BUTTON_W, BUTTON_H}
CHAR_DELETE_BUTTON :: Rect{234, 119, BUTTON_W, BUTTON_H}
CHAR_PLAYER_BUTTON :: Rect{274, 119, BUTTON_W, BUTTON_H}
CHAR_RENAME_BUTTON :: Rect{154, 130, BUTTON_W, BUTTON_H}

// The Features layer's buttons (the Characters layer's places, with RENAME where PLAYER was).
FEAT_NEW_BUTTON :: CHAR_NEW_BUTTON
FEAT_UNPLACE_BUTTON :: CHAR_UNPLACE_BUTTON
FEAT_DELETE_BUTTON :: CHAR_DELETE_BUTTON
FEAT_RENAME_BUTTON :: CHAR_PLAYER_BUTTON

// The Triggers layer's buttons (the Features layer's places).
TRIG_NEW_BUTTON :: CHAR_NEW_BUTTON
TRIG_UNPLACE_BUTTON :: CHAR_UNPLACE_BUTTON
TRIG_DELETE_BUTTON :: CHAR_DELETE_BUTTON
TRIG_RENAME_BUTTON :: CHAR_PLAYER_BUTTON

// The Items layer's buttons (the Characters layer's first row).
ITEM_OPEN_BUTTON :: CHAR_NEW_BUTTON
ITEM_CLEAR_BUTTON :: CHAR_UNPLACE_BUTTON

HELP_Y :: 152 // up to four lines at the font's pitch
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

