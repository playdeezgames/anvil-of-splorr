package common

// Shared by the editors that paint a Bitmap (glyph editor, font editor): geometry for scaling a
// bitmap into an area, and the drawing of the canvas itself.

Rect :: struct {
	x, y, w, h: int,
}

rect_contains :: proc(r: Rect, x, y: int) -> bool {
	return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h
}

// The overlap of two rects, if they share any pixels (touching edges do not count).
rect_intersect :: proc(a, b: Rect) -> (r: Rect, ok: bool) {
	x0, y0 := max(a.x, b.x), max(a.y, b.y)
	x1, y1 := min(a.x + a.w, b.x + b.w), min(a.y + a.h, b.y + b.h)
	if x1 <= x0 || y1 <= y0 {
		return {}, false
	}
	return Rect{x0, y0, x1 - x0, y1 - y0}, true
}

// Pixels per bitmap pixel so a width x height bitmap fits in area (at least 1).
canvas_cell_size :: proc(area: Rect, width, height: int) -> int {
	return max(1, min(area.w / width, area.h / height))
}

// The bitmap pixel under a logical position, if any. The bitmap is top-left aligned in area.
canvas_cell_at :: proc(area: Rect, width, height, px, py: int) -> (x, y: int, ok: bool) {
	c := canvas_cell_size(area, width, height)
	cx, cy := px - area.x, py - area.y
	if cx < 0 || cy < 0 {
		return 0, 0, false
	}
	x, y = cx / c, cy / c
	return x, y, x < width && y < height
}

canvas_cell_rect :: proc(area: Rect, width, height, x, y: int) -> Rect {
	c := canvas_cell_size(area, width, height)
	return Rect{area.x + x * c, area.y + y * c, c, c}
}

Canvas_Colors :: struct {
	on, off, grid, cursor: Color,
}

// Draws the bitmap with a cursor outline at (cx, cy) (nothing if cx is negative). With cells of 3+
// pixels each gets a 1 px gap so the grid shows; smaller cells are merged into horizontal runs.
canvas_draw :: proc(r: ^Renderer, area: Rect, b: ^Bitmap, cx, cy: int, colors: Canvas_Colors) {
	fill :: proc(r: ^Renderer, rc: Rect, c: Color) {
		renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
	}
	c := canvas_cell_size(area, b.width, b.height)
	fill(r, Rect{area.x, area.y, b.width * c, b.height * c}, colors.off)
	gap := c >= 3 ? 1 : 0
	for y in 0 ..< b.height {
		x := 0
		for x < b.width {
			if !b.bits[y][x] {
				x += 1
				continue
			}
			if gap == 1 {
				cr := canvas_cell_rect(area, b.width, b.height, x, y)
				fill(r, Rect{cr.x, cr.y, c - 1, c - 1}, colors.on)
				x += 1
			} else {
				start := x
				for x < b.width && b.bits[y][x] {
					x += 1
				}
				cr := canvas_cell_rect(area, b.width, b.height, start, y)
				fill(r, Rect{cr.x, cr.y, (x - start) * c, c}, colors.on)
			}
		}
	}
	if gap == 1 { 	// grid lines in the gaps
		for x in 1 ..< b.width {
			fill(r, Rect{area.x + x * c - 1, area.y, 1, b.height * c}, colors.grid)
		}
		for y in 1 ..< b.height {
			fill(r, Rect{area.x, area.y + y * c - 1, b.width * c, 1}, colors.grid)
		}
	}
	if cx >= 0 { 	// a 1 px outline just outside the cell, so it shows on any pixel colour
		cr := canvas_cell_rect(area, b.width, b.height, cx, cy)
		fill(r, Rect{cr.x - 1, cr.y - 1, cr.w + 2, 1}, colors.cursor)
		fill(r, Rect{cr.x - 1, cr.y + cr.h, cr.w + 2, 1}, colors.cursor)
		fill(r, Rect{cr.x - 1, cr.y, 1, cr.h}, colors.cursor)
		fill(r, Rect{cr.x + cr.w, cr.y, 1, cr.h}, colors.cursor)
	}
}

// Draws an indexed-colour image scaled into area, each pixel in its palette colour, with a cursor
// outline at (cx, cy) (nothing if cx is negative). With cells of 3+ pixels each gets a 1 px gap in
// the `grid` colour so the pixels can be told apart; smaller cells merge runs of one colour.
canvas_draw_image :: proc(r: ^Renderer, area: Rect, img: ^Image4, palette: ^Palette, cx, cy: int, grid, cursor: Color) {
	fill :: proc(r: ^Renderer, rc: Rect, c: Color) {
		renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
	}
	c := canvas_cell_size(area, img.width, img.height)
	fill(r, Rect{area.x, area.y, img.width * c, img.height * c}, grid)
	gap := c >= 3 ? 1 : 0
	for y in 0 ..< img.height {
		x := 0
		for x < img.width {
			color := img.pixels[y][x]
			start := x
			if gap == 1 {
				x += 1
			} else {
				for x < img.width && img.pixels[y][x] == color {
					x += 1
				}
			}
			cr := canvas_cell_rect(area, img.width, img.height, start, y)
			fill(r, Rect{cr.x, cr.y, (x - start) * c - gap, c - gap}, palette[color & 0x0F])
		}
	}
	if cx >= 0 {
		cr := canvas_cell_rect(area, img.width, img.height, cx, cy)
		fill(r, Rect{cr.x - 1, cr.y - 1, cr.w + 2, 1}, cursor)
		fill(r, Rect{cr.x - 1, cr.y + cr.h, cr.w + 2, 1}, cursor)
		fill(r, Rect{cr.x - 1, cr.y, 1, cr.h}, cursor)
		fill(r, Rect{cr.x + cr.w, cr.y, 1, cr.h}, cursor)
	}
}

// Draws img as a small picture centred in area and returns the rect it covered. An image that fits
// is drawn at the largest whole-number scale (so a 4 x 4 tile in a 16 x 16 area is 4x); a bigger
// one is sampled down (nearest pixel) to fit, keeping its proportions. Runs of one colour are
// merged, so a flat image costs a few rects. Pixels of the `transparent` palette index (0..15; -1
// for none) are not drawn, so whatever is already in the area shows through.
canvas_draw_thumbnail :: proc(r: ^Renderer, area: Rect, img: ^Image4, palette: ^Palette, transparent := -1) -> Rect {
	w, h := img.width, img.height
	if w <= 0 || h <= 0 || area.w <= 0 || area.h <= 0 {
		return {}
	}
	if w <= area.w && h <= area.h {
		s := min(area.w / w, area.h / h)
		out := Rect{area.x + (area.w - w * s) / 2, area.y + (area.h - h * s) / 2, w * s, h * s}
		for y in 0 ..< h {
			x := 0
			for x < w {
				color := img.pixels[y][x]
				start := x
				for x < w && img.pixels[y][x] == color {
					x += 1
				}
				if int(color) != transparent {
					renderer_fill_rect(r, out.x + start * s, out.y + y * s, (x - start) * s, s, palette[color & 0x0F])
				}
			}
		}
		return out
	}
	tw, th: int
	if w * area.h >= h * area.w {
		tw, th = area.w, max(1, h * area.w / w)
	} else {
		tw, th = max(1, w * area.h / h), area.h
	}
	out := Rect{area.x + (area.w - tw) / 2, area.y + (area.h - th) / 2, tw, th}
	for dy in 0 ..< th {
		sy := dy * h / th
		dx := 0
		for dx < tw {
			color := img.pixels[sy][dx * w / tw]
			start := dx
			for dx < tw && img.pixels[sy][dx * w / tw] == color {
				dx += 1
			}
			if int(color) != transparent {
				renderer_fill_rect(r, out.x + start, out.y + dy, dx - start, 1, palette[color & 0x0F])
			}
		}
	}
	return out
}

// Fills `area` with a two-tone checkerboard of `size` pixel squares: the usual backdrop for
// pictures with transparent parts. Runs are one rect per square (a few dozen for a thumbnail).
canvas_draw_checker :: proc(r: ^Renderer, area: Rect, a, b: Color, size := 4) {
	if area.w <= 0 || area.h <= 0 || size <= 0 {
		return
	}
	renderer_fill_rect(r, area.x, area.y, area.w, area.h, a)
	for y := 0; y * size < area.h; y += 1 {
		for x := (y + 1) % 2; x * size < area.w; x += 2 {
			renderer_fill_rect(r, area.x + x * size, area.y + y * size, min(size, area.w - x * size), min(size, area.h - y * size), b)
		}
	}
}
