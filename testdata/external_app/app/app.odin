// A tiny stand-in for a game's own app, outside the Anvil's apps/ folder: it imports the Anvil's
// packages through the "anvil" collection (no relative paths into the Anvil repo) and gives the
// frontends a Tool. `./build.sh check` builds it for native and the web so GAMES.md cannot rot.
package app

import anvil "anvil:anvil_runtime"
import cm "anvil:common"

Clock :: struct {
	seconds: f64,
	world:   ^anvil.World,
}

clock: Clock

make_tool :: proc() -> cm.Tool {
	clock.world = anvil.new_world()
	return cm.Tool {
		title = "External",
		data = &clock,
		handle_event = proc(data: rawptr, ev: cm.Input_Event) {},
		update = proc(data: rawptr, dt_ms: f64) {(^Clock)(data).seconds += dt_ms / 1000},
		draw = proc(data: rawptr, r: ^cm.Renderer) {
			cm.renderer_clear(r, cm.Color{0, 0, 40})
			cm.draw_text(r, 8, 8, "EXTERNAL APP", cm.Color{255, 255, 255})
		},
	}
}
