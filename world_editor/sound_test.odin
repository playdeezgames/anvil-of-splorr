#+build !js
package world_editor

import cm "../common"
import "core:strings"
import "core:testing"

// An editor with one sound "beep" (text given) and its screen open.
with_sound :: proc(text: string, loop := false) -> ^Editor {
	e := new_editor()
	i := cm.world_add_sound(&e.world, "beep")
	cm.world_set_sound_text(&e.world, i, text)
	cm.world_set_sound_loop(&e.world, i, loop)
	e.section = .Sounds
	e.mode = .List
	press(e, .Green)
	return e
}

// The audio requests the editor hands out now.
take_all :: proc(e: ^Editor) -> (out: [dynamic]cm.Audio_Request) {
	out.allocator = context.temp_allocator
	for {
		req, ok := editor_take_audio(e)
		if !ok {
			return
		}
		append(&out, req)
	}
}

@(test)
test_the_sound_list_opens_from_the_rules_section_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		e := new_editor()
		cm.world_add_sound(&e.world, "beep")
		switch m {
		case .Commands:
			goto_hub(e, .Sounds)
			press(e, .Green)
		case .Mouse:
			click_hub(e, .Sounds)
		}
		testing.expectf(t, e.mode == .List && e.section == .Sounds, "%v", m)
		press(e, .Green) // open the selected sound
		testing.expect_value(t, e.mode, Mode.Sound)
		free(e)
	}
}

@(test)
test_a_new_sound_is_named_then_given_text_with_the_keypad :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := new_editor()
	defer free(e)
	open(e, .Sounds)
	run(e, .New)
	name_typed(e, "pickup")
	testing.expect_value(t, e.mode, Mode.Sound) // New opens the sound
	testing.expect(t, e.world.sound_count == 1 && cm.name_str(&e.world.sounds[0].name) == "pickup" && e.dirty)
	press(e, .Yellow) // type the PLAY text
	testing.expect(t, e.mode == .Text && e.text_target == .Sound_Text && e.entry.max_len == cm.SOUND_TEXT_MAX)
	type_with_commands(e, "T200 O5 L16 CEG")
	press_keypad_action(e, .Done)
	testing.expect_value(t, e.mode, Mode.Sound)
	testing.expect_value(t, cm.sound_text(&e.world.sounds[0]), "T200 O5 L16 CEG")
	// Cancelling keeps what was there.
	press(e, .Yellow)
	type_with_commands(e, "X")
	press(e, .Red)
	testing.expect(t, e.mode == .Sound && cm.sound_text(&e.world.sounds[0]) == "T200 O5 L16 CEG")
	// A text with an error can be stored: the screen shows it and nothing plays.
	press(e, .Yellow)
	press_keypad_action(e, .Clear)
	type_with_commands(e, "C X")
	press_keypad_action(e, .Done)
	testing.expect_value(t, cm.sound_text(&e.world.sounds[0]), "C X")
	take_all(e) // (the stops queued while typing)
	press(e, .Green)
	testing.expect(t, e.note == NOTE_SOUND_ERROR && len(take_all(e)) == 0)
}

@(test)
test_green_plays_blue_and_red_stop_and_left_right_loop :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_sound("T240 L8 C D E")
	defer free(e)
	press(e, .Green)
	reqs := take_all(e)
	testing.expect(t, len(reqs) == 1 && reqs[0].action == .Play && reqs[0].channel == AUDITION_CHANNEL && !reqs[0].loop)
	notes, _, _ := cm.play_parse("T240 L8 C D E")
	testing.expect_value(t, len(reqs[0].samples), len(cm.play_render(notes)))
	// Loop on: the next play loops, and the world is changed.
	e.dirty = false
	press(e, .Right)
	testing.expect(t, e.world.sounds[0].loop && e.dirty)
	press(e, .Green)
	reqs = take_all(e)
	testing.expect(t, len(reqs) == 1 && reqs[0].loop)
	press(e, .Left)
	testing.expect(t, !e.world.sounds[0].loop)
	press(e, .Blue)
	reqs = take_all(e)
	testing.expect(t, len(reqs) == 1 && reqs[0].action == .Stop && reqs[0].channel == AUDITION_CHANNEL)
	// Red stops too and goes back to the list.
	press(e, .Red)
	reqs = take_all(e)
	testing.expect(t, e.mode == .List && len(reqs) == 1 && reqs[0].action == .Stop)
	// Typing text silences it first.
	press(e, .Green, .Yellow)
	reqs = take_all(e)
	testing.expect(t, e.mode == .Text && len(reqs) == 1 && reqs[0].action == .Stop)
}

@(test)
test_empty_and_wrong_text_do_not_play :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_sound("")
	defer free(e)
	press(e, .Green)
	testing.expect(t, e.note == NOTE_SOUND_NOTHING && len(take_all(e)) == 0)
	cm.world_set_sound_text(&e.world, 0, "   ") // only spaces: no notes
	press(e, .Green)
	testing.expect(t, e.note == NOTE_SOUND_NOTHING && len(take_all(e)) == 0)
	cm.world_set_sound_text(&e.world, 0, "T999")
	press(e, .Green)
	testing.expect(t, e.note == NOTE_SOUND_ERROR && len(take_all(e)) == 0)
}

@(test)
test_every_sound_screen_function_is_reachable_by_mouse :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_sound("C D E")
	defer free(e)
	click_rect(e, SOUND_PLAY)
	reqs := take_all(e)
	testing.expect(t, len(reqs) == 1 && reqs[0].action == .Play)
	click_rect(e, SOUND_STOP)
	reqs = take_all(e)
	testing.expect(t, len(reqs) == 1 && reqs[0].action == .Stop)
	click_rect(e, SOUND_LOOP)
	testing.expect(t, e.world.sounds[0].loop)
	click_rect(e, SOUND_LOOP)
	testing.expect(t, !e.world.sounds[0].loop)
	click_rect(e, SOUND_EDIT) // the keypad
	testing.expect(t, e.mode == .Text && e.text_target == .Sound_Text)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Sound)
	click_rect(e, SOUND_TEXT) // clicking the text edits it too
	testing.expect(t, e.mode == .Text)
	press(e, .Red)
	click_rect(e, SOUND_BACK)
	testing.expect_value(t, e.mode, Mode.List)
}

@(test)
test_sound_status_and_list_details :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: cm.Sound
	text, at := sound_status(&s)
	testing.expect(t, text == "EMPTY: NOTHING TO PLAY" && at == -1)
	cm.name_assign(&s.name, "x")
	n := "C D E"
	copy(s.text[:], n)
	s.text_len = len(n)
	text, at = sound_status(&s)
	testing.expect(t, text == "1.50 SECONDS, 3 NOTES" && at == -1, text)
	n = "C X"
	copy(s.text[:], n)
	s.text_len = len(n)
	text, at = sound_status(&s)
	testing.expect(t, strings.has_prefix(text, "ERROR AT CHARACTER 3: ") && at == 2, text)
	// The list's detail column.
	e := new_editor()
	defer free(e)
	cm.world_add_sound(&e.world, "a")
	cm.world_add_sound(&e.world, "b")
	cm.world_add_sound(&e.world, "c")
	cm.world_set_sound_text(&e.world, 1, "L8 CDEF")
	cm.world_set_sound_text(&e.world, 2, "Q")
	cm.world_set_sound_loop(&e.world, 1, true)
	testing.expect_value(t, item_detail(e, .Sounds, 0), "EMPTY")
	testing.expect_value(t, item_detail(e, .Sounds, 1), "1.0 S LOOP")
	testing.expect_value(t, item_detail(e, .Sounds, 2), "ERROR")
}

@(test)
test_sound_screen_text_fits_and_is_in_the_font :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_sound("C")
	defer free(e)
	for text in ([]string{sound_banner_text(e)}) {
		testing.expectf(t, cm.text_is_drawable(text) && BANNER.x + 4 + cm.text_width(text) <= BANNER.x + BANNER.w, "banner: %s", text)
	}
	lines, n := sound_help_lines(e)
	for line in lines[:n] {
		testing.expectf(t, cm.text_is_drawable(line) && 8 + cm.text_width(line) <= cm.SCREEN_W, "help: %s", line)
	}
	testing.expect(t, HELP_Y + n * cm.LINE_ADVANCE <= cm.SCREEN_H)
	for text in ([]string{NOTE_SOUND_NOTHING, NOTE_SOUND_ERROR, NOTE_SOUND_TEXT_BAD, "PLAYS ONCE", "LOOPS", "LOOP: ON", "LOOP: OFF", "(EMPTY: PRESS THE TEXT BUTTON)", "MORE..."}) {
		testing.expectf(t, cm.text_is_drawable(text), "text: %s", text)
	}
	// Every parser error, as shown: upper case, drawable, and within the screen at the worst position.
	bad := []string{"C X", "C65", "L0", "T31", "O7", "N85", "P0", "O0 <", "O6 >", "M", "MX", "O6 B#", "O0 C-", "C;", "L1 T32 C C C C C C C C C C"}
	for b in bad {
		s: cm.Sound
		copy(s.text[:], b)
		s.text_len = len(b)
		line, at := sound_status(&s)
		testing.expectf(t, at >= 0 && cm.text_is_drawable(line) && 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "%q -> %s", b, line)
	}
	longest := "ERROR AT CHARACTER 1024: THE TUNE IS LONGER THAN 60 SECONDS"
	testing.expect(t, 8 + cm.text_width(longest) <= cm.SCREEN_W - 8)
	// A full 1024-character text wraps inside its box and is cut with a marker.
	full, _ := strings.repeat("C", 1024, context.temp_allocator)
	wrapped, cut := wrap_text(full, SOUND_TEXT.w - 6, SOUND_TEXT_LINES)
	testing.expect(t, cut && len(wrapped) == SOUND_TEXT_LINES)
	for line in wrapped {
		testing.expect(t, cm.text_width(line) <= SOUND_TEXT.w - 6)
	}
	short, cut2 := wrap_text("C D E", SOUND_TEXT.w - 6, SOUND_TEXT_LINES)
	testing.expect(t, !cut2 && len(short) == 1 && short[0] == "C D E")
	// The screen's rects lie on the surface and do not overlap one another.
	rects := []Rect{SOUND_TEXT, SOUND_PLAY, SOUND_STOP, SOUND_EDIT, SOUND_LOOP, SOUND_BACK}
	for a, i in rects {
		testing.expect(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= HELP_Y)
		for b, j in rects {
			if i < j {
				testing.expectf(t, !(a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h), "rects %d and %d overlap", i, j)
			}
		}
	}
	testing.expect(t, cm.text_width("LOOP: OFF") <= SOUND_LOOP.w - 2 && SOUND_TEXT.y + SOUND_TEXT_LINES * cm.LINE_ADVANCE + 3 <= SOUND_TEXT.y + SOUND_TEXT.h)
	// Drawing the screen with a full text and an error stays on the surface.
	cm.world_set_sound_text(&e.world, 0, full)
	log: Draw_Log
	r := logging_renderer(&log)
	editor_draw(e, &r)
	testing.expect_value(t, log.out_of_bounds, 0)
	testing.expect_value(t, log.presents, 1)
}

@(test)
test_leaving_a_loaded_world_silences_the_audition :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e := with_sound("C")
	defer free(e)
	tl := tool(e)
	testing.expect(t, tl.take_audio != nil)
	press(e, .Green)
	take_all(e) // played
	good := cm.world_to_json(&e.world)
	testing.expect(t, tl.load(tl.data, transmute([]u8)good))
	reqs := take_all(e)
	testing.expect(t, len(reqs) == 1 && reqs[0].action == .Stop)
}
