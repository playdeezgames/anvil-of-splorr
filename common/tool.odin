package common

// What a frontend needs from a tool. Frontends are tool-agnostic: they own the window, event
// translation, pad polling and file IO, and drive any Tool through these procs. Optional procs
// may be nil. Each tool package provides a `tool` proc that builds one of these.

Platform_Info :: struct {
	can_quit: bool, // false on the web: there is nothing to quit to
}

Tool :: struct {
	title:        string,
	default_file: string, // "" if the tool has no file
	data:         rawptr,
	configure:    proc(data: rawptr, info: Platform_Info),
	handle_event: proc(data: rawptr, ev: Input_Event),
	update_pads:  proc(data: rawptr, pads: ^Pads), // full per-frame snapshot, for tools that show raw pads
	draw:         proc(data: rawptr, r: ^Renderer),
	wants_quit:   proc(data: rawptr) -> bool,
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

tool_wants_quit :: proc(t: ^Tool) -> bool {
	return t.wants_quit != nil && t.wants_quit(t.data)
}

tool_is_dirty :: proc(t: ^Tool) -> bool {
	return t.is_dirty != nil && t.is_dirty(t.data)
}

// Per-frame gamepad update: sends bound-button presses as Pad_Events, hands the raw snapshot to
// tools that want it, and remembers it as `prev` for the next call.
tool_update_pads :: proc(t: ^Tool, prev, now: ^Pads) {
	for i in 0 ..< MAX_PADS {
		pressed, released := pad_edges(&prev[i], &now[i])
		for b in pressed {
			t.handle_event(t.data, Pad_Event{b, true})
		}
		for b in released {
			t.handle_event(t.data, Pad_Event{b, false})
		}
	}
	if t.update_pads != nil {
		t.update_pads(t.data, now)
	}
	prev^ = now^
}
