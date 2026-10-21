package common

import "core:fmt"
import "core:math"

// The PLAY text of a sound (see SOUND.md): the dialect of Microsoft BASIC's PLAY statement, turned
// into a list of notes. Pure and deterministic; nothing here knows about audio devices.
//
//   A..G [# + -] [length] [dots]   a note (sharp: # or +; flat: -); the length 1..64 overrides L
//   On        octave 0..6 (default 4; octave 3 starts at middle C)      < and >  one octave down / up
//   Nn        note by number 0..84 (0 is a rest; 1 is C of octave 0)
//   Ln        default note length 1..64 (1 whole, 4 quarter; default 4)
//   Pn [dots] pause of length n (1..64)
//   Tn        tempo, quarter notes a minute, 32..255 (default 120)
//   MN ML MS  normal (7/8 of the length sounds), legato (all of it), staccato (3/4)
// Letters may be in either case and spaces are ignored. Each dot after a note or pause adds half of
// what the previous part added (one dot makes it 3/2 as long, two dots 7/4). Anything else is an
// error with its position, and nothing plays from a text with an error. A text may not run longer
// than PLAY_MAX_SECONDS.

PLAY_MAX_SECONDS :: 60
PLAY_LOWEST_C :: 32.703195662574829 // Hz of C in octave 0 (so octave 3 starts at middle C, 261.63 Hz)

// One note or rest of a tune. Times are in seconds. The note owns `duration` seconds of the tune, of
// which the first `sounding` seconds make a sound and the rest is silence. A rest has frequency 0.
Play_Note :: struct {
	frequency: f64,
	duration:  f64,
	sounding:  f64,
}

Play_Error :: struct {
	position: int, // the index (from 0) of the character at fault
	message:  string, // on the temp allocator
}

// The frequency of pitch 0..83 (C of octave 0 is 0).
play_frequency :: proc(pitch: int) -> f64 {
	return PLAY_LOWEST_C * math.pow(2.0, f64(pitch) / 12.0)
}

// Parses PLAY text. ok is false with `err` set on the first error; the notes are then nil.
play_parse :: proc(text: string, allocator := context.temp_allocator) -> (notes: []Play_Note, err: Play_Error, ok: bool) {
	out := make([dynamic]Play_Note, allocator)
	p := 0
	octave, length, tempo := 4, 4, 120
	mode := 7.0 / 8.0
	total := 0.0

	fail :: proc(at: int, format: string, args: ..any) -> (Play_Note, Play_Error) {
		return {}, Play_Error{at, fmt.tprintf(format, ..args)}
	}

	skip_spaces :: proc(text: string, p: ^int) {
		for p^ < len(text) && (text[p^] == ' ' || text[p^] == '\t') {
			p^ += 1
		}
	}

	// A whole number starting at p (after spaces). found is false if there is none.
	read_number :: proc(text: string, p: ^int) -> (n: int, found: bool) {
		skip_spaces(text, p)
		for p^ < len(text) && text[p^] >= '0' && text[p^] <= '9' {
			n = min(n * 10 + int(text[p^] - '0'), 100000)
			found = true
			p^ += 1
		}
		return
	}

	// How many dots follow, as the factor on the length.
	read_dots :: proc(text: string, p: ^int) -> f64 {
		factor, add := 1.0, 0.5
		for {
			skip_spaces(text, p)
			if p^ >= len(text) || text[p^] != '.' {
				break
			}
			factor += add
			add /= 2
			p^ += 1
		}
		return factor
	}

	// Adds a note or rest of the given length (1..64) and dots.
	add :: proc(out: ^[dynamic]Play_Note, frequency: f64, note_length: int, dots: f64, tempo: int, mode: f64, total: ^f64) {
		duration := 4.0 / f64(note_length) * 60.0 / f64(tempo) * dots
		sounding := frequency > 0 ? duration * mode : 0.0
		append(out, Play_Note{frequency, duration, sounding})
		total^ += duration
	}

	for {
		skip_spaces(text, &p)
		if p >= len(text) {
			break
		}
		at := p
		c := text[p]
		if c >= 'a' && c <= 'z' {
			c -= 'a' - 'A'
		}
		p += 1
		switch c {
		case 'A' ..= 'G':
			base := 0 // semitones above C
			switch c {
			case 'A':
				base = 9
			case 'B':
				base = 11
			case 'D':
				base = 2
			case 'E':
				base = 4
			case 'F':
				base = 5
			case 'G':
				base = 7
			}
			if p < len(text) {
				switch text[p] {
				case '#', '+':
					base += 1
					p += 1
				case '-':
					base -= 1
					p += 1
				}
			}
			note_length := length
			skip_spaces(text, &p)
			digits_at := p
			if n, found := read_number(text, &p); found {
				if n < 1 || n > 64 {
					return nil, Play_Error{digits_at, fmt.tprintf("a note length is 1 to 64, not %d", n)}, false
				}
				note_length = n
			}
			pitch := octave * 12 + base
			if pitch < 0 || pitch > 83 {
				return nil, Play_Error{at, "that note is outside octaves 0 to 6"}, false
			}
			add(&out, play_frequency(pitch), note_length, read_dots(text, &p), tempo, mode, &total)
		case 'N':
			n, found := read_number(text, &p)
			if !found || n > 84 {
				return nil, Play_Error{at, "N needs a note number from 0 to 84"}, false
			}
			add(&out, n == 0 ? 0 : play_frequency(n - 1), length, read_dots(text, &p), tempo, mode, &total)
		case 'P':
			n, found := read_number(text, &p)
			if !found || n < 1 || n > 64 {
				return nil, Play_Error{at, "P needs a pause length from 1 to 64"}, false
			}
			add(&out, 0, n, read_dots(text, &p), tempo, mode, &total)
		case 'L':
			n, found := read_number(text, &p)
			if !found || n < 1 || n > 64 {
				return nil, Play_Error{at, "L needs a note length from 1 to 64"}, false
			}
			length = n
		case 'T':
			n, found := read_number(text, &p)
			if !found || n < 32 || n > 255 {
				return nil, Play_Error{at, "T needs a tempo from 32 to 255"}, false
			}
			tempo = n
		case 'O':
			n, found := read_number(text, &p)
			if !found || n > 6 {
				return nil, Play_Error{at, "O needs an octave from 0 to 6"}, false
			}
			octave = n
		case '<':
			if octave == 0 {
				return nil, Play_Error{at, "already in the lowest octave"}, false
			}
			octave -= 1
		case '>':
			if octave == 6 {
				return nil, Play_Error{at, "already in the highest octave"}, false
			}
			octave += 1
		case 'M':
			if p >= len(text) {
				return nil, Play_Error{at, "M needs N, L or S after it"}, false
			}
			m := text[p]
			if m >= 'a' && m <= 'z' {
				m -= 'a' - 'A'
			}
			switch m {
			case 'N':
				mode = 7.0 / 8.0
			case 'L':
				mode = 1.0
			case 'S':
				mode = 3.0 / 4.0
			case:
				return nil, Play_Error{at, "M needs N, L or S after it"}, false
			}
			p += 1
		case:
			return nil, Play_Error{at, fmt.tprintf("unexpected %c", text[at])}, false
		}
		if total > PLAY_MAX_SECONDS {
			return nil, Play_Error{at, fmt.tprintf("the tune is longer than %d seconds", PLAY_MAX_SECONDS)}, false
		}
	}
	return out[:], {}, true
}

// The length of a tune in seconds.
play_duration :: proc(notes: []Play_Note) -> (seconds: f64) {
	for n in notes {
		seconds += n.duration
	}
	return
}
