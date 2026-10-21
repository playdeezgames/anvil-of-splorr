package world_editor

import cm "../common"

// Adapter that lets frontends drive an Editor as a cm.Tool.
tool :: proc(e: ^Editor) -> cm.Tool {
	return cm.Tool {
		title = "World Editor",
		default_file = "world.json",
		data = e,
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {editor_set_labels((^Editor)(data), m)},
		enter = proc(data: rawptr) {editor_enter((^Editor)(data))},
		allow_close = proc(data: rawptr) -> bool {return editor_allow_close((^Editor)(data))},
		take_exit = proc(data: rawptr) -> bool {
			e := (^Editor)(data)
			defer e.exit_requested = false
			return e.exit_requested
		},
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {editor_handle_event((^Editor)(data), ev)},
		draw = proc(data: rawptr, r: ^cm.Renderer) {editor_draw((^Editor)(data), r)},
		is_dirty = proc(data: rawptr) -> bool {return editor_dirty((^Editor)(data))},
		// tileset.json, for importing a tileset into the world.
		// The files the editor asks the frontend for: tileset.json (to import) and game_tags.json (the
		// tags the game needs), one at a time, named by what is pending. No request: no file.
		aux_file_name = proc(data: rawptr) -> string {
			e := (^Editor)(data)
			switch {
			case .Tileset in e.aux_requests:
				return TILESET_FILE
			case .Game_Tags in e.aux_requests:
				return GAME_TAGS_FILE
			}
			return ""
		},
		wants_aux_load = proc(data: rawptr) -> bool {
			e := (^Editor)(data)
			switch {
			case .Tileset in e.aux_requests:
				e.aux_requests -= {.Tileset}
				e.aux_current = .Tileset
				return true
			case .Game_Tags in e.aux_requests:
				e.aux_requests -= {.Game_Tags}
				e.aux_current = .Game_Tags
				return true
			}
			return false
		},
		load_aux = proc(data: rawptr, bytes: []u8) -> bool {
			e := (^Editor)(data)
			if e.aux_current == .Game_Tags {
				return editor_load_game_tags(e, bytes)
			}
			return editor_import_tileset(e, bytes)
		},
		take_save = proc(data: rawptr) -> (string, bool) {
			e := (^Editor)(data)
			if .Save not_in e.requests {
				return "", false
			}
			e.requests -= {.Save}
			return cm.world_to_json(&e.world), true
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
			if cm.world_from_json(bytes, &e.world) != "" {
				return false
			}
			// A loaded world replaces everything the editor was showing.
			e.dirty = false
			e.mode = .Hub
			e.confirm_delete = false
			e.confirm_exit = false
			e.open_after = false
			e.sel = {}
			e.scroll = 0
			return true
		},
	}
}
