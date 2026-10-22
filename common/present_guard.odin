package common

// A frame must reach the screen, and a game should not have to know whether its frontend needs
// `renderer_present` (SDL2 does; the web canvas shows every draw at once). The frontends draw through a
// guard: the tool may present (the editors do) or not (a game that only draws); either way the frame is
// presented exactly once, after `draw` returns, unless the tool already did.
//
//     guard := Present_Guard{inner = real_renderer}
//     r := present_guard_renderer(&guard)
//     present_guard_begin(&guard)
//     tool.draw(tool.data, &r)
//     present_guard_end(&guard)

Present_Guard :: struct {
	inner:     Renderer, // the frontend's own renderer
	presented: int, // how many times the tool presented during this frame
}

// The renderer to hand to `Tool.draw`: it forwards everything to the real one and notes presents.
present_guard_renderer :: proc(g: ^Present_Guard) -> Renderer {
	return Renderer {
		data = g,
		clear = proc(data: rawptr, c: Color) {
			g := (^Present_Guard)(data)
			g.inner.clear(g.inner.data, c)
		},
		fill_rect = proc(data: rawptr, x, y, w, h: int, c: Color) {
			g := (^Present_Guard)(data)
			g.inner.fill_rect(g.inner.data, x, y, w, h, c)
		},
		present = proc(data: rawptr) {
			g := (^Present_Guard)(data)
			g.presented += 1
			g.inner.present(g.inner.data)
		},
	}
}

// Call before each frame's draw.
present_guard_begin :: proc(g: ^Present_Guard) {
	g.presented = 0
}

// Call after the frame's draw: presents the frame if the tool did not. Returns true if it had to.
present_guard_end :: proc(g: ^Present_Guard) -> bool {
	if g.presented > 0 {
		return false
	}
	g.inner.present(g.inner.data)
	return true
}
