package common

import "core:math"

// A square-wave voice: notes (play_text.odin) to mono 16-bit samples, and a WAV file around them.
// Pure and deterministic, so the same text gives the same samples everywhere (editor, game, tests,
// MCP). Timing is sample-exact: each note starts at the rounded sample of the time its predecessors
// add up to, so rounding never builds up.

SOUND_RATE :: 22050 // samples a second
SOUND_AMPLITUDE :: 8191 // a quarter of full scale: a square wave is loud

// The samples of a tune. Nothing for no notes.
play_render :: proc(notes: []Play_Note, rate := SOUND_RATE, allocator := context.temp_allocator) -> []i16 {
	total := play_duration(notes)
	samples := make([]i16, int(math.round(total * f64(rate))), allocator)
	amplitude := i16(SOUND_AMPLITUDE)
	start := 0.0
	for n in notes {
		first := int(math.round(start * f64(rate)))
		sounding_end := min(int(math.round((start + n.sounding) * f64(rate))), len(samples))
		if n.frequency > 0 {
			for i in first ..< sounding_end {
				phase := f64(i - first) * n.frequency / f64(rate)
				samples[i] = phase - math.floor(phase) < 0.5 ? amplitude : -amplitude
			}
		}
		start += n.duration
	}
	return samples
}

// A WAV file (RIFF, PCM, mono, 16 bits, little endian) holding the samples.
wav_encode :: proc(samples: []i16, rate := SOUND_RATE, allocator := context.temp_allocator) -> []u8 {
	data_bytes := len(samples) * 2
	out := make([dynamic]u8, 0, 44 + data_bytes, allocator)
	put32 :: proc(out: ^[dynamic]u8, v: u32) {
		append(out, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))
	}
	put16 :: proc(out: ^[dynamic]u8, v: u16) {
		append(out, u8(v), u8(v >> 8))
	}
	append(&out, 'R', 'I', 'F', 'F')
	put32(&out, u32(36 + data_bytes))
	append(&out, 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ')
	put32(&out, 16) // size of the format part
	put16(&out, 1) // PCM
	put16(&out, 1) // mono
	put32(&out, u32(rate))
	put32(&out, u32(rate * 2)) // bytes a second
	put16(&out, 2) // bytes a sample frame
	put16(&out, 16) // bits a sample
	append(&out, 'd', 'a', 't', 'a')
	put32(&out, u32(data_bytes))
	for s in samples {
		put16(&out, u16(s))
	}
	return out[:]
}
