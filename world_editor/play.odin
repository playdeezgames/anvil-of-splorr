package world_editor

import rt "../anvil_runtime"
import cm "../common"
import "core:fmt"

// Play mode: walk the world's player around its map to check that the walls, tags and placements
// behave as authored. It is the first user of `anvil_runtime`: the Play_State holds where everyone
// is, the loaded world is never touched, and leaving (red) simply drops the state, so the authored
// positions are back the next time. One step per command press, blocked by solid cells, the map's
// edge and other characters. The mouse clicks a neighbouring cell (or BACK).

PLAY_STRIP_H :: 11 // the top strip: the banner, the last message, BACK
PLAY_MAP_Y :: PLAY_STRIP_H + 1
PLAY_MAP_H :: cm.SCREEN_H - PLAY_MAP_Y
PLAY_BACK :: Rect{276, 1, 40, 9}
PLAY_STATUS_X :: 130 // where the last message starts in the strip (the banner ends before it)

NOTE_NO_PLAYER :: "THE WORLD HAS NO PLAYER"
NOTE_PLAYER_OFF_MAP :: "THE PLAYER IS ON NO MAP"
NOTE_CLICK_NEXT_TO :: "CLICK A CELL NEXT TO THE PLAYER"

// The largest whole-number zoom (1..8) at which the whole map fits below the strip; 1 if not even
// that fits (then the view scrolls with the player).
play_zoom :: proc(w: ^cm.World, mi: int) -> int {
	cols, rows, ok := rt.map_size(w, mi)
	if !ok {
		return 1
	}
	best := 1
	for z in 1 ..= 8 {
		if cols * w.tile_w * z <= cm.SCREEN_W && rows * w.tile_h * z <= PLAY_MAP_H {
			best = z
		}
	}
	return best
}

// The window of the map the screen shows: the whole map, centred, if it fits; else a window the size
// of the screen that follows the player.
play_window :: proc(e: ^Editor) -> rt.World_Draw {
	w := &e.world
	p := rt.play_position(&e.play, e.play_player)
	cols, rows, _ := rt.map_size(w, p.map_index)
	z := play_zoom(w, p.map_index)
	cell_w, cell_h := w.tile_w * z, w.tile_h * z
	vc, vr := min(cols, max(cm.SCREEN_W / cell_w, 1)), min(rows, max(PLAY_MAP_H / cell_h, 1))
	col0 := clamp(p.x - vc / 2, 0, cols - vc)
	row0 := clamp(p.y - vr / 2, 0, rows - vr)
	x := (cm.SCREEN_W - vc * cell_w) / 2
	y := PLAY_MAP_Y + (PLAY_MAP_H - vr * cell_h) / 2
	d := rt.zoom_window(w, p.map_index, col0, row0, vc, vr, x, y, z)
	d.clip = Rect{0, PLAY_MAP_Y, cm.SCREEN_W, PLAY_MAP_H}
	d.mark_player = true
	return d
}

// Starts playing if the world has a player standing on a map; else says why not.
begin_play :: proc(e: ^Editor) {
	ci, has := rt.player(&e.world)
	if !has {
		e.note = NOTE_NO_PLAYER
		return
	}
	if _, _, _, placed := rt.authored_location(&e.world, ci); !placed {
		e.note = NOTE_PLAYER_OFF_MAP
		return
	}
	rt.play_init(&e.play, &e.world)
	e.play_player = ci
	e.play_steps = 0
	e.mode = .Play
}

@(private = "file")
step_player :: proc(e: ^Editor, dx, dy: int) {
	result, tx, ty := rt.play_can_step(&e.play, &e.world, e.play_player, dx, dy)
	switch result {
	case .Moved:
		rt.play_step(&e.play, &e.world, e.play_player, dx, dy)
		e.play_steps += 1
		e.note = ""
	case .Solid:
		e.note = "BLOCKED: SOLID"
	case .Outside:
		e.note = "THE EDGE OF THE MAP"
	case .Occupied:
		p := rt.play_position(&e.play, e.play_player)
		other := rt.play_character_at(&e.play, p.map_index, tx, ty)
		name := other >= 0 ? cm.name_str(&e.world.characters[other].name) : ""
		e.note = fmt.tprintf("BLOCKED BY %s", name[:min(len(name), 20)])
	case .Feature:
		fi := rt.play_feature_at(&e.play, rt.play_position(&e.play, e.play_player).map_index, tx, ty)
		name := fi >= 0 ? cm.name_str(&e.world.features[fi].name) : ""
		e.note = fmt.tprintf("BLOCKED BY %s", name[:min(len(name), 20)])
	case .Not_Placed:
		e.note = NOTE_PLAYER_OFF_MAP
	}
}

// Commands and the mouse in Play mode.
handle_play :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch v in ev {
	case cm.Command:
		switch v.action {
		case .Up:
			step_player(e, 0, -1)
		case .Down:
			step_player(e, 0, 1)
		case .Left:
			step_player(e, -1, 0)
		case .Right:
			step_player(e, 1, 0)
		case .Red:
			e.mode = .Hub // the Play_State is dropped: the authored positions are untouched
			e.note = ""
		case .Green, .Yellow, .Blue:
		}
	case cm.Mouse_Move:
	case cm.Mouse_Button_Event:
		if v.button != .Left || !v.down {
			return
		}
		if rect_contains(PLAY_BACK, v.x, v.y) {
			e.mode = .Hub
			e.note = ""
			return
		}
		cx, cy, ok := rt.cell_at_pixel(&e.world, play_window(e), v.x, v.y)
		if !ok {
			return
		}
		p := rt.play_position(&e.play, e.play_player)
		dx, dy := cx - p.x, cy - p.y
		switch {
		case dx == 0 && dy == 0:
			e.note = ""
		case abs(dx) + abs(dy) == 1:
			step_player(e, dx, dy)
		case:
			e.note = NOTE_CLICK_NEXT_TO
		}
	case cm.Mouse_Wheel:
	}
}

play_banner_text :: proc(e: ^Editor) -> string {
	return fmt.tprintf("PLAYING  %s: BACK", label(e, .Red))
}

play_help_text :: proc(e: ^Editor) -> string {
	return fmt.tprintf("%s/%s/%s/%s: STEP", label(e, .Up), label(e, .Down), label(e, .Left), label(e, .Right))
}

draw_play :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	d := play_window(e)
	rt.draw_terrain(r, &e.world, d)
	rt.draw_features(r, &e.world, &e.play, d)
	rt.draw_characters(r, &e.world, &e.play, d)
	// The top strip, drawn last so nothing from the map shows through it.
	fill(r, Rect{0, 0, cm.SCREEN_W, PLAY_STRIP_H}, PANEL)
	cm.draw_text(r, 4, 3, play_banner_text(e), TEXT)
	p := rt.play_position(&e.play, e.play_player)
	status := e.note != "" ? e.note : fmt.tprintf("AT %d,%d  STEPS %d", p.x, p.y, e.play_steps)
	cm.draw_text(r, PLAY_STATUS_X, 3, status, e.note != "" ? WARN : HILITE)
	fill(r, PLAY_BACK, BG)
	cm.draw_text(r, PLAY_BACK.x + (PLAY_BACK.w - cm.text_width("BACK")) / 2, PLAY_BACK.y + 2, "BACK", TEXT)
	cm.renderer_present(r)
}
