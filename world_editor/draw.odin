package world_editor

import cce "../character_editor"
import cm "../common"
import cte "../character_type_editor"
import me "../map_editor"
import pe "../palette_editor"
import spe "../sprite_editor"
import te "../tileset_editor"
import tre "../terrain_editor"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
DIM :: cm.Color{120, 120, 134}
HILITE :: cm.Color{255, 220, 80}
WARN :: cm.Color{235, 100, 90}

label :: proc(e: ^Editor, a: cm.Action) -> string {
	return cm.action_label(e.labels, a)
}

hub_label :: proc(row: Hub_Row) -> string {
	switch row {
	case .Palette:
		return "PALETTE"
	case .Tile_Width:
		return "TILE WIDTH"
	case .Tile_Height:
		return "TILE HEIGHT"
	case .Tags:
		return "TAGS"
	case .Params:
		return "PARAMS"
	case .Tilesets:
		return "TILESETS"
	case .Terrain_Sets:
		return "TERRAIN SETS"
	case .Sprite_Sets:
		return "SPRITE SETS"
	case .Character_Types:
		return "CHARACTER TYPES"
	case .Characters:
		return "CHARACTERS"
	case .Maps:
		return "MAPS"
	}
	return ""
}

section_title :: proc(s: Section) -> string {
	switch s {
	case .Tags:
		return "TAGS"
	case .Params:
		return "PARAMS"
	case .Tilesets:
		return "TILESETS"
	case .Terrain_Sets:
		return "TERRAIN SETS"
	case .Sprite_Sets:
		return "SPRITE SETS"
	case .Maps:
		return "MAPS"
	}
	return ""
}

// Strings are on the temp allocator: valid until the frontend's next free_all.
banner_text :: proc(e: ^Editor) -> string {
	if e.confirm_exit {
		return fmt.tprintf("UNSAVED   %s: LEAVE ANYWAY", label(e, .Red))
	}
	if e.confirm_rename {
		return fmt.tprintf("NEEDED BY THE GAME  %s: RENAME", label(e, .Green))
	}
	if e.confirm_delete {
		if e.section == .Tags && needed_index(e, selected(e)) >= 0 {
			return fmt.tprintf("NEEDED BY THE GAME  %s: DELETE", label(e, .Green))
		}
		return fmt.tprintf("DELETE IT?  %s: CONFIRM", label(e, .Green))
	}
	switch e.mode {
	case .Hub:
		return fmt.tprintf("WORLD   %s: OPEN", label(e, .Green))
	case .List:
		return fmt.tprintf("%s   %s: OPEN", section_title(e.section), label(e, .Green))
	case .Setup:
		return fmt.tprintf("ACTIONS   %s: DONE", label(e, .Red))
	case .File:
		return fmt.tprintf("FILE: %s SAVE  %s LOAD", label(e, .Green), label(e, .Yellow))
	case .Text, .Value, .Palette, .Tileset, .Terrain, .Sprite, .Char_Type, .Character, .Map:
		// These modes draw their own screens.
	}
	return ""
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .Hub:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE  %s/%s: TILE SIZE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)),
			fmt.tprintf("%s: OPEN THE PART", l(e, .Green)),
			fmt.tprintf("%s: SAVE / LOAD  %s: MAIN MENU", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK A ROW TO OPEN IT",
		}
		return lines, 4
	case .List:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: OPEN IT  %s: ACTIONS", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: BACK TO THE WORLD", l(e, .Red)),
			"MOUSE: CLICK AN ITEM, AGAIN TO OPEN; WHEEL SCROLLS",
		}
		return lines, 4
	case .Setup:
		lines = {
			fmt.tprintf("%s/%s: CHOOSE AN ACTION", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: RUN IT (DELETE: TWICE)", l(e, .Green)),
			fmt.tprintf("%s: DONE", l(e, .Red)),
			"",
		}
		return lines, 3
	case .File:
		lines = {fmt.tprintf("%s: SAVE  %s: LOAD", l(e, .Green), l(e, .Yellow)), fmt.tprintf("%s: CANCEL", l(e, .Red)), "", ""}
		return lines, 2
	case .Text, .Value, .Palette, .Tileset, .Terrain, .Sprite, .Char_Type, .Character, .Map:
	}
	return lines, 0
}

fill :: proc(r: ^cm.Renderer, rc: Rect, c: cm.Color) {
	cm.renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, c)
}

// The detail text of list item i ("12 IMAGES", "5 TERRAINS", "32X16").
item_detail :: proc(e: ^Editor, s: Section, i: int) -> string {
	switch s {
	case .Tags:
		return tag_detail(e, i)
	case .Params:
		p := &e.world.params[i]
		if p.kind == .Number {
			return cm.param_value_text(p)
		}
		text := cm.param_value_text(p)
		return fmt.tprintf("\"%s\"", len(text) > 12 ? text[:12] : text)
	case .Tilesets:
		n := e.world.tilesets[i].count
		return fmt.tprintf("%d IMAGE%s", n, n == 1 ? "" : "S")
	case .Terrain_Sets:
		n := e.world.sets[i].count
		return fmt.tprintf("%d TERRAIN%s", n, n == 1 ? "" : "S")
	case .Sprite_Sets:
		n := e.world.sprite_sets[i].count
		return fmt.tprintf("%d SPRITE%s", n, n == 1 ? "" : "S")
	case .Maps:
		return fmt.tprintf("%dX%d", e.world.maps[i].width, e.world.maps[i].height)
	}
	return ""
}

// The word at the right of a row of the Tags list: whether the game needs the tag and how it stands.
tag_detail :: proc(e: ^Editor, i: int) -> string {
	if is_missing_row(e, i) {
		return "MISSING"
	}
	needed := needed_index(e, i)
	switch {
	case needed >= 0 && cm.tag_is_reserved(i):
		return "FIXED, NEEDED"
	case needed >= 0:
		return cm.game_tag_status(&e.world, &e.game_tags, needed) == .Unused ? "NEEDED, UNUSED" : "NEEDED"
	case cm.tag_is_reserved(i):
		return "FIXED"
	}
	return ""
}

// One line about the selected item, shown under the banner.
item_info :: proc(e: ^Editor) -> string {
	n := section_count(e, e.section)
	if n == 0 {
		return fmt.tprintf("NO %s YET (0 OF %d)", section_title(e.section), section_limit(e.section))
	}
	i := selected(e)
	if e.section == .Tags && !e.confirm_delete {
		if note := needed_note(e, i); note != "" {
			return fmt.tprintf("%d OF %d  %s%s", i + 1, n, note, e.dirty ? "  *" : "")
		}
	}
	if e.confirm_delete && e.section == .Tags && i < e.world.tag_count {
		uses := cm.world_tag_uses(&e.world, i)
		return fmt.tprintf("THIS TAG IS USED BY %d THING%s", uses, uses == 1 ? "" : "S")
	}
	extra := ""
	if e.section == .Maps {
		extra = fmt.tprintf("  SET %s", cm.name_str(&e.world.maps[i].set))
	} else if e.section == .Terrain_Sets {
		extra = fmt.tprintf("  DEFAULT %s", cm.name_str(&e.world.sets[i].terrains[e.world.sets[i].default].name))
	}
	return fmt.tprintf("%d OF %d%s%s", i + 1, n, extra, e.dirty ? "  *" : "")
}

Button :: struct {
	rc:   Rect,
	text: string,
	row:  Maybe(Setup_Row),
}

// The game's one-line note about the tag in row i of the Tags list, cut to fit the info line.
needed_note :: proc(e: ^Editor, i: int) -> string {
	k := -1
	if is_missing_row(e, i) {
		k = cm.game_tag_find(&e.game_tags, missing_tag_name(e, i - e.world.tag_count))
	} else {
		k = needed_index(e, i)
	}
	note := cm.game_tag_note(&e.game_tags, k)
	return len(note) > 44 ? note[:44] : note
}

list_buttons :: proc() -> [7]Button {
	return {
		{OPEN_BUTTON, "OPEN", .Open},
		{RENAME_BUTTON, "RENAME", .Rename},
		{NEW_BUTTON, "NEW", .New},
		{DUPLICATE_BUTTON, "DUP", .Duplicate},
		{DELETE_BUTTON, "DEL", .Delete},
		{IMPORT_BUTTON, "IMPORT", .Import},
		{BACK_BUTTON, "BACK", nil},
	}
}

editor_draw :: proc(e: ^Editor, r: ^cm.Renderer) {
	switch e.mode {
	case .Text:
		cm.text_entry_draw(&e.entry, r, e.labels)
		return
	case .Value:
		draw_value(e, r)
		return
	case .Palette:
		pe.editor_draw(&e.palette_ed, r)
		return
	case .Tileset:
		te.editor_draw(&e.tileset_ed, r)
		return
	case .Terrain:
		tre.editor_draw(&e.terrain_ed, r)
		return
	case .Sprite:
		spe.editor_draw(&e.sprite_ed, r)
		return
	case .Char_Type:
		cte.editor_draw(&e.char_type_ed, r)
		return
	case .Character:
		cce.editor_draw(&e.character_ed, r)
		return
	case .Map:
		me.editor_draw(&e.map_ed, r)
		return
	case .Hub, .List, .Setup, .File:
	}
	cm.renderer_clear(r, BG)
	warning := e.confirm_exit || e.confirm_delete
	plain := e.mode == .Hub || e.mode == .List
	fill(r, BANNER, warning ? WARN : (plain ? PANEL : HILITE))
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, banner_text(e), (warning || !plain) ? BG : TEXT)

	if e.mode == .Hub || e.mode == .File {
		draw_hub(e, r)
	} else {
		draw_list(e, r)
	}

	lines, n := help_lines(e)
	for line, i in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + i * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}

draw_hub :: proc(e: ^Editor, r: ^cm.Renderer) {
	w := &e.world
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	} else {
		cm.draw_text(r, INFO_X, INFO_Y, e.dirty ? "UNSAVED CHANGES *" : "NO UNSAVED CHANGES", e.dirty ? TEXT : DIM)
	}
	for row in Hub_Row {
		y := HUB_Y + int(row) * HUB_PITCH
		color := e.mode == .Hub && e.hub == row ? HILITE : TEXT
		if e.mode == .Hub && e.hub == row {
			cm.draw_text(r, HUB_MARKER_X, y, ">", HILITE)
		}
		cm.draw_text(r, HUB_X, y, hub_label(row), color)
		switch row {
		case .Palette:
			for i in 0 ..< cm.PALETTE_SIZE {
				fill(r, Rect{HUB_VALUE_X + i * 8, y - 1, 8, 8}, w.palette[i])
			}
		case .Tile_Width:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d", w.tile_w), color)
		case .Tile_Height:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d", w.tile_h), color)
		case .Params:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d OF %d", w.param_count, cm.WORLD_MAX_PARAMS), color)
		case .Tags:
			text := fmt.tprintf("%d OF %d", w.tag_count, cm.WORLD_MAX_TAGS)
			cm.draw_text(r, HUB_VALUE_X, y, text, color)
			if missing := tags_missing(e); missing > 0 {
				cm.draw_text(r, HUB_VALUE_X + cm.text_width(text) + 8, y, fmt.tprintf("%d MISSING", missing), WARN)
			}
		case .Tilesets:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d OF %d", w.tileset_count, cm.WORLD_MAX_TILESETS), color)
		case .Terrain_Sets:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d OF %d", w.set_count, cm.WORLD_MAX_TERRAIN_SETS), color)
		case .Sprite_Sets:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d OF %d", w.sprite_set_count, cm.WORLD_MAX_SPRITE_SETS), color)
		case .Character_Types:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d OF %d", w.char_type_count, cm.WORLD_MAX_CHARACTER_TYPES), color)
		case .Characters:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d OF %d", w.character_count, cm.WORLD_MAX_CHARACTERS), color)
		case .Maps:
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d OF %d", w.map_count, cm.WORLD_MAX_MAPS), color)
		}
	}
	for b in ([4]struct {
			rc:  Rect,
			txt: string,
		}{{WIDTH_MINUS, "-"}, {WIDTH_PLUS, "+"}, {HEIGHT_MINUS, "-"}, {HEIGHT_PLUS, "+"}}) {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + 3, b.txt, TEXT)
	}
	for b in ([3]struct {
			rc:  Rect,
			txt: string,
		}{{SAVE_BUTTON, "SAVE"}, {LOAD_BUTTON, "LOAD"}, {MENU_BUTTON, "MENU"}}) {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + (b.rc.h - cm.GLYPH_H) / 2, b.txt, TEXT)
	}
}

draw_list :: proc(e: ^Editor, r: ^cm.Renderer) {
	n := section_count(e, e.section)
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	} else {
		cm.draw_text(r, INFO_X, INFO_Y, item_info(e), TEXT)
	}
	for row in 0 ..< LIST_ROWS {
		index := e.scroll + row
		if index >= n {
			break
		}
		rc := list_row_rect(row)
		isel := index == selected(e)
		if isel {
			fill(r, rc, e.mode == .List ? HILITE : PANEL)
		}
		color := isel && e.mode == .List ? BG : TEXT
		cm.draw_text(r, rc.x + 2, rc.y + 2, section_item_name(e, e.section, index), color)
		detail := item_detail(e, e.section, index)
		detail_color := isel && e.mode == .List ? BG : (detail == "MISSING" ? WARN : DIM)
		cm.draw_text(r, LIST_X + LIST_W - cm.text_width(detail) - 3, rc.y + 2, detail, detail_color)
	}
	for btn in list_buttons() {
		if btn.rc == IMPORT_BUTTON && e.section != .Tilesets && e.section != .Tags && e.section != .Params {
			continue
		}
		btn := btn
		if btn.rc == IMPORT_BUTTON && e.section == .Tags { 	// the same button creates the tags the game needs
			btn.text, btn.row = "CREATE", Setup_Row.Create
		}
		if btn.rc == IMPORT_BUTTON && e.section == .Params { 	// ... and switches a parameter between number and text
			btn.text, btn.row = "KIND", Setup_Row.Kind
		}
		lit := false
		if row, has := btn.row.?; has && e.mode == .Setup && e.row == row {
			lit = true
		}
		needs := btn.row != nil && btn.row != Setup_Row.New && btn.row != Setup_Row.Import && btn.row != Setup_Row.Create
		enabled := !needs || n > 0
		fill(r, btn.rc, lit ? HILITE : PANEL)
		cm.draw_text(r, btn.rc.x + (btn.rc.w - cm.text_width(btn.text)) / 2, btn.rc.y + (btn.rc.h - cm.GLYPH_H) / 2, btn.text, lit ? BG : (enabled ? TEXT : DIM))
	}
}
