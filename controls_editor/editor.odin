package controls_editor

import cm "../common"
import "core:fmt"

// The controls editor edits input_map.json: which key and which gamepad button mean each of the eight
// commands, and what the tools call each command on screen. It works on the *live* map the frontend
// gave the tool, so a change applies at once (the next press is already read with it); SAVE writes
// input_map.json, keeping the notes of the file it replaces. Pad buttons and keys are captured raw
// (Tool.wants_raw): the frontends hand the next press over instead of turning it into a command.
//
//   Table:   up/down choose a row (the commands, then DEFAULTS), left/right choose the column (key,
//            pad button, label); green on a key or pad cell captures the next press, on a label opens
//            the keypad, on DEFAULTS asks (green again resets, in memory); yellow unbinds the cell (a
//            label goes back to the command's name); blue opens File; red leaves (asks first when
//            there are unsaved changes).
//   Capture: press the new key or pad button. A key or button another command already has is refused
//            (the note says which). Only the mouse (CANCEL) or a few seconds of waiting abandons it.
//   File:    green saves, yellow loads the file again (dropping unsaved edits), red or blue cancel.
//   Text:    the keypad, for a label (empty = the command's name).
// The mouse works everywhere: click a cell as green does and use the buttons.
Mode :: enum {
	Table,
	Capture,
	File,
	Text,
}

Request :: enum {
	Save,
	Load,
}

ORIGINAL_CAP :: 16 * 1024 // the largest file whose notes are kept
CAPTURE_MS :: 8000.0 // how long a capture waits before it gives up

Editor :: struct {
	map_:           ^cm.Input_Map, // the live map (the frontend's), or `own` when run on its own
	own:            cm.Input_Map,
	saved:          cm.Input_Map, // what the file holds (as far as this editor knows)
	original:       [ORIGINAL_CAP]u8, // the file's text, for its notes
	original_len:   int,
	row:            int, // 0..7 a command, 8 the defaults row
	col:            Column,
	mode:           Mode,
	capture_col:    Column, // Capture: .Key or .Pad
	capture_ms:     f64, // how long the capture has waited
	requests:       bit_set[Request],
	confirm_leave:  bool, // red was pressed with unsaved changes: the next red leaves
	confirm_reset:  bool, // green on DEFAULTS: the next green resets
	exit_requested: bool,
	note:           string,
	pending:        [ORIGINAL_CAP]u8, // the text handed to the frontend for the save in progress
	pending_len:    int,
	entry:          cm.Text_Entry,
}

NOTE_KEY_ONLY :: "PRESS A KEY, NOT A PAD BUTTON"
NOTE_PAD_ONLY :: "PRESS A PAD BUTTON, NOT A KEY"
NOTE_BAD_KEY :: "THAT KEY CANNOT BE BOUND"
NOTE_TIMED_OUT :: "NOTHING PRESSED: CANCELLED"
NOTE_FILE_BAD :: "THE FILE IS NOT VALID: KEPT WHAT YOU HAVE"
NOTE_RESET_ASK :: "PRESS AGAIN TO RESET EVERYTHING"

// A ready editor working on its own copy of the defaults (the frontend replaces it with the live map).
editor_init :: proc() -> (e: Editor) {
	e.own = cm.default_input_map()
	e.saved = e.own
	e.map_ = &e.own
	return
}

// The frontend gives the live map once; the editor edits it in place.
editor_set_map :: proc(e: ^Editor, m: ^cm.Input_Map) {
	e.map_ = m
	e.saved = m^
}

// Each time the tool is opened: back to the table, and ask for the file again (it may have changed).
editor_enter :: proc(e: ^Editor) {
	e.mode = .Table
	e.row, e.col = 0, .Key
	e.confirm_leave, e.confirm_reset = false, false
	e.exit_requested = false
	e.note = ""
	e.saved = e.map_^ // until the file says otherwise, the live map is what the file holds
	e.requests = {.Load}
}

editor_dirty :: proc(e: ^Editor) -> bool {
	return e.map_^ != e.saved
}

action_at :: proc(row: int) -> cm.Action {
	return cm.Action(clamp(row, 0, len(cm.Action) - 1))
}

on_defaults :: proc(e: ^Editor) -> bool {
	return e.row >= len(cm.Action)
}

// The text of a command's key or pad button for the table ("-" when unbound).
key_text :: proc(e: ^Editor, a: cm.Action) -> string {
	k := cm.key_name(&e.map_.keys[a])
	return k == "" ? "-" : k
}

pad_text :: proc(e: ^Editor, a: cm.Action) -> string {
	if e.map_.pad[a] == cm.NO_BUTTON {
		return "-"
	}
	return fmt.tprintf("%d", e.map_.pad[a])
}

// The name of a standard-layout button for the info line.
pad_name :: proc(index: int) -> string {
	if index >= 0 && index < cm.STANDARD_BUTTON_COUNT {
		return cm.STANDARD_BUTTON_NAMES[index]
	}
	return "?"
}

// --- The file ---

// Takes the file's bytes: its notes are kept for the next save, and when it is a valid map it becomes
// the live map (what the file says is what the tools now use). Returns false for an invalid file.
editor_load :: proc(e: ^Editor, bytes: []u8) -> bool {
	m, err := cm.input_map_from_json(bytes)
	if err != "" {
		e.note = NOTE_FILE_BAD
		return false
	}
	e.original_len = min(len(bytes), ORIGINAL_CAP)
	copy(e.original[:e.original_len], bytes[:e.original_len])
	e.map_^ = m
	e.saved = m
	e.confirm_leave = false
	return true
}

// The text to write for a save.
editor_save_text :: proc(e: ^Editor) -> string {
	return cm.input_map_to_json_keeping(e.map_^, e.original[:e.original_len])
}

// The text to write for a save, remembered until the frontend says it wrote it.
editor_take_save_text :: proc(e: ^Editor) -> string {
	text := editor_save_text(e)
	e.pending_len = min(len(text), ORIGINAL_CAP)
	copy(e.pending[:e.pending_len], text[:e.pending_len])
	return text
}

// After the frontend wrote the file: this is what it holds now, notes and all.
editor_mark_saved :: proc(e: ^Editor) {
	e.saved = e.map_^
	e.original_len = e.pending_len
	copy(e.original[:e.original_len], e.pending[:e.pending_len])
	e.confirm_leave = false
	e.note = "SAVED"
}

// --- Changing a binding ---

// Which command (other than `except`) has this key, if any.
@(private = "file")
key_owner :: proc(e: ^Editor, code: string, except: cm.Action) -> (cm.Action, bool) {
	for a in cm.Action {
		if a != except && code != "" && cm.key_name(&e.map_.keys[a]) == code {
			return a, true
		}
	}
	return {}, false
}

@(private = "file")
pad_owner :: proc(e: ^Editor, button: int, except: cm.Action) -> (cm.Action, bool) {
	for a in cm.Action {
		if a != except && button != cm.NO_BUTTON && e.map_.pad[a] == button {
			return a, true
		}
	}
	return {}, false
}

@(private = "file")
begin_capture :: proc(e: ^Editor, col: Column) {
	e.mode = .Capture
	e.capture_col = col
	e.capture_ms = 0
}

@(private = "file")
end_capture :: proc(e: ^Editor, note: string) {
	e.mode = .Table
	e.note = note
}

// The raw press the frontend hands over while a capture is on.
editor_handle_raw :: proc(e: ^Editor, raw: cm.Raw_Input) {
	if e.mode != .Capture {
		return
	}
	a := action_at(e.row)
	e.capture_ms = 0 // a press, even a wrong one, shows the user is there
	switch e.capture_col {
	case .Key:
		if raw.from_pad {
			e.note = NOTE_KEY_ONLY
			return
		}
		if raw.key == "" {
			e.note = NOTE_BAD_KEY
			return
		}
		if other, taken := key_owner(e, raw.key, a); taken {
			end_capture(e, fmt.tprintf("%s HAS THAT KEY ALREADY: UNBIND IT FIRST", cm.action_label(e.map_, other)))
			return
		}
		cm.set_key_name(&e.map_.keys[a], raw.key)
	case .Pad:
		if !raw.from_pad {
			e.note = NOTE_PAD_ONLY
			return
		}
		if other, taken := pad_owner(e, raw.button, a); taken {
			end_capture(e, fmt.tprintf("%s HAS THAT BUTTON ALREADY: UNBIND IT FIRST", cm.action_label(e.map_, other)))
			return
		}
		e.map_.pad[a] = raw.button
	case .Label:
	}
	e.confirm_leave = false
	end_capture(e, "")
}

editor_wants_raw :: proc(e: ^Editor) -> bool {
	return e.mode == .Capture
}

// The clock: a capture that nobody answers gives up.
editor_update :: proc(e: ^Editor, dt_ms: f64) {
	if e.mode == .Capture {
		e.capture_ms += dt_ms
		if e.capture_ms >= CAPTURE_MS {
			end_capture(e, NOTE_TIMED_OUT)
		}
	}
}

// Yellow: the selected cell back to unbound (a label back to the command's name).
@(private = "file")
unbind :: proc(e: ^Editor) {
	if on_defaults(e) {
		return
	}
	a := action_at(e.row)
	switch e.col {
	case .Key:
		e.map_.keys[a] = {}
	case .Pad:
		e.map_.pad[a] = cm.NO_BUTTON
	case .Label:
		e.map_.labels[a] = {}
	}
	e.confirm_leave = false
}

@(private = "file")
begin_label :: proc(e: ^Editor) {
	a := action_at(e.row)
	prompt := fmt.tprintf("LABEL FOR %s", cm.DEFAULT_LABELS[a])
	cm.text_entry_begin(&e.entry, prompt, cm.key_name(&e.map_.labels[a]), cm.LABEL_CAP)
	e.mode = .Text
}

@(private = "file")
handle_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.mode = .Table
	case .Done:
		text := cm.text_entry_text(&e.entry)
		a := action_at(e.row)
		if text == "" || text == cm.DEFAULT_LABELS[a] {
			e.map_.labels[a] = {} // the command's name
		} else {
			cm.set_key_name(&e.map_.labels[a], text)
		}
		e.confirm_leave = false
		e.mode = .Table
	}
}

// Green on the selected cell (or a click on it).
@(private = "file")
activate :: proc(e: ^Editor) {
	if on_defaults(e) {
		if !e.confirm_reset {
			e.confirm_reset = true
			e.note = NOTE_RESET_ASK
			return
		}
		e.confirm_reset = false
		e.map_^ = cm.default_input_map()
		e.confirm_leave = false
		e.note = "DEFAULTS: SAVE TO KEEP THEM"
		return
	}
	switch e.col {
	case .Key, .Pad:
		begin_capture(e, e.col)
	case .Label:
		begin_label(e)
	}
}

// Leaving: with unsaved changes the first request only warns.
@(private = "file")
leave :: proc(e: ^Editor) {
	if editor_dirty(e) && !e.confirm_leave {
		e.confirm_leave = true
		return
	}
	e.exit_requested = true
}

editor_allow_close :: proc(e: ^Editor) -> bool {
	if editor_dirty(e) && !e.confirm_leave {
		e.confirm_leave = true
		return false
	}
	return true
}

// --- Events ---

editor_handle_event :: proc(e: ^Editor, ev: cm.Input_Event) {
	if e.mode == .Text {
		handle_text(e, ev)
		return
	}
	// A command or a left press clears the note and cancels a pending question (unless it answers it).
	armed_leave, armed_reset := e.confirm_leave, e.confirm_reset
	switch v in ev {
	case cm.Command:
		e.note = ""
		e.confirm_leave, e.confirm_reset = false, false
		editor_apply_action(e, v.action, armed_leave, armed_reset)
	case cm.Mouse_Move, cm.Mouse_Wheel:
	case cm.Mouse_Button_Event:
		if v.button == .Left && v.down {
			e.note = ""
			e.confirm_leave, e.confirm_reset = false, false
			click(e, v.x, v.y, armed_leave, armed_reset)
		}
	}
}

editor_apply_action :: proc(e: ^Editor, a: cm.Action, armed_leave := false, armed_reset := false) {
	switch e.mode {
	case .Table:
		switch a {
		case .Up:
			e.row = max(e.row - 1, 0)
		case .Down:
			e.row = min(e.row + 1, ROW_COUNT - 1)
		case .Left:
			e.col = Column(max(int(e.col) - 1, 0))
		case .Right:
			e.col = Column(min(int(e.col) + 1, len(Column) - 1))
		case .Green:
			e.confirm_reset = armed_reset // (green on DEFAULTS twice resets)
			activate(e)
		case .Yellow:
			unbind(e)
		case .Blue:
			e.mode = .File
		case .Red:
			e.confirm_leave = armed_leave
			leave(e)
		}
	case .File:
		#partial switch a {
		case .Green:
			e.requests += {.Save}
			e.mode = .Table
		case .Yellow:
			e.requests += {.Load}
			e.mode = .Table
		case .Red, .Blue:
			e.mode = .Table
		}
	case .Capture, .Text:
		// (a capture takes raw presses; the keypad sees events first)
	}
}

@(private = "file")
click :: proc(e: ^Editor, x, y: int, armed_leave, armed_reset: bool) {
	if e.mode == .Capture {
		if rect_contains(CANCEL_BUTTON, x, y) {
			end_capture(e, "CANCELLED")
		}
		return
	}
	if e.mode == .File {
		e.mode = .Table // a click outside the keys and buttons just closes File
	}
	if row, col, ok := cell_at(x, y); ok {
		e.row, e.col = row, row < len(cm.Action) ? col : .Key
		e.confirm_reset = armed_reset
		activate(e)
		return
	}
	switch {
	case rect_contains(SAVE_BUTTON, x, y):
		e.requests += {.Save}
	case rect_contains(LOAD_BUTTON, x, y):
		e.requests += {.Load}
	case rect_contains(UNBIND_BUTTON, x, y):
		unbind(e)
	case rect_contains(MENU_BUTTON, x, y):
		e.confirm_leave = armed_leave
		leave(e)
	}
}
