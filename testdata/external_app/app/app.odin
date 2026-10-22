// A tiny stand-in for a game's own app, outside the Anvil's apps/ folder: it imports the Anvil's
// packages through the "anvil" collection (no relative paths into the Anvil repo) and gives the
// frontends a Tool. `./build.sh check` builds it for native and the web so GAMES.md cannot rot.
// It also shows the two hooks a game uses: `update` (the clock) and `take_audio` (sound: green plays a
// jingle on channel 0, blue loops a tune on channel 1, red stops everything).
package app

import anvil "anvil:anvil_runtime"
import cm "anvil:common"
import "core:fmt"

JINGLE :: "T200 O5 L16 C E G >C"
TUNE :: "T140 O3 L8 C E G E C E G E F A >C <A F A >C <A"

Demo :: struct {
	seconds: f64,
	world:   ^anvil.World,
	pending: [dynamic]cm.Audio_Request,
	played:  int, // how many sounds were asked for, shown on screen
}

demo: Demo

// A real game gets its sounds from the world file (made in the world editor); this stand-in makes two.
add_sound :: proc(w: ^anvil.World, name, text: string, loop: bool) {
	i := cm.world_add_sound(w, name)
	cm.world_set_sound_text(w, i, text)
	cm.world_set_sound_loop(w, i, loop)
}

make_tool :: proc() -> cm.Tool {
	demo.world = anvil.new_world()
	add_sound(demo.world, "jingle", JINGLE, false)
	add_sound(demo.world, "tune", TUNE, true)
	return cm.Tool {
		title = "External",
		data = &demo,
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {
			d := (^Demo)(data)
			cmd, ok := ev.(cm.Command)
			if !ok {
				return
			}
			switch cmd.action {
			case .Green:
				if req, ok := anvil.sound_play(d.world, "jingle", 0); ok {
					append(&d.pending, req)
					d.played += 1
				}
			case .Blue:
				if req, ok := anvil.sound_play(d.world, "tune", 1); ok {
					append(&d.pending, req)
					d.played += 1
				}
			case .Red:
				append(&d.pending, anvil.sound_stop_all())
			case .Up, .Down, .Left, .Right, .Yellow:
			}
		},
		update = proc(data: rawptr, dt_ms: f64) {(^Demo)(data).seconds += dt_ms / 1000},
		take_audio = proc(data: rawptr) -> (cm.Audio_Request, bool) {
			d := (^Demo)(data)
			if len(d.pending) == 0 {
				return {}, false
			}
			return pop_front(&d.pending), true
		},
		draw = proc(data: rawptr, r: ^cm.Renderer) {
			d := (^Demo)(data)
			cm.renderer_clear(r, cm.Color{0, 0, 40})
			cm.draw_text(r, 8, 8, "EXTERNAL APP", cm.Color{255, 255, 255})
			cm.draw_text(r, 8, 20, "GREEN: JINGLE  BLUE: LOOP  RED: STOP", cm.Color{180, 180, 255})
			cm.draw_text(r, 8, 32, fmt_clock(d), cm.Color{255, 220, 80})
		},
	}
}

// "TIME 12.3  SOUNDS 2"
fmt_clock :: proc(d: ^Demo) -> string {
	tenths := int(d.seconds * 10)
	return fmt.tprintf("TIME %d.%d  SOUNDS %d", tenths / 10, tenths % 10, d.played)
}
