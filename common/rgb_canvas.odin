package common

// A Renderer that draws into an in-memory picture of any size (3 bytes per pixel), for tools that
// want a picture rather than a window: the MCP server's renders, tests. Drawing is clipped to the
// picture, never an error.

Rgb_Canvas :: struct {
	width, height: int,
	pixels:        []u8, // width * height * 3, rows top to bottom
}

rgb_canvas_make :: proc(width, height: int, background: Color, allocator := context.temp_allocator) -> Rgb_Canvas {
	c := Rgb_Canvas {
		width  = max(width, 1),
		height = max(height, 1),
	}
	c.pixels = make([]u8, c.width * c.height * 3, allocator)
	rgb_canvas_fill(&c, 0, 0, c.width, c.height, background)
	return c
}

rgb_canvas_fill :: proc(c: ^Rgb_Canvas, x, y, w, h: int, color: Color) {
	x0, y0 := max(x, 0), max(y, 0)
	x1, y1 := min(x + w, c.width), min(y + h, c.height)
	for py in y0 ..< y1 {
		for px in x0 ..< x1 {
			i := (py * c.width + px) * 3
			c.pixels[i], c.pixels[i + 1], c.pixels[i + 2] = color.r, color.g, color.b
		}
	}
}

// The Renderer view of a canvas (the canvas must outlive it).
rgb_canvas_renderer :: proc(c: ^Rgb_Canvas) -> Renderer {
	return Renderer {
		data = c,
		clear = proc(data: rawptr, color: Color) {
			c := (^Rgb_Canvas)(data)
			rgb_canvas_fill(c, 0, 0, c.width, c.height, color)
		},
		fill_rect = proc(data: rawptr, x, y, w, h: int, color: Color) {
			rgb_canvas_fill((^Rgb_Canvas)(data), x, y, w, h, color)
		},
		present = proc(data: rawptr) {},
	}
}
