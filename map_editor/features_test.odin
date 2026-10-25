#+build !js
package map_editor

import cm "../common"
import "core:testing"

// The character world plus feature types "tree" (slime sprite) and "rock" (bat sprite) and features
// Oak (tree, at 2,1), Boulder (rock, off the map) and Stump (tree, off the map). Goo (a character) is
// at 1,0.
feat_world :: proc(w := 6, h := 4) -> ^cm.World {
	world := char_world(w, h)
	tree := cm.world_add_feature_type(world, "tree")
	rock := cm.world_add_feature_type(world, "rock")
	cm.name_assign(&world.feature_types[rock].sprite, "bat")
	for spec in ([][2]string{{"Oak", "tree"}, {"Boulder", "rock"}, {"Stump", "tree"}}) {
		n := cm.world_add_feature(world, spec[1] == "rock" ? rock : tree)
		cm.name_assign(&world.features[n].name, spec[0])
	}
	cm.world_place_feature(world, 0, 2, 1, world.features[0].uuid)
	return world
}

// An editor in the Features layer.
feat_editor :: proc(w := 6, h := 4) -> (e: ^Editor, world: ^cm.World) {
	world = feat_world(w, h)
	e = new(Editor)
	editor_begin(e, world, 0)
	toggle_layer(e) // characters
	toggle_layer(e) // features
	return
}

goto_cell :: proc(e: ^Editor, x, y: int) {
	e.cx, e.cy = x, y
}

@(test)
test_green_places_picks_and_refuses_in_the_features_layer :: proc(t: ^testing.T) {
	e, world := feat_editor()
	defer free_both(e, world)
	testing.expect_value(t, e.layer, Layer.Features)
	oak, boulder := world.features[0].uuid, world.features[1].uuid
	// Green on the oak picks it up; on an empty cell it puts the current feature there.
	goto_cell(e, 2, 1)
	press(e, .Green)
	testing.expect_value(t, e.cur_feat, 0)
	testing.expect(t, !e.dirty)
	goto_cell(e, 3, 2)
	press(e, .Green)
	testing.expect(t, e.dirty && cm.world_feature_at(world, 0, 3, 2) == 0 && cm.world_feature_at(world, 0, 2, 1) == -1) // the oak moved
	// Another feature: pick Boulder, place it; a cell holding a feature cannot take a second one.
	step_feature(e, 1)
	testing.expect_value(t, e.cur_feat, 1)
	goto_cell(e, 5, 3)
	press(e, .Green)
	testing.expect_value(t, cm.world_feature_at(world, 0, 5, 3), 1)
	// A cell with a character refuses a feature, and says so; so does the Characters layer the other way.
	goto_cell(e, 1, 0) // Goo
	step_feature(e, 1) // Stump
	press(e, .Green)
	testing.expect(t, e.note == NOTE_CELL_CHARACTER && cm.world_feature_at(world, 0, 1, 0) == -1)
	e.layer = .Characters
	e.mode = .Draw
	e.cur_char = 1 // Flap
	goto_cell(e, 3, 2) // the oak is there now
	e.note = ""
	press(e, .Green) // picks nothing (no character): the cell holds a feature, so placing is refused
	testing.expect(t, e.note == NOTE_CELL_FEATURE && cm.world_character_at(world, 0, 3, 2) == -1)
	_ = oak
	_ = boulder
}

@(test)
test_features_layer_setup_rows_new_rename_type_unplace_delete :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := feat_editor()
	defer free_both(e, world)
	press(e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Setup)
	// Type of the current feature (Oak, a tree) steps to the next type.
	goto_row(e, .Feat_Type)
	press(e, .Right)
	testing.expect_value(t, cm.name_str(&world.features[0].type), "rock")
	press(e, .Left)
	testing.expect_value(t, cm.name_str(&world.features[0].type), "tree")
	// Feature row steps through the table and the cursor follows a placed one.
	goto_row(e, .Feature)
	press(e, .Right)
	testing.expect_value(t, e.cur_feat, 1)
	press(e, .Left)
	testing.expect(t, e.cur_feat == 0 && e.cx == 2 && e.cy == 1)
	// Unplace.
	run(e, .Feat_Unplace)
	testing.expect(t, cm.world_feature_at(world, 0, 2, 1) == -1 && e.dirty)
	e.note = ""
	run(e, .Feat_Unplace)
	testing.expect_value(t, e.note, NOTE_NOT_PLACED)
	// New: a feature of the current type at the cursor (free cell), then named with the keypad.
	e.cx, e.cy = 0, 3
	run(e, .Feat_New)
	testing.expect_value(t, e.mode, Mode.Text)
	name_typed_in_map(e, "Gate")
	testing.expect(t, e.mode == .Setup && world.feature_count == 4 && feature_name(e, 3) == "Gate")
	testing.expect_value(t, cm.world_feature_at(world, 0, 0, 3), 3)
	// Rename.
	run(e, .Feat_Rename)
	name_typed_in_map(e, "Door")
	testing.expect_value(t, feature_name(e, 3), "Door")
	run(e, .Feat_Rename)
	keypad_cancel(e)
	testing.expect_value(t, feature_name(e, 3), "Door")
	// Delete needs a second press and takes the feature off the map.
	run(e, .Feat_Delete)
	testing.expect(t, e.confirm_delete && world.feature_count == 4)
	press(e, .Up) // anything else cancels
	testing.expect(t, !e.confirm_delete)
	e.row = .Feat_Delete
	press(e, .Green, .Green)
	testing.expect(t, world.feature_count == 3 && cm.world_feature_at(world, 0, 0, 3) == -1)
	// With no feature types New says so; with no features everything else does.
	world.feature_type_count = 0
	e.note = ""
	run(e, .Feat_New)
	testing.expect_value(t, e.note, NOTE_NEED_FEATURE_TYPE)
	world.feature_count = 0
	e.note = ""
	run(e, .Feat_Rename)
	testing.expect_value(t, e.note, NOTE_NO_FEATURES)
	e.note = ""
	run(e, .Feat_Unplace)
	testing.expect_value(t, e.note, NOTE_NO_FEATURES)
}

@(test)
test_the_features_layer_cycles_and_tags_a_feature :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := feat_editor()
	defer free_both(e, world)
	cm.world_toggle_feature_type_tag(world, 0, cm.TAG_SOLID) // trees are solid
	water := cm.world_add_tag(world, "water")
	press(e, .Yellow)
	run(e, .Tags)
	testing.expect_value(t, e.mode, Mode.Tags)
	view := tag_view(e)
	testing.expect(t, view.inherited & cm.tag_bit(cm.TAG_SOLID) != 0 && view.set == 0 && view.instance)
	press(e, .Green) // tag 0 (solid): inherit -> set
	testing.expect(t, world.features[0].tags_set & cm.tag_bit(cm.TAG_SOLID) != 0 && e.dirty)
	press(e, .Green) // -> cleared
	testing.expect(t, world.features[0].tags_cleared & cm.tag_bit(cm.TAG_SOLID) != 0)
	press(e, .Down, .Green) // the water tag
	testing.expect(t, world.features[0].tags_set & cm.tag_bit(water) != 0)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.Setup)
	// The terrain layer's tags are the cell's, as before.
	toggle_layer(e) // items
	toggle_layer(e) // triggers
	toggle_layer(e)
	testing.expect_value(t, e.layer, Layer.Terrain)
	e.mode = .Setup
	run(e, .Tags)
	testing.expect(t, !tag_view(e).instance || tag_view(e).set == 0)
	press(e, .Red)
	// No feature, no tags screen.
	e.layer = .Features
	world.feature_count = 0
	e.mode = .Setup
	e.note = ""
	run(e, .Tags)
	testing.expect(t, e.mode == .Setup && e.note == NOTE_NO_FEATURES)
}

@(test)
test_every_features_layer_function_is_reachable_by_each_input :: proc(t: ^testing.T) {
	for m in Input_Method {
		e, world := feat_editor()
		// Pick (right click on the oak's cell, or the picker), then place at a free cell.
		oak := cell_rect(e, 2, 1)
		switch m {
		case .Commands:
			goto_cell(e, 2, 1)
			press(e, .Green)
		case .Mouse:
			editor_handle_event(e, cm.Mouse_Button_Event{button = .Right, x = oak.x + 2, y = oak.y + 2, down = true})
		}
		testing.expectf(t, e.cur_feat == 0, "%v pick", m)
		free_cell := cell_rect(e, 4, 2)
		switch m {
		case .Commands:
			goto_cell(e, 4, 2)
			press(e, .Green)
		case .Mouse:
			click_at(e, free_cell.x + 2, free_cell.y + 2)
		}
		testing.expectf(t, cm.world_feature_at(world, 0, 4, 2) == 0, "%v place", m)
		// The picker chooses another feature.
		e.mode = .Draw
		switch m {
		case .Commands:
			press(e, .Blue) // next page: wraps to the same one with 3 features
			e.cur_feat = 0
			step_feature(e, 1)
		case .Mouse:
			slot := picker_rect(1)
			click_at(e, slot.x + 2, slot.y + 2)
		}
		testing.expectf(t, e.cur_feat == 1, "%v picker", m)
		// Type -/+, new, unplace, rename (keypad), delete (twice), layer, back.
		switch m {
		case .Commands:
			goto_row(e, .Feat_Type)
			press(e, .Right)
		case .Mouse:
			click_rect(e, COLUMNS_PLUS)
		}
		testing.expectf(t, cm.name_str(&world.features[1].type) == "tree", "%v type", m)
		switch m {
		case .Commands:
			run(e, .Feat_New)
		case .Mouse:
			click_rect(e, FEAT_NEW_BUTTON)
		}
		testing.expectf(t, e.mode == .Text && world.feature_count == 4, "%v new", m)
		keypad_cancel(e)
		switch m {
		case .Commands:
			run(e, .Feat_Unplace)
		case .Mouse:
			click_rect(e, FEAT_UNPLACE_BUTTON)
		}
		_, _, _, still_placed := cm.world_feature_location(world, world.features[3].uuid)
		testing.expectf(t, !still_placed, "%v unplace", m) // the new feature went off the map
		switch m {
		case .Commands:
			run(e, .Feat_Rename)
		case .Mouse:
			click_rect(e, FEAT_RENAME_BUTTON)
		}
		testing.expectf(t, e.mode == .Text, "%v rename", m)
		keypad_cancel(e)
		switch m {
		case .Commands:
			run(e, .Feat_Delete)
			press(e, .Green)
		case .Mouse:
			click_rect(e, FEAT_DELETE_BUTTON)
			click_rect(e, FEAT_DELETE_BUTTON)
		}
		testing.expectf(t, world.feature_count == 3, "%v delete", m)
		switch m {
		case .Commands:
			run(e, .Layer)
		case .Mouse:
			click_rect(e, LAYER_BUTTON)
		}
		testing.expectf(t, e.layer == .Items, "%v layer", m) // the next layer after features
		e.layer = .Features
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
test_features_are_drawn_over_the_terrain_and_the_layer_texts_fit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	log: Colour_Log
	defer delete(log.colors)
	defer delete(log.rects)
	r := colour_renderer(&log)
	e, world := feat_editor()
	defer free_both(e, world)
	world.palette[9] = {10, 200, 30} // a colour only the creatures' tile uses
	for i in 0 ..< world.tilesets[0].count {
		cm.image4_set(&world.tilesets[0].images[i], 0, 0, 9)
	}
	cell := cell_rect(e, 2, 1) // the oak
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
		testing.expectf(t, inside > 0, "%v: the oak's sprite is not on its cell", layer)
	}
	// Texts: banner, help (both modes), notes, row labels and buttons are in the font and fit.
	e.layer = .Features
	for mode in ([]Mode{.Draw, .Setup}) {
		e.mode = mode
		testing.expect(t, cm.text_is_drawable(banner_text(e)) && BANNER.x + 4 + cm.text_width(banner_text(e)) <= BANNER.x + BANNER.w)
		lines, n := help_lines(e)
		for line in lines[:n] {
			testing.expectf(t, cm.text_is_drawable(line) && 8 + cm.text_width(line) <= cm.SCREEN_W - 8, "help: %s", line)
		}
	}
	for note in ([]string{NOTE_NO_FEATURES, NOTE_NEED_FEATURE_TYPE, NOTE_CELL_CHARACTER, NOTE_FEATURE_FULL}) {
		testing.expectf(t, cm.text_is_drawable(note) && INFO_X + cm.text_width(note) <= cm.SCREEN_W - 2, "note: %s", note)
	}
	for b in feat_buttons() {
		testing.expectf(t, cm.text_width(b.txt) <= b.rc.w - 2 && cm.text_is_drawable(b.txt), "label %s", b.txt)
	}
	for word in ([]string{"FEATURE", "TYPE", "TAGS", "PLACE", "ZOOM", "NONE", "OFF MAP", "AT 63,63"}) {
		testing.expect(t, cm.text_is_drawable(word))
	}
	rects := make([dynamic]Rect, context.temp_allocator)
	for b in feat_buttons() {
		append(&rects, b.rc)
	}
	append(&rects, Rect{PICKER_X, PICKER_Y, PICKER_COLS * PICKER_PITCH - 1, PICKER_ROWS * PICKER_PITCH - 1})
	for a, i in rects {
		for b, j in rects {
			if i < j {
				testing.expectf(t, !(a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h), "rects %d and %d overlap", i, j)
			}
		}
	}
	// The busiest map (every feature type and 2048 features) draws on screen at every zoom.
	big: Draw_Log
	lr := logging_renderer(&big)
	for world.feature_count < cm.WORLD_MAX_FEATURES {
		cm.world_add_feature(world, world.feature_count % 2)
	}
	cm.world_map_set_size(world, 0, 64, 64)
	for k in 0 ..< cm.WORLD_MAX_FEATURES {
		cm.world_place_feature(world, 0, k % 64, (k / 64) % 64, world.features[k].uuid)
	}
	for zoom in 0 ..< 8 {
		e.zoom = zoom
		for pos in ([][2]int{{0, 0}, {63, 31}}) {
			e.cx, e.cy = pos.x, pos.y
			press(e, .Left, .Right) // moves the view to follow the cursor
			big = {}
			editor_draw(e, &lr)
			testing.expectf(t, big.out_of_bounds == 0 && big.presents == 1, "zoom %d at %v", zoom, pos)
		}
	}
}

@(test)
test_the_delete_and_rename_buttons_are_not_dimmed_on_a_non_square_map :: proc(t: ^testing.T) {
	log: Colour_Log
	defer delete(log.colors)
	defer delete(log.rects)
	r := colour_renderer(&log)
	// The layers' buttons share places with the terrain layer's turn buttons, which a non-square map dims.
	e, world := feat_editor(6, 4)
	defer free_both(e, world)
	for layer in ([]Layer{.Features, .Characters}) {
		e.layer = layer
		clear(&log.colors)
		clear(&log.rects)
		editor_draw(e, &r)
		for button in ([]Rect{CHAR_DELETE_BUTTON, layer == .Features ? FEAT_RENAME_BUTTON : CHAR_PLAYER_BUTTON}) {
			bright := 0
			for rc, i in log.rects {
				if rc.x >= button.x && rc.y >= button.y && rc.x + rc.w <= button.x + button.w && rc.y + rc.h <= button.y + button.h && log.colors[i] == TEXT {
					bright += 1
				}
			}
			testing.expectf(t, bright > 0, "%v: the button at %d,%d is dimmed", layer, button.x, button.y)
		}
	}
}
