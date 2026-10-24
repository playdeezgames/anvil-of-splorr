package anvil_runtime

import cm "../common"

// Triggers for a game (design in coxswain task #64 of project `anvil`, file format in `WORLD.md`). A
// trigger sits in a map cell or on a feature and never blocks. The Anvil only *notifies*: when a
// character steps and the step is allowed, `play_step` queues an `Entered` event for each trigger in
// the cell it entered; when the step is refused (a feature, another character or solid terrain in the
// way) it queues a `Bumped` event, with the reason, for each trigger in the cell it tried to enter, and,
// when the refusal was a feature, for each trigger on that feature. The game drains the queue
// (`play_take_triggered`), looks at the mover's tags and the trigger's tags and values, and decides what
// happens. The loaded world never changes: places and values live in the `Play_State`.

Trigger_Kind :: enum {
	Entered, // the step succeeded: the mover is in the cell now
	Bumped, // the step was refused: the mover is where it was
}

Bump_Reason :: enum {
	None, // (Entered)
	Feature, // a feature stands in the cell
	Character, // another character stands in the cell
	Solid, // the terrain or the cell is solid
}

// A trigger went off. `trigger` and `mover` are indexes into the world's tables; the cell is the one
// the mover entered or tried to enter, on `map_index`; (dx, dy) is the step.
Triggered :: struct {
	mover:     int,
	trigger:   int,
	kind:      Trigger_Kind,
	reason:    Bump_Reason,
	map_index: int,
	x, y:      int,
	dx, dy:    int,
}

// Where a trigger is now: nowhere, a cell of a map, or on a feature (an index of the world's table).
Trigger_Pos :: struct {
	kind:      cm.Trigger_Place,
	map_index: int,
	x, y:      int,
	feature:   int,
}

// --- As authored ---------------------------------------------------------------------------------

trigger_count :: proc(w: ^World) -> int {
	return w.trigger_count
}

trigger_type :: proc(w: ^World, ti: int) -> ^cm.Trigger_Type {
	if ti < 0 || ti >= w.trigger_count {
		return nil
	}
	tt := cm.world_find_trigger_type(w, cm.name_str(&w.triggers[ti].type))
	return tt >= 0 ? &w.trigger_types[tt] : nil
}

// The sprite a trigger draws (through its type), or nil.
trigger_sprite :: proc(w: ^World, ti: int) -> ^Sprite {
	return cm.world_trigger_sprite(w, ti)
}

// The tile image of a trigger's sprite, or nil (draw it without the sprite's `transparent` colour).
trigger_image :: proc(w: ^World, ti: int) -> ^Image4 {
	sp := trigger_sprite(w, ti)
	return sp == nil ? nil : cm.world_sprite_image(w, sp)
}

// Whether a trigger has a tag: its own setting if it has one, else its type's.
trigger_has_tag :: proc(w: ^World, ti, tag: int) -> bool {
	return cm.world_trigger_has_tag(w, ti, tag)
}

// The triggers that have a tag, in table order. On the temp allocator unless another is given.
triggers_with_tag :: proc(w: ^World, tag: int, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for ti in 0 ..< w.trigger_count {
		if cm.world_trigger_has_tag(w, ti, tag) {
			append(&out, ti)
		}
	}
	return out[:]
}

// The position of a property in a trigger's type's list, by name.
trigger_prop_index :: proc(w: ^World, ti: int, name: string) -> (index: int, ok: bool) {
	tt := trigger_type(w, ti)
	if tt == nil {
		return 0, false
	}
	i := cm.prop_set_find(&tt.props, name)
	return i, i >= 0
}

// The type's default for a property (0 for no such trigger or property).
trigger_prop_default :: proc(w: ^World, ti, p: int) -> i32 {
	tt := trigger_type(w, ti)
	if tt == nil || p < 0 || p >= tt.props.count {
		return 0
	}
	return tt.props.values[p]
}

// What the authors set: the trigger's own value, else its type's default.
trigger_value :: proc(w: ^World, ti, p: int) -> i32 {
	return cm.world_trigger_value(w, ti, p)
}

// Where the authors put a trigger: its map and cell (not for one on a feature or nowhere; ask
// `authored_trigger_feature` for that).
authored_trigger_cell :: proc(w: ^World, ti: int) -> (mi, x, y: int, ok: bool) {
	return cm.world_trigger_cell(w, ti)
}

// The feature a trigger is on, as authored (an index into the world's feature table).
authored_trigger_feature :: proc(w: ^World, ti: int) -> (fi: int, ok: bool) {
	if ti < 0 || ti >= w.trigger_count || w.triggers[ti].place != .Feature {
		return 0, false
	}
	i := cm.world_find_feature(w, w.triggers[ti].feature)
	return i, i >= 0
}

// --- In play -------------------------------------------------------------------------------------

@(private = "package")
play_init_triggers :: proc(ps: ^Play_State, w: ^World) {
	ps.trigger_count = w.trigger_count
	for ti in 0 ..< w.trigger_count {
		t := &w.triggers[ti]
		ps.trigger_values[ti] = t.overrides
		switch t.place {
		case .None:
		case .Cell:
			if mi := cm.world_find_map(w, cm.name_str(&t.map_name)); mi >= 0 {
				ps.trigger_places[ti] = Trigger_Pos{kind = .Cell, map_index = mi, x = t.x, y = t.y}
			}
		case .Feature:
			if fi := cm.world_find_feature(w, t.feature); fi >= 0 {
				ps.trigger_places[ti] = Trigger_Pos{kind = .Feature, feature = fi}
			}
		}
	}
}

// Where a trigger is now (kind .None for no such trigger or one in no place).
play_trigger_place :: proc(ps: ^Play_State, ti: int) -> Trigger_Pos {
	if ti < 0 || ti >= ps.trigger_count {
		return {}
	}
	return ps.trigger_places[ti]
}

// The triggers in a cell now, in table order. On the temp allocator unless another is given.
play_triggers_in_cell :: proc(ps: ^Play_State, mi, x, y: int, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for ti in 0 ..< ps.trigger_count {
		p := ps.trigger_places[ti]
		if p.kind == .Cell && p.map_index == mi && p.x == x && p.y == y {
			append(&out, ti)
		}
	}
	return out[:]
}

// The triggers on a feature now (a feature index), in table order.
play_triggers_on_feature :: proc(ps: ^Play_State, fi: int, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for ti in 0 ..< ps.trigger_count {
		p := ps.trigger_places[ti]
		if p.kind == .Feature && p.feature == fi {
			append(&out, ti)
		}
	}
	return out[:]
}

// Puts a trigger in a cell (of any map), taking it from where it was. Refused (nothing changes) for a
// trigger or map that does not exist (Unknown) or a cell outside the map (Outside).
play_place_trigger :: proc(ps: ^Play_State, w: ^World, ti, mi, x, y: int) -> cm.Trigger_Place_Result {
	if ti < 0 || ti >= ps.trigger_count || mi < 0 || mi >= w.map_count {
		return .Unknown
	}
	columns, rows, _ := map_size(w, mi)
	if x < 0 || y < 0 || x >= columns || y >= rows {
		return .Outside
	}
	ps.trigger_places[ti] = Trigger_Pos{kind = .Cell, map_index = mi, x = x, y = y}
	return .Placed
}

// Puts a trigger on a feature (it then has no cell of its own). False for no such trigger or feature.
play_attach_trigger :: proc(ps: ^Play_State, ti, fi: int) -> bool {
	if ti < 0 || ti >= ps.trigger_count || fi < 0 || fi >= ps.feature_count {
		return false
	}
	ps.trigger_places[ti] = Trigger_Pos{kind = .Feature, feature = fi}
	return true
}

// Takes a trigger out of its cell or off its feature (a spent trap). Returns true if it had a place.
play_unplace_trigger :: proc(ps: ^Play_State, ti: int) -> bool {
	if ti < 0 || ti >= ps.trigger_count || ps.trigger_places[ti].kind == .None {
		return false
	}
	ps.trigger_places[ti] = {}
	return true
}

// A trigger's value now: what the game set, else the authored value, else the type's default.
play_trigger_value :: proc(ps: ^Play_State, w: ^World, ti, p: int) -> i32 {
	tt := trigger_type(w, ti)
	if tt == nil || ti >= ps.trigger_count {
		return 0
	}
	return cm.prop_value(&tt.props, &ps.trigger_values[ti], p)
}

// Sets a trigger's value for the rest of the play (a value equal to the default is the default
// again). False for no such trigger or property.
play_set_trigger_value :: proc(ps: ^Play_State, w: ^World, ti, p: int, value: i32) -> bool {
	tt := trigger_type(w, ti)
	if tt == nil || ti >= ps.trigger_count {
		return false
	}
	return cm.prop_override_set(&tt.props, &ps.trigger_values[ti], p, value)
}

// --- The events ----------------------------------------------------------------------------------

// The next trigger event since the last call (oldest first), or ok = false when there is none. A game
// drains these once a frame after its steps.
play_take_triggered :: proc(ps: ^Play_State) -> (e: Triggered, ok: bool) {
	if ps.triggered_count == 0 {
		return {}, false
	}
	e = ps.triggered[ps.triggered_head]
	ps.triggered_head = (ps.triggered_head + 1) % MAX_COLLISIONS
	ps.triggered_count -= 1
	return e, true
}

// Forgets the events not yet taken (and the lost count).
play_clear_triggered :: proc(ps: ^Play_State) {
	ps.triggered_head, ps.triggered_count, ps.triggered_lost = 0, 0, 0
}

@(private = "file")
push_triggered :: proc(ps: ^Play_State, e: Triggered) {
	if ps.triggered_count == MAX_COLLISIONS {
		ps.triggered_head = (ps.triggered_head + 1) % MAX_COLLISIONS
		ps.triggered_count -= 1
		ps.triggered_lost += 1
	}
	ps.triggered[(ps.triggered_head + ps.triggered_count) % MAX_COLLISIONS] = e
	ps.triggered_count += 1
}

// What `play_step` calls after deciding a step: the triggers of the cell it entered (Entered) or tried
// to enter (Bumped, for any refusal into a cell), then, when a feature was the reason, the triggers on
// that feature. Steps off the map, or by a character that is on no map, fire nothing.
@(private = "package")
trigger_events :: proc(ps: ^Play_State, ci: int, result: Move_Result, tx, ty, dx, dy: int) {
	if ps.trigger_count == 0 {
		return
	}
	kind: Trigger_Kind
	reason: Bump_Reason
	switch result {
	case .Moved:
		kind = .Entered
	case .Solid:
		kind, reason = .Bumped, .Solid
	case .Feature:
		kind, reason = .Bumped, .Feature
	case .Occupied:
		kind, reason = .Bumped, .Character
	case .Outside, .Not_Placed:
		return
	}
	mi := ps.positions[ci].map_index
	for ti in 0 ..< ps.trigger_count {
		p := ps.trigger_places[ti]
		if p.kind == .Cell && p.map_index == mi && p.x == tx && p.y == ty {
			push_triggered(ps, {ci, ti, kind, reason, mi, tx, ty, dx, dy})
		}
	}
	if result == .Feature {
		if fi := play_feature_at(ps, mi, tx, ty); fi >= 0 {
			for ti in 0 ..< ps.trigger_count {
				if p := ps.trigger_places[ti]; p.kind == .Feature && p.feature == fi {
					push_triggered(ps, {ci, ti, kind, reason, mi, tx, ty, dx, dy})
				}
			}
		}
	}
}

// --- Drawing -------------------------------------------------------------------------------------

// Draws the triggers in cells of the window's map *now* (the Play_State), over the terrain: each in its
// cell, without its sprite's transparent colour; several in one cell draw one over the other. Draw them
// before the inventories, features and characters. A game that keeps some hidden simply does not call
// this for them (draw them one at a time with `cm.world_draw_trigger`).
draw_triggers :: proc(r: ^cm.Renderer, w: ^World, ps: ^Play_State, d: World_Draw) {
	if d.cell_w <= 0 || d.cell_h <= 0 {
		return
	}
	for ti in 0 ..< ps.trigger_count {
		p := ps.trigger_places[ti]
		if p.kind != .Cell || p.map_index != d.map_index {
			continue
		}
		if p.x < d.col || p.y < d.row || p.x >= d.col + d.cols || p.y >= d.row + d.rows {
			continue
		}
		cm.world_draw_trigger(r, w, ti, cm.world_cell_rect(d, p.x, p.y), d.clip, d.missing)
	}
}
