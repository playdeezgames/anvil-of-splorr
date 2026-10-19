package image_editor

import cm "../common"

// The palette editor's file: its saved palette supplies the colours.
PALETTE_FILE :: "palette.json"

// Adapter that lets frontends drive an Editor as a cm.Tool.
tool :: proc(e: ^Editor) -> cm.Tool {
	return cm.Tool {
		title = "Image Editor",
		default_file = "image.json",
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
		aux_file_name = proc(data: rawptr) -> string {return PALETTE_FILE},
		wants_aux_load = proc(data: rawptr) -> bool {
			e := (^Editor)(data)
			if .Palette not_in e.aux_requests {
				return false
			}
			e.aux_requests -= {.Palette}
			return true
		},
		load_aux = proc(data: rawptr, bytes: []u8) -> bool {
			p, ok := cm.palette_from_json(bytes)
			if ok {
				editor_set_palette((^Editor)(data), p)
			}
			return ok
		},
		take_save = proc(data: rawptr) -> (string, bool) {
			e := (^Editor)(data)
			if .Save not_in e.requests {
				return "", false
			}
			e.requests -= {.Save}
			return cm.image4_to_json(&e.image), true
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
			img, err := cm.image4_from_json(bytes)
			if err == "" {
				editor_set_image((^Editor)(data), img)
			}
			return err == ""
		},
	}
}
