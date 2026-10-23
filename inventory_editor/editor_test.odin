#+build !js
package inventory_editor

import cm "../common"
import "core:testing"

// A world (tile size 4) with tileset "a", sprite set "things" (sword, coin), terrain set "land", map
// "m" (3 x 3), character "Hero", item types "sword" (never stacks; damage 5, durability 100), "gold"
// (stacks to 100) and "potion" (stacks to 10, no properties). Hero carries a sword.
make_world :: proc() -> ^cm.World {
	w := new(cm.World)
	cm.world_reset(w)
	cm.world_seed_uuids(w, 9)
	cm.world_set_tile_size(w, 4, 4)
	a := cm.world_add_tileset(w, "a")
	for k in 0 ..< 3 {
		n := cm.tileset_insert_blank(&w.tilesets[a], k, "a0")
		cm.image4_set(&w.tilesets[a].images[n], k, 0, k + 1)
	}
	ts := cm.world_add_terrain_set(w, "land")
	cm.name_assign(&w.sets[ts].terrains[0].name, "grass")
	things := cm.world_add_sprite_set(w, "things")
	for name in ([]string{"sword", "coin"}) {
		n := cm.world_add_sprite(w, things)
		cm.name_assign(&w.sprite_sets[things].sprites[n].name, name)
	}
	cm.world_add_map(w, ts, "m")
	sword := cm.world_add_item_type(w, "sword")
	cm.world_item_type_add_prop(w, sword, "damage", 5)
	cm.world_item_type_add_prop(w, sword, "durability", 100)
	gold := cm.world_add_item_type(w, "gold")
	cm.world_set_item_type_max_stack(w, gold, 100)
	potion := cm.world_add_item_type(w, "potion")
	cm.world_set_item_type_max_stack(w, potion, 10)
	ct := cm.world_add_char_type(w, "hero")
	hero := cm.world_add_character(w, ct)
	cm.name_assign(&w.characters[hero].name, "Hero")
	cm.world_owner_add(w, cm.owner_character(w.characters[hero].uuid), sword, 1)
	return w
}

hero_owner :: proc(w: ^cm.World) -> cm.Inventory_Owner {
	return cm.owner_character(w.characters[0].uuid)
}

new_editor :: proc(owner_is_hero := true) -> (e: ^Editor, world: ^cm.World) {
	world = make_world()
	e = new(Editor)
	editor_begin(e, world, owner_is_hero ? hero_owner(world) : cm.owner_cell(0, 1, 1))
	return
}

free_both :: proc(e: ^Editor, world: ^cm.World) {
	free(e)
	free(world)
}

press :: proc(e: ^Editor, actions: ..cm.Action) {
	for a in actions {
		editor_handle_event(e, cm.Command{action = a})
	}
}

click_at :: proc(e: ^Editor, x, y: int) {
	editor_handle_event(e, cm.Mouse_Button_Event{x = x, y = y, button = .Left, down = true})
	editor_handle_event(e, cm.Mouse_Button_Event{x = x, y = y, button = .Left, down = false})
}

click_rect :: proc(e: ^Editor, rc: Rect) {
	click_at(e, rc.x + rc.w / 2, rc.y + rc.h / 2)
}

click_row :: proc(e: ^Editor, row: int) {
	rc := list_row_rect(row)
	click_at(e, rc.x + 20, rc.y + 3)
}

type_with_commands :: proc(e: ^Editor, text: string) {
	for i in 0 ..< len(text) {
		ch := text[i]
		if e.entry.row == cm.TEXT_ENTRY_ROWS - 1 {
			press(e, .Up)
		}
		tcol, trow := -1, -1
		for r in 0 ..< cm.TEXT_ENTRY_CHAR_ROWS {
			for c in 0 ..< cm.TEXT_ENTRY_COLS {
				if g, ok := cm.text_entry_char_at(c, r); ok && g == ch {
					tcol, trow = c, r
				}
			}
		}
		rights := (tcol - e.entry.col + cm.TEXT_ENTRY_COLS) % cm.TEXT_ENTRY_COLS
		downs := (trow - e.entry.row + cm.TEXT_ENTRY_ROWS) % cm.TEXT_ENTRY_ROWS
		for _ in 0 ..< rights {
			press(e, .Right)
		}
		for _ in 0 ..< downs {
			press(e, .Down)
		}
		press(e, .Green)
	}
}

press_keypad_action :: proc(e: ^Editor, a: cm.Text_Entry_Action) {
	if e.mode != .Text {
		return
	}
	for e.entry.row != cm.TEXT_ENTRY_ROWS - 1 {
		press(e, .Down)
	}
	for cm.text_entry_action_at(e.entry.col) != a {
		press(e, .Right)
	}
	press(e, .Green)
}

// Replaces the keypad's text with `text` and presses DONE.
typed :: proc(e: ^Editor, text: string) {
	if e.mode != .Text {
		return // (never loop on a missing keypad: the test's own expectations say what went wrong)
	}
	for e.entry.len > 0 {
		press_keypad_action(e, .Backspace)
	}
	type_with_commands(e, text)
	press_keypad_action(e, .Done)
}

@(test)
test_an_owner_without_items_shows_only_the_new_row :: proc(t: ^testing.T) {
	e, world := new_editor(false)
	defer free_both(e, world)
	testing.expect(t, e.mode == .List && entry_count(e) == 0 && list_rows(e) == 1 && current_entry(e) == nil)
	press(e, .Left, .Right, .Yellow, .Blue, .Up, .Down) // nothing to change
	testing.expect(t, e.mode == .List && !e.confirm_delete && !e.dirty && world.inventory_count == 1)
	testing.expect_value(t, owner_text(e), "CELL 1,1 OF m")
	press(e, .Green) // the NEW row: the item types
	testing.expect_value(t, e.mode, Mode.Types)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.List)
	press(e, .Red)
	testing.expect(t, e.exit_requested)
	// Without item types there is nothing to add.
	e2, w2 := new_editor(false)
	defer free_both(e2, w2)
	w2.item_type_count = 0
	press(e2, .Green)
	testing.expect(t, e2.mode == .List && e2.note == NOTE_NO_TYPES)
}

@(test)
test_adding_items_joins_matching_stacks_and_selects_where_they_went :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor(false)
	defer free_both(e, world)
	press(e, .Green, .Down, .Green) // gold
	testing.expect(t, e.mode == .List && e.dirty && entry_count(e) == 1)
	testing.expect_value(t, cm.name_str(&current_entry(e).type), "gold")
	testing.expect_value(t, world.maps[0].inventories[1][1] != cm.UUID_NONE, true)
	testing.expect_value(t, world.maps[0].inventories[1][1] != cm.UUID_NONE, true)
}

@(test)
test_counts_change_by_one_or_are_typed_within_the_stack :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	// Hero's sword never stacks; add gold.
	press(e, .Down, .Green, .Down, .Green) // NEW row, gold (type 1)
	gold := current_entry(e)
	testing.expect_value(t, cm.name_str(&gold.type), "gold")
	testing.expect_value(t, gold.count, 1)
	press(e, .Right, .Right, .Left)
	testing.expect_value(t, gold.count, 2)
	for _ in 0 ..< 150 {
		press(e, .Right)
	}
	testing.expect_value(t, gold.count, 100) // the type's max stack
	for _ in 0 ..< 150 {
		press(e, .Left)
	}
	testing.expect_value(t, gold.count, 1)
	press(e, .Yellow)
	testing.expect_value(t, e.mode, Mode.Text)
	typed(e, "57")
	testing.expect(t, e.mode == .List && gold.count == 57)
	press(e, .Yellow)
	typed(e, "0")
	testing.expect(t, e.mode == .Text)
	typed(e, "101")
	testing.expect(t, e.mode == .Text)
	typed(e, "x")
	testing.expect(t, e.mode == .Text)
	press_keypad_action(e, .Cancel)
	testing.expect(t, e.mode == .List && gold.count == 57)
	// The sword is stuck at one.
	press(e, .Up)
	sword := current_entry(e)
	testing.expect_value(t, cm.name_str(&sword.type), "sword")
	press(e, .Right, .Left)
	testing.expect_value(t, sword.count, 1)
	press(e, .Yellow)
	typed(e, "2")
	testing.expect(t, e.mode == .Text && sword.count == 1)
}

@(test)
test_adding_the_same_type_again_adds_to_its_stack_and_swords_stay_apart :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	add :: proc(e: ^Editor, type_row: int) {
		press(e, .Down, .Down, .Down, .Down, .Down) // the NEW row
		e.sel = entry_count(e)
		press(e, .Green) // the types
		e.type_sel = type_row
		press(e, .Green)
	}
	add(e, 1)
	add(e, 1)
	add(e, 1)
	testing.expect(t, entry_count(e) == 2 && current_entry(e).count == 3) // sword, gold x3
	add(e, 0)
	testing.expect(t, entry_count(e) == 3 && cm.name_str(&current_entry(e).type) == "sword" && current_entry(e).count == 1)
	add(e, 2)
	testing.expect_value(t, entry_count(e), 4)
	testing.expect_value(t, e.sel, 3)
}

@(test)
test_properties_are_changed_typed_and_reset :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	sword := current_entry(e)
	press(e, .Green)
	testing.expect_value(t, e.mode, Mode.Props)
	testing.expect_value(t, prop_rows(e), 2)
	press(e, .Right, .Right, .Left)
	testing.expect(t, e.dirty && cm.world_entry_value(world, sword, 0) == 6 && sword.overrides.mask == 1)
	press(e, .Left) // back to the default: no override kept
	testing.expect(t, cm.world_entry_value(world, sword, 0) == 5 && sword.overrides.mask == 0)
	press(e, .Down, .Green)
	testing.expect_value(t, e.mode, Mode.Text)
	typed(e, "-40")
	testing.expect(t, e.mode == .Props && cm.world_entry_value(world, sword, 1) == -40)
	press(e, .Green)
	typed(e, "abc")
	testing.expect(t, e.mode == .Text)
	typed(e, "99999999999")
	testing.expect(t, e.mode == .Text)
	press_keypad_action(e, .Cancel)
	testing.expect_value(t, cm.world_entry_value(world, sword, 1), -40)
	press(e, .Yellow)
	testing.expect(t, cm.world_entry_value(world, sword, 1) == 100 && sword.overrides.mask == 0)
	press(e, .Up, .Up, .Up)
	testing.expect_value(t, e.prop_sel, 0)
	press(e, .Red)
	testing.expect_value(t, e.mode, Mode.List)
	// An entry whose type has no properties says so.
	press(e, .Down, .Green, .Down, .Down, .Green) // NEW row, types, potion
	testing.expect_value(t, cm.name_str(&current_entry(e).type), "potion")
	press(e, .Green)
	testing.expect(t, e.mode == .List && e.note == NOTE_NO_PROPS)
}

@(test)
test_delete_needs_blue_then_green_and_the_last_entry_takes_the_inventory :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	testing.expect_value(t, world.inventory_count, 1)
	press(e, .Blue)
	testing.expect(t, e.confirm_delete && banner_text(e) == "DELETE THE ENTRY?  GREEN: CONFIRM")
	press(e, .Down) // anything else cancels
	testing.expect(t, !e.confirm_delete && entry_count(e) == 1)
	press(e, .Up, .Blue, .Green)
	testing.expect(t, entry_count(e) == 0 && e.dirty && world.inventory_count == 0 && world.entry_count == 0)
	testing.expect_value(t, cm.world_owner_inventory(world, hero_owner(world)), cm.UUID_NONE)
	testing.expect_value(t, e.mode, Mode.List)
	testing.expect_value(t, list_rows(e), 1)
	// The same by mouse.
	press(e, .Green, .Green) // gold
	click_rect(e, DELETE_BUTTON)
	testing.expect(t, e.confirm_delete && entry_count(e) == 1)
	click_rect(e, DELETE_BUTTON)
	testing.expect_value(t, entry_count(e), 0)
}

@(test)
test_everything_is_reachable_by_mouse :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	// NEW row, a type, then the count buttons.
	click_rect(e, NEW_BUTTON)
	testing.expect_value(t, e.mode, Mode.Types)
	click_row(e, 1) // select gold
	testing.expect_value(t, e.type_sel, 1)
	click_row(e, 1) // again: use it
	testing.expect(t, e.mode == .List && cm.name_str(&current_entry(e).type) == "gold")
	click_rect(e, PLUS)
	click_rect(e, PLUS)
	click_rect(e, MINUS)
	testing.expect_value(t, current_entry(e).count, 2)
	click_rect(e, COUNT_BUTTON)
	typed(e, "9")
	testing.expect_value(t, current_entry(e).count, 9)
	// Rows: select the sword, again opens its properties.
	click_row(e, 0)
	testing.expect(t, e.sel == 0 && e.mode == .List)
	click_row(e, 0)
	testing.expect_value(t, e.mode, Mode.Props)
	click_rect(e, PLUS)
	click_rect(e, PLUS)
	testing.expect_value(t, cm.world_entry_value(world, current_entry(e), 0), 7)
	click_rect(e, PROPS_BUTTON) // DEFAULT
	testing.expect_value(t, cm.world_entry_value(world, current_entry(e), 0), 5)
	click_row(e, 1)
	click_row(e, 1) // again: type the value
	testing.expect_value(t, e.mode, Mode.Text)
	typed(e, "12")
	testing.expect_value(t, cm.world_entry_value(world, current_entry(e), 1), 12)
	click_rect(e, COUNT_BUTTON)
	typed(e, "13")
	testing.expect_value(t, cm.world_entry_value(world, current_entry(e), 1), 13)
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.List)
	click_rect(e, PROPS_BUTTON)
	testing.expect_value(t, e.mode, Mode.Props)
	click_rect(e, BACK_BUTTON)
	// The NEW row by clicking the selected row; BACK from Types; BACK leaves.
	click_row(e, 2)
	click_row(e, 2)
	testing.expect_value(t, e.mode, Mode.Types)
	click_rect(e, BACK_BUTTON)
	testing.expect_value(t, e.mode, Mode.List)
	click_rect(e, BACK_BUTTON)
	testing.expect(t, e.exit_requested)
	// The wheel scrolls long lists.
	for _ in 0 ..< 40 {
		cm.world_owner_add(world, hero_owner(world), 0, 1)
	}
	editor_handle_event(e, cm.Mouse_Wheel{dy = -3})
	testing.expect_value(t, e.scroll, 3)
	editor_handle_event(e, cm.Mouse_Wheel{dy = 50})
	testing.expect_value(t, e.scroll, 0)
}

@(test)
test_the_list_scrolls_with_the_selection_and_stops_at_256_entries :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	e, world := new_editor()
	defer free_both(e, world)
	for entry_count(e) < cm.INVENTORY_MAX_ENTRIES {
		cm.world_owner_add(world, hero_owner(world), 0, 1) // swords never stack
	}
	testing.expect_value(t, list_rows(e), cm.INVENTORY_MAX_ENTRIES) // no NEW row any more
	for _ in 0 ..< 300 {
		press(e, .Down)
	}
	testing.expect_value(t, e.sel, cm.INVENTORY_MAX_ENTRIES - 1)
	testing.expect_value(t, e.scroll, cm.INVENTORY_MAX_ENTRIES - LIST_ROWS)
	for _ in 0 ..< 300 {
		press(e, .Up)
	}
	testing.expect(t, e.sel == 0 && e.scroll == 0)
	// A full inventory refuses another item type's entry.
	e.mode = .Types
	e.type_sel = 1
	press(e, .Green)
	testing.expect(t, e.mode == .List && e.note == NOTE_FULL && entry_count(e) == cm.INVENTORY_MAX_ENTRIES)
	// Deleting one makes room for the NEW row again.
	press(e, .Blue, .Green)
	testing.expect_value(t, list_rows(e), cm.INVENTORY_MAX_ENTRIES)
	testing.expect_value(t, entry_count(e), cm.INVENTORY_MAX_ENTRIES - 1)
}

@(test)
test_layout_text_and_drawing_fit_the_screen :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	rects := make([dynamic]Rect, context.temp_allocator)
	append(&rects, BANNER, Rect{LIST_X, LIST_Y, LIST_W, LIST_ROWS * LIST_PITCH}, MINUS, PLUS, COUNT_BUTTON, PROPS_BUTTON, NEW_BUTTON, DELETE_BUTTON, BACK_BUTTON, PREVIEW_FRAME)
	for a, i in rects {
		testing.expectf(t, a.x >= 0 && a.y >= 0 && a.x + a.w <= cm.SCREEN_W && a.y + a.h <= cm.SCREEN_H, "rect %d off screen", i)
		for b, j in rects {
			if i < j {
				overlap := a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
				testing.expectf(t, !overlap, "rects %d and %d overlap", i, j)
			}
		}
	}
	testing.expect(t, LIST_X + LIST_W < PANEL_X && LIST_Y + LIST_ROWS * LIST_PITCH <= HELP_Y)
	testing.expect(t, LIST_X + VALUE_X + cm.text_width("X1000000000") <= LIST_X + LIST_W)
	testing.expect(t, LIST_X + VALUE_X + 56 + cm.text_width("CHANGED") <= LIST_X + LIST_W + 4 || LIST_X + VALUE_X + 56 + cm.text_width("CHANGED") <= PANEL_X)
	testing.expect(t, LIST_X + NAME_X + NAME_CHARS * cm.text_width("W") <= LIST_X + VALUE_X)
	testing.expect(t, HELP_Y + MAX_HELP_LINES * cm.LINE_ADVANCE <= cm.SCREEN_H && PREVIEW_FRAME.y + PREVIEW_FRAME.h + 4 + cm.GLYPH_H <= BACK_BUTTON.y)
	// Every string the screens can show is in the font, and the lines fit.
	e, world := new_editor()
	defer free_both(e, world)
	cm.world_owner_add(world, hero_owner(world), 1, 77)
	for mode in Mode {
		if mode == .Text {
			continue
		}
		e.mode = mode
		for armed in ([]bool{false, true}) {
			e.confirm_delete = armed
			for text in ([]string{banner_text(e)}) {
				testing.expectf(t, cm.text_is_drawable(text) && cm.text_width(text) <= BANNER.w - 8, "%v banner %s", mode, text)
			}
		}
		lines, n := help_lines(e)
		for line in lines[:n] {
			testing.expectf(t, cm.text_is_drawable(line) && cm.text_width(line) <= cm.SCREEN_W - 16, "%v help %s", mode, line)
		}
		list, count := buttons(e)
		for b in list[:count] {
			testing.expectf(t, cm.text_is_drawable(b.text) && cm.text_width(b.text) <= b.rc.w - 2, "%v button %s", mode, b.text)
		}
	}
	for note in ([]string{NOTE_FULL, NOTE_NO_TYPES, NOTE_NO_PROPS, NOTE_NOT_NUMBER, NOTE_VALUE_RANGE, "1 TO 1000000000", "CHARACTER WWWWWWWWWWWWWWWWWWWW  256 ENTRIES *", "CELL 63,63 OF WWWWWWWWWWWWWWWW  256 ENTRIES *", "NEW ITEM", "CHANGED", "DEFAULT", "X1000000000"}) {
		testing.expectf(t, cm.text_is_drawable(note), "%s", note)
		if note[0] != 'X' && note[0] != 'N' && note[0] != 'C' || len(note) > 12 {
			testing.expectf(t, INFO_X + cm.text_width(note) <= cm.SCREEN_W, "%s is too wide", note)
		}
	}
	// Every mode draws inside the surface, with a full inventory too.
	for entry_count(e) < cm.INVENTORY_MAX_ENTRIES {
		cm.world_owner_add(world, hero_owner(world), 0, 1)
	}
	log: Draw_Log
	r := logging_renderer(&log)
	for mode in Mode {
		e.mode = mode
		e.sel, e.prop_sel, e.type_sel = 255, 1, 2
		fix_selection(e)
		if mode == .Text {
			cm.text_entry_begin(&e.entry, "HOW MANY", "12", 10)
		}
		log = {}
		editor_draw(e, &r)
		testing.expectf(t, log.out_of_bounds == 0 && log.presents == 1, "%v: %d off screen, %d presents", mode, log.out_of_bounds, log.presents)
	}
}

Draw_Log :: struct {
	rects, out_of_bounds, presents: int,
}

logging_renderer :: proc(l: ^Draw_Log) -> cm.Renderer {
	return cm.Renderer {
		data = l,
		clear = proc(d: rawptr, c: cm.Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: cm.Color) {
			k := (^Draw_Log)(d)
			k.rects += 1
			if x < 0 || y < 0 || x + w > cm.SCREEN_W || y + h > cm.SCREEN_H {
				k.out_of_bounds += 1
			}
		},
		present = proc(d: rawptr) {(^Draw_Log)(d).presents += 1},
	}
}
