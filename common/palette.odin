package common

PALETTE_SIZE :: 16

Color :: [3]u8

Channel :: enum {
	R,
	G,
	B,
}

Palette :: [PALETTE_SIZE]Color

// The 16 standard VGA text-mode colours.
default_palette :: proc() -> Palette {
	return Palette {
		{0, 0, 0},
		{0, 0, 170},
		{0, 170, 0},
		{0, 170, 170},
		{170, 0, 0},
		{170, 0, 170},
		{170, 85, 0},
		{170, 170, 170},
		{85, 85, 85},
		{85, 85, 255},
		{85, 255, 85},
		{85, 255, 255},
		{255, 85, 85},
		{255, 85, 255},
		{255, 255, 85},
		{255, 255, 255},
	}
}

// Sets a channel, saturating the value to 0..255. Returns false if index is out of range.
palette_set_channel :: proc(p: ^Palette, index: int, ch: Channel, value: int) -> bool {
	if index < 0 || index >= PALETTE_SIZE {
		return false
	}
	p[index][ch] = u8(clamp(value, 0, 255))
	return true
}

// Adds delta to a channel, saturating at 0 and 255. Returns false if index is out of range.
palette_adjust_channel :: proc(p: ^Palette, index: int, ch: Channel, delta: int) -> bool {
	if index < 0 || index >= PALETTE_SIZE {
		return false
	}
	return palette_set_channel(p, index, ch, int(p[index][ch]) + delta)
}
