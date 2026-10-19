package palette_editor

import cm "../common"

// Adapter that lets frontends drive an Editor as a cm.Tool.
tool :: proc(e: ^Editor) -> cm.Tool {
	return cm.Tool {
		title = "Palette Editor",
		default_file = "palette.json",
		data = e,
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {(^Editor)(data).labels = m},
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {editor_handle_event((^Editor)(data), ev)},
		enter = proc(data: rawptr) {editor_enter((^Editor)(data))},
		allow_close = proc(data: rawptr) -> bool {return editor_allow_close((^Editor)(data))},
		take_exit = proc(data: rawptr) -> bool {
			e := (^Editor)(data)
			defer e.exit_requested = false
			return e.exit_requested
		},
		draw = proc(data: rawptr, r: ^cm.Renderer) {editor_draw((^Editor)(data), r)},
		is_dirty = proc(data: rawptr) -> bool {return (^Editor)(data).dirty},
		take_save = proc(data: rawptr) -> (string, bool) {
			e := (^Editor)(data)
			if .Save not_in e.requests {
				return "", false
			}
			e.requests -= {.Save}
			return cm.palette_to_json(e.palette), true
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
			p, ok := cm.palette_from_json(bytes)
			if ok {
				editor_set_palette((^Editor)(data), p)
			}
			return ok
		},
	}
}
