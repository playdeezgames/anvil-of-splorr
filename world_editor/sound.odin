package world_editor

import cm "../common"
import "core:fmt"
import "core:strings"

// A sound's screen (Mode.Sound): its name, loop setting, its PLAY text (typed with the long keypad)
// and what the parser makes of it, with the error's character marked. Green plays it (again from the
// start), blue stops it, yellow edits the text, left/right switch looping on and off, red goes back
// to the list. The mouse has PLAY, STOP, EDIT, LOOP and BACK buttons, and clicking the text edits it.
// Nothing plays from text with an error. Audio goes out as requests (`editor_take_audio`).

// The channel an audition plays on.
AUDITION_CHANNEL :: 0

Audio_Op :: enum {
	Play,
	Stop,
}

NOTE_SOUND_NOTHING :: "NOTHING TO PLAY"
NOTE_SOUND_ERROR :: "FIX THE ERROR FIRST"
NOTE_SOUND_TEXT_BAD :: "UNUSABLE CHARACTER IN TEXT"

@(private = "file")
sound_index :: proc(e: ^Editor) -> int {
	return e.sel[.Sounds]
}

@(private = "file")
current_sound :: proc(e: ^Editor) -> ^cm.Sound {
	return &e.world.sounds[sound_index(e)]
}

queue_audio :: proc(e: ^Editor, op: Audio_Op) {
	if e.audio_ops_n < len(e.audio_ops) {
		e.audio_ops[e.audio_ops_n] = op
		e.audio_ops_n += 1
	}
}

begin_sound :: proc(e: ^Editor) {
	e.mode = .Sound
}

@(private = "file")
leave_sound :: proc(e: ^Editor) {
	queue_audio(e, .Stop)
	e.mode = .List
}

// The next audio request the editor has for the frontend, if any. Rendering happens here, so the
// samples are on the temp allocator of the frame that uses them.
editor_take_audio :: proc(e: ^Editor) -> (req: cm.Audio_Request, ok: bool) {
	for e.audio_ops_n > 0 {
		op := e.audio_ops[0]
		for i in 1 ..< e.audio_ops_n {
			e.audio_ops[i - 1] = e.audio_ops[i]
		}
		e.audio_ops_n -= 1
		switch op {
		case .Stop:
			return cm.Audio_Request{action = .Stop, channel = AUDITION_CHANNEL}, true
		case .Play:
			if e.world.sound_count == 0 || sound_index(e) >= e.world.sound_count {
				continue
			}
			s := current_sound(e)
			notes, _, parsed := cm.play_parse(cm.sound_text(s))
			if !parsed || len(notes) == 0 {
				continue
			}
			return cm.Audio_Request{action = .Play, channel = AUDITION_CHANNEL, samples = cm.play_render(notes), loop = s.loop}, true
		}
	}
	return {}, false
}

// Plays the sound from the start, or says why it cannot.
@(private = "file")
play_sound :: proc(e: ^Editor) {
	notes, _, parsed := cm.play_parse(cm.sound_text(current_sound(e)))
	switch {
	case !parsed:
		e.note = NOTE_SOUND_ERROR
	case len(notes) == 0:
		e.note = NOTE_SOUND_NOTHING
	case:
		queue_audio(e, .Play)
	}
}

@(private = "file")
edit_sound_text :: proc(e: ^Editor) {
	queue_audio(e, .Stop) // (silence while typing)
	e.text_target = .Sound_Text
	cm.text_entry_begin_long(&e.entry, "PLAY TEXT", cm.sound_text(current_sound(e)), cm.SOUND_TEXT_MAX)
	e.mode = .Text
}

@(private = "file")
toggle_loop :: proc(e: ^Editor) {
	s := current_sound(e)
	cm.world_set_sound_loop(&e.world, sound_index(e), !s.loop)
	touched(e)
}

// The keypad for the text: Done stores it (it may still have PLAY errors, which the screen shows),
// Cancel keeps what was there.
handle_sound_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.text_target = .Name
		e.mode = .Sound
	case .Done:
		if problem := cm.world_set_sound_text(&e.world, sound_index(e), cm.text_entry_text(&e.entry)); problem != .None {
			cm.text_entry_resume(&e.entry, NOTE_SOUND_TEXT_BAD)
			return
		}
		touched(e)
		e.text_target = .Name
		e.mode = .Sound
	}
}

// Commands and the mouse on the sound screen.
handle_sound :: proc(e: ^Editor, ev: cm.Input_Event) {
	#partial switch v in ev {
	case cm.Command:
		e.note = ""
	case cm.Mouse_Button_Event:
		if v.down {
			e.note = ""
		}
	}
	switch v in ev {
	case cm.Command:
		#partial switch v.action {
		case .Green:
			play_sound(e)
		case .Blue:
			queue_audio(e, .Stop)
		case .Yellow:
			edit_sound_text(e)
		case .Left, .Right:
			toggle_loop(e)
		case .Red:
			leave_sound(e)
		}
	case cm.Mouse_Move:
	case cm.Mouse_Button_Event:
		if v.button == .Left && v.down {
			switch {
			case rect_contains(SOUND_PLAY, v.x, v.y):
				play_sound(e)
			case rect_contains(SOUND_STOP, v.x, v.y):
				queue_audio(e, .Stop)
			case rect_contains(SOUND_EDIT, v.x, v.y), rect_contains(SOUND_TEXT, v.x, v.y):
				edit_sound_text(e)
			case rect_contains(SOUND_LOOP, v.x, v.y):
				toggle_loop(e)
			case rect_contains(SOUND_BACK, v.x, v.y):
				leave_sound(e)
			}
		}
	case cm.Mouse_Wheel:
	}
}

sound_banner_text :: proc(e: ^Editor) -> string {
	return fmt.tprintf("SOUND   %s: PLAY  %s: STOP  %s: TEXT", label(e, .Green), label(e, .Blue), label(e, .Yellow))
}

sound_help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	lines = {
		fmt.tprintf("%s: PLAY FROM THE START  %s: STOP", l(e, .Green), l(e, .Blue)),
		fmt.tprintf("%s: TYPE THE PLAY TEXT", l(e, .Yellow)),
		fmt.tprintf("%s/%s: LOOP ON / OFF  %s: BACK", l(e, .Left), l(e, .Right), l(e, .Red)),
		"MOUSE: THE BUTTONS; CLICK THE TEXT TO EDIT IT",
	}
	return lines, 4
}

// What the parser makes of a sound's text, for the line under its name: the length and note count,
// or the error (upper case, with its 1-based character number). `error_at` is the 0-based position of
// the bad character, or -1.
sound_status :: proc(s: ^cm.Sound) -> (text: string, error_at: int) {
	if s.text_len == 0 {
		return "EMPTY: NOTHING TO PLAY", -1
	}
	notes, err, ok := cm.play_parse(cm.sound_text(s))
	if !ok {
		return fmt.tprintf("ERROR AT CHARACTER %d: %s", err.position + 1, strings.to_upper(err.message, context.temp_allocator)), err.position
	}
	return fmt.tprintf("%.2f SECONDS, %d NOTES", cm.play_duration(notes), len(notes)), -1
}

// Splits text into lines no wider than `width` pixels (by characters). More than `max_lines` lines
// are cut; `cut` says so.
wrap_text :: proc(text: string, width, max_lines: int) -> (lines: []string, cut: bool) {
	out := make([dynamic]string, context.temp_allocator)
	start, used := 0, 0
	for i in 0 ..< len(text) {
		w := cm.text_width(text[i:i + 1])
		if used + w > width && i > start {
			append(&out, text[start:i])
			start, used = i, 0
		}
		used += w
	}
	if start < len(text) {
		append(&out, text[start:])
	}
	if len(out) > max_lines {
		return out[:max_lines], true
	}
	return out[:], false
}

SOUND_TEXT_LINES :: 12

draw_sound :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	i := sound_index(e)
	s := current_sound(e)
	fill(r, BANNER, HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, sound_banner_text(e), BG)
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	} else {
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("%d OF %d%s", i + 1, e.world.sound_count, e.dirty ? "  *" : ""), TEXT)
	}
	cm.draw_text(r, 8, 28, cm.name_str(&s.name), HILITE)
	loop := s.loop ? "LOOPS" : "PLAYS ONCE"
	cm.draw_text(r, 304 - cm.text_width(loop), 28, loop, TEXT)
	status, error_at := sound_status(s)
	cm.draw_text(r, 8, 38, status, error_at >= 0 ? WARN : DIM)
	// The text, wrapped; the bad character, if any, in the warning colour.
	fill(r, SOUND_TEXT, PANEL)
	text := cm.sound_text(s)
	if text == "" {
		cm.draw_text(r, SOUND_TEXT.x + 3, SOUND_TEXT.y + 3, "(EMPTY: PRESS THE TEXT BUTTON)", DIM)
	}
	lines, cut := wrap_text(text, SOUND_TEXT.w - 6, SOUND_TEXT_LINES)
	offset := 0
	for line, k in lines {
		y := SOUND_TEXT.y + 3 + k * cm.LINE_ADVANCE
		cm.draw_text(r, SOUND_TEXT.x + 3, y, line, TEXT)
		if error_at >= offset && error_at < offset + len(line) {
			bad := text[error_at:error_at + 1]
			x := SOUND_TEXT.x + 3 + cm.text_width(line[:error_at - offset])
			fill(r, Rect{x, y, max(cm.text_width(bad), 3), cm.GLYPH_H - 1}, WARN)
			cm.draw_text(r, x, y, bad, BG)
		}
		offset += len(line)
	}
	if cut {
		cm.draw_text(r, SOUND_TEXT.x + SOUND_TEXT.w - 3 - cm.text_width("MORE..."), SOUND_TEXT.y + SOUND_TEXT.h - 8, "MORE...", DIM)
	}
	for b in ([5]struct {
			rc:  Rect,
			txt: string,
		}{{SOUND_PLAY, "PLAY"}, {SOUND_STOP, "STOP"}, {SOUND_EDIT, "TEXT"}, {SOUND_LOOP, s.loop ? "LOOP: ON" : "LOOP: OFF"}, {SOUND_BACK, "BACK"}}) {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + (b.rc.h - cm.GLYPH_H) / 2, b.txt, TEXT)
	}
	lines2, n := sound_help_lines(e)
	for line, k in lines2[:n] {
		cm.draw_text(r, 8, HELP_Y + k * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
