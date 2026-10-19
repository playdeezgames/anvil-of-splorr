#+build js
package main

import cm "../../common"
import pe "../../palette_editor"
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
	download :: proc(data: [^]u8, len: i32) ---
}

MAX_PADS :: 4

ctx: runtime.Context
editor: pe.Editor
pad_down: [MAX_PADS]bit_set[cm.Pad_Button]

renderer := cm.Renderer {
	clear     = proc(_: rawptr, c: cm.Color) {canvas_clear(i32(c.r), i32(c.g), i32(c.b))},
	fill_rect = proc(_: rawptr, x, y, w, h: int, c: cm.Color) {
		canvas_fill_rect(i32(x), i32(y), i32(w), i32(h), i32(c.r), i32(c.g), i32(c.b))
	},
	present   = proc(_: rawptr) {},
}

main :: proc() {
	ctx = context
	editor = pe.editor_init()
	editor.can_quit = false

	restore_from_storage()

	js.add_window_event_listener(.Key_Down, nil, on_key_down)
	js.add_window_event_listener(.Key_Up, nil, on_key_up)
	// Move and release go to the window so a slider drag survives leaving the canvas.
	js.add_window_event_listener(.Mouse_Move, nil, on_mouse_move)
	js.add_window_event_listener(.Mouse_Up, nil, on_mouse_up)
	js.add_event_listener("canvas", .Mouse_Down, nil, on_mouse_down)
	js.add_event_listener("canvas", .Wheel, nil, on_wheel)
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	poll_gamepads()
	service_requests()
	pe.editor_draw(&editor, &renderer)
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

// Returns 1 if the file was a valid palette.
@(export)
file_loaded :: proc "c" (n: i32) -> i32 {
	context = ctx
	if n < 0 || int(n) > len(file_buf) {
		return 0
	}
	p, ok := cm.palette_from_json(file_buf[:n])
	free_all(context.temp_allocator)
	if !ok {
		return 0
	}
	pe.editor_set_palette(&editor, p)
	return 1
}

restore_from_storage :: proc() {
	buf: [FILE_CAP]u8
	n := storage_get(&buf[0], len(buf))
	if n < 0 || int(n) > len(buf) {
		return
	}
	if p, ok := cm.palette_from_json(buf[:n]); ok {
		pe.editor_set_palette(&editor, p)
	}
}

service_requests :: proc() {
	if .Save in editor.requests {
		text := cm.palette_to_json(editor.palette)
		storage_set(raw_data(text), i32(len(text)))
		download(raw_data(text), i32(len(text)))
		pe.editor_mark_saved(&editor)
	}
	if .Load in editor.requests {
		// Load restores the last save from browser storage; opening a file is the page's button.
		restore_from_storage()
	}
	editor.requests = {}
}

poll_gamepads :: proc() {
	for i in 0 ..< MAX_PADS {
		s: js.Gamepad_State
		if !js.get_gamepad_state(i, &s) || !s.connected || s.mapping != "standard" {
			pad_down[i] = {}
			continue
		}
		now: bit_set[cm.Pad_Button]
		for bi in 0 ..< min(s.button_count, 17) {
			if b, ok := pad_button_for_index(bi); ok && s.buttons[bi].pressed {
				now += {b}
			}
		}
		for b in now - pad_down[i] {
			pe.editor_handle_event(&editor, cm.Pad_Event{b, true})
		}
		for b in pad_down[i] - now {
			pe.editor_handle_event(&editor, cm.Pad_Event{b, false})
		}
		pad_down[i] = now
	}
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
	pe.editor_handle_event(&editor, cm.Key_Event{key = k, shift = e.key.shift, down = down})
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
	pe.editor_handle_event(&editor, cm.Mouse_Move{x, y})
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
		pe.editor_handle_event(&editor, cm.Mouse_Button_Event{b, x, y, true})
	}
}

on_mouse_up :: proc(e: js.Event) {
	context = ctx
	if b, ok := mouse_button(e.mouse.button); ok {
		x, y := to_logical(e)
		pe.editor_handle_event(&editor, cm.Mouse_Button_Event{b, x, y, false})
	}
}

on_wheel :: proc(e: js.Event) {
	context = ctx
	js.event_prevent_default()
	// DOM deltaY > 0 is scroll down; the editor wants up = positive.
	dy := e.wheel.delta[1]
	if dy != 0 {
		pe.editor_handle_event(&editor, cm.Mouse_Wheel{dy < 0 ? 1 : -1})
	}
}
