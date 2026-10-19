#+build !js
package palette_editor

import cm "../common"
import "core:testing"

cmd :: proc(a: cm.Action) -> cm.Input_Event {
	return cm.Command{a}
}

press :: proc(e: ^Editor, actions: ..cm.Action) {
	for a in actions {
		editor_handle_event(e, cmd(a))
	}
}

click_at :: proc(e: ^Editor, x, y: int) {
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = true})
	editor_handle_event(e, cm.Mouse_Button_Event{button = .Left, x = x, y = y, down = false})
}

@(test)
test_browse_moves_selection_with_wrap :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Left)
	testing.expect_value(t, e.selected, 3)
	press(&e, .Right)
	testing.expect_value(t, e.selected, 0)
	press(&e, .Up)
	testing.expect_value(t, e.selected, 12)
	press(&e, .Down)
	testing.expect_value(t, e.selected, 0)
}

@(test)
test_browse_dpad_never_edits_values :: proc(t: ^testing.T) {
	e := editor_init()
	before := e.palette
	press(&e, .Up, .Right, .Down, .Left)
	testing.expect(t, e.palette == before && !e.dirty)
}

@(test)
test_green_enters_edit_then_cycles_channels :: proc(t: ^testing.T) {
	e := editor_init()
	testing.expect_value(t, e.mode, Mode.Browse)
	press(&e, .Green)
	testing.expect_value(t, e.mode, Mode.Edit)
	testing.expect_value(t, e.channel, cm.Channel.R)
	press(&e, .Green)
	testing.expect_value(t, e.channel, cm.Channel.G)
	press(&e, .Green, .Green)
	testing.expect_value(t, e.channel, cm.Channel.R) // wraps
	press(&e, .Red)
	testing.expect_value(t, e.mode, Mode.Browse)
}

@(test)
test_edit_changes_values_and_selection_is_frozen :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 0 // black
	press(&e, .Green, .Right, .Right)
	testing.expect_value(t, e.palette[0].r, 2)
	press(&e, .Up)
	testing.expect_value(t, e.palette[0].r, 18)
	press(&e, .Down, .Down)
	testing.expect_value(t, e.palette[0].r, 0) // saturates at 0
	press(&e, .Left)
	testing.expect_value(t, e.palette[0].r, 0)
	testing.expect_value(t, e.selected, 0) // d-pad did not move the cursor
	testing.expect(t, e.dirty)
}

@(test)
test_edit_saturates_high_and_clean_when_unchanged :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 0
	press(&e, .Green, .Left) // already 0
	testing.expect(t, !e.dirty)
	for _ in 0 ..< 30 {
		press(&e, .Up)
	}
	testing.expect_value(t, e.palette[0].r, 255)
}

@(test)
test_save_and_load_requests :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Blue)
	testing.expect(t, e.requests == {.Save})
	press(&e, .Yellow)
	testing.expect(t, e.requests == {.Save, .Load})
	e.mode = .Edit
	e.requests = {}
	press(&e, .Yellow)
	testing.expect(t, e.requests == {.Load}) // works in edit mode too
}

@(test)
test_mouse_selects_swatch_and_buttons :: proc(t: ^testing.T) {
	e := editor_init()
	e.mode = .Edit
	r := swatch_rect(6)
	click_at(&e, r.x + 3, r.y + 3)
	testing.expect_value(t, e.selected, 6)
	testing.expect_value(t, e.mode, Mode.Browse)
	click_at(&e, SAVE_BUTTON.x + 1, SAVE_BUTTON.y + 1)
	testing.expect(t, .Save in e.requests)
	click_at(&e, LOAD_BUTTON.x + 1, LOAD_BUTTON.y + 1)
	testing.expect(t, .Load in e.requests)
	_, ok := swatch_at(GRID_X + CELL + 1, GRID_Y) // gap between swatches
	testing.expect(t, !ok)
}

@(test)
test_slider_click_and_drag :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 0
	rg := slider_rect(.G)
	click_at(&e, rg.x + rg.w - 1, rg.y + 2)
	testing.expect_value(t, e.channel, cm.Channel.G)
	testing.expect_value(t, e.mode, Mode.Edit)
	testing.expect_value(t, e.palette[0].g, 255)
	click_at(&e, rg.x, rg.y + 2)
	testing.expect_value(t, e.palette[0].g, 0)
	testing.expect(t, e.dirty)

	// Drag past both ends clamps.
	editor_handle_event(&e, cm.Mouse_Button_Event{button = .Left, x = rg.x + 10, y = rg.y, down = true})
	editor_handle_event(&e, cm.Mouse_Move{rg.x + 500, 0})
	testing.expect_value(t, e.palette[0].g, 255)
	editor_handle_event(&e, cm.Mouse_Move{rg.x - 500, 170})
	testing.expect_value(t, e.palette[0].g, 0)
	editor_handle_event(&e, cm.Mouse_Button_Event{button = .Left, x = 0, y = 0, down = false})
	editor_handle_event(&e, cm.Mouse_Move{rg.x + 60, 0})
	testing.expect_value(t, e.palette[0].g, 0) // no longer dragging
}

@(test)
test_wheel :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 8 // (85,85,85)
	editor_handle_event(&e, cm.Mouse_Move{0, 0})
	editor_handle_event(&e, cm.Mouse_Wheel{dy = 3})
	testing.expect_value(t, e.palette[8].r, 88)
	rb := slider_rect(.B)
	editor_handle_event(&e, cm.Mouse_Move{rb.x + 5, rb.y + 5})
	editor_handle_event(&e, cm.Mouse_Wheel{dy = -2})
	testing.expect_value(t, e.palette[8].b, 83)
	testing.expect_value(t, e.channel, cm.Channel.B)
}

Fill_Log :: struct {
	colors:   [dynamic]cm.Color,
	presents: int,
	cleared:  int,
}

@(test)
test_draw_shows_selected_color_in_both_modes :: proc(t: ^testing.T) {
	log: Fill_Log
	defer delete(log.colors)
	r := cm.Renderer {
		data = &log,
		clear = proc(d: rawptr, c: cm.Color) {(^Fill_Log)(d).cleared += 1},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			append(&(^Fill_Log)(d).colors, c)
		},
		present = proc(d: rawptr) {(^Fill_Log)(d).presents += 1},
	}
	e := editor_init()
	e.palette[5] = {12, 34, 56}
	e.selected = 5
	for m in Mode {
		e.mode = m
		clear(&log.colors)
		editor_draw(&e, &r)
		found := 0
		for c in log.colors {
			if c == (cm.Color{12, 34, 56}) {
				found += 1
			}
		}
		testing.expectf(t, found >= 2, "mode %v: swatch + preview expected", m) // swatch + preview
	}
	testing.expect_value(t, log.presents, len(Mode))
}

@(test)
test_layout_fits_screen :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, r: Rect) {
		testing.expect(t, r.x >= 0 && r.y >= 0 && r.x + r.w <= cm.SCREEN_W && r.y + r.h <= cm.SCREEN_H)
	}
	for i in 0 ..< cm.PALETTE_SIZE {
		check(t, swatch_rect(i))
	}
	for ch in cm.Channel {
		check(t, slider_rect(ch))
	}
	check(t, BANNER)
	check(t, PREVIEW)
	check(t, SAVE_BUTTON)
	check(t, LOAD_BUTTON)
	check(t, COPY_BUTTON)
	check(t, PASTE_BUTTON)
	check(t, CLIP_CHIP)
}

// --- Parity: every function must be reachable with the commands alone and with the mouse alone. ---

Input_Method :: enum {
	Commands, // keyboard or gamepad: both produce the same eight commands
	Mouse,
}

select_swatch_via :: proc(e: ^Editor, m: Input_Method, target: int) {
	switch m {
	case .Commands:
		for _ in 0 ..< target % GRID_COLS {
			press(e, .Right)
		}
		for _ in 0 ..< target / GRID_COLS {
			press(e, .Down)
		}
	case .Mouse:
		r := swatch_rect(target)
		click_at(e, r.x + r.w / 2, r.y + r.h / 2)
	}
}

@(test)
test_every_swatch_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for target in 0 ..< cm.PALETTE_SIZE {
			e := editor_init()
			select_swatch_via(&e, m, target)
			testing.expectf(t, e.selected == target, "%v could not select swatch %d (got %d)", m, target, e.selected)
		}
	}
}

// Make `ch` of swatch 0 reach `target`, starting from black.
set_value_via :: proc(e: ^Editor, m: Input_Method, ch: cm.Channel, target: int) {
	switch m {
	case .Commands:
		press(e, .Green) // enter edit mode on R
		for _ in 0 ..< int(ch) {
			press(e, .Green) // cycle to the channel
		}
		for _ in 0 ..< target / cm.STEP_BIG {
			press(e, .Up)
		}
		for _ in 0 ..< target % cm.STEP_BIG {
			press(e, .Right)
		}
	case .Mouse:
		// Click the slider at the closest pixel, then trim with the wheel.
		rc := slider_rect(ch)
		px := (target * (rc.w - 1) + 127) / 255
		click_at(e, rc.x + px, rc.y + 2)
		diff := target - int(e.palette[e.selected][ch])
		editor_handle_event(e, cm.Mouse_Wheel{diff})
	}
}

@(test)
test_every_value_of_every_channel_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for ch in cm.Channel {
			for target in 0 ..= 255 {
				e := editor_init()
				e.palette[0] = {}
				set_value_via(&e, m, ch, target)
				got := int(e.palette[0][ch])
				if got != target {
					testing.expectf(t, false, "%v could not set %v to %d (got %d)", m, ch, target, got)
					return
				}
			}
		}
	}
}

@(test)
test_slider_mapping_is_monotonic_with_exact_ends :: proc(t: ^testing.T) {
	e := editor_init()
	e.palette[0] = {}
	rc := slider_rect(.R)
	prev := -1
	for dx in 0 ..< rc.w {
		click_at(&e, rc.x + dx, rc.y + 2)
		v := int(e.palette[0].r)
		testing.expectf(t, v >= prev, "slider not monotonic at %d: %d < %d", dx, v, prev)
		if dx == 0 {
			testing.expect_value(t, v, 0)
		}
		prev = v
	}
	testing.expect_value(t, prev, 255)
}

@(test)
test_save_and_load_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for req in Request {
			e := editor_init()
			switch m {
			case .Commands:
				press(&e, req == .Save ? .Blue : .Yellow)
			case .Mouse:
				b := req == .Save ? SAVE_BUTTON : LOAD_BUTTON
				click_at(&e, b.x + b.w / 2, b.y + b.h / 2)
			}
			testing.expectf(t, req in e.requests, "%v could not request %v", m, req)
		}
	}
}

// --- Labels: help and banner text come from input_map.json. ---

@(test)
test_help_uses_default_labels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := editor_init()
	lines, n := help_lines(&e)
	testing.expect_value(t, n, 5)
	testing.expect_value(t, lines[0], "UP/DOWN/LEFT/RIGHT: MOVE")
	testing.expect_value(t, lines[1], "GREEN: EDIT COLOR")
	testing.expect_value(t, banner_text(&e), "BROWSING   GREEN: EDIT")
	e.mode = .Edit
	lines, _ = help_lines(&e)
	testing.expect_value(t, lines[3], "BLUE: SAVE  YELLOW: LOAD")
	testing.expect_value(t, banner_text(&e), "EDITING   RED: DONE")
}

@(test)
test_help_follows_edited_labels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := cm.default_input_map()
	cm.set_key_name(&m.labels[.Green], "SPACE")
	cm.set_key_name(&m.labels[.Red], "ESC")
	e := editor_init()
	e.labels = &m
	lines, _ := help_lines(&e)
	testing.expect_value(t, lines[1], "SPACE: EDIT COLOR")
	testing.expect_value(t, banner_text(&e), "BROWSING   SPACE: EDIT")
	e.mode = .Edit
	testing.expect_value(t, banner_text(&e), "EDITING   ESC: DONE")
	// The map is read live: changing it later (web loads the file after start) shows up.
	cm.set_key_name(&m.labels[.Red], "B")
	testing.expect_value(t, banner_text(&e), "EDITING   B: DONE")
}

@(test)
test_longest_labels_still_fit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := cm.default_input_map()
	for a in cm.Action {
		cm.set_key_name(&m.labels[a], "WWWWWWWWWWWW") // 12 chars, the maximum
	}
	e := editor_init()
	e.labels = &m
	for mode in Mode {
		e.mode = mode
		lines, n := help_lines(&e)
		for line in lines[:n] {
			testing.expectf(t, 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help line too wide: %s", line)
		}
		testing.expectf(t, cm.text_width(banner_text(&e)) + 8 <= BANNER.w, "banner too wide in %v", mode)
		testing.expect(t, HELP_Y + n * cm.LINE_ADVANCE <= cm.SCREEN_H)
	}
}

@(test)
test_help_block_clears_the_readouts :: proc(t: ^testing.T) {
	testing.expect(t, HELP_Y > READOUT_Y + cm.GLYPH_H)
	testing.expect(t, READOUT_Y > PREVIEW.y + PREVIEW.h)
	testing.expect(t, HELP_Y > swatch_rect(15).y + CELL) // below the swatch grid
	testing.expect(t, HELP_Y > LOAD_BUTTON.y + LOAD_BUTTON.h)
	// Buttons do not overlap each other or the clipboard chip.
	rects := [?]Rect{SAVE_BUTTON, LOAD_BUTTON, COPY_BUTTON, PASTE_BUTTON, PREVIEW, BANNER}
	for a, i in rects {
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "layout rects %d and %d overlap", i, j)
			}
		}
	}
	testing.expect(t, CLIP_CHIP.x + CLIP_CHIP.w + 4 + cm.text_width("CLIP") < SAVE_BUTTON.x)
}

// --- Copy and paste ---

@(test)
test_red_copies_and_enters_paste_mode :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 3 // (0,170,170)
	press(&e, .Red)
	testing.expect_value(t, e.mode, Mode.Paste)
	c, has := e.clipboard.?
	testing.expect(t, has && c == cm.Color{0, 170, 170})
	testing.expect(t, !e.dirty) // copying changes nothing
}

@(test)
test_paste_stamps_onto_several_swatches :: proc(t: ^testing.T) {
	e := editor_init()
	e.selected = 3
	press(&e, .Red, .Right, .Green, .Right, .Green) // copy 3, paste onto 0 (wrapped), then 1
	testing.expect_value(t, e.mode, Mode.Paste)
	testing.expect(t, e.palette[0] == e.palette[3])
	testing.expect(t, e.palette[1] == e.palette[3])
	testing.expect(t, e.dirty)
	testing.expect(t, e.palette[2] != e.palette[3]) // untouched
	// Moving in paste mode does not edit values.
	press(&e, .Up, .Left)
	testing.expect(t, e.palette[0] == e.palette[3])
}

@(test)
test_red_leaves_paste_mode_and_clipboard_survives :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Red) // copy swatch 0, enter paste
	press(&e, .Red) // done
	testing.expect_value(t, e.mode, Mode.Browse)
	_, has := e.clipboard.?
	testing.expect(t, has)
	// Green in browse still means edit, not paste.
	e.selected = 5
	before := e.palette[5]
	press(&e, .Green)
	testing.expect_value(t, e.mode, Mode.Edit)
	testing.expect(t, e.palette[5] == before)
}

@(test)
test_paste_of_identical_colour_is_not_a_change :: proc(t: ^testing.T) {
	e := editor_init()
	press(&e, .Red, .Green) // paste onto the swatch it was copied from
	testing.expect(t, !e.dirty)
}

@(test)
test_paste_without_clipboard_does_nothing :: proc(t: ^testing.T) {
	e := editor_init()
	before := e.palette
	click_at(&e, PASTE_BUTTON.x + 2, PASTE_BUTTON.y + 2)
	testing.expect(t, e.palette == before && !e.dirty)
	e.mode = .Paste // reachable only by hand, but must be safe
	press(&e, .Green)
	testing.expect(t, e.palette == before && !e.dirty)
}

@(test)
test_mouse_copy_and_paste :: proc(t: ^testing.T) {
	e := editor_init()
	a, b := swatch_rect(2), swatch_rect(9)
	click_at(&e, a.x + 3, a.y + 3)
	click_at(&e, COPY_BUTTON.x + 2, COPY_BUTTON.y + 2)
	testing.expect_value(t, e.mode, Mode.Paste)
	click_at(&e, b.x + 3, b.y + 3) // selecting in paste mode keeps paste mode
	testing.expect_value(t, e.mode, Mode.Paste)
	testing.expect_value(t, e.selected, 9)
	click_at(&e, PASTE_BUTTON.x + 2, PASTE_BUTTON.y + 2)
	testing.expect(t, e.palette[9] == e.palette[2] && e.dirty)
	// A slider click leaves paste mode for edit mode.
	r := slider_rect(.R)
	click_at(&e, r.x + 5, r.y + 2)
	testing.expect_value(t, e.mode, Mode.Edit)
}

@(test)
test_copy_paste_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		for src in ([]int{0, 5, 15}) {
			for dst in ([]int{1, 8, 14}) {
				e := editor_init()
				e.palette[src] = {11, 22, 33}
				switch m {
				case .Commands:
					select_swatch_via(&e, m, src)
					press(&e, .Red) // copy
					// Walk to dst in paste mode: back to 0 first, then across and down.
					e.selected = 0
					for _ in 0 ..< dst % GRID_COLS {
						press(&e, .Right)
					}
					for _ in 0 ..< dst / GRID_COLS {
						press(&e, .Down)
					}
					press(&e, .Green) // paste
				case .Mouse:
					a, b := swatch_rect(src), swatch_rect(dst)
					click_at(&e, a.x + 3, a.y + 3)
					click_at(&e, COPY_BUTTON.x + 2, COPY_BUTTON.y + 2)
					click_at(&e, b.x + 3, b.y + 3)
					click_at(&e, PASTE_BUTTON.x + 2, PASTE_BUTTON.y + 2)
				}
				testing.expectf(t, e.palette[dst] == (cm.Color{11, 22, 33}), "%v: copy %d -> paste %d failed", m, src, dst)
			}
		}
	}
}
