package mcp_server

import cm "../common"
import "core:encoding/json"
import "core:fmt"

// The largest picture a render may produce, in pixels per side (stored uncompressed, about one byte
// per pixel), and the size a render aims for when no zoom is asked for.
MAX_RENDER_SIDE :: 1024
AUTO_RENDER_SIDE :: 512

GRID_COLOR :: cm.Color{255, 0, 255}

render_tools :: proc() -> []Tool {
	@(static) table := [?]Tool {
		{
			"render_map",
			"Draw a map (or a window of it: x, y, width, height in cells) as a PNG, with the items lying in its cells, its features and its characters. zoom is pixels per tile pixel (default: the largest that keeps the picture within 512 pixels, at most 1024). grid true draws magenta cell lines so cells can be counted; items false / features false / characters false leave them out.",
			`{"type":"object","properties":{"name":{"type":"string"},"x":{"type":"integer"},"y":{"type":"integer"},"width":{"type":"integer"},"height":{"type":"integer"},"zoom":{"type":"integer"},"grid":{"type":"boolean"},"characters":{"type":"boolean"},"features":{"type":"boolean"},"items":{"type":"boolean"}},"required":["name"]}`,
			tool_render_map,
		},
		{
			"render_tile",
			"Draw a tileset image as a PNG (zoom defaults to about 128 pixels).",
			`{"type":"object","properties":{"tileset":{"type":"string"},"name":{"type":"string"},"zoom":{"type":"integer"}},"required":["tileset","name"]}`,
			tool_render_tile,
		},
		{
			"render_sprite",
			"Draw a sprite over a checkerboard (its transparent colour shows the checkerboard) as a PNG.",
			`{"type":"object","properties":{"set":{"type":"string"},"name":{"type":"string"},"zoom":{"type":"integer"}},"required":["set","name"]}`,
			tool_render_sprite,
		},
		{"render_palette", "Draw the 16 palette colours as a PNG: two rows of eight swatches, index 0 at the top left, read row by row (8 starts the second row).", `{"type":"object","properties":{}}`, tool_render_palette},
	}
	return table[:]
}

// An answer with a picture.
picture :: proc(c: ^cm.Rgb_Canvas, text: string) -> Tool_Result {
	return {text = text, png = cm.png_encode_rgb(c.pixels, c.width, c.height)}
}

// The zoom for a picture of `w` x `h` source pixels: the one asked for (checked), else the largest
// that keeps it within `AUTO_RENDER_SIDE`.
pick_zoom :: proc(args: json.Object, w, h: int, aim: int) -> (zoom: int, res: Tool_Result, ok: bool) {
	if _, has := args["zoom"]; has {
		z, is_int := arg_int(args, "zoom")
		if !is_int || z < 1 {
			return 0, fail("zoom is a whole number, 1 or more"), false
		}
		if w * z > MAX_RENDER_SIDE || h * z > MAX_RENDER_SIDE {
			return 0, fail(fmt.tprintf("a picture of %dx%d at zoom %d would be over %d pixels a side", w, h, z, MAX_RENDER_SIDE)), false
		}
		return z, {}, true
	}
	z := max(1, min(aim / max(w, 1), aim / max(h, 1)))
	if w * z > MAX_RENDER_SIDE || h * z > MAX_RENDER_SIDE {
		return 0, fail(fmt.tprintf("%dx%d pixels is over %d a side even at zoom 1: ask for a smaller window", w, h, MAX_RENDER_SIDE)), false
	}
	return z, {}, true
}

tool_render_map :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	mi, r1, ok1 := find_map_arg(s, args)
	if !ok1 {
		return r1
	}
	m := &w.maps[mi]
	x0, y0 := 0, 0
	if v, has := arg_int(args, "x"); has {
		x0 = v
	}
	if v, has := arg_int(args, "y"); has {
		y0 = v
	}
	cols, rows := m.width - x0, m.height - y0
	if v, has := arg_int(args, "width"); has {
		cols = v
	}
	if v, has := arg_int(args, "height"); has {
		rows = v
	}
	if x0 < 0 || y0 < 0 || x0 >= m.width || y0 >= m.height || cols < 1 || rows < 1 {
		return fail("the window is outside the map")
	}
	cols, rows = min(cols, m.width - x0), min(rows, m.height - y0)
	zoom, r2, ok2 := pick_zoom(args, cols * w.tile_w, rows * w.tile_h, AUTO_RENDER_SIDE)
	if !ok2 {
		return r2
	}
	d := cm.world_zoom_draw(w, mi, x0, y0, cols, rows, 0, 0, zoom)
	pw, ph := cols * d.cell_w, rows * d.cell_h
	d.clip = cm.Rect{0, 0, pw, ph}
	canvas := cm.rgb_canvas_make(pw, ph, cm.Color{})
	r := cm.rgb_canvas_renderer(&canvas)
	cm.world_draw_terrain(&r, w, d)
	if _, has := args["items"]; !has || arg_bool(args, "items") {
		cm.world_draw_authored_inventories(&r, w, d)
	}
	if _, has := args["features"]; !has || arg_bool(args, "features") {
		cm.world_draw_authored_features(&r, w, d)
	}
	if _, has := args["characters"]; !has || arg_bool(args, "characters") {
		cm.world_draw_authored_characters(&r, w, d)
	}
	if arg_bool(args, "grid") {
		for cx in 0 ..= cols {
			cm.renderer_fill_rect(&r, min(cx * d.cell_w, pw - 1), 0, 1, ph, GRID_COLOR)
		}
		for cy in 0 ..= rows {
			cm.renderer_fill_rect(&r, 0, min(cy * d.cell_h, ph - 1), pw, 1, GRID_COLOR)
		}
	}
	text := fmt.tprintf(`{{"x":%d,"y":%d,"cols":%d,"rows":%d,"zoom":%d,"cell_pixels":[%d,%d],"picture":[%d,%d]}}`, x0, y0, cols, rows, zoom, d.cell_w, d.cell_h, pw, ph)
	return picture(&canvas, text)
}

tool_render_tile :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	t, i, res, ok := find_image(s, args)
	if !ok {
		return res
	}
	img := &s.world.tilesets[t].images[i]
	zoom, r2, ok2 := pick_zoom(args, img.width, img.height, 128)
	if !ok2 {
		return r2
	}
	canvas := cm.rgb_canvas_make(img.width * zoom, img.height * zoom, cm.Color{})
	r := cm.rgb_canvas_renderer(&canvas)
	cm.canvas_draw_thumbnail(&r, cm.Rect{0, 0, canvas.width, canvas.height}, img, &s.world.palette)
	return picture(&canvas, fmt.tprintf(`{{"zoom":%d,"picture":[%d,%d]}}`, zoom, canvas.width, canvas.height))
}

tool_render_sprite :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	w := s.world
	si, i, res, ok := find_sprite(s, args)
	if !ok {
		return res
	}
	sp := &w.sprite_sets[si].sprites[i]
	img := cm.world_sprite_image(w, sp)
	if img == nil {
		return fail("the sprite has no picture set")
	}
	zoom, r2, ok2 := pick_zoom(args, img.width, img.height, 128)
	if !ok2 {
		return r2
	}
	canvas := cm.rgb_canvas_make(img.width * zoom, img.height * zoom, cm.Color{})
	r := cm.rgb_canvas_renderer(&canvas)
	area := cm.Rect{0, 0, canvas.width, canvas.height}
	cm.canvas_draw_checker(&r, area, cm.Color{90, 90, 90}, cm.Color{150, 150, 150}, max(2, zoom * 2))
	cm.canvas_draw_thumbnail(&r, area, img, &w.palette, sp.transparent)
	return picture(&canvas, fmt.tprintf(`{{"zoom":%d,"picture":[%d,%d]}}`, zoom, canvas.width, canvas.height))
}

tool_render_palette :: proc(s: ^Server, args: json.Object) -> Tool_Result {
	if res, ok := need_world(s); !ok {
		return res
	}
	SWATCH :: 32
	GAP :: 2
	canvas := cm.rgb_canvas_make(8 * (SWATCH + GAP) + GAP, 2 * (SWATCH + GAP) + GAP, cm.Color{30, 30, 30})
	r := cm.rgb_canvas_renderer(&canvas)
	for c, i in s.world.palette {
		cm.renderer_fill_rect(&r, GAP + (i % 8) * (SWATCH + GAP), GAP + (i / 8) * (SWATCH + GAP), SWATCH, SWATCH, c)
	}
	return picture(&canvas, `{"layout":"2 rows of 8 swatches, index 0 top left, 8 at the start of the second row"}`)
}
