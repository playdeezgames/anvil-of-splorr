package common

// Rectangles for the pixel editors. A rectangle is given by two opposite corners (any order); it
// is either a Frame (the one pixel wide outline) or a Fill (every pixel inside). A rectangle that
// is one pixel wide or high is the same either way.

Shape :: enum {
	None,
	Frame,
	Fill,
}

// True if pixel (x, y) belongs to the shape spanned by corners (x0, y0) and (x1, y1).
shape_has_cell :: proc(shape: Shape, x0, y0, x1, y1, x, y: int) -> bool {
	lx, rx := min(x0, x1), max(x0, x1)
	ty, by := min(y0, y1), max(y0, y1)
	if shape == .None || x < lx || x > rx || y < ty || y > by {
		return false
	}
	return shape == .Fill || x == lx || x == rx || y == ty || y == by
}

// Bitmap: sets the shape's pixels to `on`. Corners outside the visible area are clamped to it.
// Returns true if any pixel changed.
bitmap_draw_shape :: proc(g: ^Bitmap, shape: Shape, x0, y0, x1, y1: int, on: bool) -> (changed: bool) {
	cx0, cx1 := clamp(x0, 0, g.width - 1), clamp(x1, 0, g.width - 1)
	cy0, cy1 := clamp(y0, 0, g.height - 1), clamp(y1, 0, g.height - 1)
	for y in min(cy0, cy1) ..= max(cy0, cy1) {
		for x in min(cx0, cx1) ..= max(cx0, cx1) {
			if shape_has_cell(shape, cx0, cy0, cx1, cy1, x, y) && g.bits[y][x] != on {
				g.bits[y][x] = on
				changed = true
			}
		}
	}
	return
}

// Image4: sets the shape's pixels to `color` (clamped to 0..15). Corners outside the visible area
// are clamped to it. Returns true if any pixel changed.
image4_draw_shape :: proc(img: ^Image4, shape: Shape, x0, y0, x1, y1: int, color: int) -> (changed: bool) {
	c := u8(clamp(color, 0, IMAGE_COLORS - 1))
	cx0, cx1 := clamp(x0, 0, img.width - 1), clamp(x1, 0, img.width - 1)
	cy0, cy1 := clamp(y0, 0, img.height - 1), clamp(y1, 0, img.height - 1)
	for y in min(cy0, cy1) ..= max(cy0, cy1) {
		for x in min(cx0, cx1) ..= max(cx0, cx1) {
			if shape_has_cell(shape, cx0, cy0, cx1, cy1, x, y) && img.pixels[y][x] != c {
				img.pixels[y][x] = c
				changed = true
			}
		}
	}
	return
}
