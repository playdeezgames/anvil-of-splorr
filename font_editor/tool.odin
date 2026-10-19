package font_editor

import cm "../common"

// Adapter that lets frontends drive an Editor as a cm.Tool.
tool :: proc(e: ^Editor) -> cm.Tool {
	return cm.Tool {
		title = "Font Editor",
		default_file = "font.json",
		data = e,
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {(^Editor)(data).labels = m},
		enter = proc(data: rawptr) {editor_enter((^Editor)(data))},
		allow_close = proc(data: rawptr) -> bool {return editor_allow_close((^Editor)(data))},
		take_exit = proc(data: rawptr) -> bool {
			e := (^Editor)(data)
			defer e.exit_requested = false
			return e.exit_requested
		},
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {editor_handle_event((^Editor)(data), ev)},
		draw = proc(data: rawptr, r: ^cm.Renderer) {editor_draw((^Editor)(data), r)},
		is_dirty = proc(data: rawptr) -> bool {return (^Editor)(data).dirty},
		take_save = proc(data: rawptr) -> (string, bool) {
			e := (^Editor)(data)
			if .Save not_in e.requests {
				return "", false
			}
			e.requests -= {.Save}
			return cm.pixel_font_to_json(&e.font), true
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
		load = proc(data: rawptr, bytes: []u8) -> bool {
			e := (^Editor)(data)
			if cm.pixel_font_from_json(bytes, &e.font) != "" {
				return false
			}
			// A loaded font replaces everything, including whether the glyph being edited exists:
			// go back to the grid rather than keep editing something that may be gone.
			e.dirty = false
			e.mode, e.back = .Pick, .Pick
			e.paint, e.confirm_delete = nil, false
			clamp_cursor(e)
			return true
		},
	}
}
