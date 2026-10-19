package glyph_editor

import cm "../common"

// Adapter that lets frontends drive an Editor as a cm.Tool.
tool :: proc(e: ^Editor) -> cm.Tool {
	return cm.Tool {
		title = "Glyph Editor",
		default_file = "glyph.json",
		data = e,
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {(^Editor)(data).labels = m},
		enter = proc(data: rawptr) {editor_enter((^Editor)(data))},
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
			return cm.bitmap_to_json(&e.bitmap), true
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
			b, err := cm.bitmap_from_json(bytes)
			if err == "" {
				editor_set_bitmap((^Editor)(data), b)
			}
			return err == ""
		},
	}
}
