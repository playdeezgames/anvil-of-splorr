package map_editor

import cm "../common"
import "core:fmt"

// The Items layer of the map editor, the fourth layer after Terrain, Characters and Features. A map
// cell can hold an inventory (see common/world_items.odin): the items lying there. This layer shows
// them on the map (the first entry's sprite, under features and characters, in every layer) and
// opens the inventory screen for the cell under the cursor; the screen itself belongs to the host
// (the world editor hosts the inventory editor), which learns about the request through
// `items_requested`.
//
//   Draw:  d-pad moves the cursor; green opens the cell's inventory screen; yellow opens Setup; red
//          leaves.
//   Setup: up/down choose a row (Open, Clear, Zoom, Layer); left/right change Zoom; green runs Open,
//          Clear (twice: the first asks) and Layer; red returns to Draw.
// The mouse: click a cell moves the cursor there and opens its inventory; right click only moves the
// cursor; the OPEN, CLEAR (second click confirms) and LAYER buttons and the zoom buttons.

NOTE_NOTHING_HERE :: "NOTHING LIES HERE"

// The inventory the cell under the cursor holds, or none.
cell_inventory :: proc(e: ^Editor) -> cm.Uuid {
	m := current_map(e)
	if e.cx < 0 || e.cy < 0 || e.cx >= m.width || e.cy >= m.height {
		return cm.UUID_NONE
	}
	return m.inventories[e.cy][e.cx]
}

// How many entries the cell under the cursor holds.
cell_entry_count :: proc(e: ^Editor) -> int {
	return cm.world_inventory_entry_count(e.world, cell_inventory(e))
}

// How many items (not entries) lie on the whole map.
map_item_total :: proc(e: ^Editor) -> (n: int) {
	m := current_map(e)
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			u := m.inventories[y][x]
			if uuid_none(u) {
				continue
			}
			for i in 0 ..< e.world.entry_count {
				if e.world.entries[i].inventory == u {
					n += e.world.entries[i].count
				}
			}
		}
	}
	return
}

@(private = "file")
uuid_none :: proc(u: cm.Uuid) -> bool {
	return cm.uuid_is_none(u)
}

// The cell under the cursor as the owner of its inventory (what the host opens).
cursor_owner :: proc(e: ^Editor) -> cm.Inventory_Owner {
	return cm.owner_cell(e.index, e.cx, e.cy)
}

@(private = "file")
open_items :: proc(e: ^Editor) {
	e.items_requested = true
}

// The first call asks (the banner says so); the next one throws the cell's items away.
@(private = "file")
clear_items :: proc(e: ^Editor) {
	if uuid_none(cell_inventory(e)) {
		e.note = NOTE_NOTHING_HERE
		e.confirm_delete = false
		return
	}
	if !e.confirm_delete {
		e.confirm_delete = true
		return
	}
	e.confirm_delete = false
	cm.world_owner_clear_inventory(e.world, cursor_owner(e))
	e.dirty = true
}

@(private = "file")
run_item_row :: proc(e: ^Editor, row: Setup_Row) {
	#partial switch row {
	case .Cell_Open:
		open_items(e)
	case .Cell_Clear:
		clear_items(e)
	case .Layer:
		toggle_layer(e)
	}
}

// Commands in the Items layer (Draw and Setup modes). Returns false for anything else.
item_action :: proc(e: ^Editor, a: cm.Action) -> bool {
	if !(e.mode == .Setup && e.row == .Cell_Clear && a == .Green) {
		e.confirm_delete = false
	}
	m := current_map(e)
	switch e.mode {
	case .Draw:
		#partial switch a {
		case .Up:
			e.cy = max(e.cy - 1, 0)
		case .Down:
			e.cy = min(e.cy + 1, m.height - 1)
		case .Left:
			e.cx = max(e.cx - 1, 0)
		case .Right:
			e.cx = min(e.cx + 1, m.width - 1)
		case .Green:
			open_items(e)
		case .Yellow:
			e.mode = .Setup
		case .Red:
			e.exit_requested = true
		}
		return true
	case .Setup:
		#partial switch a {
		case .Up:
			e.row = next_row(e, -1)
		case .Down:
			e.row = next_row(e, 1)
		case .Left:
			if e.row == .Zoom {
				step_zoom(e, -1)
			}
		case .Right:
			if e.row == .Zoom {
				step_zoom(e, 1)
			}
		case .Green:
			run_item_row(e, e.row)
		case .Red:
			e.mode = .Draw
		}
		return true
	case .Rect, .Text, .Tags:
	}
	return false
}

// Right click: move the cursor to the cell under the pointer (the screen opens with a left click).
item_pick :: proc(e: ^Editor, x, y: int) {
	if cx, cy, ok := cell_at(e, x, y); ok {
		e.cx, e.cy = cx, cy
	}
}

// A left click in the Items layer. Everything is handled here.
item_click :: proc(e: ^Editor, x, y: int) {
	if cx, cy, ok := cell_at(e, x, y); ok {
		e.cx, e.cy = cx, cy
		e.mode = .Draw
		open_items(e)
		return
	}
	if click_bars(e, x, y) {
		return
	}
	if !rect_contains(ITEM_CLEAR_BUTTON, x, y) {
		e.confirm_delete = false
	}
	action :: proc(e: ^Editor, row: Setup_Row) {
		e.mode, e.row = .Setup, row
		run_item_row(e, row)
	}
	switch {
	case rect_contains(ZOOM_MINUS, x, y):
		e.mode, e.row = .Setup, .Zoom
		step_zoom(e, -1)
	case rect_contains(ZOOM_PLUS, x, y):
		e.mode, e.row = .Setup, .Zoom
		step_zoom(e, 1)
	case rect_contains(ITEM_OPEN_BUTTON, x, y):
		action(e, .Cell_Open)
	case rect_contains(ITEM_CLEAR_BUTTON, x, y):
		action(e, .Cell_Clear) // a second click confirms
	case rect_contains(LAYER_BUTTON, x, y):
		toggle_layer(e)
	case rect_contains(BACK_BUTTON, x, y):
		e.exit_requested = true
	}
}

// "N ENTRIES" / "NOTHING" for the cell under the cursor.
cell_items_text :: proc(e: ^Editor) -> string {
	n := cell_entry_count(e)
	switch n {
	case 0:
		return "NOTHING"
	case 1:
		return "1 ENTRY"
	}
	return fmt.tprintf("%d ENTRIES", n)
}

// The lines of the list drawn where the picker is: the cell's entries, "TYPE X3", a few of them.
ITEM_LIST_LINES :: 4

item_list_line :: proc(e: ^Editor, n: int) -> string {
	if en := cm.world_owner_entry(e.world, cursor_owner(e), n); en != nil {
		name := cm.name_str(&en.type)
		return fmt.tprintf("%s X%d", name[:min(len(name), 20)], en.count)
	}
	return ""
}
