package main

import cm "../../common"
import pe "../../palette_editor"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl2"

SCALE :: 4
DEFAULT_FILE :: "palette.json"

Gamepad :: struct {
	handle: ^sdl.GameController,
	id:     sdl.JoystickID,
}

gamepads: [dynamic]Gamepad

main :: proc() {
	if sdl.Init({.VIDEO, .GAMECONTROLLER}) != 0 {
		fmt.eprintln("SDL_Init failed:", sdl.GetError())
		os.exit(1)
	}
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Palette Editor",
		sdl.WINDOWPOS_CENTERED,
		sdl.WINDOWPOS_CENTERED,
		cm.SCREEN_W * SCALE,
		cm.SCREEN_H * SCALE,
		{.RESIZABLE},
	)
	if window == nil {
		fmt.eprintln("SDL_CreateWindow failed:", sdl.GetError())
		os.exit(1)
	}
	defer sdl.DestroyWindow(window)

	renderer := sdl.CreateRenderer(window, -1, {.ACCELERATED, .PRESENTVSYNC})
	if renderer == nil {
		renderer = sdl.CreateRenderer(window, -1, {.SOFTWARE})
	}
	if renderer == nil {
		fmt.eprintln("SDL_CreateRenderer failed:", sdl.GetError())
		os.exit(1)
	}
	defer sdl.DestroyRenderer(renderer)
	// The editor draws at a fixed logical size; SDL scales it and reports mouse positions in it.
	sdl.RenderSetLogicalSize(renderer, cm.SCREEN_W, cm.SCREEN_H)
	sdl.RenderSetIntegerScale(renderer, true)

	for i in 0 ..< sdl.NumJoysticks() {
		open_gamepad(i)
	}
	defer for g in gamepads {
		sdl.GameControllerClose(g.handle)
	}

	path := len(os.args) > 1 ? os.args[1] : DEFAULT_FILE
	editor := pe.editor_init()
	load(&editor, path, quiet_if_missing = true)

	r := cm.Renderer {
		data      = renderer,
		clear     = proc(data: rawptr, c: cm.Color) {
			rd := (^sdl.Renderer)(data)
			sdl.SetRenderDrawColor(rd, c.r, c.g, c.b, 255)
			sdl.RenderClear(rd)
		},
		fill_rect = proc(data: rawptr, x, y, w, h: int, c: cm.Color) {
			rd := (^sdl.Renderer)(data)
			sdl.SetRenderDrawColor(rd, c.r, c.g, c.b, 255)
			rect := sdl.Rect{i32(x), i32(y), i32(w), i32(h)}
			sdl.RenderFillRect(rd, &rect)
		},
		present   = proc(data: rawptr) {
			sdl.RenderPresent((^sdl.Renderer)(data))
		},
	}

	shown_dirty := !editor.dirty // forces the first title update
	for !editor.quit {
		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			handle_sdl_event(&editor, &ev)
		}
		service_requests(&editor, path)

		pe.editor_draw(&editor, &r)

		if editor.dirty != shown_dirty {
			shown_dirty = editor.dirty
			title := fmt.ctprintf("Palette Editor - %s%s", path, shown_dirty ? " *" : "")
			sdl.SetWindowTitle(window, title)
		}
		sdl.Delay(8) // vsync is not guaranteed (software renderer)
		free_all(context.temp_allocator)
	}
}

handle_sdl_event :: proc(editor: ^pe.Editor, ev: ^sdl.Event) {
	#partial switch ev.type {
	case .QUIT:
		editor.quit = true
	case .KEYDOWN, .KEYUP:
		pe.editor_handle_event(
			editor,
			cm.Key_Event {
				key = translate_key(ev.key.keysym.scancode),
				shift = .LSHIFT in ev.key.keysym.mod || .RSHIFT in ev.key.keysym.mod,
				down = ev.type == .KEYDOWN,
			},
		)
	case .MOUSEMOTION:
		pe.editor_handle_event(editor, cm.Mouse_Move{int(ev.motion.x), int(ev.motion.y)})
	case .MOUSEBUTTONDOWN, .MOUSEBUTTONUP:
		btn: cm.Mouse_Button
		switch ev.button.button {
		case sdl.BUTTON_LEFT:
			btn = .Left
		case sdl.BUTTON_RIGHT:
			btn = .Right
		case sdl.BUTTON_MIDDLE:
			btn = .Middle
		case:
			return
		}
		pe.editor_handle_event(
			editor,
			cm.Mouse_Button_Event {
				button = btn,
				x = int(ev.button.x),
				y = int(ev.button.y),
				down = ev.type == .MOUSEBUTTONDOWN,
			},
		)
	case .MOUSEWHEEL:
		dy := int(ev.wheel.y)
		if ev.wheel.direction == u32(sdl.MouseWheelDirection.FLIPPED) {
			dy = -dy
		}
		pe.editor_handle_event(editor, cm.Mouse_Wheel{dy})
	case .CONTROLLERBUTTONDOWN, .CONTROLLERBUTTONUP:
		if b, ok := translate_pad_button(sdl.GameControllerButton(ev.cbutton.button)); ok {
			pe.editor_handle_event(editor, cm.Pad_Event{b, ev.type == .CONTROLLERBUTTONDOWN})
		}
	case .CONTROLLERDEVICEADDED:
		open_gamepad(ev.cdevice.which)
	case .CONTROLLERDEVICEREMOVED:
		close_gamepad(sdl.JoystickID(ev.cdevice.which))
	}
}

translate_key :: proc(sc: sdl.Scancode) -> cm.Key {
	#partial switch sc {
	case .LEFT:
		return .Left
	case .RIGHT:
		return .Right
	case .UP:
		return .Up
	case .DOWN:
		return .Down
	case .TAB:
		return .Tab
	case .PAGEUP:
		return .Page_Up
	case .PAGEDOWN:
		return .Page_Down
	case .EQUALS, .KP_PLUS:
		return .Plus
	case .MINUS, .KP_MINUS:
		return .Minus
	case .R:
		return .R
	case .G:
		return .G
	case .B:
		return .B
	case .S:
		return .S
	case .L:
		return .L
	case .ESCAPE:
		return .Escape
	}
	return .None
}

translate_pad_button :: proc(b: sdl.GameControllerButton) -> (cm.Pad_Button, bool) {
	#partial switch b {
	case .DPAD_UP:
		return .Dpad_Up, true
	case .DPAD_DOWN:
		return .Dpad_Down, true
	case .DPAD_LEFT:
		return .Dpad_Left, true
	case .DPAD_RIGHT:
		return .Dpad_Right, true
	case .A:
		return .A, true
	case .B:
		return .B, true
	case .X:
		return .X, true
	case .Y:
		return .Y, true
	case .LEFTSHOULDER:
		return .Left_Shoulder, true
	case .RIGHTSHOULDER:
		return .Right_Shoulder, true
	case .START:
		return .Start, true
	case .BACK:
		return .Back, true
	case .GUIDE:
		return .Guide, true
	}
	return {}, false
}

open_gamepad :: proc(device_index: i32) {
	if !sdl.IsGameController(device_index) {
		return
	}
	handle := sdl.GameControllerOpen(device_index)
	if handle == nil {
		return
	}
	id := sdl.JoystickInstanceID(sdl.GameControllerGetJoystick(handle))
	for g in gamepads {
		if g.id == id { 	// already open
			sdl.GameControllerClose(handle)
			return
		}
	}
	append(&gamepads, Gamepad{handle, id})
}

close_gamepad :: proc(id: sdl.JoystickID) {
	for g, i in gamepads {
		if g.id == id {
			sdl.GameControllerClose(g.handle)
			unordered_remove(&gamepads, i)
			return
		}
	}
}

service_requests :: proc(editor: ^pe.Editor, path: string) {
	if .Save in editor.requests {
		text := cm.palette_to_json(editor.palette)
		if err := os.write_entire_file(path, text); err != nil {
			fmt.eprintfln("save %s failed: %v", path, err)
		} else {
			pe.editor_mark_saved(editor)
		}
	}
	if .Load in editor.requests {
		load(editor, path)
	}
	editor.requests = {}
}

load :: proc(editor: ^pe.Editor, path: string, quiet_if_missing := false) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		if !quiet_if_missing {
			fmt.eprintfln("load %s failed: %v", path, err)
		}
		return
	}
	defer delete(data)
	if p, ok := cm.palette_from_json(data); ok {
		pe.editor_set_palette(editor, p)
	} else {
		fmt.eprintfln("load %s failed: not a valid palette JSON file", path)
	}
}
