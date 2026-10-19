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
