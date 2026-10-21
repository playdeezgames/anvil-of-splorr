#+build !js
package common

import "core:math"
import "core:testing"

tune :: proc(t: ^testing.T, text: string) -> []Play_Note {
	notes, err, ok := play_parse(text)
	testing.expectf(t, ok, "%q: %v at %d", text, err.message, err.position)
	return notes
}

near :: proc(a, b: f64, tolerance := 0.001) -> bool {
	return math.abs(a - b) <= tolerance
}

@(test)
test_pitches_follow_the_basic_octaves :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect(t, near(tune(t, "O3 C")[0].frequency, 261.626, 0.01)) // octave 3 starts at middle C
	testing.expect(t, near(tune(t, "O3 A")[0].frequency, 440.0, 0.01))
	testing.expect(t, near(tune(t, "A")[0].frequency, 880.0, 0.02)) // the default octave is 4
	testing.expect(t, near(tune(t, "o0c")[0].frequency, 32.703, 0.001)) // case does not matter
	testing.expect(t, near(tune(t, "O6 B")[0].frequency, 3951.07, 0.05))
	testing.expect(t, near(tune(t, "N37")[0].frequency, 261.626, 0.01)) // note number: 1 = C of octave 0
	testing.expect(t, near(tune(t, "N1")[0].frequency, 32.703, 0.001) && near(tune(t, "N84")[0].frequency, 3951.07, 0.05))
	testing.expect_value(t, tune(t, "N0")[0].frequency, 0.0) // a rest
	// Sharps, flats, and the octave boundary.
	testing.expect(t, near(tune(t, "O3 C#")[0].frequency, tune(t, "O3 D-")[0].frequency, 0.0001))
	testing.expect(t, near(tune(t, "O3 C+")[0].frequency, 277.183, 0.01))
	testing.expect(t, near(tune(t, "O3 B#")[0].frequency, tune(t, "O4 C")[0].frequency, 0.0001))
	testing.expect(t, near(tune(t, "O4 C-")[0].frequency, tune(t, "O3 B")[0].frequency, 0.0001))
	testing.expect(t, near(tune(t, "O3 E#")[0].frequency, tune(t, "O3 F")[0].frequency, 0.0001))
	// < and > move the octave.
	n := tune(t, "O3 C > C < < C")
	testing.expect(t, near(n[1].frequency, 2 * n[0].frequency, 0.001) && near(n[2].frequency, n[0].frequency / 2, 0.001))
}

@(test)
test_lengths_tempo_dots_and_modes :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	n := tune(t, "C") // L4 at T120: half a second
	testing.expect(t, near(n[0].duration, 0.5) && near(n[0].sounding, 0.5 * 7 / 8))
	n = tune(t, "L8 C C4 C16 P2")
	testing.expect(t, near(n[0].duration, 0.25) && near(n[1].duration, 0.5) && near(n[2].duration, 0.125) && near(n[3].duration, 1.0))
	testing.expect(t, n[3].frequency == 0 && n[3].sounding == 0) // a pause makes no sound
	n = tune(t, "C. C.. P4.")
	testing.expect(t, near(n[0].duration, 0.75) && near(n[1].duration, 0.875) && near(n[2].duration, 0.75))
	n = tune(t, "T60 C T240 C")
	testing.expect(t, near(n[0].duration, 1.0) && near(n[1].duration, 0.25))
	n = tune(t, "MS C ML C MN C")
	testing.expect(t, near(n[0].sounding, 0.5 * 0.75) && near(n[1].sounding, 0.5) && near(n[2].sounding, 0.5 * 7 / 8))
	testing.expect(t, near(play_duration(tune(t, "C D E F G A B > C")), 4.0))
	testing.expect_value(t, len(tune(t, "")), 0)
	testing.expect_value(t, len(tune(t, "   ")), 0)
	// Spaces are ignored anywhere between parts.
	testing.expect(t, near(tune(t, "L 8 C 4 .")[0].duration, 0.75))
	testing.expect(t, near(tune(t, "t 90 o 2 l 2 n 12")[0].duration, 4.0 / 2 * 60.0 / 90))
}

@(test)
test_errors_say_where_they_are :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	cases := []struct {
		text:     string,
		position: int,
	} {
		{"C X", 2},
		{"1", 0}, // a number with nothing to apply to
		{"C65", 1},
		{"C0", 1},
		{"L0", 0},
		{"L65", 0},
		{"T31", 0},
		{"T256", 0},
		{"T", 0},
		{"O7", 0},
		{"O", 0},
		{"N85", 0},
		{"N", 0},
		{"P0", 0},
		{"P", 0},
		{"C O7", 2},
		{"O0 <", 3},
		{"O6 >", 3},
		{"M", 0},
		{"MX", 0},
		{"O6 B#", 3}, // would be octave 7
		{"O0 C-", 3}, // would be below octave 0
		{"C;", 1},
		{"C\nD", 1},
		{"MF C", 0}, // foreground/background is not supported
	}
	for c in cases {
		notes, err, ok := play_parse(c.text)
		testing.expectf(t, !ok && notes == nil && err.message != "" && err.position == c.position, "%q: ok=%v pos=%d (%s), wanted %d", c.text, ok, err.position, err.message, c.position)
	}
	// A tune over a minute is refused at the note that passes it.
	_, err, ok := play_parse("L1 T32 C C C C C C C C C")
	testing.expect(t, !ok && err.position > 0)
}

@(test)
test_synth_makes_square_waves_of_the_right_pitch_and_length :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	notes := tune(t, "O3 A ML P4")
	samples := play_render(notes)
	testing.expect_value(t, len(samples), SOUND_RATE) // a half-second note and a half-second pause
	// 440 Hz for 7/8 of half a second: count the rises.
	rises := 0
	for i in 1 ..< len(samples) {
		if samples[i - 1] <= 0 && samples[i] > 0 {
			rises += 1
		}
	}
	testing.expect(t, rises >= 191 && rises <= 193, "about 192 cycles of 440 Hz in 0.4375 s")
	testing.expect_value(t, samples[10], i16(SOUND_AMPLITUDE) * (samples[10] > 0 ? 1 : -1)) // only two levels
	sounding_end := int(math.round(0.4375 * f64(SOUND_RATE)))
	silent := true
	for i in sounding_end + 1 ..< len(samples) {
		silent &&= samples[i] == 0
	}
	testing.expect(t, silent)
	testing.expect(t, samples[sounding_end - 2] != 0)
	// Deterministic, and empty for no notes.
	again := play_render(notes)
	same := len(again) == len(samples)
	for i in 0 ..< min(len(again), len(samples)) {
		same &&= again[i] == samples[i]
	}
	testing.expect(t, same)
	testing.expect_value(t, len(play_render(nil)), 0)
	// Notes do not drift apart: a hundred short notes take exactly their total length.
	many := tune(t, "L64 T200 CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC")
	testing.expect_value(t, len(play_render(many)), int(math.round(play_duration(many) * SOUND_RATE)))
}

@(test)
test_wav_files_have_a_valid_header :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	samples := []i16{0, 1, -1, 32767, -32768}
	wav := wav_encode(samples)
	testing.expect_value(t, len(wav), 44 + 10)
	testing.expect(t, string(wav[0:4]) == "RIFF" && string(wav[8:12]) == "WAVE" && string(wav[12:16]) == "fmt " && string(wav[36:40]) == "data")
	u32_at :: proc(b: []u8, i: int) -> u32 {
		return u32(b[i]) | u32(b[i + 1]) << 8 | u32(b[i + 2]) << 16 | u32(b[i + 3]) << 24
	}
	testing.expect_value(t, u32_at(wav, 4), u32(36 + 10)) // file size minus 8
	testing.expect_value(t, u32_at(wav, 24), u32(SOUND_RATE))
	testing.expect_value(t, u32_at(wav, 28), u32(SOUND_RATE * 2))
	testing.expect_value(t, u32_at(wav, 40), u32(10))
	testing.expect(t, wav[20] == 1 && wav[22] == 1 && wav[34] == 16) // PCM, mono, 16 bits
	testing.expect(t, wav[44] == 0 && wav[46] == 1 && wav[48] == 0xFF && wav[49] == 0xFF && wav[50] == 0xFF && wav[51] == 0x7F && wav[53] == 0x80)
}
