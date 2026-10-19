package common

// Logical drawing surface shared by every frontend. Frontends scale it to the window or canvas.
SCREEN_W :: 320
SCREEN_H :: 180

// The only thing a frontend has to implement to draw a tool. Coordinates are logical pixels.
Renderer :: struct {
	data:      rawptr,
	clear:     proc(data: rawptr, c: Color),
	fill_rect: proc(data: rawptr, x, y, w, h: int, c: Color),
	present:   proc(data: rawptr),
}

renderer_clear :: proc(r: ^Renderer, c: Color) {
	r.clear(r.data, c)
}

renderer_fill_rect :: proc(r: ^Renderer, x, y, w, h: int, c: Color) {
	if w <= 0 || h <= 0 {
		return
	}
	r.fill_rect(r.data, x, y, w, h, c)
}

renderer_present :: proc(r: ^Renderer) {
	r.present(r.data)
}
