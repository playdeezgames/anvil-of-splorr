package controls_editor

import cm "../common"

// The tool the frontends and the launcher drive. The file is input_map.json, in the working
// directory on native; on the web a save goes to browser storage and is offered as a download (the
// page reads the served file at start, so the downloaded copy has to replace it).
tool :: proc(e: ^Editor) -> cm.Tool {
	return cm.Tool {
		title = "Controls",
		default_file = "input_map.json",
		data = e,
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {editor_set_map((^Editor)(data), m)},
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {editor_handle_event((^Editor)(data), ev)},
		wants_raw = proc(data: rawptr) -> bool {return editor_wants_raw((^Editor)(data))},
		handle_raw = proc(data: rawptr, raw: cm.Raw_Input) {editor_handle_raw((^Editor)(data), raw)},
		update = proc(data: rawptr, dt_ms: f64) {editor_update((^Editor)(data), dt_ms)},
		enter = proc(data: rawptr) {editor_enter((^Editor)(data))},
		allow_close = proc(data: rawptr) -> bool {return editor_allow_close((^Editor)(data))},
		take_exit = proc(data: rawptr) -> bool {
			e := (^Editor)(data)
			defer e.exit_requested = false
			return e.exit_requested
		},
		draw = proc(data: rawptr, r: ^cm.Renderer) {editor_draw((^Editor)(data), r)},
		is_dirty = proc(data: rawptr) -> bool {return editor_dirty((^Editor)(data))},
		take_save = proc(data: rawptr) -> (string, bool) {
			e := (^Editor)(data)
			if .Save not_in e.requests {
				return "", false
			}
			e.requests -= {.Save}
			return editor_take_save_text(e), true
		},
		saved = proc(data: rawptr) {editor_mark_saved((^Editor)(data))},
		wants_load = proc(data: rawptr) -> bool {
			e := (^Editor)(data)
			if .Load not_in e.requests {
				return false
			}
			e.requests -= {.Load}
			return true
		},
		load = proc(data: rawptr, bytes: []u8) -> bool {return editor_load((^Editor)(data), bytes)},
	}
}
