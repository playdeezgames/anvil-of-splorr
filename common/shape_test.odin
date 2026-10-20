#+build !js
package common

import "core:testing"

// A deterministic, asymmetric picture so any wrong move shows up.
sample_bitmap :: proc(w, h: int) -> Bitmap {
	g := bitmap_make(w, h)
	for y in 0 ..< h {
		for x in 0 ..< w {
			bitmap_set(&g, x, y, (x * 3 + y * 7 + x * y) % 5 < 2)
		}
	}
	return g
}

sample_image :: proc(w, h: int) -> Image4 {
	img := image4_make(w, h)
	for y in 0 ..< h {
		for x in 0 ..< w {
			image4_set(&img, x, y, (x * 3 + y * 5 + x * y) % 16)
		}
	}
	return img
}

@(test)
test_rotations_move_every_pixel_to_the_right_place :: proc(t: ^testing.T) {
	for size in ([][2]int{{1, 1}, {1, 5}, {5, 1}, {2, 3}, {3, 2}, {4, 4}, {7, 3}, {9, 9}, {64, 5}, {5, 64}, {64, 64}}) {
		w, h := size[0], size[1]
		g := sample_bitmap(w, h)
		orig := g
		bitmap_rotate_right(&g)
		testing.expectf(t, g.width == h && g.height == w, "%dx%d right: size", w, h)
		for y in 0 ..< h {
			for x in 0 ..< w {
				// Clockwise: (x, y) -> (h-1-y, x).
				testing.expectf(t, g.bits[x][h - 1 - y] == orig.bits[y][x], "%dx%d right (%d,%d)", w, h, x, y)
			}
		}
		g = orig
		bitmap_rotate_left(&g)
		testing.expectf(t, g.width == h && g.height == w, "%dx%d left: size", w, h)
		for y in 0 ..< h {
			for x in 0 ..< w {
				// Counter-clockwise: (x, y) -> (y, w-1-x).
				testing.expectf(t, g.bits[w - 1 - x][y] == orig.bits[y][x], "%dx%d left (%d,%d)", w, h, x, y)
			}
		}
		g = orig
		bitmap_rotate_180(&g)
		testing.expectf(t, g.width == w && g.height == h, "%dx%d 180: size", w, h)
		for y in 0 ..< h {
			for x in 0 ..< w {
				testing.expectf(t, g.bits[h - 1 - y][w - 1 - x] == orig.bits[y][x], "%dx%d 180 (%d,%d)", w, h, x, y)
			}
		}
	}
}

@(test)
test_rotations_compose :: proc(t: ^testing.T) {
	g := sample_bitmap(7, 3)
	orig := g
	for _ in 0 ..< 4 {
		bitmap_rotate_right(&g)
	}
	testing.expect(t, bitmap_visible_equal(&g, &orig)) // four right turns are none
	bitmap_rotate_right(&g)
	bitmap_rotate_left(&g)
	testing.expect(t, bitmap_visible_equal(&g, &orig)) // right then left cancel
	bitmap_rotate_180(&g)
	bitmap_rotate_180(&g)
	testing.expect(t, bitmap_visible_equal(&g, &orig))
	bitmap_rotate_right(&g)
	bitmap_rotate_right(&g)
	twice := g
	g = orig
	bitmap_rotate_180(&g)
	testing.expect(t, bitmap_visible_equal(&g, &twice)) // 180 is two quarter turns
}

@(test)
test_rotation_change_reporting_and_hidden_pixels :: proc(t: ^testing.T) {
	// "Changed" includes the size: a blank 3 x 5 turned is a blank 5 x 3, which is a different image
	// (and file). A blank square image really is unchanged.
	blank := bitmap_make(3, 5)
	testing.expect(t, bitmap_rotate_right(&blank) && blank.width == 5 && blank.height == 3)
	blank_sq := bitmap_make(4, 4)
	testing.expect(t, !bitmap_rotate_right(&blank_sq) && !bitmap_rotate_left(&blank_sq) && !bitmap_rotate_180(&blank_sq))
	sq := bitmap_make(4, 4)
	bitmap_set(&sq, 1, 1, true)
	bitmap_set(&sq, 2, 2, true) // point symmetric about the centre
	testing.expect(t, !bitmap_rotate_180(&sq))
	testing.expect(t, bitmap_rotate_right(&sq)) // but a quarter turn moves them
	// Hidden pixels outside the new visible area are untouched; ones inside it are replaced.
	g := bitmap_make(8, 8)
	g.bits[40][40] = true // far away
	bitmap_resize(&g, 4, 2)
	g.bits[5][1] = true // hidden now, and inside the 2 x 4 area after a turn
	bitmap_set(&g, 0, 0, true)
	bitmap_rotate_right(&g)
	testing.expect(t, g.width == 2 && g.height == 4)
	testing.expect(t, g.bits[40][40])
	testing.expect(t, g.bits[0][1]) // the old top-left pixel is now top-right
	for y in 0 ..< 4 {
		for x in 0 ..< 2 {
			if !(x == 1 && y == 0) {
				testing.expectf(t, !g.bits[y][x], "(%d,%d) must be clear: hidden pixels were overwritten", x, y)
			}
		}
	}
}

@(test)
test_image4_rotations :: proc(t: ^testing.T) {
	for size in ([][2]int{{1, 1}, {2, 3}, {3, 2}, {7, 3}, {64, 5}, {64, 64}}) {
		w, h := size[0], size[1]
		img := sample_image(w, h)
		orig := img
		image4_rotate_right(&img)
		testing.expectf(t, img.width == h && img.height == w, "%dx%d size", w, h)
		for y in 0 ..< h {
			for x in 0 ..< w {
				testing.expectf(t, img.pixels[x][h - 1 - y] == orig.pixels[y][x], "%dx%d right (%d,%d)", w, h, x, y)
			}
		}
		img = orig
		image4_rotate_left(&img)
		for y in 0 ..< h {
			for x in 0 ..< w {
				testing.expectf(t, img.pixels[w - 1 - x][y] == orig.pixels[y][x], "%dx%d left (%d,%d)", w, h, x, y)
			}
		}
		img = orig
		image4_rotate_180(&img)
		for y in 0 ..< h {
			for x in 0 ..< w {
				testing.expectf(t, img.pixels[h - 1 - y][w - 1 - x] == orig.pixels[y][x], "%dx%d 180 (%d,%d)", w, h, x, y)
			}
		}
		img = orig
		for _ in 0 ..< 4 {
			image4_rotate_right(&img)
		}
		testing.expect(t, image4_visible_equal(&img, &orig))
		image4_rotate_left(&img)
		image4_rotate_right(&img)
		testing.expect(t, image4_visible_equal(&img, &orig))
	}
	blank := image4_make(2, 6)
	testing.expect(t, image4_rotate_left(&blank) && blank.width == 6 && blank.height == 2) // the size changed
	blank_sq := image4_make(4, 4)
	testing.expect(t, !image4_rotate_right(&blank_sq) && !image4_rotate_180(&blank_sq))
	sq := image4_make(3, 3)
	image4_set(&sq, 0, 0, 4)
	image4_set(&sq, 2, 2, 4) // point symmetric
	testing.expect(t, !image4_rotate_180(&sq) && image4_rotate_right(&sq))
}

@(test)
test_shape_has_cell :: proc(t: ^testing.T) {
	// A 4 x 3 rectangle with corners given in a "wrong" order.
	for y in 0 ..< 5 {
		for x in 0 ..< 6 {
			inside := x >= 1 && x <= 4 && y >= 1 && y <= 3
			border := inside && (x == 1 || x == 4 || y == 1 || y == 3)
			testing.expectf(t, shape_has_cell(.Fill, 4, 3, 1, 1, x, y) == inside, "fill (%d,%d)", x, y)
			testing.expectf(t, shape_has_cell(.Frame, 4, 1, 1, 3, x, y) == border, "frame (%d,%d)", x, y)
			testing.expect(t, !shape_has_cell(.None, 1, 1, 4, 3, x, y))
		}
	}
	// One pixel wide or high: frame and fill agree.
	for y in 0 ..< 4 {
		for x in 0 ..< 4 {
			testing.expect(t, shape_has_cell(.Frame, 2, 0, 2, 3, x, y) == shape_has_cell(.Fill, 2, 0, 2, 3, x, y))
			testing.expect(t, shape_has_cell(.Frame, 0, 1, 3, 1, x, y) == shape_has_cell(.Fill, 0, 1, 3, 1, x, y))
		}
	}
	testing.expect(t, shape_has_cell(.Frame, 2, 2, 2, 2, 2, 2)) // a single cell
}

@(test)
test_bitmap_draw_shapes :: proc(t: ^testing.T) {
	g := bitmap_make(8, 6)
	testing.expect(t, bitmap_draw_shape(&g, .Frame, 1, 1, 5, 4, true))
	count := 0
	for y in 0 ..< 6 {
		for x in 0 ..< 8 {
			want := shape_has_cell(.Frame, 1, 1, 5, 4, x, y)
			testing.expectf(t, g.bits[y][x] == want, "frame (%d,%d)", x, y)
			if g.bits[y][x] {
				count += 1
			}
		}
	}
	testing.expect_value(t, count, 5 * 2 + 2 * 2) // 5 wide x 4 high outline: 14 pixels
	testing.expect(t, !bitmap_draw_shape(&g, .Frame, 1, 1, 5, 4, true)) // same again: no change
	testing.expect(t, bitmap_draw_shape(&g, .Fill, 1, 1, 5, 4, true)) // fills the inside
	testing.expect(t, g.bits[2][3] && g.bits[3][2])
	// Off erases: the fill with `on = false` clears the whole rectangle but nothing else.
	bitmap_set(&g, 7, 5, true)
	testing.expect(t, bitmap_draw_shape(&g, .Fill, 5, 4, 1, 1, false)) // reversed corners
	for y in 1 ..= 4 {
		for x in 1 ..= 5 {
			testing.expect(t, !g.bits[y][x])
		}
	}
	testing.expect(t, g.bits[5][7])
	// Corners outside the image are clamped to it.
	g = bitmap_make(4, 4)
	testing.expect(t, bitmap_draw_shape(&g, .Fill, -5, -5, 100, 100, true))
	for y in 0 ..< 4 {
		for x in 0 ..< 4 {
			testing.expect(t, g.bits[y][x])
		}
	}
	testing.expect(t, g.bits[4][0] == false) // nothing outside the visible area
	g = bitmap_make(4, 4)
	bitmap_draw_shape(&g, .None, 0, 0, 3, 3, true)
	testing.expect(t, !g.bits[0][0]) // no shape draws nothing
}

@(test)
test_image4_draw_shapes :: proc(t: ^testing.T) {
	img := image4_make(8, 6)
	testing.expect(t, image4_draw_shape(&img, .Frame, 1, 1, 5, 4, 9))
	for y in 0 ..< 6 {
		for x in 0 ..< 8 {
			want: u8 = shape_has_cell(.Frame, 1, 1, 5, 4, x, y) ? 9 : 0
			testing.expectf(t, img.pixels[y][x] == want, "frame (%d,%d)", x, y)
		}
	}
	testing.expect(t, !image4_draw_shape(&img, .Frame, 1, 1, 5, 4, 9)) // no change
	testing.expect(t, image4_draw_shape(&img, .Fill, 1, 1, 5, 4, 3)) // recolours the frame too
	testing.expect(t, img.pixels[1][1] == 3 && img.pixels[2][3] == 3 && img.pixels[0][0] == 0)
	testing.expect(t, image4_draw_shape(&img, .Frame, 0, 0, 7, 5, 200)) // colour clamps to 15
	testing.expect(t, img.pixels[0][0] == 15 && img.pixels[5][7] == 15 && img.pixels[1][1] == 3)
	testing.expect(t, image4_draw_shape(&img, .Fill, 6, 4, 6, 4, 2)) // a single pixel
	testing.expect(t, img.pixels[4][6] == 2)
	testing.expect(t, image4_draw_shape(&img, .Fill, 99, 99, 99, 99, 1) && img.pixels[5][7] == 1) // clamped to the corner
}
