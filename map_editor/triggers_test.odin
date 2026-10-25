#+build !js
package map_editor

import cm "../common"
import "core:testing"

// The feature world plus trigger types "spikes" and "alarm" (bat sprite) and triggers Pit (spikes, at
// 3,2), Siren (alarm, off the map) and Snare (spikes, at 3,2 too).
trig_world :: proc(w := 6, h := 4) -> ^cm.World {
	world := feat_world(w, h)
	spikes := cm.world_add_trigger_type(world, "spikes")
	alarm := cm.world_add_trigger_type(world, "alarm")
	cm.name_assign(&world.trigger_types[alarm].sprite, "bat")
	for spec in ([][2]string{{"Pit", "spikes"}, {"Siren", "alarm"}, {"Snare", "spikes"}}) {
		n := cm.world_add_trigger(world, spec[1] == "alarm" ? alarm : spikes)
		cm.name_assign(&world.triggers[n].name, spec[0])
	}
	cm.world_place_trigger(world, world.triggers[0].uuid, 0, 3, 2)
	cm.world_place_trigger(world, world.triggers[2].uuid, 0, 3, 2)
	return world
}

trig_editor :: proc(w := 6, h := 4) -> (e: ^Editor, world: ^cm.World) {
	world = trig_world(w, h)
	e = new(Editor)
	editor_begin(e, world, 0)
	for e.layer != .Triggers {
		toggle_layer(e)
	}
	return
}

@(test)
test_green_places_the_current_trigger_and_here_cycles :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := trig_editor()
	defer free_both(e, world)
	testing.expect_value(t, e.layer, Layer.Triggers)
	// Siren (current after a step) goes to a cell; a cell may hold several triggers.
	step_trigger(e, 1)
	testing.expect_value(t, e.cur_trig, 1)
	goto_cell(e, 3, 2)
	press(e, .Green)
	testing.expect(t, e.dirty && len(cell_triggers(e)) == 3)
	e.dirty = false
	press(e, .Green) // again: nothing changes
	testing.expect(t, !e.dirty)
	// Here walks the cell's triggers.
	e.mode = .Setup
	goto_row(e, .Trig_Here)
	press(e, .Right)
	testing.expect_value(t, e.cur_trig, 2)
	press(e, .Right)
	testing.expect_value(t, e.cur_trig, 0)
	goto_cell(e, 0, 0)
	e.note = ""
	press(e, .Right)
	testing.expect_value(t, e.note, NOTE_NOT_HERE)
}

@(test)
test_trigger_setup_rows_new_rename_type_unplace_delete :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := trig_editor()
	defer free_both(e, world)
	goto_row(e, .Trig_Type)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&world.triggers[0].type), "alarm")
	press(e, .Left)
	testing.expect_value(t, cm.name_str(&world.triggers[0].type), "spikes")
	goto_row(e, .Trigger)
	press(e, .Right)
	press(e, .Left)
	testing.expect(t, e.cur_trig == 0 && e.cx == 3 && e.cy == 2)
	run(e, .Trig_Unplace)
	testing.expect(t, len(cell_triggers(e)) == 1 && e.dirty)
	e.note = ""
	run(e, .Trig_Unplace)
	testing.expect_value(t, e.note, NOTE_NOT_PLACED)
	e.cx, e.cy = 0, 3
	run(e, .Trig_New)
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed_in_map(e, "Mine")
	testing.expect(t, world.trigger_count == 4 && trigger_name(e, 3) == "Mine" && len(cell_triggers(e)) == 1)
	run(e, .Trig_Rename)
	name_typed_in_map(e, "Mind")
	testing.expect_value(t, trigger_name(e, 3), "Mind")
	run(e, .Trig_Rename)
	keypad_cancel(e)
	testing.expect_value(t, trigger_name(e, 3), "Mind")
	run(e, .Trig_Delete)
	testing.expect(t, e.confirm_delete && world.trigger_count == 4)
	press(e, .Up)
	testing.expect(t, !e.confirm_delete)
	e.row = .Trig_Delete
	press(e, .Green, .Green)
	testing.expect(t, world.trigger_count == 3 && len(cell_triggers(e)) == 0)
	world.trigger_type_count = 0
	e.note = ""
	run(e, .Trig_New)
	testing.expect_value(t, e.note, NOTE_NEED_TRIGGER_TYPE)
	world.trigger_count = 0
	e.note = ""
	run(e, .Trig_Rename)
	testing.expect_value(t, e.note, NOTE_NO_TRIGGERS)
	e.note = ""
	press(e, .Red) // back to draw
	press(e, .Green)
	testing.expect_value(t, e.note, NOTE_NO_TRIGGERS)
}

@(test)
test_every_trigger_function_by_each_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	Method :: enum {
		Commands,
		Mouse,
	}
	for m in Method {
		e, world := trig_editor()
		// Place: green / click a cell.
		e.cur_trig = 1
		switch m {
		case .Commands:
			goto_cell(e, 4, 1)
			press(e, .Green)
		case .Mouse:
			click_cell(e, 4, 1)
		}
		testing.expectf(t, len(cell_triggers(e)) == 1 && e.cur_trig == 1, "%v place", m)
		// Pick: right click a cell with triggers takes one; blue steps a page; the picker chooses.
		switch m {
		case .Commands:
			goto_cell(e, 3, 2)
			e.mode = .Setup
			goto_row(e, .Trig_Here)
			press(e, .Right)
		case .Mouse:
			rc := cell_rect(e, 3, 2)
			mouse(e, rc.x + 1, rc.y + 1, true, .Right)
			mouse(e, rc.x + 1, rc.y + 1, false, .Right)
		}
		testing.expectf(t, e.cur_trig == 0 || e.cur_trig == 2, "%v pick", m)
		switch m {
		case .Commands:
			step_trigger(e, 1)
		case .Mouse:
			slot := picker_rect(1)
			click_at(e, slot.x + 2, slot.y + 2)
		}
		testing.expectf(t, e.cur_trig == 1, "%v picker", m)
		switch m {
		case .Commands:
			goto_row(e, .Trig_Type)
			press(e, .Right)
		case .Mouse:
			click_rect(e, COLUMNS_PLUS)
		}
		testing.expectf(t, cm.name_str(&world.triggers[1].type) == "spikes", "%v type", m)
		switch m {
		case .Commands:
			run(e, .Trig_New)
		case .Mouse:
			click_rect(e, TRIG_NEW_BUTTON)
		}
		testing.expectf(t, e.mode == .Text && world.trigger_count == 4, "%v new", m)
		keypad_cancel(e)
		switch m {
		case .Commands:
			run(e, .Trig_Unplace)
		case .Mouse:
			click_rect(e, TRIG_UNPLACE_BUTTON)
		}
		_, _, _, still := cm.world_trigger_cell(world, 3)
		testing.expectf(t, !still, "%v unplace", m)
		switch m {
		case .Commands:
			run(e, .Trig_Rename)
		case .Mouse:
			click_rect(e, TRIG_RENAME_BUTTON)
		}
		testing.expectf(t, e.mode == .Text, "%v rename", m)
		keypad_cancel(e)
		switch m {
		case .Commands:
			run(e, .Trig_Delete)
			press(e, .Green)
		case .Mouse:
			click_rect(e, TRIG_DELETE_BUTTON)
			click_rect(e, TRIG_DELETE_BUTTON)
		}
		testing.expectf(t, world.trigger_count == 3, "%v delete", m)
		switch m {
		case .Commands:
			run(e, .Layer)
		case .Mouse:
			click_rect(e, LAYER_BUTTON)
		}
		testing.expectf(t, e.layer == .Terrain, "%v layer", m) // the layer after triggers is the first
		e.layer = .Triggers
		switch m {
		case .Commands:
			e.mode = .Draw
			press(e, .Red)
		case .Mouse:
			click_rect(e, BACK_BUTTON)
		}
		testing.expectf(t, e.exit_requested, "%v leave", m)
		free_both(e, world)
	}
}

@(test)
test_triggers_are_drawn_and_the_layer_texts_fit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Colour_Log
	defer delete(log.colors)
	defer delete(log.rects)
	r := colour_renderer(&log)
	e, world := trig_editor()
	defer free_both(e, world)
	world.palette[9] = {10, 200, 30}
	for i in 0 ..< world.tilesets[0].count {
		cm.image4_set(&world.tilesets[0].images[i], 0, 0, 9)
	}
	cell := cell_rect(e, 3, 2)
	for layer in Layer {
		e.layer = layer
		clear(&log.colors)
		clear(&log.rects)
		editor_draw(e, &r)
		inside := 0
		for rc, i in log.rects {
			if rc.x >= cell.x && rc.y >= cell.y && rc.x + rc.w <= cell.x + cell.w + 1 && rc.y + rc.h <= cell.y + cell.h + 1 && log.colors[i] == (cm.Color{10, 200, 30}) {
				inside += 1
			}
		}
		testing.expectf(t, inside > 0, "%v: the trigger's sprite is not on its cell", layer)
	}
	e.layer = .Triggers
	for mode in ([]Mode{.Draw, .Setup}) {
		e.mode = mode
		testing.expect(t, cm.text_is_drawable(banner_text(e)) && BANNER.x + 4 + cm.text_width(banner_text(e)) <= BANNER.x + BANNER.w)
		lines, n := help_lines(e)
		for line in lines[:n] {
			testing.expectf(t, cm.text_is_drawable(line) && 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help: %s", line)
		}
	}
	for note in ([]string{NOTE_NO_TRIGGERS, NOTE_NEED_TRIGGER_TYPE, NOTE_NOT_HERE, NOTE_TRIGGER_FULL}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 2, "note: %s", note)
	}
	for b in trig_buttons() {
		testing.expectf(t, cm.text_width(b.txt) <= b.rc.w - 2 && cm.text_is_drawable(b.txt), "label %s", b.txt)
	}
	for word in ([]string{"TRIGGER", "TYPE", "HERE", "PLACE", "NO PLACE", "AT 63,63"}) {
		testing.expect(t, cm.text_is_drawable(word))
	}
	// The busiest map draws on screen at every zoom.
	big: Draw_Log
	lr := logging_renderer(&big)
	for world.trigger_count < cm.WORLD_MAX_TRIGGERS {
		cm.world_add_trigger(world, world.trigger_count % 2)
	}
	cm.world_map_set_size(world, 0, 64, 64)
	for k in 0 ..< cm.WORLD_MAX_TRIGGERS {
		cm.world_place_trigger(world, world.triggers[k].uuid, 0, k % 64, (k / 64) % 64)
	}
	for zoom in 0 ..< 8 {
		e.zoom = zoom
		for pos in ([][2]int{{0, 0}, {63, 31}}) {
			e.cx, e.cy = pos.x, pos.y
			press(e, .Left, .Right)
			big = {}
			editor_draw(e, &lr)
			testing.expectf(t, big.out_of_bounds == 0 && big.presents == 1, "zoom %d at %v", zoom, pos)
		}
	}
}
