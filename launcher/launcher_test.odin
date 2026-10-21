#+build !js
package launcher

import cm "../common"
import "core:testing"

// A stand-in tool that records what it is sent and can ask to exit.
Probe :: struct {
	name:         string,
	events:       int,
	pad_updates:  int,
	entered:      int,
	draws:        int,
	exit_next:    bool,
	file:         string, // "" = no files
	saved_calls:  int,
	loaded_bytes: int,
	save_pending: bool,
	maps:         int,
	dirty:        bool,
	close_asks:   int,
	allow:        bool,
	aux:          string, // "" = no aux file
	aux_pending:  bool,
	aux_loaded:   int,
	aux_named_while_pending: bool, // the name is "" unless a request is pending (like the world editor)
}

probe_tool :: proc(p: ^Probe) -> cm.Tool {
	t := cm.Tool {
		data          = p,
		set_input_map = proc(d: rawptr, m: ^cm.Input_Map) {(^Probe)(d).maps += 1},
		handle_event  = proc(d: rawptr, ev: cm.Input_Event) {
			p := (^Probe)(d)
			p.events += 1
			if c, ok := ev.(cm.Command); ok && c.action == .Red {
				p.exit_next = true
			}
		},
		update_pads   = proc(d: rawptr, pads: ^cm.Pads) {(^Probe)(d).pad_updates += 1},
		draw          = proc(d: rawptr, r: ^cm.Renderer) {(^Probe)(d).draws += 1},
		enter         = proc(d: rawptr) {(^Probe)(d).entered += 1},
		is_dirty      = proc(d: rawptr) -> bool {return (^Probe)(d).dirty},
		allow_close   = proc(d: rawptr) -> bool {
			p := (^Probe)(d)
			p.close_asks += 1
			return p.allow
		},
		take_exit     = proc(d: rawptr) -> bool {
			p := (^Probe)(d)
			defer p.exit_next = false
			return p.exit_next
		},
	}
	if p.file != "" {
		t.default_file = p.file
		t.take_save = proc(d: rawptr) -> (string, bool) {
			p := (^Probe)(d)
			defer p.save_pending = false
			return "saved-text", p.save_pending
		}
		t.saved = proc(d: rawptr) {(^Probe)(d).saved_calls += 1}
		t.wants_load = proc(d: rawptr) -> bool {return false}
		t.load = proc(d: rawptr, b: []u8) -> bool {
			(^Probe)(d).loaded_bytes = len(b)
			return true
		}
	}
	if p.aux != "" {
		t.aux_file_name = proc(d: rawptr) -> string {
			p := (^Probe)(d)
			return p.aux_named_while_pending && !p.aux_pending ? "" : p.aux
		}
		t.wants_aux_load = proc(d: rawptr) -> bool {
			p := (^Probe)(d)
			defer p.aux_pending = false
			return p.aux_pending
		}
		t.load_aux = proc(d: rawptr, b: []u8) -> bool {
			(^Probe)(d).aux_loaded += len(b)
			return true
		}
	}
	return t
}

Fixture :: struct {
	a, b:    Probe,
	entries: [2]Entry,
	l:       Launcher,
}

setup :: proc(f: ^Fixture) -> cm.Tool {
	f.a = Probe {
		name = "A",
		file = "a.json",
	}
	f.b = Probe {
		name = "B",
	}
	f.entries = {{"ALPHA", probe_tool(&f.a)}, {"BETA", probe_tool(&f.b)}}
	f.l = launcher_init("MENU", f.entries[:])
	return tool(&f.l)
}

cmd :: proc(a: cm.Action) -> cm.Input_Event {
	return cm.Command{action = a}
}

@(test)
test_menu_navigation_wraps_and_opens :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	testing.expect_value(t, f.l.active, NO_TOOL)
	lt.handle_event(lt.data, cmd(.Up))
	testing.expect_value(t, f.l.selected, 1) // wrapped
	lt.handle_event(lt.data, cmd(.Down))
	testing.expect_value(t, f.l.selected, 0)
	lt.handle_event(lt.data, cmd(.Green))
	testing.expect_value(t, f.l.active, 0)
	testing.expect_value(t, f.a.entered, 1)
	testing.expect_value(t, f.b.entered, 0)
	testing.expect_value(t, f.a.events, 0) // the opening command is not forwarded
}

@(test)
test_menu_ignores_other_commands_and_pad_updates :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	for a in ([]cm.Action{.Red, .Blue, .Yellow, .Left, .Right}) {
		lt.handle_event(lt.data, cmd(a))
	}
	pads: cm.Pads
	lt.update_pads(lt.data, &pads)
	testing.expect_value(t, f.l.active, NO_TOOL)
	testing.expect_value(t, f.a.events + f.b.events + f.a.pad_updates + f.b.pad_updates, 0)
}

@(test)
test_events_and_pads_go_to_the_running_tool_only :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	lt.handle_event(lt.data, cmd(.Down))
	lt.handle_event(lt.data, cmd(.Green)) // open B
	lt.handle_event(lt.data, cmd(.Up))
	lt.handle_event(lt.data, cm.Mouse_Move{1, 2})
	pads: cm.Pads
	lt.update_pads(lt.data, &pads)
	r: cm.Renderer
	lt.draw(lt.data, &r)
	testing.expect_value(t, f.b.events, 2)
	testing.expect_value(t, f.b.pad_updates, 1)
	testing.expect_value(t, f.b.draws, 1)
	testing.expect_value(t, f.a.events + f.a.pad_updates + f.a.draws, 0)
}

@(test)
test_tool_exit_returns_to_menu_and_can_reopen :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	lt.handle_event(lt.data, cmd(.Green)) // open A
	lt.handle_event(lt.data, cmd(.Red)) // A asks to exit
	testing.expect_value(t, f.l.active, NO_TOOL)
	testing.expect_value(t, f.l.selected, 0) // cursor stays on the tool you came from
	lt.handle_event(lt.data, cmd(.Green))
	testing.expect_value(t, f.l.active, 0)
	testing.expect_value(t, f.a.entered, 2) // enter runs on every open
}

@(test)
test_mouse_hover_and_click :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	r := row_rect(1)
	lt.handle_event(lt.data, cm.Mouse_Move{r[0] + 5, r[1] + 3})
	testing.expect_value(t, f.l.selected, 1)
	lt.handle_event(lt.data, cm.Mouse_Button_Event{button = .Left, x = r[0] + 5, y = r[1] + 3, down = true})
	testing.expect_value(t, f.l.active, 1)
	lt.handle_event(lt.data, cmd(.Red))
	// A click outside every row does nothing.
	lt.handle_event(lt.data, cm.Mouse_Button_Event{button = .Left, x = 2, y = 2, down = true})
	testing.expect_value(t, f.l.active, NO_TOOL)
}

@(test)
test_file_hooks_follow_the_running_tool :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	// Menu: no file.
	testing.expect_value(t, cm.tool_file_name(&lt), "")
	_, ok := lt.take_save(lt.data)
	testing.expect(t, !ok)
	// A has files; B does not.
	lt.handle_event(lt.data, cmd(.Green))
	testing.expect_value(t, cm.tool_file_name(&lt), "a.json")
	f.a.save_pending = true
	text, saved := lt.take_save(lt.data)
	testing.expect(t, saved && text == "saved-text")
	lt.saved(lt.data)
	testing.expect_value(t, f.a.saved_calls, 1)
	testing.expect(t, lt.load(lt.data, []u8{1, 2, 3}))
	testing.expect_value(t, f.a.loaded_bytes, 3)
	lt.handle_event(lt.data, cmd(.Red))
	lt.handle_event(lt.data, cmd(.Down))
	lt.handle_event(lt.data, cmd(.Green)) // B
	testing.expect_value(t, cm.tool_file_name(&lt), "")
	testing.expect(t, !lt.load(lt.data, []u8{1}))
}

@(test)
test_dirty_and_input_map_forwarding :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	f.a.dirty = true
	testing.expect(t, !cm.tool_is_dirty(&lt)) // the menu itself is never dirty
	lt.handle_event(lt.data, cmd(.Green))
	testing.expect(t, cm.tool_is_dirty(&lt))
	m := cm.default_input_map()
	lt.set_input_map(lt.data, &m)
	testing.expect_value(t, f.a.maps, 1)
	testing.expect_value(t, f.b.maps, 1)
	testing.expect(t, f.l.labels == &m)
}

Count :: struct {
	rects, out_of_bounds, presents: int,
}

@(test)
test_menu_draws_on_screen :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	defer free_all(context.temp_allocator)
	c: Count
	r := cm.Renderer {
		data = &c,
		clear = proc(d: rawptr, col: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, col: cm.Color) {
			k := (^Count)(d)
			k.rects += 1
			if x < 0 || y < 0 || x + w > cm.SCREEN_W || y + h > cm.SCREEN_H {
				k.out_of_bounds += 1
			}
		},
		present = proc(d: rawptr) {(^Count)(d).presents += 1},
	}
	m := cm.default_input_map()
	for a in cm.Action { // longest labels must still fit
		cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW")
	}
	lt.set_input_map(lt.data, &m)
	lt.draw(lt.data, &r)
	testing.expect_value(t, c.presents, 1)
	testing.expect(t, c.rects > 20)
	testing.expect_value(t, c.out_of_bounds, 0)
	// Every menu row is on screen.
	for i in 0 ..< len(f.entries) {
		rc := row_rect(i)
		testing.expect(t, rc[0] + rc[2] <= cm.SCREEN_W && rc[1] + rc[3] <= 150)
	}
}

@(test)
test_window_close_goes_to_the_running_tool :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	testing.expect(t, cm.tool_allow_close(&lt)) // at the menu: always fine
	testing.expect_value(t, f.a.close_asks + f.b.close_asks, 0)
	lt.handle_event(lt.data, cmd(.Green)) // open A
	f.a.allow = false
	testing.expect(t, !cm.tool_allow_close(&lt)) // A holds the close
	f.a.allow = true
	testing.expect(t, cm.tool_allow_close(&lt))
	testing.expect_value(t, f.a.close_asks, 2)
	testing.expect_value(t, f.b.close_asks, 0)
}

@(test)
test_aux_file_hooks_follow_the_running_tool :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	f.a.aux = "palette.json"
	f.entries[0].tool = probe_tool(&f.a) // rebuild A's hooks now that it has an aux file
	// Menu: none.
	testing.expect_value(t, cm.tool_aux_file_name(&lt), "")
	testing.expect(t, !lt.wants_aux_load(lt.data) && !lt.load_aux(lt.data, []u8{1}))
	lt.handle_event(lt.data, cmd(.Green)) // open A
	testing.expect_value(t, cm.tool_aux_file_name(&lt), "palette.json")
	f.a.aux_pending = true
	testing.expect(t, lt.wants_aux_load(lt.data) && !lt.wants_aux_load(lt.data))
	testing.expect(t, lt.load_aux(lt.data, []u8{1, 2}))
	testing.expect_value(t, f.a.aux_loaded, 2)
	// B has none.
	lt.handle_event(lt.data, cmd(.Red))
	lt.handle_event(lt.data, cmd(.Down))
	lt.handle_event(lt.data, cmd(.Green))
	testing.expect_value(t, cm.tool_aux_file_name(&lt), "")
	testing.expect(t, !lt.load_aux(lt.data, []u8{1}))
}

@(test)
test_aux_bytes_arrive_even_after_the_tool_stops_naming_its_file :: proc(t: ^testing.T) {
	f: Fixture
	lt := setup(&f)
	f.a.aux = "game_tags.json"
	f.a.aux_named_while_pending = true
	f.entries[0].tool = probe_tool(&f.a)
	lt.handle_event(lt.data, cmd(.Green)) // open A
	testing.expect_value(t, cm.tool_aux_file_name(&lt), "") // nothing pending: no file
	f.a.aux_pending = true
	testing.expect_value(t, cm.tool_aux_file_name(&lt), "game_tags.json") // the frontend reads the name first
	testing.expect(t, lt.wants_aux_load(lt.data)) // ... the request is taken ...
	testing.expect_value(t, cm.tool_aux_file_name(&lt), "") // ... so the name is gone when the bytes come
	testing.expect(t, lt.load_aux(lt.data, []u8{1, 2, 3}))
	testing.expect_value(t, f.a.aux_loaded, 3)
}
