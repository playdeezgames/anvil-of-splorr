#+build !js
package common

import "core:image"
import "core:image/png"
import "core:testing"

decode :: proc(t: ^testing.T, bytes: []u8) -> ^image.Image {
	img, err := png.load_from_bytes(bytes, {.alpha_drop_if_present}, context.temp_allocator)
	testing.expect_value(t, err, nil)
	return img
}

@(test)
test_png_round_trips_indexed_and_truecolour :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Few colours: indexed. 300 x 3 pixels so the data needs more than one stored block? (900 px, no) -
	// use a tall one below for that.
	c := rgb_canvas_make(7, 5, Color{10, 20, 30})
	r := rgb_canvas_renderer(&c)
	renderer_fill_rect(&r, 2, 1, 3, 2, Color{255, 0, 128})
	renderer_fill_rect(&r, -5, -5, 7, 7, Color{1, 2, 3}) // clipped to the picture
	bytes := png_encode_rgb(c.pixels, c.width, c.height)
	img := decode(t, bytes)
	testing.expect(t, img != nil && img.width == 7 && img.height == 5 && img.channels == 3 && img.depth == 8)
	pix := img.pixels.buf[:]
	for y in 0 ..< 5 {
		for x in 0 ..< 7 {
			want := [3]u8{c.pixels[(y * 7 + x) * 3], c.pixels[(y * 7 + x) * 3 + 1], c.pixels[(y * 7 + x) * 3 + 2]}
			got := [3]u8{pix[(y * 7 + x) * 3], pix[(y * 7 + x) * 3 + 1], pix[(y * 7 + x) * 3 + 2]}
			testing.expectf(t, want == got, "pixel %d,%d", x, y)
		}
	}
	// More than 256 colours: truecolour, and enough data to need several stored blocks.
	big := rgb_canvas_make(200, 120, Color{})
	for y in 0 ..< 120 {
		for x in 0 ..< 200 {
			rgb_canvas_fill(&big, x, y, 1, 1, Color{u8(x), u8(y), u8(x ~ y)})
		}
	}
	bytes = png_encode_rgb(big.pixels, big.width, big.height)
	img = decode(t, bytes)
	testing.expect(t, img != nil && img.width == 200 && img.height == 120)
	if img != nil {
		pix = img.pixels.buf[:]
		same := true
		for i in 0 ..< len(big.pixels) {
			same &&= pix[i] == big.pixels[i]
		}
		testing.expect(t, same)
	}
	testing.expect(t, png_encode_rgb(nil, 0, 0) == nil && png_encode_rgb([]u8{1, 2}, 1, 1) == nil)
}
