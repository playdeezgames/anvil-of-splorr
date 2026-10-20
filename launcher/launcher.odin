package launcher

import cm "../common"
import "core:fmt"

// The main menu. A Launcher is itself a cm.Tool that hosts the real tools: it shows a menu, hands
// everything (events, pad snapshots, drawing, file IO) to the chosen tool, and returns to the
// menu when that tool asks to exit. Adding an editor to the suite means adding an Entry.

Entry :: struct {
	title: string,
	tool:  cm.Tool,
}

NO_TOOL :: -1

Launcher :: struct {
	title:    string,
	entries:  []Entry, // owned by the caller; must outlive the launcher
	selected: int, // highlighted menu entry
	active:   int, // index of the running tool, or NO_TOOL while the menu is showing
	labels:   ^cm.Input_Map,
}

ROW_X :: 60
ROW_W :: 200
ROW_Y :: 44
ROW_H :: 14
ROW_PITCH :: 15

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
HILITE :: cm.Color{255, 220, 80}
DIM :: cm.Color{120, 120, 134}

launcher_init :: proc(title: string, entries: []Entry) -> Launcher {
	return Launcher{title = title, entries = entries, active = NO_TOOL}
}

row_rect :: proc(i: int) -> [4]int {
	return {ROW_X, ROW_Y + i * ROW_PITCH, ROW_W, ROW_H}
}

row_at :: proc(l: ^Launcher, x, y: int) -> (int, bool) {
	for i in 0 ..< len(l.entries) {
		r := row_rect(i)
		if x >= r[0] && y >= r[1] && x < r[0] + r[2] && y < r[1] + r[3] {
			return i, true
		}
	}
	return 0, false
}

running :: proc(l: ^Launcher) -> ^cm.Tool {
	if l.active == NO_TOOL {
		return nil
	}
	return &l.entries[l.active].tool
}

open_tool :: proc(l: ^Launcher, i: int) {
	if i < 0 || i >= len(l.entries) {
		return
	}
	l.active = i
	l.selected = i
	if t := running(l); t.enter != nil {
		t.enter(t.data)
	}
}

// If the running tool asked to leave, go back to the menu.
@(private = "file")
check_exit :: proc(l: ^Launcher) {
	if t := running(l); t != nil && t.take_exit != nil && t.take_exit(t.data) {
		l.active = NO_TOOL
	}
}

launcher_handle_event :: proc(l: ^Launcher, ev: cm.Input_Event) {
	if t := running(l); t != nil {
		t.handle_event(t.data, ev)
		check_exit(l)
		return
	}
	n := len(l.entries)
	if n == 0 {
		return
	}
	#partial switch v in ev {
	case cm.Command:
		#partial switch v.action {
		case .Up:
			l.selected = (l.selected + n - 1) % n
		case .Down:
			l.selected = (l.selected + 1) % n
		case .Green:
			open_tool(l, l.selected)
		}
	case cm.Mouse_Move:
		if i, ok := row_at(l, v.x, v.y); ok {
			l.selected = i
		}
	case cm.Mouse_Button_Event:
		if v.down && v.button == .Left {
			if i, ok := row_at(l, v.x, v.y); ok {
				open_tool(l, i)
			}
		}
	}
}

launcher_update_pads :: proc(l: ^Launcher, pads: ^cm.Pads) {
	if t := running(l); t != nil && t.update_pads != nil {
		t.update_pads(t.data, pads)
		check_exit(l)
	}
}

launcher_draw :: proc(l: ^Launcher, r: ^cm.Renderer) {
	if t := running(l); t != nil {
		t.draw(t.data, r)
		return
	}
	cm.renderer_clear(r, BG)
	cm.draw_text(r, (cm.SCREEN_W - cm.text_width(l.title, 2)) / 2, 16, l.title, HILITE, 2)
	sub := "CHOOSE AN EDITOR"
	cm.draw_text(r, (cm.SCREEN_W - cm.text_width(sub)) / 2, 36, sub, DIM)
	for e, i in l.entries {
		rc := row_rect(i)
		sel := i == l.selected
		if sel {
			cm.renderer_fill_rect(r, rc[0], rc[1], rc[2], rc[3], PANEL)
			cm.renderer_fill_rect(r, rc[0], rc[1], 3, rc[3], HILITE)
		}
		cm.draw_text(r, rc[0] + 10, rc[1] + 2, e.title, sel ? HILITE : TEXT, 2)
	}
	lab := proc(l: ^Launcher, a: cm.Action) -> string {return cm.action_label(l.labels, a)}
	cm.draw_text(r, 8, 156, fmt.tprintf("%s/%s: SELECT  %s: OPEN", lab(l, .Up), lab(l, .Down), lab(l, .Green)), TEXT)
	cm.draw_text(r, 8, 164, "MOUSE: CLICK AN EDITOR", TEXT)
	cm.renderer_present(r)
}

// --- Forwarding of the optional Tool hooks to whichever tool is running ---

@(private = "file")
file_tool :: proc(l: ^Launcher) -> ^cm.Tool {
	if t := running(l); t != nil && cm.tool_has_files(t) {
		return t
	}
	return nil
}

tool :: proc(l: ^Launcher) -> cm.Tool {
	return cm.Tool {
		title = l.title,
		data = l,
		set_input_map = proc(data: rawptr, m: ^cm.Input_Map) {
			l := (^Launcher)(data)
			l.labels = m
			for &e in l.entries {
				if e.tool.set_input_map != nil {
					e.tool.set_input_map(e.tool.data, m)
				}
			}
		},
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {launcher_handle_event((^Launcher)(data), ev)},
		update_pads = proc(data: rawptr, pads: ^cm.Pads) {launcher_update_pads((^Launcher)(data), pads)},
		draw = proc(data: rawptr, r: ^cm.Renderer) {launcher_draw((^Launcher)(data), r)},
		allow_close = proc(data: rawptr) -> bool {
			t := running((^Launcher)(data))
			return t == nil || cm.tool_allow_close(t)
		},
		is_dirty = proc(data: rawptr) -> bool {
			t := running((^Launcher)(data))
			return t != nil && cm.tool_is_dirty(t)
		},
		file_name = proc(data: rawptr) -> string {
			if t := file_tool((^Launcher)(data)); t != nil {
				return cm.tool_file_name(t)
			}
			return ""
		},
		aux_file_name = proc(data: rawptr) -> string {
			if t := running((^Launcher)(data)); t != nil {
				return cm.tool_aux_file_name(t)
			}
			return ""
		},
		wants_aux_load = proc(data: rawptr) -> bool {
			if t := running((^Launcher)(data)); t != nil && cm.tool_aux_file_name(t) != "" {
				return t.wants_aux_load(t.data)
			}
			return false
		},
		load_aux = proc(data: rawptr, bytes: []u8) -> bool {
			if t := running((^Launcher)(data)); t != nil && cm.tool_aux_file_name(t) != "" {
				return t.load_aux(t.data, bytes)
			}
			return false
		},
		take_save = proc(data: rawptr) -> (string, bool) {
			if t := file_tool((^Launcher)(data)); t != nil {
				return t.take_save(t.data)
			}
			return "", false
		},
		saved = proc(data: rawptr) {
			if t := file_tool((^Launcher)(data)); t != nil && t.saved != nil {
				t.saved(t.data)
			}
		},
		wants_load = proc(data: rawptr) -> bool {
			if t := file_tool((^Launcher)(data)); t != nil {
				return t.wants_load(t.data)
			}
			return false
		},
		load = proc(data: rawptr, bytes: []u8) -> bool {
			if t := file_tool((^Launcher)(data)); t != nil {
				return t.load(t.data, bytes)
			}
			return false
		},
	}
}
