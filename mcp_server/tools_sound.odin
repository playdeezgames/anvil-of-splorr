package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

// A sound longer than this (seconds) is not sent inline as audio; export it to a file instead.
MAX_INLINE_SECONDS :: 30

sound_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{"sound_list", "List the sounds: name, loop, length in seconds and notes (or the error in the text).", `{"type":"object","properties":{}}`, tool_sound_list},
		{
			"sound_check",
			"Check PLAY text without storing it: says whether it is valid (and its length and note count) or where the first error is. PLAY text is BASIC-style: T120 tempo, O4 octave (O3 starts at middle C), L8 default length, notes A-G with # + - and a length and dots, P4 pause, N37 note number, < > octave, MN ML MS style. See SOUND.md.",
			`{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}`,
			tool_sound_check,
		},
		{
			"sound_new",
			"Add a sound (up to 64) with PLAY text (up to 1024 characters, must be valid) and a loop setting.",
			`{"type":"object","properties":{"name":{"type":"string"},"text":{"type":"string"},"loop":{"type":"boolean"}},"required":["name","text"]}`,
			tool_sound_new,
		},
		{
			"sound_set",
			"Change a sound; only the fields given change. New text must be valid PLAY text.",
			`{"type":"object","properties":{"name":{"type":"string"},"new_name":{"type":"string"},"text":{"type":"string"},"loop":{"type":"boolean"}},"required":["name"]}`,
			tool_sound_set,
		},
		{"sound_delete", "Delete a sound.", NAME_ARG, tool_sound_delete},
		{"sound_get", "A sound's text, loop setting, length and note count.", NAME_ARG, tool_sound_get},
		{
			"sound_render",
			"Render a sound (by name) or PLAY text (text) to audio: a mono 16-bit 22050 Hz WAV of a square-wave voice, attached as audio content (up to 30 seconds; longer ones: use sound_export).",
			`{"type":"object","properties":{"name":{"type":"string"},"text":{"type":"string"}}}`,
			tool_sound_render,
		},
		{
			"sound_export",
			"Write a sound (by name) or PLAY text (text) as a .wav file so a person can play it: path is absolute or relative to the server's folder and ends in .wav; replacing a file needs overwrite true.",
			`{"type":"object","properties":{"name":{"type":"string"},"text":{"type":"string"},"path":{"type":"string"},"overwrite":{"type":"boolean"}},"required":["path"]}`,
			tool_sound_export,
		},
	}
	return table[:]
}

find_sound_arg :: proc(s: ^Server, args: json.Object, key := "name") -> (index: int, res: Tool_Result, ok: bool) {
	name, r, got := need_string(args, key)
	if !got {
		return 0, r, false
	}
	i := cm.world_find_sound(s.world, name)
	if i < 0 {
		return 0, fail(fmt.tprintf("no sound named %s", name)), false
	}
	return i, {}, true
}

// Parses PLAY text for a tool: the notes, or the failure naming the position.
parsed :: proc(text: string) -> (notes: []cm.Play_Note, res: Tool_Result, ok: bool) {
	n, err, good := cm.play_parse(text)
	if !good {
		return nil, fail(fmt.tprintf("PLAY text error at character %d: %s", err.position, err.message)), false
	}
	return n, {}, true
}

// The sound named by `name`, or the text in `text`: its notes. Exactly one must be given.
notes_from_args :: proc(s: ^Server, args: json.Object) -> (notes: []cm.Play_Note, res: Tool_Result, ok: bool) {
	name, has_name := arg_string(args, "name")
	text, has_text := arg_string(args, "text")
	if has_name == has_text {
		return nil, fail("give exactly one of name and text"), false
	}
	if has_text {
		return parsed(text)
	}
	if !s.open {
		return nil, fail(NOT_OPEN), false
	}
	i := cm.world_find_sound(s.world, name)
	if i < 0 {
		return nil, fail(fmt.tprintf("no sound named %s", name)), false
	}
	return parsed(cm.sound_text(&s.world.sounds[i]))
}

tool_sound_list :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `{"sounds":[`)
	for i in 0 ..< w.sound_count {
		sd := &w.sounds[i]
		fmt.sbprintf(&b, `%s{{"name":%s,"loop":%v`, i > 0 ? "," : "", quote(cm.name_str(&sd.name)), sd.loop)
		if notes, err, good := cm.play_parse(cm.sound_text(sd)); good {
			fmt.sbprintf(&b, `,"seconds":%.3f,"notes":%d}}`, cm.play_duration(notes), len(notes))
		} else {
			fmt.sbprintf(&b, `,"error":%s}}`, quote(fmt.tprintf("character %d: %s", err.position, err.message)))
		}
	}
	strings.write_string(&b, "]}")
	return ok_result(strings.to_string(b))
}

tool_sound_check :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	text, res, ok := need_string(args, "text")
	if !ok {
		return res
	}
	n, err, good := cm.play_parse(text)
	if !good {
		return ok_result(fmt.tprintf(`{{"valid":false,"position":%d,"error":%s}}`, err.position, quote(err.message)))
	}
	return ok_result(fmt.tprintf(`{{"valid":true,"seconds":%.3f,"notes":%d,"characters":%d}}`, cm.play_duration(n), len(n), len(text)))
}

tool_sound_new :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	name, r1, ok1 := need_string(args, "name")
	if !ok1 {
		return r1
	}
	text, r2, ok2 := need_string(args, "text")
	if !ok2 {
		return r2
	}
	if p := cm.world_check_sound_name(w, -1, name); p != .None {
		return fail(problem_text(p))
	}
	if p := cm.sound_text_problem(text); p != .None {
		return fail(fmt.tprintf("the text: %s (at most %d printable ASCII characters)", problem_text(p), cm.SOUND_TEXT_MAX))
	}
	if _, r3, ok3 := parsed(text); !ok3 {
		return r3
	}
	i := cm.world_add_sound(w, name)
	if i < 0 {
		return fail("the world already has 64 sounds")
	}
	cm.world_set_sound_text(w, i, text)
	cm.world_set_sound_loop(w, i, arg_bool(args, "loop"))
	return changed(s, fmt.tprintf("added sound %s", name))
}

tool_sound_set :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	i, r1, ok1 := find_sound_arg(s, args)
	if !ok1 {
		return r1
	}
	new_name, has_name := arg_string(args, "new_name")
	if has_name {
		if p := cm.world_check_sound_name(w, i, new_name); p != .None {
			return fail(problem_text(p))
		}
	}
	text, has_text := arg_string(args, "text")
	if has_text {
		if p := cm.sound_text_problem(text); p != .None {
			return fail(fmt.tprintf("the text: %s (at most %d printable ASCII characters)", problem_text(p), cm.SOUND_TEXT_MAX))
		}
		if _, r2, ok2 := parsed(text); !ok2 {
			return r2
		}
	}
	if has_name {
		cm.world_rename_sound(w, i, new_name)
	}
	if has_text {
		cm.world_set_sound_text(w, i, text)
	}
	if _, has_loop := args["loop"]; has_loop {
		cm.world_set_sound_loop(w, i, arg_bool(args, "loop"))
	}
	return changed(s, "sound updated")
}

tool_sound_delete :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, r1, ok1 := find_sound_arg(s, args)
	if !ok1 {
		return r1
	}
	cm.world_delete_sound(s.world, i)
	return changed(s, "deleted the sound")
}

tool_sound_get :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	i, r1, ok1 := find_sound_arg(s, args)
	if !ok1 {
		return r1
	}
	sd := &s.world.sounds[i]
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `{{"name":%s,"text":%s,"loop":%v`, quote(cm.name_str(&sd.name)), quote(cm.sound_text(sd)), sd.loop)
	if notes, err, good := cm.play_parse(cm.sound_text(sd)); good {
		fmt.sbprintf(&b, `,"seconds":%.3f,"notes":%d}}`, cm.play_duration(notes), len(notes))
	} else {
		fmt.sbprintf(&b, `,"error_position":%d,"error":%s}}`, err.position, quote(err.message))
	}
	return ok_result(strings.to_string(b))
}

tool_sound_render :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	notes, res, ok := notes_from_args(s, args)
	if !ok {
		return res
	}
	seconds := cm.play_duration(notes)
	if seconds > MAX_INLINE_SECONDS {
		return fail(fmt.tprintf("%.1f seconds is too long to send inline (limit %d): use sound_export", seconds, MAX_INLINE_SECONDS))
	}
	if len(notes) == 0 {
		return fail("there is nothing to play: the text has no notes")
	}
	wav := cm.wav_encode(cm.play_render(notes))
	return {text = fmt.tprintf(`{{"seconds":%.3f,"notes":%d,"rate":%d,"bytes":%d}}`, seconds, len(notes), cm.SOUND_RATE, len(wav)), wav = wav}
}

tool_sound_export :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	notes, res, ok := notes_from_args(s, args)
	if !ok {
		return res
	}
	name, r2, ok2 := need_string(args, "path")
	if !ok2 {
		return r2
	}
	path, perr := resolve_path(s, name, allow_absolute = true, extension = ".wav")
	if perr != "" {
		return fail(perr)
	}
	if len(notes) == 0 {
		return fail("there is nothing to play: the text has no notes")
	}
	if os.exists(path) && !arg_bool(args, "overwrite") {
		return fail(fmt.tprintf("%s already exists: pass overwrite true to replace it", name))
	}
	wav := cm.wav_encode(cm.play_render(notes))
	if err := os.write_entire_file(path, wav); err != nil {
		return fail(fmt.tprintf("cannot write %s (does its folder exist?)", name))
	}
	return ok_result(fmt.tprintf(`{{"exported":%s,"path":%s,"seconds":%.3f,"bytes":%d}}`, quote(name), quote(absolute_path(path)), cm.play_duration(notes), len(wav)))
}
