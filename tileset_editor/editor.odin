package tileset_editor

import cm "../common"
import ie "../image_editor"
import "core:mem"

Request :: enum {
	Save,
	Load,
}

Aux_Request :: enum {
	Palette,
}

// Red always means "back". Five modes:
//   Pick:  d-pad moves over the thumbnails (left/right one image, up/down one row of eight); green
//          edits the selected image; yellow opens Setup; blue opens File; red leaves for the main
//          menu (twice if there are unsaved changes).
//   Edit:  the image editor, with all its tools, on the selected image. The tile size is the
//          tileset's, so it cannot be changed there and only a square tile can be turned a quarter.
//          Red returns to the thumbnails.
//   Setup: up/down choose a row, left/right change the tile size (Width, Height rows), green runs
//          the action rows: Rename (opens the keypad), New (a blank image after the selected one),
//          Duplicate, Delete (green twice), Copy, Paste (replace the selected image's pixels with
//          the copy) and Move left / Move right (reorder). Blue opens File; red returns to Pick.
//   File:  green saves, yellow loads, red or blue cancel; every choice returns to Pick.
//   Text:  the keypad, for renaming.
// The mouse works in every mode (click a thumbnail to select it and again to edit; a button for
// every row) and switches mode itself.
Mode :: enum {
	Pick,
	Edit,
	Setup,
	File,
	Text,
}

Setup_Row :: enum {
	Rename,
	New,
	Duplicate,
	Delete,
	Copy,
	Paste,
	Move_Left,
	Move_Right,
	Width,
	Height,
}

// State for the tileset editor. About 1 MB because of the tileset: create it as a global or with
// new() and initialise it in place with editor_init. Never copy or return one by value.
Editor :: struct {
	tileset:        cm.Tileset,
	sel:            int, // the selected image; always valid when the tileset has images, else 0
	scroll:         int, // the first visible grid row
	mode:           Mode,
	row:            Setup_Row,
	edit_after_name: bool, // the keypad was opened by New or Duplicate: go on to the image editor when it closes
	dirty:          bool, // the tileset changed since the last save/load
	requests:       bit_set[Request],
	aux_requests:   bit_set[Aux_Request],
	exit_requested: bool,
	confirm_exit:   bool, // unsaved changes: the next exit request is the confirmation
	confirm_delete: bool, // Delete was run once: the next Delete is the confirmation
	note:           string, // a one-line message about the last action; cleared by the next input
	clipboard:      cm.Image4, // the last copied image (when has_clip)
	has_clip:       bool,
	clip_name:      [cm.TILESET_NAME_MAX]u8,
	clip_name_len:  int,
	palette:        cm.Palette, // the palette editor's saved palette, or the default
	editor:         ie.Editor, // the image editor, while in Edit mode
	entry:          cm.Text_Entry, // the keypad, while in Text mode
	labels:         ^cm.Input_Map,
}

NOTE_NO_IMAGES :: "NO IMAGES YET: USE NEW"
NOTE_FULL :: "THE TILESET IS FULL"
NOTE_NOTHING_TO_PASTE :: "NOTHING COPIED YET"
NOTE_NAME_EMPTY :: "A NAME CANNOT BE EMPTY"
NOTE_NAME_USED :: "NAME ALREADY IN USE"
NOTE_NAME_BAD :: "UNUSABLE CHARACTER IN NAME"

// Starts blank: no images, 16 x 16 tiles, the default palette.
editor_init :: proc(e: ^Editor) {
	labels := e.labels
	mem.zero_item(e)
	e.labels = labels
	cm.tileset_reset(&e.tileset)
	e.palette = cm.default_palette()
	e.editor = ie.editor_init()
	e.editor.labels = labels
}

// Called each time the tool becomes the active one: start blank (so unsaved edits do not survive
// leaving), then ask the frontend for the saved tileset and the palette.
editor_enter :: proc(e: ^Editor) {
	editor_init(e)
	e.requests = {.Load}
	e.aux_requests = {.Palette}
}

editor_mark_saved :: proc(e: ^Editor) {
	e.dirty = false
}

editor_set_labels :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.labels = m
	e.editor.labels = m
}

editor_set_palette :: proc(e: ^Editor, p: cm.Palette) {
	e.palette = p
}

has_images :: proc(e: ^Editor) -> bool {
	return e.tileset.count > 0
}

// The selected image's name ("" if the tileset is empty).
selected_name :: proc(e: ^Editor) -> string {
	return cm.tileset_name(&e.tileset, e.sel)
}

// Keeps the selection valid and the selected row visible after the tileset changed.
fix_selection :: proc(e: ^Editor) {
	e.sel = clamp(e.sel, 0, max(e.tileset.count - 1, 0))
	rows := grid_total_rows(e.tileset.count)
	row := e.sel / GRID_COLS
	if row < e.scroll {
		e.scroll = row
	} else if row >= e.scroll + GRID_ROWS {
		e.scroll = row - GRID_ROWS + 1
	}
	e.scroll = clamp(e.scroll, 0, max(rows - GRID_ROWS, 0))
}

@(private = "file")
select :: proc(e: ^Editor, index: int) {
	e.sel = index
	fix_selection(e)
}

// Something changed: the unsaved marker goes on.
@(private = "file")
touched :: proc(e: ^Editor) {
	e.dirty = true
}

// --- Actions on the selected image (also the Setup rows) ---

@(private = "file")
need_images :: proc(e: ^Editor) -> bool {
	if !has_images(e) {
		e.note = NOTE_NO_IMAGES
		return false
	}
	return true
}

@(private = "file")
begin_rename :: proc(e: ^Editor) {
	if need_images(e) {
		cm.text_entry_begin(&e.entry, "RENAME IMAGE", selected_name(e), cm.TILESET_NAME_MAX)
		e.mode = .Text
	}
}

@(private = "file")
new_image :: proc(e: ^Editor) {
	at := has_images(e) ? e.sel + 1 : 0
	if n := cm.tileset_insert_blank(&e.tileset, at, "image"); n >= 0 {
		select(e, n)
		touched(e)
		begin_rename(e) // name it first, then draw it
		e.edit_after_name = true
	} else {
		e.note = NOTE_FULL
	}
}

@(private = "file")
duplicate_image :: proc(e: ^Editor) {
	if !need_images(e) {
		return
	}
	if n := cm.tileset_duplicate(&e.tileset, e.sel); n >= 0 {
		select(e, n)
		touched(e)
		begin_rename(e) // give the copy its own name, then edit it
		e.edit_after_name = true
	} else {
		e.note = NOTE_FULL
	}
}

// The first call arms the deletion (the banner asks for confirmation); the next one deletes.
@(private = "file")
delete_image :: proc(e: ^Editor) {
	if !need_images(e) {
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.tileset_delete(&e.tileset, e.sel)
	fix_selection(e)
	touched(e)
}

@(private = "file")
copy_image :: proc(e: ^Editor) {
	if !need_images(e) {
		return
	}
	e.clipboard = e.tileset.images[e.sel]
	name := selected_name(e)
	e.clip_name = {}
	copy(e.clip_name[:], name)
	e.clip_name_len = len(name)
	e.has_clip = true
}

// Replaces the selected image's pixels with the copy (fitted to the current tile size).
@(private = "file")
paste_image :: proc(e: ^Editor) {
	if !need_images(e) {
		return
	}
	if !e.has_clip {
		e.note = NOTE_NOTHING_TO_PASTE
		return
	}
	fitted := e.clipboard
	cm.image4_resize(&fitted, e.tileset.width, e.tileset.height)
	if !cm.image4_visible_equal(&e.tileset.images[e.sel], &fitted) {
		e.tileset.images[e.sel] = fitted
		touched(e)
	}
}

@(private = "file")
move_image :: proc(e: ^Editor, delta: int) {
	if !need_images(e) {
		return
	}
	if n := cm.tileset_move(&e.tileset, e.sel, delta); n != e.sel {
		select(e, n)
		touched(e)
	}
}

@(private = "file")
change_size :: proc(e: ^Editor, w, h: int) {
	if cm.tileset_set_size(&e.tileset, w, h) {
		touched(e)
	}
}

// Starts editing the selected image in the embedded image editor.
@(private = "file")
begin_edit :: proc(e: ^Editor) {
	if !need_images(e) {
		return
	}
	ie.editor_begin_embedded(&e.editor, &e.tileset.images[e.sel], &e.palette)
	e.editor.labels = e.labels
	e.mode = .Edit
}

// Copies the embedded editor's image back into the tileset if it changed, and leaves Edit mode
// when the image editor asks to.
@(private = "file")
sync_embedded :: proc(e: ^Editor) {
	if e.editor.dirty {
		e.tileset.images[e.sel] = e.editor.image
		e.editor.dirty = false
		touched(e)
	}
	if e.editor.exit_requested {
		e.editor.exit_requested = false
		e.mode = .Pick
	}
}

@(private = "file")
run_row :: proc(e: ^Editor, row: Setup_Row) {
	switch row {
	case .Rename:
		begin_rename(e)
	case .New:
		new_image(e)
	case .Duplicate:
		duplicate_image(e)
	case .Delete:
		delete_image(e)
	case .Copy:
		copy_image(e)
	case .Paste:
		paste_image(e)
	case .Move_Left:
		move_image(e, -1)
	case .Move_Right:
		move_image(e, 1)
	case .Width, .Height:
		// Settings, not actions: left/right change them.
	}
}

@(private = "file")
change_setting :: proc(e: ^Editor, row: Setup_Row, delta: int) {
	#partial switch row {
	case .Width:
		change_size(e, e.tileset.width + delta, e.tileset.height)
	case .Height:
		change_size(e, e.tileset.width, e.tileset.height + delta)
	}
}

// --- Events ---

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	// The keypad and the image editor see everything while they are up.
	switch e.mode {
	case .Text:
		handle_text(e, ev)
		return
	case .Edit:
		ie.editor_handle_event(&e.editor, ev)
		sync_embedded(e)
		return
	case .Pick, .Setup, .File:
	}
	// Any command or button press clears the message; moving the mouse or letting go does not.
	#partial switch v in ev {
	case cm.Command:
		e.note = ""
	case cm.Mouse_Button_Event:
		if v.down {
			e.note = ""
		}
	}
	switch v in ev {
	case cm.Command:
		editor_apply_action(e, v.action)
	case cm.Mouse_Move:
	case cm.Mouse_Button_Event:
		if v.button == .Left && v.down {
			click(e, v.x, v.y)
		}
	case cm.Mouse_Wheel:
		e.scroll = clamp(e.scroll - v.dy, 0, max(grid_total_rows(e.tileset.count) - GRID_ROWS, 0))
	}
}

// After naming a brand new image the image editor opens on it.
@(private = "file")
finish_name :: proc(e: ^Editor) {
	if e.edit_after_name {
		e.edit_after_name = false
		begin_edit(e)
	}
}

@(private = "file")
handle_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = .Setup
		finish_name(e)
	case .Done:
		name := cm.text_entry_text(&e.entry)
		switch cm.tileset_check_name(&e.tileset, e.sel, name) {
		case .None:
			if name != selected_name(e) {
				cm.tileset_set_name(&e.tileset, e.sel, name)
				touched(e)
			}
			e.mode = .Setup
			finish_name(e)
		case .Empty:
			cm.text_entry_resume(&e.entry, NOTE_NAME_EMPTY)
		case .In_Use:
			cm.text_entry_resume(&e.entry, NOTE_NAME_USED)
		case .Too_Long, .Bad_Character:
			cm.text_entry_resume(&e.entry, NOTE_NAME_BAD)
		}
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action) {
	if a != .Red {
		e.confirm_exit = false // any other command cancels the "leave anyway?" prompt
	}
	if !(e.mode == .Setup && e.row == .Delete && a == .Green) {
		e.confirm_delete = false // so does anything but running Delete again
	}
	switch e.mode {
	case .Pick:
		#partial switch a {
		case .Up:
			if has_images(e) && e.sel - GRID_COLS >= 0 {
				select(e, e.sel - GRID_COLS)
			}
		case .Down:
			if has_images(e) && e.sel + GRID_COLS < e.tileset.count {
				select(e, e.sel + GRID_COLS)
			}
		case .Left:
			if e.sel > 0 {
				select(e, e.sel - 1)
			}
		case .Right:
			if e.sel + 1 < e.tileset.count {
				select(e, e.sel + 1)
			}
		case .Green:
			begin_edit(e)
		case .Yellow:
			e.mode = .Setup
		case .Blue:
			e.mode = .File
		case .Red:
			request_exit(e)
		}
	case .Setup:
		#partial switch a {
		case .Up:
			e.row = Setup_Row((int(e.row) + len(Setup_Row) - 1) % len(Setup_Row))
		case .Down:
			e.row = Setup_Row((int(e.row) + 1) % len(Setup_Row))
		case .Left:
			change_setting(e, e.row, -1)
		case .Right:
			change_setting(e, e.row, 1)
		case .Green:
			run_row(e, e.row)
		case .Blue:
			e.mode = .File
		case .Red:
			e.mode = .Pick
		}
	case .File:
		#partial switch a {
		case .Green:
			e.requests += {.Save}
			e.mode = .Pick
		case .Yellow:
			e.requests += {.Load}
			e.mode = .Pick
		case .Red, .Blue:
			e.mode = .Pick
		}
	case .Edit, .Text:
		// Handled before this point: those modes own the input.
	}
}

// Leaving with unsaved changes needs a second request.
@(private = "file")
request_exit :: proc(e: ^Editor) {
	if e.dirty && !e.confirm_exit {
		e.confirm_exit = true
		return
	}
	e.confirm_exit = false
	e.exit_requested = true
}

// The window is closing. Clean: fine. Dirty: the first ask shows the "unsaved" prompt and says no;
// asking again while the prompt is still up says yes.
editor_allow_close :: proc(e: ^Editor) -> bool {
	if !e.dirty || e.confirm_exit {
		return true
	}
	e.confirm_exit = true
	return false
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int) {
	if !rect_contains(MENU_BUTTON, x, y) {
		e.confirm_exit = false
	}
	if !rect_contains(DELETE_BUTTON, x, y) {
		e.confirm_delete = false
	}
	if col, row, ok := grid_cell_at(x, y); ok {
		index := (e.scroll + row) * GRID_COLS + col
		if index < e.tileset.count {
			if index == e.sel && e.mode == .Pick {
				begin_edit(e) // clicking the selected image again edits it
			} else {
				select(e, index)
				e.mode = .Pick
			}
		}
		return
	}
	// A button: it opens Setup on its row (so the keyboard and mouse agree) and runs it.
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		run_row(e, row)
	}
	switch {
	case rect_contains(WIDTH_MINUS, x, y):
		e.mode, e.row = .Setup, .Width
		change_setting(e, .Width, -1)
	case rect_contains(WIDTH_PLUS, x, y):
		e.mode, e.row = .Setup, .Width
		change_setting(e, .Width, 1)
	case rect_contains(HEIGHT_MINUS, x, y):
		e.mode, e.row = .Setup, .Height
		change_setting(e, .Height, -1)
	case rect_contains(HEIGHT_PLUS, x, y):
		e.mode, e.row = .Setup, .Height
		change_setting(e, .Height, 1)
	case rect_contains(RENAME_BUTTON, x, y):
		action(e, .Rename)
	case rect_contains(NEW_BUTTON, x, y):
		action(e, .New)
	case rect_contains(DUPLICATE_BUTTON, x, y):
		action(e, .Duplicate)
	case rect_contains(DELETE_BUTTON, x, y):
		action(e, .Delete) // a second click confirms
	case rect_contains(COPY_BUTTON, x, y):
		action(e, .Copy)
	case rect_contains(PASTE_BUTTON, x, y):
		action(e, .Paste)
	case rect_contains(MOVE_LEFT_BUTTON, x, y):
		action(e, .Move_Left)
	case rect_contains(MOVE_RIGHT_BUTTON, x, y):
		action(e, .Move_Right)
	case rect_contains(EDIT_BUTTON, x, y):
		begin_edit(e)
	case rect_contains(SAVE_BUTTON, x, y):
		e.requests += {.Save}
	case rect_contains(LOAD_BUTTON, x, y):
		e.requests += {.Load}
	case rect_contains(MENU_BUTTON, x, y):
		request_exit(e)
	}
}
