#+build js
package main

import cm "../../common"
import app "app:app"
import "base:runtime"
import "core:math"
import "core:sys/wasm/js"

// Drawing and persistence are JS imports implemented by index.html.
foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	canvas_clear :: proc(r, g, b: i32) ---
	canvas_fill_rect :: proc(x, y, w, h: i32, r, g, b: i32) ---
}

foreign import host "host"
@(default_calling_convention = "contextless")
foreign host {
	// Returns the stored length, or -1 if nothing is stored. Stored text is the palette JSON.
	storage_get :: proc(buf: [^]u8, cap: i32) -> i32 ---
	storage_set :: proc(data: [^]u8, len: i32) ---
	// Offers data to the user as a file download.
	download :: proc(data: [^]u8, len: i32, name: [^]u8, name_len: i32) ---
}

MAX_PADS :: 4

ctx: runtime.Context
tool: cm.Tool
pads, prev_pads: cm.Pads

renderer := cm.Renderer {
	clear     = proc(_: rawptr, c: cm.Color) {canvas_clear(i32(c.r), i32(c.g), i32(c.b))},
	fill_rect = proc(_: rawptr, x, y, w, h: int, c: cm.Color) {
		canvas_fill_rect(i32(x), i32(y), i32(w), i32(h), i32(c.r), i32(c.g), i32(c.b))
	},
	present   = proc(_: rawptr) {},
}

main :: proc() {
	ctx = context
	tool = app.make_tool()
	if tool.configure != nil {
		tool.configure(tool.data, {can_quit = false})
	}
	if cm.tool_has_files(&tool) {
		restore_from_storage()
	}

	js.add_window_event_listener(.Key_Down, nil, on_key_down)
	js.add_window_event_listener(.Key_Up, nil, on_key_up)
	// Move and release go to the window so a slider drag survives leaving the canvas.
	js.add_window_event_listener(.Mouse_Move, nil, on_mouse_move)
	js.add_window_event_listener(.Mouse_Up, nil, on_mouse_up)
	js.add_event_listener("canvas", .Mouse_Down, nil, on_mouse_down)
	js.add_event_listener("canvas", .Wheel, nil, on_wheel)
}

// The page hides its "open file" button when this is 0.
@(export)
tool_has_files :: proc "c" () -> i32 {
	context = ctx
	return cm.tool_has_files(&tool) ? 1 : 0
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	poll_gamepads()
	if cm.tool_has_files(&tool) {
		service_files()
	}
	tool.draw(tool.data, &renderer)
	free_all(context.temp_allocator)
	return true
}

// JS copies a chosen file's bytes into file_buffer (FILE_CAP bytes) and then calls file_loaded(len).
FILE_CAP :: 4096
file_buf: [FILE_CAP]u8

@(export)
file_buffer :: proc "c" () -> rawptr {
	return &file_buf
}

// Returns 1 if the tool accepted the file.
@(export)
file_loaded :: proc "c" (n: i32) -> i32 {
	context = ctx
	if n < 0 || int(n) > len(file_buf) || !cm.tool_has_files(&tool) {
		return 0
	}
	ok := tool.load(tool.data, file_buf[:n])
	free_all(context.temp_allocator)
	return ok ? 1 : 0
}

restore_from_storage :: proc() {
	buf: [FILE_CAP]u8
	n := storage_get(&buf[0], len(buf))
	if n < 0 || int(n) > len(buf) {
		return
	}
	tool.load(tool.data, buf[:n])
}

service_files :: proc() {
	if text, ok := tool.take_save(tool.data); ok {
		name := tool.default_file
		storage_set(raw_data(text), i32(len(text)))
		download(raw_data(text), i32(len(text)), raw_data(name), i32(len(name)))
		tool.saved(tool.data)
	}
	if tool.wants_load(tool.data) {
		// Load restores the last save from browser storage; opening a file is the page's button.
		restore_from_storage()
	}
}

poll_gamepads :: proc() {
	for i in 0 ..< cm.MAX_PADS {
		s: js.Gamepad_State
		p := &pads[i]
		p^ = {}
		if !js.get_gamepad_state(i, &s) || !s.connected {
			continue
		}
		p.connected = true
		p.standard = s.mapping == "standard"
		cm.pad_set_name(p, s.id)
		p.button_count = min(s.button_count, cm.MAX_PAD_BUTTONS)
		p.axis_count = min(s.axis_count, cm.MAX_PAD_AXES)
		for b in 0 ..< p.button_count {
			p.buttons[b] = {s.buttons[b].pressed, f32(s.buttons[b].value)}
		}
		for a in 0 ..< p.axis_count {
			p.axes[a] = f32(s.axes[a])
		}
	}
	cm.tool_update_pads(&tool, &prev_pads, &pads)
}

handle_key :: proc(e: js.Event, down: bool) {
	context = ctx
	if e.key.ctrl || e.key.alt || e.key.meta {
		return // leave browser shortcuts alone
	}
	k := key_for_code(e.key.code)
	if k == .None {
		return
	}
	js.event_prevent_default() // Tab, arrows and Page keys would otherwise move focus / scroll
	tool.handle_event(tool.data, cm.Key_Event{key = k, shift = e.key.shift, down = down})
}

on_key_down :: proc(e: js.Event) {handle_key(e, true)}
on_key_up :: proc(e: js.Event) {handle_key(e, false)}

// Client coordinates -> logical surface pixels.
to_logical :: proc(e: js.Event) -> (x, y: int) {
	r := js.get_bounding_client_rect("canvas")
	if r.width <= 0 || r.height <= 0 {
		return 0, 0
	}
	x = int(math.floor((f64(e.mouse.client.x) - r.x) * cm.SCREEN_W / r.width))
	y = int(math.floor((f64(e.mouse.client.y) - r.y) * cm.SCREEN_H / r.height))
	return
}

on_mouse_move :: proc(e: js.Event) {
	context = ctx
	x, y := to_logical(e)
	tool.handle_event(tool.data, cm.Mouse_Move{x, y})
}

mouse_button :: proc(b: i16) -> (cm.Mouse_Button, bool) {
	switch b {
	case 0:
		return .Left, true
	case 1:
		return .Middle, true
	case 2:
		return .Right, true
	}
	return {}, false
}

on_mouse_down :: proc(e: js.Event) {
	context = ctx
	if b, ok := mouse_button(e.mouse.button); ok {
		x, y := to_logical(e)
		tool.handle_event(tool.data, cm.Mouse_Button_Event{b, x, y, true})
	}
}

on_mouse_up :: proc(e: js.Event) {
	context = ctx
	if b, ok := mouse_button(e.mouse.button); ok {
		x, y := to_logical(e)
		tool.handle_event(tool.data, cm.Mouse_Button_Event{b, x, y, false})
	}
}

on_wheel :: proc(e: js.Event) {
	context = ctx
	js.event_prevent_default()
	// DOM deltaY > 0 is scroll down; the editor wants up = positive.
	dy := e.wheel.delta[1]
	if dy != 0 {
		tool.handle_event(tool.data, cm.Mouse_Wheel{dy < 0 ? 1 : -1})
	}
}
