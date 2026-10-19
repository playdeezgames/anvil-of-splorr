#+build !js
package common

import "core:strings"
import "core:testing"

@(test)
test_set_channel_saturates :: proc(t: ^testing.T) {
	p := default_palette()
	testing.expect(t, palette_set_channel(&p, 3, .G, 300))
	testing.expect_value(t, p[3].g, 255)
	testing.expect(t, palette_set_channel(&p, 3, .G, -5))
	testing.expect_value(t, p[3].g, 0)
	testing.expect(t, palette_set_channel(&p, 3, .G, 0))
	testing.expect(t, palette_set_channel(&p, 3, .G, 255))
	testing.expect_value(t, p[3].g, 255)
}

@(test)
test_adjust_channel_saturates :: proc(t: ^testing.T) {
	p: Palette
	palette_set_channel(&p, 0, .R, 250)
	palette_adjust_channel(&p, 0, .R, 16)
	testing.expect_value(t, p[0].r, 255)
	palette_adjust_channel(&p, 0, .R, -300)
	testing.expect_value(t, p[0].r, 0)
	palette_adjust_channel(&p, 0, .R, 1)
	testing.expect_value(t, p[0].r, 1)
}

@(test)
test_index_bounds :: proc(t: ^testing.T) {
	p := default_palette()
	before := p
	testing.expect(t, !palette_set_channel(&p, -1, .R, 1))
	testing.expect(t, !palette_set_channel(&p, PALETTE_SIZE, .R, 1))
	testing.expect(t, !palette_adjust_channel(&p, PALETTE_SIZE, .B, 1))
	testing.expect(t, p == before)
	testing.expect(t, palette_set_channel(&p, PALETTE_SIZE - 1, .B, 7))
}

@(test)
test_json_round_trip :: proc(t: ^testing.T) {
	p := default_palette()
	palette_set_channel(&p, 5, .B, 1)
	palette_set_channel(&p, 15, .R, 7)
	text := palette_to_json(p)
	defer free_all(context.temp_allocator)
	q, ok := palette_from_json(transmute([]u8)text)
	testing.expect(t, ok)
	testing.expect(t, q == p)
}

@(test)
test_json_text_is_stable :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	text := palette_to_json(default_palette())
	testing.expect(t, strings.has_prefix(text, "{\n  \"colors\": [\n    {\"r\": 0, \"g\": 0, \"b\": 0},\n"))
	testing.expect(t, strings.has_suffix(text, "{\"r\": 255, \"g\": 255, \"b\": 255}\n  ]\n}\n"))
}

parse_str :: proc(s: string) -> bool {
	_, ok := palette_from_json(transmute([]u8)s)
	return ok
}

@(test)
test_json_rejects_bad_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	good := palette_to_json(default_palette())
	testing.expect(t, parse_str(good))
	testing.expect(t, !parse_str(""))
	testing.expect(t, !parse_str("not json"))
	testing.expect(t, !parse_str("[]"))
	testing.expect(t, !parse_str("{}"))
	testing.expect(t, !parse_str(`{"colors": []}`))
	// 15 entries
	short, _ := strings.replace(good, "    {\"r\": 0, \"g\": 0, \"b\": 0},\n", "", 1, context.temp_allocator)
	testing.expect(t, !parse_str(short))
	// out of range, negative, fractional, wrong type, missing channel
	bad1, _ := strings.replace(good, `"r": 170`, `"r": 256`, 1, context.temp_allocator)
	bad2, _ := strings.replace(good, `"r": 170`, `"r": -1`, 1, context.temp_allocator)
	bad3, _ := strings.replace(good, `"r": 170`, `"r": 1.5`, 1, context.temp_allocator)
	bad4, _ := strings.replace(good, `"r": 170`, `"r": "170"`, 1, context.temp_allocator)
	bad5, _ := strings.replace(good, `"r": 170, `, "", 1, context.temp_allocator)
	for b in ([]string{bad1, bad2, bad3, bad4, bad5}) {
		testing.expectf(t, !parse_str(b), "accepted: %s", b)
	}
}

@(test)
test_json_accepts_integral_floats_and_extra_fields :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	good := palette_to_json(default_palette())
	a, _ := strings.replace(good, `"r": 170`, `"r": 170.0`, 1, context.temp_allocator)
	testing.expect(t, parse_str(a))
	b, _ := strings.replace(good, `"colors"`, `"name": "x", "colors"`, 1, context.temp_allocator)
	testing.expect(t, parse_str(b))
}
