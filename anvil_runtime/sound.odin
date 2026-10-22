package anvil_runtime

import cm "../common"

// Sounds of a world, for a game. A sound is PLAY text (see SOUND.md) that the world's authors made in
// the editor; the game asks for it by name and hands the result to the frontend as an audio request
// from its Tool's `take_audio` hook:
//
//     take_audio = proc(data: rawptr) -> (rt.Audio_Request, bool) {
//         // pop the next request the game queued, e.g. one made with rt.sound_play(world, "pickup", 0)
//     },
//
// Nothing here touches an audio device, so the package still builds everywhere and a game with no
// sound simply never calls it. Rendering a sound (parse, then square wave) takes a moment of CPU: a
// game that plays the same short effect often can keep the request's samples (`sound_pcm`) and
// reuse them.

Audio_Request :: cm.Audio_Request
AUDIO_CHANNELS :: cm.AUDIO_CHANNELS // the frontend's mixer has this many voices; a request names one

sound_count :: proc(w: ^World) -> int {
	return w.sound_count
}

// The index of a sound by name.
find_sound :: proc(w: ^World, name: string) -> (index: int, ok: bool) {
	i := cm.world_find_sound(w, name)
	return i, i >= 0
}

// Which of `required` sound names the world lacks, in the order given (empty if it has them all):
// check this once at start-up, like `required_missing` for tags. On the temp allocator unless
// another is given.
missing_sounds :: proc(w: ^World, required: []string, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	for name in required {
		if cm.world_find_sound(w, name) < 0 {
			append(&out, name)
		}
	}
	return out[:]
}

// The names of sounds whose PLAY text has an error (a sound the editor let through): empty if every
// sound is fine, so a game can stop at start-up instead of playing silence later. An empty text is
// not an error here. On the temp allocator unless another is given.
broken_sounds :: proc(w: ^World, allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	for i in 0 ..< w.sound_count {
		s := &w.sounds[i]
		if _, _, ok := cm.play_parse(cm.sound_text(s)); !ok {
			append(&out, cm.name_str(&s.name))
		}
	}
	return out[:]
}

// Whether the sound is meant to repeat until stopped.
sound_loops :: proc(w: ^World, index: int) -> bool {
	return index >= 0 && index < w.sound_count && w.sounds[index].loop
}

// The length in seconds of a sound, or 0 if it has no notes or its text has an error.
sound_seconds :: proc(w: ^World, index: int) -> f64 {
	if index < 0 || index >= w.sound_count {
		return 0
	}
	notes, _, ok := cm.play_parse(cm.sound_text(&w.sounds[index]))
	return ok ? cm.play_duration(notes) : 0
}

// The samples of a sound (mono, 16 bits, `cm.SOUND_RATE` a second), or ok = false for no such sound,
// text with an error, or no notes. On the temp allocator unless another is given.
sound_pcm :: proc(w: ^World, index: int, allocator := context.temp_allocator) -> (samples: []i16, ok: bool) {
	if index < 0 || index >= w.sound_count {
		return nil, false
	}
	notes, _, parsed := cm.play_parse(cm.sound_text(&w.sounds[index]), context.temp_allocator)
	if !parsed || len(notes) == 0 {
		return nil, false
	}
	return cm.play_render(notes, cm.SOUND_RATE, allocator), true
}

// The request that plays a sound by name on a channel (0..AUDIO_CHANNELS-1), looping if the sound is
// set to. ok is false for an unknown or unplayable sound. The samples are on the temp allocator
// unless another is given, so hand the request to the frontend in the same frame.
sound_play :: proc(w: ^World, name: string, channel: int, allocator := context.temp_allocator) -> (req: Audio_Request, ok: bool) {
	i, found := find_sound(w, name)
	if !found || channel < 0 || channel >= AUDIO_CHANNELS {
		return {}, false
	}
	samples, rendered := sound_pcm(w, i, allocator)
	if !rendered {
		return {}, false
	}
	return Audio_Request{action = .Play, channel = channel, samples = samples, rate = cm.SOUND_RATE, loop = w.sounds[i].loop}, true
}

// The request that silences a channel, and the one that silences everything.
sound_stop :: proc(channel: int) -> Audio_Request {
	return Audio_Request{action = .Stop, channel = channel}
}

sound_stop_all :: proc() -> Audio_Request {
	return Audio_Request{action = .Stop_All}
}
