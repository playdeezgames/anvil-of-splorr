#+build !js
package tileset_editor

import cm "../common"
import "core:fmt"
import "core:testing"

// The editor is about 1 MB: always heap allocated and freed by the test.
new_editor :: proc() -> ^Editor {
	e := new(Editor)
	editor_init(e)
	return e
}

// An editor with `n` blank images named image, image_2, ...
with_images :: proc(n: int) -> ^Editor {
	e := new_editor()
	for _ in 0 ..< n {
		cm.tileset_insert_blank(&e.tileset, e.tileset.count, "image")
	}
	return e
}

press :: proc(e: ^Editor, actions: ..cm.Action) {
	for a in actions {
		editor_handle_event(e, cm.Command{action = a})
	}
}

mouse :: proc(e: ^Editor, x, y: int, down: bool) {
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = down})
}

click_at :: proc(e: ^Editor, x, y: int) {
	mouse(e, x, y, true)
	mouse(e, x, y, false)
}

click_rect :: proc(e: ^Editor, r: Rect) {
	click_at(e, r.x + r.w / 2, r.y + r.h / 2)
}

// Clicks the thumbnail of image `index` (it must be in the visible window).
click_thumb :: proc(e: ^Editor, index: int) {
	row := index / GRID_COLS - e.scroll
	click_rect(e, grid_cell_rect(index % GRID_COLS, row))
}

take_exit :: proc(e: ^Editor) -> bool {
	tl := tool(e)
	return tl.take_exit(tl.data)
}

// Opens Setup and moves down to a row.
goto_row :: proc(e: ^Editor, row: Setup_Row) {
	e.mode = .Setup
	for e.row != row {
		press(e, .Down)
	}
}

// Runs a Setup row from Pick.
run :: proc(e: ^Editor, row: Setup_Row) {
	e.mode = .Pick
	press(e, .Yellow)
	goto_row(e, row)
	press(e, .Green)
}

pixel :: proc(e: ^Editor, index, x, y: int) -> int {
	return int(cm.image4_get(&e.tileset.images[index], x, y))
}

name_of :: proc(e: ^Editor, index: int) -> string {
	return cm.tileset_name(&e.tileset, index)
}

// Types `text` into the keypad with only the commands: walk to each character's cell and press green.
type_with_commands :: proc(e: ^Editor, text: string) {
	for i in 0 ..< len(text) {
		ch := text[i]
		if e.entry.row == cm.TEXT_ENTRY_ROWS - 1 {
			press(e, .Up) // leave the action row: there left/right step by whole cells
		}
		tcol, trow := -1, -1
		for r in 0 ..< cm.TEXT_ENTRY_CHAR_ROWS {
			for c in 0 ..< cm.TEXT_ENTRY_COLS {
				if g, ok := cm.text_entry_char_at(c, r); ok && g == ch {
					tcol, trow = c, r
				}
			}
		}
		// (Computed first: a range's bounds are re-read as the cursor moves.)
		rights := (tcol - e.entry.col + cm.TEXT_ENTRY_COLS) % cm.TEXT_ENTRY_COLS
		downs := (trow - e.entry.row + cm.TEXT_ENTRY_ROWS) % cm.TEXT_ENTRY_ROWS
		for _ in 0 ..< rights {
			press(e, .Right)
		}
		for _ in 0 ..< downs {
			press(e, .Down)
		}
		press(e, .Green)
	}
}

// Presses a keypad action cell with the commands (BKSP 0, CLEAR 1, DONE 2, CANCEL 3).
press_keypad_action :: proc(e: ^Editor, a: cm.Text_Entry_Action) {
	for e.entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(e.entry.col) != a {
		press(e, .Right)
	}
	press(e, .Green)
}

@(test)
test_starts_empty_in_pick_mode :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	testing.expect(t, e.mode == .Pick && e.tileset.count == 0 && !e.dirty && e.sel == 0)
	testing.expect(t, e.tileset.width == 16 && e.tileset.height == 16)
	// Everything that needs an image says so instead of doing anything.
	press(e, .Green)
	testing.expect(t, e.mode == .Pick && e.note == NOTE_NO_IMAGES)
	for row in ([]Setup_Row{.Rename, .Duplicate, .Delete, .Copy, .Paste, .Move_Left, .Move_Right}) {
		e.note = ""
		run(e, row)
		testing.expectf(t, e.note == NOTE_NO_IMAGES && !e.dirty && e.tileset.count == 0, "%v on an empty tileset", row)
	}
}

@(test)
test_new_adds_images_after_the_selected_one :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	run(e, .New)
	testing.expect(t, e.tileset.count == 1 && e.sel == 0 && name_of(e, 0) == "image" && e.dirty)
	run(e, .New)
	testing.expect(t, e.tileset.count == 2 && e.sel == 1 && name_of(e, 1) == "image_2")
	e.sel = 0
	run(e, .New) // inserted right after image 0
	testing.expect(t, e.tileset.count == 3 && e.sel == 1 && name_of(e, 1) == "image_3" && name_of(e, 2) == "image_2")
	testing.expect(t, e.tileset.images[1].width == 16 && e.tileset.images[1].height == 16)
}

@(test)
test_new_stops_when_the_tileset_is_full :: proc(t: ^testing.T) {
	e := with_images(cm.TILESET_MAX_IMAGES)
	defer free(e)
	e.sel = 5
	run(e, .New)
	testing.expect(t, e.tileset.count == cm.TILESET_MAX_IMAGES && e.note == NOTE_FULL && !e.dirty)
	e.note = ""
	run(e, .Duplicate)
	testing.expect(t, e.tileset.count == cm.TILESET_MAX_IMAGES && e.note == NOTE_FULL)
}

@(test)
test_pick_navigation_clamps_and_the_grid_scrolls :: proc(t: ^testing.T) {
	e := with_images(40)
	defer free(e)
	press(e, .Left, .Up)
	testing.expect_value(t, e.sel, 0)
	press(e, .Right)
	testing.expect_value(t, e.sel, 1)
	press(e, .Down)
	testing.expect_value(t, e.sel, 9) // one row of eight
	press(e, .Up, .Up)
	testing.expect_value(t, e.sel, 1) // clamped: row 0 has nothing above
	for _ in 0 ..< 10 {
		press(e, .Down)
	}
	testing.expect_value(t, e.sel, 33) // the last row that has a column 1 image... 1 + 4 * 8
	testing.expect_value(t, e.scroll, 0) // rows 0..7 still show image 33 (row 4)
	press(e, .Right)
	press(e, .Right, .Right, .Right, .Right, .Right, .Right)
	testing.expect_value(t, e.sel, 39) // the end
	press(e, .Right)
	testing.expect_value(t, e.sel, 39)
	// With more rows than fit, the window follows the selection.
	big := with_images(100)
	defer free(big)
	for _ in 0 ..< 10 { // row 10
		press(big, .Down)
	}
	testing.expect(t, big.sel == 80 && big.scroll == 10 - GRID_ROWS + 1)
	for _ in 0 ..< 9 {
		press(big, .Up)
	}
	testing.expect(t, big.sel == 8 && big.scroll == 1)
	press(big, .Up)
	testing.expect_value(t, big.scroll, 0)
	// An unusable sideways move at the end of a row does not jump rows silently: left/right step by one image.
	press(big, .Left)
	testing.expect_value(t, big.sel, 0)
}

@(test)
test_edit_opens_the_image_editor_on_the_selected_image :: proc(t: ^testing.T) {
	e := with_images(3)
	defer free(e)
	e.sel = 1
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Edit)
	testing.expect(t, e.editor.embedded && e.editor.lock_size && e.editor.image.width == 16)
	press(e, .Green) // the image editor paints with its current colour (white, 15)
	testing.expect_value(t, pixel(e, 1, 0, 0), 15)
	testing.expect(t, pixel(e, 0, 0, 0) == 0 && pixel(e, 2, 0, 0) == 0) // only the selected image
	testing.expect(t, e.dirty)
	press(e, .Right, .Down, .Green)
	testing.expect_value(t, pixel(e, 1, 1, 1), 15)
	press(e, .Red) // back to the thumbnails
	testing.expect_value(t, e.mode, Mode.Pick)
	testing.expect(t, !take_exit(e)) // that red only closed the image editor
	press(e, .Green) // reopening starts fresh on the same image: the earlier pixels are there
	testing.expect_value(t, pixel(e, 1, 0, 0), 15)
	testing.expect_value(t, e.editor.image.pixels[1][1], 15)
}

@(test)
test_the_image_editor_tools_work_on_a_tile :: proc(t: ^testing.T) {
	e := with_images(2)
	defer free(e)
	press(e, .Green) // edit image 0
	e.editor.color = 6
	e.editor.mode, e.editor.row = .Setup, .Clear
	press(e, .Green) // Clear the tile to colour 6
	testing.expect(t, pixel(e, 0, 0, 0) == 6 && pixel(e, 0, 15, 15) == 6 && pixel(e, 1, 0, 0) == 0)
	testing.expect(t, e.dirty && e.tileset.images[0].width == 16)
}

@(test)
test_the_tile_size_cannot_be_changed_from_the_image_editor :: proc(t: ^testing.T) {
	e := with_images(1)
	defer free(e)
	cm.tileset_set_size(&e.tileset, 8, 4)
	press(e, .Green)
	e.editor.mode, e.editor.row = .Setup, .Width
	press(e, .Right)
	testing.expect(t, e.tileset.width == 8 && e.tileset.images[0].width == 8 && e.editor.note == ie_size_locked)
	// A non-square tile cannot be turned a quarter; a half turn is fine.
	e.editor.row = .Rotate_Right
	press(e, .Green)
	testing.expect(t, e.tileset.images[0].width == 8 && e.tileset.images[0].height == 4)
	e.editor.row = .Rotate_180
	cm.image4_set(&e.editor.image, 0, 0, 5)
	e.editor.dirty = true
	press(e, .Green)
	testing.expect(t, e.tileset.images[0].width == 8 && pixel(e, 0, 7, 3) == 5)
}

ie_size_locked :: "THE TILESET SETS THE SIZE"

@(test)
test_square_tiles_can_be_turned :: proc(t: ^testing.T) {
	e := with_images(1)
	defer free(e)
	cm.image4_set(&e.tileset.images[0], 0, 0, 9)
	press(e, .Green)
	e.editor.mode, e.editor.row = .Setup, .Rotate_Right
	press(e, .Green)
	testing.expect(t, e.tileset.images[0].width == 16 && pixel(e, 0, 15, 0) == 9 && e.dirty)
}

@(test)
test_the_tilesets_palette_is_used_by_the_image_editor :: proc(t: ^testing.T) {
	e := with_images(1)
	defer free(e)
	e.palette[4] = {11, 22, 33}
	press(e, .Green)
	testing.expect(t, e.editor.palette[4] == cm.Color{11, 22, 33})
}

@(test)
test_rename_with_the_keypad :: proc(t: ^testing.T) {
	e := with_images(2)
	defer free(e)
	e.sel = 1
	run(e, .Rename)
	testing.expect_value(t, e.mode, Mode.Text)
	testing.expect_value(t, cm.text_entry_text(&e.entry), "image_2") // starts from the current name
	press_keypad_action(e, .Clear)
	type_with_commands(e, "Brick wall_01")
	testing.expect_value(t, cm.text_entry_text(&e.entry), "Brick wall_01")
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Setup && name_of(e, 1) == "Brick wall_01" && e.dirty)
	testing.expect_value(t, name_of(e, 0), "image") // the other image is untouched
}

@(test)
test_rename_can_be_cancelled_or_left_unchanged :: proc(t: ^testing.T) {
	e := with_images(1)
	defer free(e)
	run(e, .Rename)
	press_keypad_action(e, .Clear)
	type_with_commands(e, "xyz")
	press_keypad_action(e, .Cancel)
	testing.expect(t, e.mode == .Setup && name_of(e, 0) == "image" && !e.dirty)
	run(e, .Rename)
	press(e, .Red) // red cancels too
	testing.expect(t, e.mode == .Setup && name_of(e, 0) == "image" && !e.dirty)
	run(e, .Rename)
	press_keypad_action(e, .Done) // done with the unchanged name
	testing.expect(t, e.mode == .Setup && !e.dirty)
}

@(test)
test_rename_refuses_a_taken_or_empty_name_and_lets_you_fix_it :: proc(t: ^testing.T) {
	e := with_images(2)
	defer free(e)
	e.sel = 1 // "image_2"
	run(e, .Rename)
	press_keypad_action(e, .Clear)
	type_with_commands(e, "image") // already used by image 0
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Text && e.entry.note == NOTE_NAME_USED && cm.text_entry_text(&e.entry) == "image")
	testing.expect(t, name_of(e, 1) == "image_2" && !e.dirty) // nothing changed yet
	press(e, .Yellow) // backspace: "imag"... then fix it
	type_with_commands(e, "e2")
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Setup && name_of(e, 1) == "imag" + "e2" && e.dirty)
	// An empty name is refused as well.
	run(e, .Rename)
	press_keypad_action(e, .Clear)
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Text && e.entry.note == NOTE_NAME_EMPTY && name_of(e, 1) == "image2")
}

@(test)
test_rename_by_mouse :: proc(t: ^testing.T) {
	e := with_images(1)
	defer free(e)
	click_rect(e, RENAME_BUTTON)
	testing.expect(t, e.mode == .Text && e.row == .Rename)
	rc := cm.text_entry_cell_rect(cm.TEXT_ENTRY_COLS - 1, cm.TEXT_ENTRY_ROWS - 1) // the Cancel cell
	_ = rc
	// Clear, then click characters: B, r, 1
	click_keypad_cell :: proc(e: ^Editor, col, row: int) {
		r := cm.text_entry_cell_rect(col, row)
		click_at(e, r.x + r.w / 2, r.y + r.h / 2)
	}
	click_keypad_cell(e, 4, cm.TEXT_ENTRY_ROWS - 1) // CLEAR
	click_keypad_cell(e, 1, 0) // B
	click_keypad_cell(e, 1, 2) // b
	click_keypad_cell(e, 1, 4) // 1
	testing.expect_value(t, cm.text_entry_text(&e.entry), "Bb1")
	click_keypad_cell(e, 8, cm.TEXT_ENTRY_ROWS - 1) // DONE
	testing.expect(t, e.mode == .Setup && name_of(e, 0) == "Bb1")
}

@(test)
test_duplicate_makes_a_copy_after_the_original :: proc(t: ^testing.T) {
	e := with_images(2)
	defer free(e)
	cm.image4_set(&e.tileset.images[0], 3, 3, 8)
	run(e, .Duplicate)
	testing.expect(t, e.tileset.count == 3 && e.sel == 1 && name_of(e, 1) == "image_copy" && name_of(e, 2) == "image_2")
	testing.expect_value(t, pixel(e, 1, 3, 3), 8)
	testing.expect(t, e.dirty)
	cm.image4_set(&e.tileset.images[1], 3, 3, 1)
	testing.expect_value(t, pixel(e, 0, 3, 3), 8) // independent
}

@(test)
test_delete_needs_two_greens_and_anything_else_cancels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_images(3)
	defer free(e)
	e.sel = 1
	run(e, .Delete)
	testing.expect(t, e.confirm_delete && e.tileset.count == 3 && !e.dirty)
	testing.expect_value(t, banner_text(e), "DELETE IMAGE?  GREEN: CONFIRM")
	press(e, .Up) // any other command cancels
	testing.expect(t, !e.confirm_delete && e.tileset.count == 3)
	press(e, .Down) // back on Delete... (rows wrap) and arm again
	e.row = .Delete
	press(e, .Green, .Green)
	testing.expect(t, e.tileset.count == 2 && e.dirty && !e.confirm_delete)
	testing.expect(t, name_of(e, 0) == "image" && name_of(e, 1) == "image_3" && e.sel == 1)
	// Deleting the last one moves the selection back; deleting everything leaves an empty tileset.
	e.row = .Delete
	press(e, .Green, .Green)
	testing.expect(t, e.tileset.count == 1 && e.sel == 0)
	press(e, .Green, .Green)
	testing.expect(t, e.tileset.count == 0 && e.sel == 0)
	press(e, .Green) // nothing to delete: a message, never armed
	testing.expect(t, !e.confirm_delete && e.note == NOTE_NO_IMAGES)
}

@(test)
test_delete_by_mouse_needs_two_clicks :: proc(t: ^testing.T) {
	e := with_images(2)
	defer free(e)
	click_rect(e, DELETE_BUTTON)
	testing.expect(t, e.confirm_delete && e.tileset.count == 2 && e.mode == .Setup && e.row == .Delete)
	click_thumb(e, 1) // any other click cancels
	testing.expect(t, !e.confirm_delete && e.tileset.count == 2)
	click_rect(e, DELETE_BUTTON)
	click_rect(e, DELETE_BUTTON)
	testing.expect(t, e.tileset.count == 1 && !e.confirm_delete && e.dirty)
}

@(test)
test_copy_and_paste_images :: proc(t: ^testing.T) {
	e := with_images(3)
	defer free(e)
	cm.image4_set(&e.tileset.images[0], 5, 5, 12)
	cm.image4_set(&e.tileset.images[0], 15, 15, 3)
	run(e, .Copy)
	testing.expect(t, e.has_clip && !e.dirty) // copying changes nothing
	e.sel = 2
	run(e, .Paste)
	testing.expect(t, pixel(e, 2, 5, 5) == 12 && pixel(e, 2, 15, 15) == 3 && e.dirty)
	testing.expect_value(t, name_of(e, 2), "image_3") // the name stays
	testing.expect(t, pixel(e, 1, 5, 5) == 0 && pixel(e, 0, 5, 5) == 12) // others untouched
	// The copy is a snapshot: later changes to the source do not affect pastes.
	cm.image4_set(&e.tileset.images[0], 5, 5, 1)
	e.sel = 1
	run(e, .Paste)
	testing.expect_value(t, pixel(e, 1, 5, 5), 12)
	// Pasting the same pixels again is not a change.
	editor_mark_saved(e)
	run(e, .Paste)
	testing.expect(t, !e.dirty)
}

@(test)
test_paste_without_a_copy_and_after_a_size_change :: proc(t: ^testing.T) {
	e := with_images(2)
	defer free(e)
	run(e, .Paste)
	testing.expect(t, e.note == NOTE_NOTHING_TO_PASTE && !e.dirty)
	cm.image4_set(&e.tileset.images[0], 2, 2, 7)
	run(e, .Copy)
	cm.tileset_set_size(&e.tileset, 4, 4) // the tileset shrank after the copy
	e.sel = 1
	run(e, .Paste)
	testing.expect(t, e.tileset.images[1].width == 4 && pixel(e, 1, 2, 2) == 7)
	cm.tileset_set_size(&e.tileset, 32, 8) // and grew
	run(e, .Paste)
	testing.expect(t, e.tileset.images[1].width == 32 && e.tileset.images[1].height == 8 && pixel(e, 1, 2, 2) == 7)
}

@(test)
test_move_reorders_and_the_selection_follows :: proc(t: ^testing.T) {
	e := with_images(3)
	defer free(e)
	cm.tileset_set_name(&e.tileset, 0, "a")
	cm.tileset_set_name(&e.tileset, 1, "b")
	cm.tileset_set_name(&e.tileset, 2, "c")
	run(e, .Move_Right)
	testing.expect(t, name_of(e, 0) == "b" && name_of(e, 1) == "a" && e.sel == 1 && e.dirty)
	run(e, .Move_Right)
	testing.expect(t, name_of(e, 2) == "a" && e.sel == 2)
	editor_mark_saved(e)
	run(e, .Move_Right) // at the end: nothing, not an edit
	testing.expect(t, e.sel == 2 && !e.dirty && name_of(e, 2) == "a")
	run(e, .Move_Left)
	run(e, .Move_Left)
	testing.expect(t, name_of(e, 0) == "a" && e.sel == 0)
	editor_mark_saved(e)
	run(e, .Move_Left)
	testing.expect(t, !e.dirty)
}

@(test)
test_tile_size_applies_to_every_image :: proc(t: ^testing.T) {
	e := with_images(3)
	defer free(e)
	cm.image4_set(&e.tileset.images[1], 15, 15, 6)
	e.mode = .Setup
	goto_row(e, .Width)
	press(e, .Left, .Left, .Left, .Left, .Left, .Left, .Left, .Left) // 16 -> 8
	testing.expect(t, e.tileset.width == 8 && e.dirty)
	for i in 0 ..< 3 {
		testing.expect(t, e.tileset.images[i].width == 8 && e.tileset.images[i].height == 16)
	}
	press(e, .Down, .Left, .Left, .Left, .Left) // height 16 -> 12
	testing.expect(t, e.tileset.height == 12 && e.tileset.images[2].height == 12)
	testing.expect_value(t, pixel(e, 1, 15, 15), 0) // cut off
	press(e, .Up)
	for _ in 0 ..< 8 {
		press(e, .Right)
	}
	press(e, .Down)
	for _ in 0 ..< 4 {
		press(e, .Right)
	}
	testing.expect_value(t, pixel(e, 1, 15, 15), 6) // back again
	// New images take the current size; the limits hold.
	for _ in 0 ..< 80 {
		press(e, .Right)
	}
	testing.expect_value(t, e.tileset.height, cm.IMAGE_MAX)
	run(e, .New)
	testing.expect(t, e.tileset.images[e.sel].height == cm.IMAGE_MAX)
}

@(test)
test_tile_size_buttons :: proc(t: ^testing.T) {
	e := with_images(2)
	defer free(e)
	click_rect(e, WIDTH_PLUS)
	click_rect(e, WIDTH_PLUS)
	click_rect(e, HEIGHT_MINUS)
	testing.expect(t, e.tileset.width == 18 && e.tileset.height == 15 && e.mode == .Setup && e.row == .Height)
	testing.expect(t, e.tileset.images[1].width == 18 && e.tileset.images[1].height == 15)
	click_rect(e, WIDTH_MINUS)
	click_rect(e, HEIGHT_PLUS)
	click_rect(e, HEIGHT_PLUS)
	testing.expect(t, e.tileset.width == 17 && e.tileset.height == 17)
}

@(test)
test_save_and_load_through_the_tool :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_images(3)
	defer free(e)
	tl := tool(e)
	testing.expect_value(t, cm.tileset_name(&e.tileset, 0), "image")
	testing.expect_value(t, cm.tool_file_name(&tl), "tileset.json")
	_, saving := tl.take_save(tl.data)
	testing.expect(t, !saving)
	cm.tileset_set_name(&e.tileset, 1, "wall")
	cm.image4_set(&e.tileset.images[1], 4, 4, 9)
	e.sel = 1
	press(e, .Blue, .Green) // File, save
	text, ok := tl.take_save(tl.data)
	testing.expect(t, ok)
	tl.saved(tl.data)
	testing.expect(t, !e.dirty)

	other := new_editor()
	defer free(other)
	other.mode = .Edit // a load replaces whatever the editor was doing
	other.sel = 40
	other.confirm_delete = true
	otl := tool(other)
	testing.expect(t, otl.load(otl.data, transmute([]u8)text))
	testing.expect(t, other.tileset.count == 3 && cm.tileset_name(&other.tileset, 1) == "wall" && pixel(other, 1, 4, 4) == 9)
	testing.expect(t, other.mode == .Pick && other.sel == 2 && !other.confirm_delete && !other.dirty) // the selection is clamped
	testing.expect(t, !otl.load(otl.data, transmute([]u8)string("nope")))
	testing.expect(t, other.tileset.count == 3) // a bad file changes nothing
}

@(test)
test_file_mode_choices :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Blue, .Green)
	testing.expect(t, e.requests == {.Save} && e.mode == .Pick)
	e.requests = {}
	press(e, .Blue, .Yellow)
	testing.expect(t, e.requests == {.Load} && e.mode == .Pick)
	e.requests = {}
	press(e, .Blue, .Red)
	press(e, .Blue, .Blue)
	testing.expect(t, e.requests == {} && e.mode == .Pick)
	press(e, .Blue, .Up, .Left, .Right, .Down)
	testing.expect(t, e.mode == .File && e.requests == {})
	press(e, .Red)
	press(e, .Yellow, .Blue)
	testing.expect_value(t, e.mode, Mode.File) // File is reachable from Setup too
}

@(test)
test_leaving_asks_when_there_are_unsaved_changes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	press(e, .Red)
	testing.expect(t, take_exit(e)) // clean: leaves at once
	run(e, .New)
	e.mode = .Pick
	press(e, .Red)
	testing.expect(t, !take_exit(e) && e.confirm_exit)
	testing.expect_value(t, banner_text(e), "UNSAVED  RED: LEAVE ANYWAY")
	press(e, .Down) // another command cancels it
	testing.expect(t, !e.confirm_exit)
	press(e, .Red, .Red)
	testing.expect(t, take_exit(e))
	e.dirty = true
	click_rect(e, MENU_BUTTON) // the MENU button has the same guard
	testing.expect(t, !take_exit(e) && e.confirm_exit)
	click_at(e, 0, 0) // any other click cancels the prompt
	testing.expect(t, !e.confirm_exit)
	click_rect(e, MENU_BUTTON)
	click_rect(e, MENU_BUTTON)
	testing.expect(t, take_exit(e))
}

@(test)
test_closing_the_window_warns_about_unsaved_changes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	tl := tool(e)
	testing.expect(t, tl.allow_close(tl.data))
	run(e, .New)
	testing.expect(t, !tl.allow_close(tl.data) && e.confirm_exit)
	testing.expect(t, tl.allow_close(tl.data))
	e.confirm_exit = false
	editor_mark_saved(e)
	testing.expect(t, tl.allow_close(tl.data))
	// An edit made inside the image editor counts too.
	e.mode = .Pick
	press(e, .Green, .Green)
	testing.expect(t, e.dirty && !tl.allow_close(tl.data))
}

// --- Mouse ---

@(test)
test_clicking_a_thumbnail_selects_and_a_second_click_edits :: proc(t: ^testing.T) {
	e := with_images(12)
	defer free(e)
	click_thumb(e, 5)
	testing.expect(t, e.sel == 5 && e.mode == .Pick)
	click_thumb(e, 5) // again
	testing.expect_value(t, e.mode, Mode.Edit)
	// The image editor now owns the mouse: its BACK button returns here.
	click_rect(e, ie_back_button)
	testing.expect_value(t, e.mode, Mode.Pick)
	// From Setup, a thumbnail click selects it and goes back to Pick (without editing).
	e.mode = .Setup
	click_thumb(e, 9)
	testing.expect(t, e.sel == 9 && e.mode == .Pick)
	// An empty slot and the gap outside the grid do nothing.
	click_rect(e, grid_cell_rect(7, 7))
	testing.expect(t, e.sel == 9 && e.mode == .Pick)
	// The gap after a cell belongs to that cell.
	r := grid_cell_rect(2, 0)
	click_at(e, r.x + THUMB, r.y + 2)
	testing.expect_value(t, e.sel, 2)
}

ie_back_button :: Rect{222, 108, 28, 10} // the image editor's MENU button, labelled BACK while embedded

@(test)
test_the_wheel_scrolls_the_grid :: proc(t: ^testing.T) {
	e := with_images(100)
	defer free(e)
	editor_handle_event(e, cm.Mouse_Wheel{dy = -3}) // wheel down: later rows
	testing.expect_value(t, e.scroll, 3)
	editor_handle_event(e, cm.Mouse_Wheel{dy = 1})
	testing.expect_value(t, e.scroll, 2)
	for _ in 0 ..< 50 {
		editor_handle_event(e, cm.Mouse_Wheel{dy = -1})
	}
	testing.expect_value(t, e.scroll, grid_total_rows(100) - GRID_ROWS) // stops at the last full window
	for _ in 0 ..< 50 {
		editor_handle_event(e, cm.Mouse_Wheel{dy = 1})
	}
	testing.expect_value(t, e.scroll, 0)
	// Clicking a thumbnail in a scrolled window picks the right image.
	editor_handle_event(e, cm.Mouse_Wheel{dy = -4})
	click_thumb(e, 4 * GRID_COLS + 3)
	testing.expect_value(t, e.sel, 4 * GRID_COLS + 3)
	small := with_images(5)
	defer free(small)
	editor_handle_event(small, cm.Mouse_Wheel{dy = -3}) // everything fits: nothing to scroll
	testing.expect_value(t, small.scroll, 0)
}

@(test)
test_every_button_runs_its_row :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_images(2)
	defer free(e)
	click_rect(e, NEW_BUTTON)
	testing.expect(t, e.tileset.count == 3 && e.row == .New && e.mode == .Text)
	press(e, .Red) // keep the suggested name; the image editor opens
	press(e, .Red) // and back to the tiles
	click_rect(e, DUPLICATE_BUTTON)
	testing.expect(t, e.tileset.count == 4 && e.row == .Duplicate && e.mode == .Text)
	press(e, .Red) // keep the suggested name; the image editor opens
	press(e, .Red)
	cm.image4_set(&e.tileset.images[e.sel], 1, 1, 4)
	click_rect(e, COPY_BUTTON)
	testing.expect(t, e.has_clip && e.row == .Copy)
	click_rect(e, MOVE_LEFT_BUTTON)
	testing.expect(t, e.row == .Move_Left && e.sel == 0 || e.sel == 1) // moved one place earlier
	e.sel = 0
	click_rect(e, PASTE_BUTTON)
	testing.expect(t, pixel(e, 0, 1, 1) == 4 && e.row == .Paste)
	click_rect(e, MOVE_RIGHT_BUTTON)
	testing.expect(t, e.sel == 1 && e.row == .Move_Right)
	click_rect(e, RENAME_BUTTON)
	testing.expect(t, e.mode == .Text)
	press(e, .Red)
	click_rect(e, SAVE_BUTTON)
	click_rect(e, LOAD_BUTTON)
	testing.expect(t, e.requests == {.Save, .Load})
	click_rect(e, EDIT_BUTTON)
	testing.expect_value(t, e.mode, Mode.Edit)
}

@(test)
test_buttons_need_an_image_where_they_should :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	click_rect(e, EDIT_BUTTON)
	testing.expect(t, e.mode == .Pick && e.note == NOTE_NO_IMAGES)
	click_rect(e, RENAME_BUTTON)
	testing.expect(t, e.mode == .Setup && e.note == NOTE_NO_IMAGES)
	click_rect(e, NEW_BUTTON) // New always works
	testing.expect_value(t, e.tileset.count, 1)
}

@(test)
test_a_note_clears_on_the_next_input_but_not_on_mouse_movement :: proc(t: ^testing.T) {
	e := new_editor()
	defer free(e)
	press(e, .Green)
	testing.expect_value(t, e.note, NOTE_NO_IMAGES)
	editor_handle_event(e, cm.Mouse_Move{5, 5})
	testing.expect_value(t, e.note, NOTE_NO_IMAGES)
	mouse(e, 0, 0, false) // releasing does not clear it either
	testing.expect_value(t, e.note, NOTE_NO_IMAGES)
	press(e, .Left)
	testing.expect_value(t, e.note, "")
}

// --- Lifecycle ---

@(test)
test_enter_starts_blank_and_asks_for_the_files :: proc(t: ^testing.T) {
	e := with_images(5)
	defer free(e)
	m := cm.default_input_map()
	editor_set_labels(e, &m)
	e.mode = .Edit
	e.dirty, e.confirm_exit, e.confirm_delete, e.has_clip = true, true, true, true
	e.palette[0] = {9, 9, 9}
	cm.tileset_set_size(&e.tileset, 5, 5)
	tl := tool(e)
	tl.enter(tl.data)
	testing.expect(t, e.tileset.count == 0 && e.tileset.width == 16 && e.mode == .Pick && !e.dirty)
	testing.expect(t, !e.confirm_exit && !e.confirm_delete && !e.has_clip && e.palette == cm.default_palette())
	testing.expect(t, e.labels == &m && e.editor.labels == &m) // the input map is kept, also for the image editor
	testing.expect(t, e.requests == {.Load} && e.aux_requests == {.Palette})
	testing.expect(t, tl.wants_load(tl.data) && !tl.wants_load(tl.data))
	testing.expect(t, tl.wants_aux_load(tl.data) && !tl.wants_aux_load(tl.data))
}

@(test)
test_the_palette_comes_from_the_aux_file :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	tl := tool(e)
	testing.expect_value(t, cm.tool_aux_file_name(&tl), "palette.json")
	custom := cm.default_palette()
	custom[2] = {7, 8, 9}
	testing.expect(t, tl.load_aux(tl.data, transmute([]u8)cm.palette_to_json(custom)))
	testing.expect(t, e.palette[2] == cm.Color{7, 8, 9} && !e.dirty)
	testing.expect(t, !tl.load_aux(tl.data, transmute([]u8)string("not json")))
	testing.expect(t, e.palette[2] == cm.Color{7, 8, 9})
}

// --- Layout, drawing and text ---

@(test)
test_layout_fits_the_screen_and_does_not_overlap :: proc(t: ^testing.T) {
	grid := Rect{GRID_X - 1, GRID_Y - 1, GRID_COLS * GRID_PITCH + 1, GRID_ROWS * GRID_PITCH + 1}
	rects := [?]Rect{grid, BANNER, WIDTH_MINUS, WIDTH_PLUS, HEIGHT_MINUS, HEIGHT_PLUS, PREVIEW_FRAME, RENAME_BUTTON, NEW_BUTTON, DUPLICATE_BUTTON, DELETE_BUTTON, COPY_BUTTON, PASTE_BUTTON, MOVE_LEFT_BUTTON, MOVE_RIGHT_BUTTON, SAVE_BUTTON, LOAD_BUTTON, EDIT_BUTTON, MENU_BUTTON}
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	// The text areas on the right panel clear what is beside them.
	testing.expect(t, grid.x + grid.w <= ROW_MARKER_X && ROW_MARKER_X + cm.text_width(">") < ROW_LABEL_X)
	testing.expect(t, ROW_LABEL_X + cm.text_width("HEIGHT") < HEIGHT_MINUS.x && ROW_VALUE_X > WIDTH_PLUS.x + WIDTH_PLUS.w)
	testing.expect(t, ROW_VALUE_X + cm.text_width("64") <= PREVIEW_FRAME.x)
	testing.expect(t, INFO_Y > BANNER.y + BANNER.h && NAME_Y > INFO_Y + cm.GLYPH_H && WIDTH_MINUS.y > NAME_Y + cm.GLYPH_H - 3)
	testing.expect(t, CLIP_Y > PREVIEW_FRAME.y + PREVIEW_FRAME.h && CLIP_Y + cm.GLYPH_H <= RENAME_BUTTON.y)
	testing.expect(t, HELP_Y >= MENU_BUTTON.y + MENU_BUTTON.h && grid.y + grid.h <= HELP_Y)
	// The preview's inner area is inside its frame, and the 32 character name line fits the panel.
	in_ := PREVIEW_INNER
	testing.expect(t, in_.x > PREVIEW_FRAME.x && in_.y > PREVIEW_FRAME.y && in_.x + in_.w < PREVIEW_FRAME.x + PREVIEW_FRAME.w && in_.y + in_.h < PREVIEW_FRAME.y + PREVIEW_FRAME.h)
	testing.expect(t, INFO_X + cm.text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W)
	testing.expect(t, CLIP_X + cm.text_width("CLIP: WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") <= cm.SCREEN_W)
	for b in buttons() {
		testing.expectf(t, cm.text_width(b.text) <= b.rc.w - 2 && cm.GLYPH_H <= b.rc.h, "label %s does not fit its button", b.text)
	}
}

@(test)
test_the_button_table_matches_the_rects_and_rows :: proc(t: ^testing.T) {
	seen: bit_set[Setup_Row]
	for b in buttons() {
		if row, has := b.row.?; has {
			seen += {row}
		}
	}
	// Every action row has a button (Width and Height have the - and + buttons instead).
	for row in Setup_Row {
		if row != .Width && row != .Height {
			testing.expectf(t, row in seen, "no button for %v", row)
		}
	}
	for c in 0 ..< 4 {
		for r in 0 ..< 3 {
			rc := button_rect(c, r)
			testing.expect(t, rc.x == BUTTON_X[c] && rc.y == BUTTON_Y[r])
		}
	}
}

@(test)
test_grid_geometry_round_trips :: proc(t: ^testing.T) {
	for row in 0 ..< GRID_ROWS {
		for col in 0 ..< GRID_COLS {
			rc := grid_cell_rect(col, row)
			for p in ([][2]int{{0, 0}, {THUMB - 1, THUMB - 1}, {THUMB, THUMB}, {THUMB / 2, THUMB / 2}}) {
				c, r, ok := grid_cell_at(rc.x + p.x, rc.y + p.y)
				testing.expectf(t, ok && c == col && r == row, "cell (%d,%d) point %v", col, row, p)
			}
		}
	}
	_, _, ok := grid_cell_at(GRID_X - 1, GRID_Y)
	testing.expect(t, !ok)
	_, _, ok = grid_cell_at(GRID_X + GRID_COLS * GRID_PITCH, GRID_Y)
	testing.expect(t, !ok)
	_, _, ok = grid_cell_at(GRID_X, GRID_Y + GRID_ROWS * GRID_PITCH)
	testing.expect(t, !ok)
	testing.expect_value(t, grid_total_rows(0), 0)
	testing.expect_value(t, grid_total_rows(1), 1)
	testing.expect_value(t, grid_total_rows(8), 1)
	testing.expect_value(t, grid_total_rows(9), 2)
	testing.expect_value(t, grid_total_rows(256), 32)
}

@(test)
test_all_on_screen_text_is_in_the_font_and_fits :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_images(2)
	defer free(e)
	m := cm.default_input_map()
	editor_set_labels(e, &m)
	for round in 0 ..< 2 {
		if round == 1 { 	// the longest labels allowed
			for a in cm.Action {
				cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
			}
		}
		for mode in ([]Mode{.Pick, .Setup, .File}) {
			e.mode = mode
			for confirm in ([]int{0, 1, 2}) { 	// none, leave anyway, delete
				e.confirm_exit, e.confirm_delete = confirm == 1, confirm == 2
				text := banner_text(e)
				if round == 0 {
					testing.expectf(t, cm.text_is_drawable(text), "banner: %s", text)
				}
				testing.expectf(t, cm.text_width(text) + 8 <= BANNER.w, "banner too wide: %s", text)
			}
			lines, n := help_lines(e)
			for line in lines[:n] {
				if round == 0 {
					testing.expectf(t, cm.text_is_drawable(line), "help: %s", line)
				}
				testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
			}
			testing.expect(t, HELP_Y + n * cm.LINE_ADVANCE <= cm.SCREEN_H)
		}
	}
	for note in ([]string{NOTE_NO_IMAGES, NOTE_FULL, NOTE_NOTHING_TO_PASTE, NOTE_NAME_EMPTY, NOTE_NAME_USED, NOTE_NAME_BAD}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 4, "note: %s", note)
		testing.expectf(t, cm.text_is_drawable(note), "keypad note: %s", note)
	}
	for b in buttons() {
		testing.expect(t, cm.text_is_drawable(b.text))
	}
	testing.expect(t, cm.text_is_drawable("IMAGE 256 OF 256 *") && cm.text_is_drawable("NO IMAGES YET *") && cm.text_is_drawable("RENAME IMAGE"))
}

Draw_Log :: struct {
	rects, out_of_bounds, presents: int,
}

logging_renderer :: proc(l: ^Draw_Log) -> cm.Renderer {
	return cm.Renderer {
		data = l,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^Draw_Log)(d)
			k.rects += 1
			if x < 0 || y < 0 || x + w > cm.SCREEN_W || y + h > cm.SCREEN_H {
				k.out_of_bounds += 1
			}
		},
		present = proc(d: rawptr) {(^Draw_Log)(d).presents += 1},
	}
}

@(test)
test_every_screen_draws_on_screen_in_every_mode_and_size :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Draw_Log
	r := logging_renderer(&log)
	for size in ([][2]int{{1, 1}, {16, 16}, {8, 3}, {64, 64}, {64, 5}}) {
		e := new_editor()
		cm.tileset_set_size(&e.tileset, size[0], size[1])
		for i in 0 ..< 100 {
			n := cm.tileset_insert_blank(&e.tileset, e.tileset.count, "t")
			for k in 0 ..< min(size[0], size[1]) { 	// a busy picture: every colour on the diagonal
				cm.image4_set(&e.tileset.images[n], k, k, (k + i) % 16)
			}
		}
		e.has_clip = true
		e.clip_name_len = 32
		for mode in ([]Mode{.Pick, .Setup, .File, .Text, .Edit}) {
			e.sel = 50
			fix_selection(e)
			if mode == .Edit {
				e.mode = .Pick
				press(e, .Green) // real Edit mode with the image editor embedded
			} else if mode == .Text {
				e.mode = .Pick
				run(e, .Rename)
			} else {
				e.mode = mode
			}
			log = {}
			editor_draw(e, &r)
			testing.expectf(t, log.out_of_bounds == 0, "%dx%d %v: %d rects off screen", size[0], size[1], mode, log.out_of_bounds)
			testing.expect_value(t, log.presents, 1)
			testing.expectf(t, log.rects < 30000, "%dx%d %v: %d rects is too many for one frame", size[0], size[1], mode, log.rects)
		}
		free(e)
	}
}

// --- Parity: every function is reachable with the commands alone and with the mouse alone. ---

Input_Method :: enum {
	Commands,
	Mouse,
}

@(test)
test_every_image_can_be_selected_and_edited_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for target in ([]int{0, 1, 7, 8, 9, 31, 32, 63, 64, 100, 255}) {
			e := with_images(256)
			switch m {
			case .Commands:
				for _ in 0 ..< target / GRID_COLS {
					press(e, .Down)
				}
				for _ in 0 ..< target % GRID_COLS {
					press(e, .Right)
				}
				press(e, .Green)
			case .Mouse:
				for _ in 0 ..< 40 { 	// scroll until the target row is in the window
					if target / GRID_COLS >= e.scroll + GRID_ROWS {
						editor_handle_event(e, cm.Mouse_Wheel{dy = -1})
					}
				}
				click_thumb(e, target)
				click_thumb(e, target)
			}
			ok := e.sel == target && e.mode == .Edit
			free(e)
			testing.expectf(t, ok, "%v could not select and edit image %d", m, target)
		}
	}
}

@(test)
test_every_action_is_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		e := with_images(3)
		e.sel = 1
		cm.image4_set(&e.tileset.images[1], 2, 2, 5)
		do_row :: proc(e: ^Editor, m: Input_Method, row: Setup_Row, button: Rect) {
			switch m {
			case .Commands:
				run(e, row)
			case .Mouse:
				e.mode = .Pick
				click_rect(e, button)
			}
		}
		do_row(e, m, .Copy, COPY_BUTTON)
		testing.expectf(t, e.has_clip, "%v copy", m)
		do_row(e, m, .Duplicate, DUPLICATE_BUTTON)
		testing.expectf(t, e.tileset.count == 4 && e.sel == 2, "%v duplicate", m)
		do_row(e, m, .New, NEW_BUTTON)
		testing.expectf(t, e.tileset.count == 5 && e.sel == 3, "%v new", m)
		do_row(e, m, .Paste, PASTE_BUTTON)
		testing.expectf(t, pixel(e, 3, 2, 2) == 5, "%v paste", m)
		do_row(e, m, .Move_Left, MOVE_LEFT_BUTTON)
		testing.expectf(t, e.sel == 2, "%v move left", m)
		do_row(e, m, .Move_Right, MOVE_RIGHT_BUTTON)
		testing.expectf(t, e.sel == 3, "%v move right", m)
		do_row(e, m, .Delete, DELETE_BUTTON)
		switch m {
		case .Commands:
			press(e, .Green) // the confirming press
		case .Mouse:
			click_rect(e, DELETE_BUTTON)
		}
		testing.expectf(t, e.tileset.count == 4, "%v delete", m)
		do_row(e, m, .Rename, RENAME_BUTTON)
		testing.expectf(t, e.mode == .Text, "%v rename", m)
		free(e)
	}
}

@(test)
test_the_tile_size_save_load_and_leave_are_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for w in ([]int{1, 8, 33, 64}) {
			for h in ([]int{1, 16, 64}) {
				e := new_editor()
				switch m {
				case .Commands:
					e.mode = .Setup
					goto_row(e, .Width)
					for _ in 0 ..< 70 {
						press(e, .Left)
					}
					for _ in 0 ..< w - 1 {
						press(e, .Right)
					}
					press(e, .Down)
					for _ in 0 ..< 70 {
						press(e, .Left)
					}
					for _ in 0 ..< h - 1 {
						press(e, .Right)
					}
				case .Mouse:
					for _ in 0 ..< 70 {
						click_rect(e, WIDTH_MINUS)
						click_rect(e, HEIGHT_MINUS)
					}
					for _ in 0 ..< w - 1 {
						click_rect(e, WIDTH_PLUS)
					}
					for _ in 0 ..< h - 1 {
						click_rect(e, HEIGHT_PLUS)
					}
				}
				ok := e.tileset.width == w && e.tileset.height == h
				free(e)
				testing.expectf(t, ok, "%v: wanted a %dx%d tile", m, w, h)
			}
		}
		for req in Request {
			e := new_editor()
			switch m {
			case .Commands:
				press(e, .Blue, req == .Save ? .Green : .Yellow)
			case .Mouse:
				click_rect(e, req == .Save ? SAVE_BUTTON : LOAD_BUTTON)
			}
			ok := req in e.requests
			free(e)
			testing.expectf(t, ok, "%v could not request %v", m, req)
		}
		e := new_editor()
		switch m {
		case .Commands:
			press(e, .Red)
		case .Mouse:
			click_rect(e, MENU_BUTTON)
		}
		ok := take_exit(e)
		free(e)
		testing.expectf(t, ok, "%v could not leave", m)
	}
}

@(test)
test_a_name_can_be_typed_with_the_mouse_alone_or_the_commands_alone :: proc(t: ^testing.T) {
	for m in Input_Method {
		e := with_images(1)
		switch m {
		case .Commands:
			run(e, .Rename)
			press_keypad_action(e, .Clear)
			type_with_commands(e, "Hello, World 42!")
			press_keypad_action(e, .Done)
		case .Mouse:
			click_rect(e, RENAME_BUTTON)
			click_kp :: proc(e: ^Editor, col, row: int) {
				r := cm.text_entry_cell_rect(col, row)
				click_at(e, r.x + r.w / 2, r.y + r.h / 2)
			}
			click_kp(e, 4, cm.TEXT_ENTRY_ROWS - 1) // CLEAR
			for ch in ([]u8{'H', 'e', 'l', 'l', 'o', ',', ' ', 'W', 'o', 'r', 'l', 'd', ' ', '4', '2', '!'}) {
				for r in 0 ..< cm.TEXT_ENTRY_CHAR_ROWS {
					for c in 0 ..< cm.TEXT_ENTRY_COLS {
						if g, ok := cm.text_entry_char_at(c, r); ok && g == ch {
							click_kp(e, c, r)
						}
					}
				}
			}
			click_kp(e, 8, cm.TEXT_ENTRY_ROWS - 1) // DONE
		}
		got := fmt.tprintf("%s", name_of(e, 0))
		free(e)
		testing.expectf(t, got == "Hello, World 42!", "%v typed %q", m, got)
	}
}

@(test)
test_new_asks_for_a_name_then_opens_the_image_editor :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	press(e, .Yellow)
	goto_row(e, .New)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Text)
	press_keypad_action(e, .Clear)
	type_with_commands(e, "Grass")
	press_keypad_action(e, .Done)
	testing.expect(t, e.mode == .Edit && name_of(e, 0) == "Grass")
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Pick)
	// A refused name keeps asking; Rename afterwards does not open the image editor.
	press(e, .Yellow)
	goto_row(e, .New)
	press(e, .Green)
	press_keypad_action(e, .Clear)
	type_with_commands(e, "Grass")
	press_keypad_action(e, .Done)
	testing.expect_value(t, e.mode, Mode.Text)
	press_keypad_action(e, .Cancel)
	testing.expect_value(t, e.mode, Mode.Edit) // cancelling keeps the suggested name
	press(e, .Red)
	e.mode = .Setup
	run(e, .Rename)
	press_keypad_action(e, .Cancel)
	testing.expect_value(t, e.mode, Mode.Setup)
}
