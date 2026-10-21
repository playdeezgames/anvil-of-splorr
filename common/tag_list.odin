package common

import "core:fmt"

// The list of a world's tags with a state per tag, shared by every editor that edits an entity's
// tags: a window of TAG_LIST_ROWS rows, a selection, and drawing / hit-testing that agree. The
// editor keeps a Tag_List and a Tag_View (what the entity's tags are) and decides what green does:
// types toggle (tag_toggle), instances cycle inherit -> set -> cleared (see world_tags.odin).

TAG_LIST_X :: 8
TAG_LIST_Y :: 28
TAG_LIST_ROWS :: 11
TAG_LIST_PITCH :: 10
TAG_LIST_W :: 200

Tag_List :: struct {
	sel, scroll: int,
}

// What the entity's tags are, for drawing. For a type only `set` matters. For an instance `set` and
// `cleared` are its own settings and `inherited` is its type's tags.
Tag_View :: struct {
	set, cleared, inherited: Tag_Mask,
	instance:                bool,
}

// Whether the tag is on for the entity: its own setting, else (instances) the type's.
tag_view_on :: proc(v: Tag_View, tag: int) -> bool {
	switch tag_state(v.set, v.cleared, tag) {
	case .Set:
		return true
	case .Cleared:
		return false
	case .Inherit:
	}
	return v.instance ? v.inherited & tag_bit(tag) != 0 : false
}

tag_list_rect :: proc(row: int) -> Rect {
	return Rect{TAG_LIST_X, TAG_LIST_Y + row * TAG_LIST_PITCH, TAG_LIST_W, TAG_LIST_PITCH}
}

// Keeps the selection inside `count` tags and the window around it.
tag_list_fix :: proc(l: ^Tag_List, count: int) {
	l.sel = clamp(l.sel, 0, max(count - 1, 0))
	if l.sel < l.scroll {
		l.scroll = l.sel
	} else if l.sel >= l.scroll + TAG_LIST_ROWS {
		l.scroll = l.sel - TAG_LIST_ROWS + 1
	}
	l.scroll = clamp(l.scroll, 0, max(count - TAG_LIST_ROWS, 0))
}

tag_list_move :: proc(l: ^Tag_List, count, delta: int) {
	l.sel += delta
	tag_list_fix(l, count)
}

tag_list_scroll :: proc(l: ^Tag_List, count, wheel_dy: int) {
	l.scroll = clamp(l.scroll - wheel_dy, 0, max(count - TAG_LIST_ROWS, 0))
}

// The tag under a point, if any.
tag_list_at :: proc(l: ^Tag_List, count, x, y: int) -> (tag: int, ok: bool) {
	if x < TAG_LIST_X || x >= TAG_LIST_X + TAG_LIST_W || y < TAG_LIST_Y {
		return 0, false
	}
	row := (y - TAG_LIST_Y) / TAG_LIST_PITCH
	if row >= TAG_LIST_ROWS || l.scroll + row >= count {
		return 0, false
	}
	return l.scroll + row, true
}

// The word at the right of a row for an instance: where the tag's value comes from.
tag_source_text :: proc(v: Tag_View, tag: int) -> string {
	if !v.instance {
		return ""
	}
	switch tag_state(v.set, v.cleared, tag) {
	case .Set:
		return "OWN ON"
	case .Cleared:
		return "OWN OFF"
	case .Inherit:
	}
	return v.inherited & tag_bit(tag) != 0 ? "TYPE ON" : "TYPE OFF"
}

TAG_COLOR_TEXT :: Color{200, 200, 210}
TAG_COLOR_DIM :: Color{120, 120, 134}
TAG_COLOR_HILITE :: Color{255, 220, 80}
TAG_COLOR_ON :: Color{120, 220, 130}
TAG_COLOR_BG :: Color{28, 28, 36}
TAG_COLOR_PANEL :: Color{64, 64, 76}

// Draws the window of tags: a box showing whether each is on, the name, and (instances) the source.
// `focused` highlights the selected row in yellow, else in a quiet grey.
tag_list_draw :: proc(r: ^Renderer, w: ^World, l: ^Tag_List, v: Tag_View, focused: bool) {
	for row in 0 ..< TAG_LIST_ROWS {
		tag := l.scroll + row
		if tag >= w.tag_count {
			break
		}
		rc := tag_list_rect(row)
		selected := tag == l.sel
		if selected {
			renderer_fill_rect(r, rc.x, rc.y, rc.w, rc.h, focused ? TAG_COLOR_HILITE : TAG_COLOR_PANEL)
		}
		on := tag_view_on(v, tag)
		text_color := selected && focused ? TAG_COLOR_BG : TAG_COLOR_TEXT
		box := Rect{rc.x + 2, rc.y + 1, 8, 8}
		renderer_fill_rect(r, box.x, box.y, box.w, box.h, selected && focused ? TAG_COLOR_BG : TAG_COLOR_PANEL)
		renderer_fill_rect(r, box.x + 1, box.y + 1, box.w - 2, box.h - 2, TAG_COLOR_BG)
		if on {
			renderer_fill_rect(r, box.x + 2, box.y + 2, box.w - 4, box.h - 4, selected && focused ? TAG_COLOR_HILITE : TAG_COLOR_ON)
		}
		draw_text(r, rc.x + 14, rc.y + 2, name_str(&w.tags[tag]), text_color)
		source := tag_source_text(v, tag)
		if source != "" {
			draw_text(r, rc.x + rc.w - text_width(source) - 3, rc.y + 2, source, selected && focused ? TAG_COLOR_BG : TAG_COLOR_DIM)
		}
	}
}

// "2 TAGS" / "1 TAG" / "NO TAGS": how many tags are on for an entity.
tag_count_text :: proc(w: ^World, v: Tag_View) -> string {
	n := 0
	for i in 0 ..< w.tag_count {
		if tag_view_on(v, i) {
			n += 1
		}
	}
	if n == 0 {
		return "NO TAGS"
	}
	return fmt.tprintf("%d TAG%s", n, n == 1 ? "" : "S")
}

// The names of the tags that are on, joined with commas ("SOLID,WATER"), for a value column.
tag_names_text :: proc(w: ^World, v: Tag_View) -> string {
	b: [dynamic]u8
	b.allocator = context.temp_allocator
	for i in 0 ..< w.tag_count {
		if tag_view_on(v, i) {
			if len(b) > 0 {
				append(&b, ',')
			}
			for ch in transmute([]u8)name_str(&w.tags[i]) {
				append(&b, ch >= 'a' && ch <= 'z' ? ch - 32 : ch)
			}
		}
	}
	return len(b) == 0 ? "NONE" : string(b[:])
}
