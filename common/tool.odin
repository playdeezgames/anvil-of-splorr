package common

// What a frontend needs from a tool. Frontends are tool-agnostic: they own the window, event
// translation, pad polling and file IO, and drive any Tool through these procs. Optional procs
// may be nil. Each tool package provides a `tool` proc that builds one of these.

Tool :: struct {
	title:        string,
	default_file: string, // "" if the tool has no file
	data:         rawptr,
	set_input_map: proc(data: rawptr, m: ^Input_Map), // frontend gives the live map once; its labels may change later
	handle_event: proc(data: rawptr, ev: Input_Event),
	update_pads:  proc(data: rawptr, pads: ^Pads), // full per-frame snapshot, for tools that show raw pads
	// Optional raw capture (the controls editor): while wants_raw says true, every key press and pad
	// button press goes to handle_raw instead of becoming a command (the mouse is unaffected).
	wants_raw:    proc(data: rawptr) -> bool,
	handle_raw:   proc(data: rawptr, raw: Raw_Input),
	// Optional clock (games; the editors leave it nil): called once a frame, before `draw`, with the
	// milliseconds that really passed since the previous frame (fractional, so 144 Hz does not drift).
	// Frontends call it through `tool_update`, which clamps the step to MAX_FRAME_MS.
	update:       proc(data: rawptr, dt_ms: f64),
	draw:         proc(data: rawptr, r: ^Renderer),
	is_dirty:     proc(data: rawptr) -> bool,

	enter:        proc(data: rawptr), // the tool just became the active one (frontends also call it once at startup)
	take_exit:    proc(data: rawptr) -> bool, // true once when the tool wants to return to the main menu
	allow_close:  proc(data: rawptr) -> bool, // the window is closing: true to let it, false to hold it (and warn about unsaved changes)

	// File IO, done by the frontend. A tool with files sets all of these.
	file_name:    proc(data: rawptr) -> string, // optional; overrides default_file (the launcher uses it)
	take_save:    proc(data: rawptr) -> (text: string, ok: bool), // ok only if a save was requested; text on the temp allocator
	// Optional autosave, for games: like take_save, but the web frontend only stores the text in
	// browser storage (no download, no message); native writes the file exactly as for take_save. A
	// tool may set this with or without take_save. Frontends call `tool_take_save`.
	take_autosave: proc(data: rawptr) -> (text: string, ok: bool),
	saved:        proc(data: rawptr), // after the frontend wrote the file (for either kind of save)
	wants_load:   proc(data: rawptr) -> bool, // true once per load request
	load:         proc(data: rawptr, bytes: []u8) -> bool, // false if the bytes are not valid

	// Sound: the requests (start a sound on a channel, stop one, stop all) the tool has queued since the
	// last call, one per call, ok false when there are none. The frontend applies them to its Mixer each
	// frame (`tool_service_audio`); samples may be on the temp allocator.
	take_audio:   proc(data: rawptr) -> (req: Audio_Request, ok: bool),

	// A second, read-only file the tool wants (the glyph editor reads the saved palette). The
	// frontend reads it, silently skipping a missing one, whenever wants_aux_load says so.
	aux_file_name: proc(data: rawptr) -> string,
	wants_aux_load: proc(data: rawptr) -> bool, // true once per request
	load_aux:     proc(data: rawptr, bytes: []u8) -> bool,
}

// The longest step a tool is told about: a hidden tab or a dragged window can leave a gap of seconds
// between frames, and a game must not end a round in one jump.
MAX_FRAME_MS :: 100.0

// What both frontends call each frame with the real elapsed milliseconds: clamps the step to
// 0..MAX_FRAME_MS (a clock that goes backwards, or a NaN, counts as 0) and passes it to the tool's
// `update` if it has one. Returns the step that was passed.
tool_update :: proc(t: ^Tool, elapsed_ms: f64) -> f64 {
	dt := elapsed_ms
	if !(dt > 0) { 	// also true for NaN
		dt = 0
	}
	dt = min(dt, MAX_FRAME_MS)
	if t.update != nil {
		t.update(t.data, dt)
	}
	return dt
}

// The file the tool currently loads and saves ("" if it has none).
tool_file_name :: proc(t: ^Tool) -> string {
	if (t.take_save == nil && t.take_autosave == nil) || t.wants_load == nil || t.load == nil {
		return ""
	}
	return t.file_name != nil ? t.file_name(t.data) : t.default_file
}

// The next save the tool wants done, if any: `silent` is true for an autosave (`take_autosave`),
// which the web frontend stores without offering a download. One request per call; a requested
// save comes before an autosave.
tool_take_save :: proc(t: ^Tool) -> (text: string, silent: bool, ok: bool) {
	if t.take_save != nil {
		if text, ok = t.take_save(t.data); ok {
			return text, false, true
		}
	}
	if t.take_autosave != nil {
		if text, ok = t.take_autosave(t.data); ok {
			return text, true, true
		}
	}
	return "", false, false
}

// The read-only second file, or "" if the tool has none.
tool_aux_file_name :: proc(t: ^Tool) -> string {
	if t.aux_file_name == nil || t.wants_aux_load == nil || t.load_aux == nil {
		return ""
	}
	return t.aux_file_name(t.data)
}

tool_has_files :: proc(t: ^Tool) -> bool {
	return tool_file_name(t) != ""
}

// Asks whether the whole app may close now. A tool with unsaved changes answers false the first
// time (showing its own warning) and true if asked again while the warning is up.
tool_allow_close :: proc(t: ^Tool) -> bool {
	return t.allow_close == nil || t.allow_close(t.data)
}

tool_is_dirty :: proc(t: ^Tool) -> bool {
	return t.is_dirty != nil && t.is_dirty(t.data)
}

tool_wants_raw :: proc(t: ^Tool) -> bool {
	return t.wants_raw != nil && t.handle_raw != nil && t.wants_raw(t.data)
}

// If the tool is capturing raw input, hands it the press and returns true (the frontend must then not
// turn the press into a command).
tool_raw :: proc(t: ^Tool, raw: Raw_Input) -> bool {
	if t.wants_raw == nil || t.handle_raw == nil || !t.wants_raw(t.data) {
		return false
	}
	t.handle_raw(t.data, raw)
	return true
}

// Per-frame gamepad update: turns presses of bound standard buttons into Commands, hands the
// raw snapshot to tools that want it (the tester), and remembers it as `prev` for the next call.
tool_update_pads :: proc(t: ^Tool, prev, now: ^Pads, m: ^Input_Map) {
	for i in 0 ..< MAX_PADS {
		pressed, _ := pad_edges(&prev[i], &now[i])
		for idx in pressed {
			if tool_raw(t, Raw_Input{from_pad = true, button = idx}) {
				continue
			}
			if a, ok := action_for_pad_button(m, idx); ok {
				t.handle_event(t.data, Command{action = a, from_pad = true})
			}
		}
	}
	if t.update_pads != nil {
		t.update_pads(t.data, now)
	}
	prev^ = now^
}
