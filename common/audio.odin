package common

// Playing sound without knowing the platform. A tool (or a game) asks for a sound to start or stop by
// returning `Audio_Request`s from `Tool.take_audio`; the frontend applies them to a `Mixer`, and its
// audio device pulls samples out of the mixer (SDL2: a callback; web: a script node that calls into
// wasm). Everything here is pure, so the mixing is tested without a speaker.
//
// A mixer has AUDIO_CHANNELS voices (channels). A request names the channel, so a game decides what
// can play at once: a new sound on a busy channel replaces what was there. Samples are mono 16-bit at
// `rate` (SOUND_RATE for PLAY text) and are copied into the mixer, so the request's slice only has to
// live until it is applied (the temp allocator is fine).

AUDIO_CHANNELS :: 4

Audio_Action :: enum {
	Play, // start `samples` on `channel`, looping if `loop`
	Stop, // silence `channel`
	Stop_All, // silence everything
}

Audio_Request :: struct {
	action:  Audio_Action,
	channel: int, // 0..AUDIO_CHANNELS-1
	samples: []i16,
	rate:    int, // samples a second of `samples`; 0 means SOUND_RATE
	loop:    bool,
}

Voice :: struct {
	samples: []i16, // owned copy
	rate:    int,
	pos:     f64, // the next sample to play, in source samples
	active:  bool,
	loop:    bool,
}

Mixer :: struct {
	voices: [AUDIO_CHANNELS]Voice,
}

mixer_free :: proc(m: ^Mixer) {
	for &v in m.voices {
		delete(v.samples)
	}
	m^ = {}
}

// Applies one request. A bad channel, or Play without samples, does nothing.
mixer_apply :: proc(m: ^Mixer, req: Audio_Request) {
	switch req.action {
	case .Play:
		if req.channel < 0 || req.channel >= AUDIO_CHANNELS || len(req.samples) == 0 {
			return
		}
		v := &m.voices[req.channel]
		delete(v.samples)
		v^ = Voice {
			samples = make([]i16, len(req.samples)),
			rate    = req.rate > 0 ? req.rate : SOUND_RATE,
			active  = true,
			loop    = req.loop,
		}
		copy(v.samples, req.samples)
	case .Stop:
		if req.channel >= 0 && req.channel < AUDIO_CHANNELS {
			m.voices[req.channel].active = false
		}
	case .Stop_All:
		for &v in m.voices {
			v.active = false
		}
	}
}

// How many channels are sounding.
mixer_active :: proc(m: ^Mixer) -> (n: int) {
	for v in m.voices {
		if v.active {
			n += 1
		}
	}
	return
}

// Fills `out` (mono 16-bit at `out_rate`) with the sum of the active voices, clipped; silence where
// nothing plays. A voice that reaches its end stops, or wraps if it loops.
mixer_render :: proc(m: ^Mixer, out: []i16, out_rate: int) {
	for i in 0 ..< len(out) {
		out[i] = 0
	}
	if out_rate <= 0 {
		return
	}
	// Mixed in chunks on the stack: an audio callback must not allocate.
	CHUNK :: 512
	for start := 0; start < len(out); start += CHUNK {
		n := min(CHUNK, len(out) - start)
		sums: [CHUNK]i32
		for &v in m.voices {
			if !v.active {
				continue
			}
			len_f := f64(len(v.samples))
			step := f64(v.rate) / f64(out_rate)
			for i in 0 ..< n {
				if v.pos >= len_f {
					if !v.loop {
						v.active = false
						break
					}
					v.pos -= len_f
				}
				sums[i] += i32(v.samples[int(v.pos)])
				v.pos += step
			}
		}
		for i in 0 ..< n {
			out[start + i] = i16(clamp(sums[i], -32768, 32767))
		}
	}
}

// What a frontend does each frame: hands every pending request of the tool to the mixer.
tool_service_audio :: proc(t: ^Tool, m: ^Mixer) {
	if t.take_audio == nil {
		return
	}
	for {
		req, ok := t.take_audio(t.data)
		if !ok {
			return
		}
		mixer_apply(m, req)
	}
}
