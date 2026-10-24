#+build !js
package anvil_runtime

import cm "../common"
import "core:testing"

// The tiny game (room 5 x 4: wall across the top row, Hero at 1,1, Star at 3,2) with trigger types
// "spikes" (damage 5, armed 1) and "lock", a feature "Door" at 3,1, and triggers Trap A and Trap B
// (spikes, both in the cell 2,1; Trap A has damage 8), Wall watch (lock, in the wall cell 2,0), Star
// watch (spikes, in the cell 3,2 where the Star stands), Latch (lock, on the Door) and Spare (in no
// place). Loaded through the file like a game gets it.
trigger_game :: proc() -> ^World {
	w := loaded_world()
	spikes := cm.world_add_trigger_type(w, "spikes")
	lock := cm.world_add_trigger_type(w, "lock")
	cm.name_assign(&w.trigger_types[lock].sprite, "star")
	cm.world_trigger_type_add_prop(w, spikes, "damage", 5)
	cm.world_trigger_type_add_prop(w, spikes, "armed", 1)
	ft := cm.world_add_feature_type(w, "door")
	door := cm.world_add_feature(w, ft, "Door")
	cm.world_place_feature(w, 0, 3, 1, w.features[door].uuid)
	add :: proc(w: ^World, type_index: int, name: string) -> int {
		return cm.world_add_trigger(w, type_index, name)
	}
	a := add(w, spikes, "Trap A")
	b := add(w, spikes, "Trap B")
	wall := add(w, lock, "Wall watch")
	star := add(w, spikes, "Star watch")
	latch := add(w, lock, "Latch")
	add(w, spikes, "Spare")
	cm.world_trigger_set_value(w, a, 0, 8)
	cm.world_place_trigger(w, w.triggers[a].uuid, 0, 2, 1)
	cm.world_place_trigger(w, w.triggers[b].uuid, 0, 2, 1)
	cm.world_place_trigger(w, w.triggers[wall].uuid, 0, 2, 0)
	cm.world_place_trigger(w, w.triggers[star].uuid, 0, 3, 2)
	cm.world_attach_trigger(w, w.triggers[latch].uuid, w.features[door].uuid)
	text := cm.world_to_json(w)
	free(w)
	back := new_world()
	assert(load(back, transmute([]u8)text) == "")
	return back
}

// Every event waiting, oldest first.
drain :: proc(ps: ^Play_State) -> []Triggered {
	out := make([dynamic]Triggered, context.temp_allocator)
	for {
		e, ok := play_take_triggered(ps)
		if !ok {
			break
		}
		append(&out, e)
	}
	return out[:]
}

@(test)
test_a_game_reads_triggers_as_authored :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_game()
	defer free(w)
	testing.expect_value(t, trigger_count(w), 6)
	testing.expect(t, trigger_type(w, 0) != nil && cm.name_str(&trigger_type(w, 0).name) == "spikes" && trigger_type(w, 9) == nil)
	testing.expect(t, trigger_sprite(w, 2) != nil && trigger_image(w, 2) != nil && trigger_image(w, 9) == nil)
	damage, ok := trigger_prop_index(w, 0, "damage")
	testing.expect(t, ok && damage == 0)
	_, found := trigger_prop_index(w, 2, "damage") // a lock has none
	testing.expect(t, !found)
	testing.expect_value(t, trigger_value(w, 0, damage), 8)
	testing.expect_value(t, trigger_value(w, 1, damage), 5)
	testing.expect_value(t, trigger_prop_default(w, 0, damage), 5)
	testing.expect_value(t, trigger_prop_default(w, 9, 0), 0)
	testing.expect(t, trigger_has_tag(w, 0, TAG_SOLID) == false)
	testing.expect_value(t, len(triggers_with_tag(w, TAG_SOLID)), 0)
	mi, x, y, in_cell := authored_trigger_cell(w, 0)
	testing.expect(t, in_cell && mi == 0 && x == 2 && y == 1)
	_, _, _, in_cell = authored_trigger_cell(w, 4) // on a feature
	testing.expect(t, !in_cell)
	fi, on_feature := authored_trigger_feature(w, 4)
	testing.expect(t, on_feature && fi == 0)
	_, on_feature = authored_trigger_feature(w, 0)
	testing.expect(t, !on_feature)
}

@(test)
test_a_step_into_a_cell_with_triggers_queues_entered_events_for_every_trigger :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_game()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero := index_of_character(w, "Hero")
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Moved)
	events := drain(ps)
	testing.expect_value(t, len(events), 2) // both traps, in table order
	testing.expect(t, events[0].trigger == 0 && events[1].trigger == 1)
	e := events[0]
	testing.expect(t, e.mover == hero && e.kind == .Entered && e.reason == .None && e.map_index == 0 && e.x == 2 && e.y == 1 && e.dx == 1 && e.dy == 0)
	// A step into an empty cell, and a look (play_can_step) or a placement, fire nothing.
	testing.expect_value(t, play_step(ps, w, hero, 0, 1), Move_Result.Moved)
	look, _, _ := play_can_step(ps, w, hero, -1, 0)
	testing.expect_value(t, look, Move_Result.Moved)
	play_place(ps, w, hero, 0, 2, 1)
	testing.expect_value(t, len(drain(ps)), 0)
	// Another character's step fires them too (the game filters by the mover).
	star := index_of_character(w, "Star")
	play_place(ps, w, star, 0, 1, 1)
	play_step(ps, w, star, 1, 0)
	events = drain(ps)
	testing.expect(t, len(events) == 2 && events[0].mover == star)
}

@(test)
test_a_refused_step_queues_bumped_events_with_the_reason :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_game()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero := index_of_character(w, "Hero")
	// Solid terrain: the wall watch in the wall cell above 2,1.
	play_step(ps, w, hero, 1, 0)
	drain(ps)
	testing.expect_value(t, play_step(ps, w, hero, 0, -1), Move_Result.Solid)
	events := drain(ps)
	testing.expect_value(t, len(events), 1)
	testing.expect(t, events[0].trigger == 2 && events[0].kind == .Bumped && events[0].reason == .Solid && events[0].x == 2 && events[0].y == 0)
	testing.expect_value(t, ps.positions[hero].y, 1) // it did not move
	// A feature: the Door at 3,1 (no cell trigger there) fires the Latch on it.
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Feature)
	events = drain(ps)
	testing.expect_value(t, len(events), 1)
	testing.expect(t, events[0].trigger == 4 && events[0].kind == .Bumped && events[0].reason == .Feature && events[0].x == 3 && events[0].y == 1)
	// The collision queue still has its own entry for the same bump.
	c, got := play_take_collision(ps)
	testing.expect(t, got && c.kind == .Feature)
	// Another character: the Star stands in 3,2 where the Star watch is.
	play_step(ps, w, hero, 0, 1) // 2,2
	drain(ps)
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Occupied)
	events = drain(ps)
	testing.expect(t, len(events) == 1 && events[0].trigger == 3 && events[0].reason == .Character)
	// The edge of the map is no cell: nothing fires.
	play_place(ps, w, hero, 0, 0, 1)
	testing.expect_value(t, play_step(ps, w, hero, -1, 0), Move_Result.Outside)
	testing.expect_value(t, len(drain(ps)), 0)
	// A character on no map fires nothing and stays put.
	play_unplace(ps, hero)
	testing.expect_value(t, play_step(ps, w, hero, 1, 0), Move_Result.Not_Placed)
	testing.expect_value(t, len(drain(ps)), 0)
}

@(test)
test_places_and_values_change_in_the_play_state_and_never_in_the_world :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_game()
	defer free(w)
	before := cm.world_to_json(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero := index_of_character(w, "Hero")
	testing.expect_value(t, ps.trigger_count, 6)
	p := play_trigger_place(ps, 0)
	testing.expect(t, p.kind == .Cell && p.map_index == 0 && p.x == 2 && p.y == 1)
	testing.expect(t, play_trigger_place(ps, 4).kind == .Feature && play_trigger_place(ps, 4).feature == 0)
	testing.expect(t, play_trigger_place(ps, 5).kind == .None && play_trigger_place(ps, 99).kind == .None)
	testing.expect_value(t, len(play_triggers_in_cell(ps, 0, 2, 1)), 2)
	testing.expect_value(t, len(play_triggers_on_feature(ps, 0)), 1)
	// Values: copied from the authors, changed in the play state only.
	testing.expect_value(t, play_trigger_value(ps, w, 0, 0), 8)
	testing.expect_value(t, play_trigger_value(ps, w, 1, 0), 5)
	testing.expect(t, play_set_trigger_value(ps, w, 1, 1, 0)) // disarmed
	testing.expect_value(t, play_trigger_value(ps, w, 1, 1), 0)
	testing.expect(t, !play_set_trigger_value(ps, w, 2, 0, 1) && !play_set_trigger_value(ps, w, 99, 0, 1) && play_trigger_value(ps, w, 99, 0) == 0)
	// A spent trap is taken out and does not fire again; others still do.
	testing.expect(t, play_unplace_trigger(ps, 0) && !play_unplace_trigger(ps, 0) && !play_unplace_trigger(ps, 99))
	play_step(ps, w, hero, 1, 0)
	events := drain(ps)
	testing.expect(t, len(events) == 1 && events[0].trigger == 1)
	// Moving a trigger: into another cell, onto another feature; refusals change nothing.
	testing.expect_value(t, play_place_trigger(ps, w, 0, 0, 4, 3), cm.Trigger_Place_Result.Placed)
	testing.expect_value(t, play_place_trigger(ps, w, 0, 0, 9, 3), cm.Trigger_Place_Result.Outside)
	testing.expect_value(t, play_place_trigger(ps, w, 99, 0, 1, 1), cm.Trigger_Place_Result.Unknown)
	testing.expect_value(t, play_place_trigger(ps, w, 0, 5, 1, 1), cm.Trigger_Place_Result.Unknown)
	testing.expect(t, play_trigger_place(ps, 0).x == 4)
	testing.expect(t, play_attach_trigger(ps, 5, 0) && play_trigger_place(ps, 5).kind == .Feature && !play_attach_trigger(ps, 5, 9) && !play_attach_trigger(ps, 99, 0))
	testing.expect_value(t, len(play_triggers_on_feature(ps, 0)), 2)
	// The world is as it was; play_init starts over.
	testing.expect_value(t, cm.world_to_json(w), before)
	play_init(ps, w)
	testing.expect(t, play_trigger_place(ps, 0).x == 2 && play_trigger_value(ps, w, 1, 1) == 1)
}

@(test)
test_the_event_queue_is_bounded_and_a_world_without_triggers_queues_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_game()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	hero := index_of_character(w, "Hero")
	for _ in 0 ..< 40 { // 2 events a time on and off the traps' cell
		play_step(ps, w, hero, 1, 0)
		play_step(ps, w, hero, -1, 0)
	}
	testing.expect_value(t, ps.triggered_count, MAX_COLLISIONS)
	testing.expect_value(t, ps.triggered_lost, 40 * 2 - MAX_COLLISIONS) // (the Door's latch is never reached from here)
	e, ok := play_take_triggered(ps)
	testing.expect(t, ok && e.kind == .Entered)
	play_clear_triggered(ps)
	_, ok = play_take_triggered(ps)
	testing.expect(t, !ok && ps.triggered_lost == 0)
	plain := loaded_world()
	defer free(plain)
	play_init(ps, plain)
	play_step(ps, plain, index_of_character(plain, "Hero"), 1, 0)
	testing.expect_value(t, ps.trigger_count, 0)
	testing.expect_value(t, len(drain(ps)), 0)
}

@(test)
test_a_game_draws_the_triggers_in_cells_now :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	w := trigger_game()
	defer free(w)
	ps := new(Play_State)
	defer free(ps)
	play_init(ps, w)
	log: Draw_Log
	defer delete(log.rects)
	defer delete(log.colors)
	r := draw_renderer(&log)
	d := zoom_window(w, 0, 0, 0, 5, 4, 20, 10, 3)
	draw_triggers(&r, w, ps, d)
	// Six triggers, one on a feature and one in no place: four in cells.
	cells := [][2]int{{2, 1}, {2, 0}, {3, 2}}
	testing.expect(t, len(log.rects) > 0)
	for rc in log.rects {
		inside := false
		for c in cells {
			cell := cm.world_cell_rect(d, c.x, c.y)
			inside ||= rc.x >= cell.x && rc.y >= cell.y && rc.x + rc.w <= cell.x + cell.w && rc.y + rc.h <= cell.y + cell.h
		}
		testing.expect(t, inside)
	}
	// A spent trap's cell stops drawing; a window without the cells draws nothing.
	count := len(log.rects)
	for ti in 0 ..< ps.trigger_count {
		play_unplace_trigger(ps, ti)
	}
	clear(&log.rects)
	clear(&log.colors)
	draw_triggers(&r, w, ps, d)
	testing.expect_value(t, len(log.rects), 0)
	play_init(ps, w)
	clear(&log.rects)
	clear(&log.colors)
	draw_triggers(&r, w, ps, zoom_window(w, 0, 3, 3, 2, 1, 20, 10, 3))
	testing.expect_value(t, len(log.rects), 0)
	_ = count
}
