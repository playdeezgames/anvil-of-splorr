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

	// File IO, done by the frontend. A tool with files sets all of these.
	take_save:    proc(data: rawptr) -> (text: string, ok: bool), // ok only if a save was requested; text on the temp allocator
	saved:        proc(data: rawptr), // after the frontend wrote the file
	wants_load:   proc(data: rawptr) -> bool, // true once per load request
	load:         proc(data: rawptr, bytes: []u8) -> bool, // false if the bytes are not valid
}

tool_has_files :: proc(t: ^Tool) -> bool {
	return t.take_save != nil && t.wants_load != nil && t.load != nil
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
				t.handle_event(t.data, Command{a})
			}
		}
	}
	if t.update_pads != nil {
		t.update_pads(t.data, now)
	}
	prev^ = now^
}
