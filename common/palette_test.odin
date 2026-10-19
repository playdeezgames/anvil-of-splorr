#+build !js
package common

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
test_bytes_round_trip :: proc(t: ^testing.T) {
	p := default_palette()
	palette_set_channel(&p, 5, .B, 1)
	bytes := palette_to_bytes(p)
	testing.expect_value(t, len(bytes), 48)
	testing.expect_value(t, bytes[5 * 3 + 2], 1)
	q, ok := palette_from_bytes(bytes[:])
	testing.expect(t, ok)
	testing.expect(t, q == p)
}

@(test)
test_from_bytes_rejects_wrong_length :: proc(t: ^testing.T) {
	buf: [PALETTE_BYTES + 1]u8
	_, ok := palette_from_bytes(buf[:PALETTE_BYTES - 1])
	testing.expect(t, !ok)
	_, ok = palette_from_bytes(buf[:])
	testing.expect(t, !ok)
	_, ok = palette_from_bytes(nil)
	testing.expect(t, !ok)
}
