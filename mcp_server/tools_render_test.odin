#+build !js
package mcp_server

import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:image"
import "core:image/png"
import "core:testing"

// Calls a render tool; returns its text and the decoded picture.
call_picture :: proc(t: ^testing.T, s: ^Server, name, args: string) -> (text: string, img: ^image.Image) {
	reply := rpc(t, s, fmt.tprintf(`{{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{{"name":%s,"arguments":%s}}}}`, quote(name), args))
	result, _ := reply["result"].(json.Object)
	content, _ := result["content"].(json.Array)
	if !testing.expectf(t, len(content) == 2, "%s gave %d content items", name, len(content)) {
		return
	}
	first, _ := content[0].(json.Object)
	text, _ = first["text"].(json.String)
	second, _ := content[1].(json.Object)
	testing.expect_value(t, second["type"].(json.String), "image")
	testing.expect_value(t, second["mimeType"].(json.String), "image/png")
	data, _ := second["data"].(json.String)
	bytes, err := base64.decode(string(data), allocator = context.temp_allocator)
	testing.expect(t, err == nil)
	img, _ = png.load_from_bytes(bytes, {.alpha_drop_if_present}, context.temp_allocator)
	testing.expect(t, img != nil)
	return
}

pixel :: proc(img: ^image.Image, x, y: int) -> [3]u8 {
	p := img.pixels.buf[:]
	return {p[(y * img.width + x) * 3], p[(y * img.width + x) * 3 + 1], p[(y * img.width + x) * 3 + 2]}
}

@(test)
test_renders_are_pngs_of_what_the_editors_draw :: proc(t: ^testing.T) {
	s := new_server("")
	defer free_server(s)
	good(t, s, "world_new", "{}")
	good(t, s, "tile_size_set", `{"width":2,"height":2}`)
	good(t, s, "palette_set", `{"colors":["#000000","#FF0000","#00FF00","#0000FF"]}`)
	good(t, s, "tileset_new", `{"name":"ground"}`)
	good(t, s, "image_new", `{"tileset":"ground","name":"floor"}`)
	good(t, s, "image_new", `{"tileset":"ground","name":"wall"}`)
	good(t, s, "image_new", `{"tileset":"ground","name":"hero"}`)
	good(t, s, "image_set", `{"tileset":"ground","name":"floor","rows":["11","11"]}`)
	good(t, s, "image_set", `{"tileset":"ground","name":"wall","rows":["22","22"]}`)
	good(t, s, "image_set", `{"tileset":"ground","name":"hero","rows":["30","33"]}`) // 0 = transparent
	good(t, s, "terrain_set_new", `{"name":"t"}`)
	good(t, s, "terrain_edit", `{"set":"t","name":"terrain","new_name":"floor","tileset":"ground","image":"floor"}`)
	good(t, s, "terrain_new", `{"set":"t","name":"wall","tileset":"ground","image":"wall","tags":["solid"]}`)
	good(t, s, "sprite_set_new", `{"name":"people"}`)
	good(t, s, "sprite_new", `{"set":"people","name":"hero","tileset":"ground","image":"hero","transparent":0}`)
	good(t, s, "char_type_new", `{"name":"hero","sprite_set":"people","sprite":"hero"}`)
	id := id_of(t, good(t, s, "character_new", `{"name":"h","type":"hero"}`))
	good(t, s, "map_new", `{"name":"m","set":"t","width":3,"height":2}`)
	good(t, s, "map_set_rows", `{"name":"m","rows":["001","010"]}`)
	good(t, s, "character_place", fmt.tprintf(`{{"id":"%s","map":"m","x":0,"y":0}}`, id))

	text, img := call_picture(t, s, "render_map", `{"name":"m","zoom":2}`)
	if img != nil {
		testing.expectf(t, img.width == 12 && img.height == 8, "%s", text)
		testing.expect_value(t, pixel(img, 5, 1), [3]u8{255, 0, 0}) // floor (cell 1,0 is floor)
		testing.expect_value(t, pixel(img, 9, 1), [3]u8{0, 255, 0}) // wall at cell (2,0)
		testing.expect_value(t, pixel(img, 0, 0), [3]u8{0, 0, 255}) // the hero's blue pixel over floor
		testing.expect_value(t, pixel(img, 2, 0), [3]u8{255, 0, 0}) // ... its transparent pixel shows floor
	}
	_, img = call_picture(t, s, "render_map", `{"name":"m","zoom":2,"characters":false}`)
	if img != nil {
		testing.expect_value(t, pixel(img, 0, 0), [3]u8{255, 0, 0})
	}
	_, img = call_picture(t, s, "render_map", `{"name":"m","zoom":1,"grid":true}`)
	if img != nil {
		testing.expect_value(t, pixel(img, 0, 0), [3]u8{255, 0, 255}) // grid line
		testing.expect_value(t, pixel(img, 1, 1), [3]u8{0, 0, 255})
	}
	// A window and the automatic zoom: the 2x1 window of 4x2 pixels is scaled up towards 512.
	text, img = call_picture(t, s, "render_map", `{"name":"m","x":1,"y":1,"width":5,"height":5}`)
	if img != nil {
		testing.expectf(t, img.width == 4 * 128 && img.height == 2 * 128, "auto zoom: %s", text)
	}
	refused(t, s, "render_map", `{"name":"m","zoom":1000}`)
	refused(t, s, "render_map", `{"name":"m","x":9}`)
	refused(t, s, "render_map", `{"name":"nope"}`)

	_, img = call_picture(t, s, "render_tile", `{"tileset":"ground","name":"hero","zoom":4}`)
	if img != nil {
		testing.expect(t, img.width == 8 && img.height == 8)
		testing.expect_value(t, pixel(img, 0, 0), [3]u8{0, 0, 255})
		testing.expect_value(t, pixel(img, 7, 0), [3]u8{0, 0, 0}) // the tile itself shows index 0
	}
	_, img = call_picture(t, s, "render_sprite", `{"set":"people","name":"hero","zoom":4}`)
	if img != nil {
		testing.expect_value(t, pixel(img, 0, 0), [3]u8{0, 0, 255})
		testing.expect(t, pixel(img, 7, 0) != [3]u8{0, 0, 0}) // transparent: the checkerboard shows
	}
	_, img = call_picture(t, s, "render_palette", "{}")
	if img != nil {
		testing.expect_value(t, pixel(img, 2 + 5, 2 + 5), [3]u8{0, 0, 0})
		testing.expect_value(t, pixel(img, 2 + 34 + 5, 2 + 5), [3]u8{255, 0, 0})
	}
}
