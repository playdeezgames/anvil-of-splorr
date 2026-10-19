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
	draw:         proc(data: rawptr, r: ^Renderer),
	is_dirty:     proc(data: rawptr) -> bool,

	enter:        proc(data: rawptr), // the tool just became the active one (frontends also call it once at startup)
	take_exit:    proc(data: rawptr) -> bool, // true once when the tool wants to return to the main menu
	allow_close:  proc(data: rawptr) -> bool, // the window is closing: true to let it, false to hold it (and warn about unsaved changes)

	// File IO, done by the frontend. A tool with files sets all of these.
	file_name:    proc(data: rawptr) -> string, // optional; overrides default_file (the launcher uses it)
	take_save:    proc(data: rawptr) -> (text: string, ok: bool), // ok only if a save was requested; text on the temp allocator
	saved:        proc(data: rawptr), // after the frontend wrote the file
	wants_load:   proc(data: rawptr) -> bool, // true once per load request
	load:         proc(data: rawptr, bytes: []u8) -> bool, // false if the bytes are not valid

	// A second, read-only file the tool wants (the glyph editor reads the saved palette). The
	// frontend reads it, silently skipping a missing one, whenever wants_aux_load says so.
	aux_file_name: proc(data: rawptr) -> string,
	wants_aux_load: proc(data: rawptr) -> bool, // true once per request
	load_aux:     proc(data: rawptr, bytes: []u8) -> bool,
}

// The file the tool currently loads and saves ("" if it has none).
tool_file_name :: proc(t: ^Tool) -> string {
	if t.take_save == nil || t.wants_load == nil || t.load == nil {
		return ""
	}
	return t.file_name != nil ? t.file_name(t.data) : t.default_file
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

// Per-frame gamepad update: turns presses of bound standard buttons into Commands, hands the
// raw snapshot to tools that want it (the tester), and remembers it as `prev` for the next call.
tool_update_pads :: proc(t: ^Tool, prev, now: ^Pads, m: ^Input_Map) {
	for i in 0 ..< MAX_PADS {
		pressed, _ := pad_edges(&prev[i], &now[i])
		for idx in pressed {
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
