package main

import cm "../../common"
import app "app:app"
import "core:fmt"
import "core:os"
import sdl "vendor:sdl2"

SCALE :: 4

Gamepad :: struct {
	handle: ^sdl.GameController,
	id:     sdl.JoystickID,
}

gamepads: [dynamic]Gamepad
window_closed: bool // the window's close button; separate from the tool's own Quit

main :: proc() {
	if sdl.Init({.VIDEO, .GAMECONTROLLER}) != 0 {
		fmt.eprintln("SDL_Init failed:", sdl.GetError())
		os.exit(1)
	}
	defer sdl.Quit()

	window := sdl.CreateWindow(
		"Asset Tool",
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

	tool := app.make_tool()
	if tool.configure != nil {
		tool.configure(tool.data, {can_quit = true})
	}
	has_files := cm.tool_has_files(&tool)
	path := len(os.args) > 1 ? os.args[1] : tool.default_file
	if has_files {
		load_file(&tool, path, quiet_if_missing = true)
	}

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

	shown_dirty := !cm.tool_is_dirty(&tool) // forces the first title update
	pads, prev_pads: cm.Pads
	for !window_closed && !cm.tool_wants_quit(&tool) {
		ev: sdl.Event
		for sdl.PollEvent(&ev) {
			handle_sdl_event(&tool, &ev)
		}
		poll_pads(&pads)
		cm.tool_update_pads(&tool, &prev_pads, &pads)
		if has_files {
			service_files(&tool, path)
		}

		tool.draw(tool.data, &r)

		if dirty := cm.tool_is_dirty(&tool); dirty != shown_dirty {
			shown_dirty = dirty
			sdl.SetWindowTitle(window, fmt.ctprintf("%s - %s%s", tool.title, path, dirty ? " *" : ""))
		}
		sdl.Delay(8) // vsync is not guaranteed (software renderer)
		free_all(context.temp_allocator)
	}
}

handle_sdl_event :: proc(tool: ^cm.Tool, ev: ^sdl.Event) {
	handle :: proc(tool: ^cm.Tool, e: cm.Input_Event) {
		tool.handle_event(tool.data, e)
	}
	#partial switch ev.type {
	case .QUIT:
		window_closed = true
	case .KEYDOWN, .KEYUP:
		handle(
			tool,
			cm.Key_Event {
				key = translate_key(ev.key.keysym.scancode),
				shift = .LSHIFT in ev.key.keysym.mod || .RSHIFT in ev.key.keysym.mod,
				down = ev.type == .KEYDOWN,
			},
		)
	case .MOUSEMOTION:
		handle(tool, cm.Mouse_Move{int(ev.motion.x), int(ev.motion.y)})
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
		handle(
			tool,
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
		handle(tool, cm.Mouse_Wheel{dy})
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

// SDL game controller button -> standard-layout index (see common/gamepad.odin).
STANDARD_INDEX :: [?]struct {
	button: sdl.GameControllerButton,
	index:  int,
} {
	{.A, 0},
	{.B, 1},
	{.X, 2},
	{.Y, 3},
	{.LEFTSHOULDER, 4},
	{.RIGHTSHOULDER, 5},
	{.BACK, 8},
	{.START, 9},
	{.LEFTSTICK, 10},
	{.RIGHTSTICK, 11},
	{.DPAD_UP, 12},
	{.DPAD_DOWN, 13},
	{.DPAD_LEFT, 14},
	{.DPAD_RIGHT, 15},
	{.GUIDE, 16},
}

axis_value :: proc(g: ^sdl.GameController, axis: sdl.GameControllerAxis) -> f32 {
	return clamp(f32(sdl.GameControllerGetAxis(g, axis)) / 32767, -1, 1)
}

// Only game controllers (devices SDL knows a standard layout for) are reported.
poll_pads :: proc(pads: ^cm.Pads) {
	pads^ = {}
	for g, slot in gamepads {
		if slot >= cm.MAX_PADS {
			break
		}
		p := &pads[slot]
		p.connected, p.standard = true, true
		p.button_count, p.axis_count = cm.STANDARD_BUTTON_COUNT, cm.STANDARD_AXIS_COUNT
		if name := sdl.GameControllerName(g.handle); name != nil {
			cm.pad_set_name(p, string(name))
		}
		for m in STANDARD_INDEX {
			down := sdl.GameControllerGetButton(g.handle, m.button) != 0
			p.buttons[m.index] = {down, down ? 1 : 0}
		}
		for t, i in ([2]sdl.GameControllerAxis{.TRIGGERLEFT, .TRIGGERRIGHT}) {
			v := max(axis_value(g.handle, t), 0)
			p.buttons[6 + i] = {v >= cm.PAD_PRESS_THRESHOLD, v}
		}
		p.axes = {
			0 = axis_value(g.handle, .LEFTX),
			1 = axis_value(g.handle, .LEFTY),
			2 = axis_value(g.handle, .RIGHTX),
			3 = axis_value(g.handle, .RIGHTY),
		}
	}
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

service_files :: proc(tool: ^cm.Tool, path: string) {
	if text, ok := tool.take_save(tool.data); ok {
		if err := os.write_entire_file(path, text); err != nil {
			fmt.eprintfln("save %s failed: %v", path, err)
		} else {
			tool.saved(tool.data)
		}
	}
	if tool.wants_load(tool.data) {
		load_file(tool, path)
	}
}

load_file :: proc(tool: ^cm.Tool, path: string, quiet_if_missing := false) {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		if !quiet_if_missing {
			fmt.eprintfln("load %s failed: %v", path, err)
		}
		return
	}
	defer delete(data)
	if !tool.load(tool.data, data) {
		fmt.eprintfln("load %s failed: not a valid file for this tool", path)
	}
}
