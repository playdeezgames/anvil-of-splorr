package world_editor

import cce "../character_editor"
import fe "../feature_editor"
import fte "../feature_type_editor"
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
	case .Sounds:
		return "SOUNDS"
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
	case .Feature_Types:
		return "FEATURE TYPES"
	case .Features:
		return "FEATURES"
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
	case .Sounds:
		return "SOUNDS"
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
		if e.hub_level == .Top {
			return fmt.tprintf("WORLD   %s: OPEN A PART", label(e, .Green))
		}
		return fmt.tprintf("%s   %s: OPEN", hub_section_title(e.hub_section), label(e, .Green))
	case .List:
		return fmt.tprintf("%s   %s: OPEN", section_title(e.section), label(e, .Green))
	case .Setup:
		return fmt.tprintf("ACTIONS   %s: DONE", label(e, .Red))
	case .File:
		return fmt.tprintf("FILE: %s SAVE  %s LOAD", label(e, .Green), label(e, .Yellow))
	case .Text, .Value, .Sound, .Play, .Palette, .Tileset, .Terrain, .Sprite, .Char_Type, .Character, .Feature_Type, .Feature, .Map:
		// These modes draw their own screens.
	}
	return ""
}

help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	switch e.mode {
	case .Hub:
		if e.hub_level == .Top {
			lines = {
				fmt.tprintf("%s/%s: CHOOSE A PART", l(e, .Up), l(e, .Down)),
				fmt.tprintf("%s: OPEN IT  %s: PLAY THE WORLD", l(e, .Green), l(e, .Yellow)),
				fmt.tprintf("%s: SAVE / LOAD  %s: MAIN MENU", l(e, .Blue), l(e, .Red)),
				"MOUSE: CLICK A PART TO OPEN IT",
			}
			return lines, 4
		}
		lines = {
			e.hub_section == .Look ? fmt.tprintf("%s/%s: CHOOSE  %s/%s: TILE SIZE", l(e, .Up), l(e, .Down), l(e, .Left), l(e, .Right)) : fmt.tprintf("%s/%s: CHOOSE", l(e, .Up), l(e, .Down)),
			fmt.tprintf("%s: OPEN  %s: PLAY THE WORLD", l(e, .Green), l(e, .Yellow)),
			fmt.tprintf("%s: SAVE / LOAD  %s: UP A LEVEL", l(e, .Blue), l(e, .Red)),
			"MOUSE: CLICK A ROW; BACK GOES UP",
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
	case .Text, .Value, .Sound, .Play, .Palette, .Tileset, .Terrain, .Sprite, .Char_Type, .Character, .Feature_Type, .Feature, .Map:
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
	case .Sounds:
		sd := &e.world.sounds[i]
		if sd.text_len == 0 {
			return "EMPTY"
		}
		notes, _, ok := cm.play_parse(cm.sound_text(sd))
		if !ok {
			return "ERROR"
		}
		return fmt.tprintf("%.1f S%s", cm.play_duration(notes), sd.loop ? " LOOP" : "")
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
	case .Sound:
		draw_sound(e, r)
		return
	case .Play:
		draw_play(e, r)
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
	case .Feature_Type:
		fte.editor_draw(&e.feature_type_ed, r)
		return
	case .Feature:
		fe.editor_draw(&e.feature_ed, r)
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
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	} else {
		cm.draw_text(r, INFO_X, INFO_Y, e.dirty ? "UNSAVED CHANGES *" : "NO UNSAVED CHANGES", e.dirty ? TEXT : DIM)
	}
	if e.hub_level == .Top {
		draw_hub_top(e, r)
	} else {
		draw_hub_inside(e, r)
	}
	buttons := [4]struct {
		rc:  Rect,
		txt: string,
	}{{SAVE_BUTTON, "SAVE"}, {LOAD_BUTTON, "LOAD"}, {MENU_BUTTON, "MENU"}, {PLAY_BUTTON, "PLAY"}}
	for b in buttons {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + (b.rc.h - cm.GLYPH_H) / 2, b.txt, TEXT)
	}
	if e.hub_level == .Inside {
		fill(r, SECTION_BACK, PANEL)
		cm.draw_text(r, SECTION_BACK.x + (SECTION_BACK.w - cm.text_width("BACK")) / 2, SECTION_BACK.y + (SECTION_BACK.h - cm.GLYPH_H) / 2, "BACK", TEXT)
	}
}

// The one-line summary under a section's title at the top of the hub.
hub_section_summary :: proc(e: ^Editor, s: Hub_Section) -> string {
	w := &e.world
	switch s {
	case .Look:
		return fmt.tprintf("%dX%d  %d TILESETS  %d TERRAIN SETS  %d SPRITE SETS", w.tile_w, w.tile_h, w.tileset_count, w.set_count, w.sprite_set_count)
	case .Rules:
		return fmt.tprintf("%d TAGS  %d PARAMS  %d SOUNDS", w.tag_count, w.param_count, w.sound_count)
	case .Actors:
		return fmt.tprintf("%d CHARACTERS  %d FEATURES  %d MAPS", w.character_count, w.feature_count, w.map_count)
	}
	return ""
}

draw_hub_top :: proc(e: ^Editor, r: ^cm.Renderer) {
	for s in Hub_Section {
		rc := top_row_rect(int(s))
		on := e.mode == .Hub && e.top == s
		if on {
			cm.draw_text(r, HUB_MARKER_X, rc.y + 3, ">", HILITE)
		}
		cm.draw_text(r, HUB_X, rc.y + 3, hub_section_title(s), on ? HILITE : TEXT)
		summary := hub_section_summary(e, s)
		cm.draw_text(r, HUB_X, rc.y + 3 + cm.LINE_ADVANCE + 3, summary, DIM)
		if s == .Rules {
			if missing := tags_missing(e); missing > 0 {
				cm.draw_text(r, HUB_X + cm.text_width(summary) + 8, rc.y + 3 + cm.LINE_ADVANCE + 3, fmt.tprintf("%d MISSING", missing), WARN)
			}
		}
	}
}

draw_hub_inside :: proc(e: ^Editor, r: ^cm.Renderer) {
	w := &e.world
	cm.draw_text(r, HUB_MARKER_X, HUB_Y - 12, hub_section_title(e.hub_section), DIM)
	for row, i in section_rows(e.hub_section) {
		y := HUB_Y + i * HUB_PITCH
		on := e.mode == .Hub && e.hub == row
		color := on ? HILITE : TEXT
		if on {
			cm.draw_text(r, HUB_MARKER_X, y, ">", HILITE)
		}
		cm.draw_text(r, HUB_X, y, hub_label(row), color)
		count :: proc(r: ^cm.Renderer, y: int, n, cap: int, color: cm.Color) {
			cm.draw_text(r, HUB_VALUE_X, y, fmt.tprintf("%d OF %d", n, cap), color)
		}
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
			count(r, y, w.param_count, cm.WORLD_MAX_PARAMS, color)
		case .Sounds:
			count(r, y, w.sound_count, cm.WORLD_MAX_SOUNDS, color)
		case .Tags:
			text := fmt.tprintf("%d OF %d", w.tag_count, cm.WORLD_MAX_TAGS)
			cm.draw_text(r, HUB_VALUE_X, y, text, color)
			if missing := tags_missing(e); missing > 0 {
				cm.draw_text(r, HUB_VALUE_X + cm.text_width(text) + 8, y, fmt.tprintf("%d MISSING", missing), WARN)
			}
		case .Tilesets:
			count(r, y, w.tileset_count, cm.WORLD_MAX_TILESETS, color)
		case .Terrain_Sets:
			count(r, y, w.set_count, cm.WORLD_MAX_TERRAIN_SETS, color)
		case .Sprite_Sets:
			count(r, y, w.sprite_set_count, cm.WORLD_MAX_SPRITE_SETS, color)
		case .Character_Types:
			count(r, y, w.char_type_count, cm.WORLD_MAX_CHARACTER_TYPES, color)
		case .Characters:
			count(r, y, w.character_count, cm.WORLD_MAX_CHARACTERS, color)
		case .Feature_Types:
			count(r, y, w.feature_type_count, cm.WORLD_MAX_FEATURE_TYPES, color)
		case .Features:
			count(r, y, w.feature_count, cm.WORLD_MAX_FEATURES, color)
		case .Maps:
			count(r, y, w.map_count, cm.WORLD_MAX_MAPS, color)
		}
	}
	if e.hub_section == .Look {
		buttons := [4]struct {
			rc:  Rect,
			txt: string,
		}{{WIDTH_MINUS, "-"}, {WIDTH_PLUS, "+"}, {HEIGHT_MINUS, "-"}, {HEIGHT_PLUS, "+"}}
		for b in buttons {
			fill(r, b.rc, PANEL)
			cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + 3, b.txt, TEXT)
		}
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
		detail_color := isel && e.mode == .List ? BG : (detail == "MISSING" || detail == "ERROR" ? WARN : DIM)
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
