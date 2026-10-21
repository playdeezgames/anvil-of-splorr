#+build !js
package common

import "core:testing"

Tag_Draw_Log :: struct {
	rects: [dynamic]Rect,
}

tag_draw_renderer :: proc(l: ^Tag_Draw_Log) -> Renderer {
	return Renderer {
		data = l,
		clear = proc(d: rawptr, c: Color) {},
		fill_rect = proc(d: rawptr, x, y, w, h: int, c: Color) {append(&(^Tag_Draw_Log)(d).rects, Rect{x, y, w, h})},
		present = proc(d: rawptr) {},
	}
}

@(test)
test_the_tag_list_keeps_its_selection_in_view :: proc(t: ^testing.T) {
	l: Tag_List
	tag_list_move(&l, 40, 1)
	testing.expect(t, l.sel == 1 && l.scroll == 0)
	tag_list_move(&l, 40, -5)
	testing.expect_value(t, l.sel, 0)
	for _ in 0 ..< 60 {
		tag_list_move(&l, 40, 1)
	}
	testing.expect(t, l.sel == 39 && l.scroll == 40 - TAG_LIST_ROWS)
	tag_list_move(&l, 40, -1)
	testing.expect_value(t, l.scroll, 40 - TAG_LIST_ROWS)
	tag_list_scroll(&l, 40, -5)
	testing.expect_value(t, l.scroll, 40 - TAG_LIST_ROWS) // already at the end
	tag_list_scroll(&l, 40, 100)
	testing.expect_value(t, l.scroll, 0)
	tag_list_scroll(&l, 40, -3)
	testing.expect_value(t, l.scroll, 3)
	tag_list_fix(&l, 3) // fewer tags than rows: everything resets
	testing.expect(t, l.sel == 2 && l.scroll == 0)
	tag_list_fix(&l, 0)
	testing.expect(t, l.sel == 0 && l.scroll == 0)
}

@(test)
test_the_tag_list_finds_the_tag_under_a_point :: proc(t: ^testing.T) {
	l := Tag_List{scroll = 5}
	for row in 0 ..< TAG_LIST_ROWS {
		rc := tag_list_rect(row)
		tag, ok := tag_list_at(&l, 40, rc.x + 1, rc.y)
		testing.expectf(t, ok && tag == 5 + row, "row %d", row)
		tag, ok = tag_list_at(&l, 40, rc.x + rc.w - 1, rc.y + rc.h - 1)
		testing.expectf(t, ok && tag == 5 + row, "row %d (far corner)", row)
	}
	_, ok := tag_list_at(&l, 40, TAG_LIST_X - 1, TAG_LIST_Y)
	testing.expect(t, !ok)
	_, ok = tag_list_at(&l, 40, TAG_LIST_X, TAG_LIST_Y + TAG_LIST_ROWS * TAG_LIST_PITCH)
	testing.expect(t, !ok)
	l.scroll = 0
	_, ok = tag_list_at(&l, 3, TAG_LIST_X, TAG_LIST_Y + 3 * TAG_LIST_PITCH) // below the last tag
	testing.expect(t, !ok)
}

@(test)
test_a_tag_is_on_by_its_own_setting_or_its_types :: proc(t: ^testing.T) {
	type_view := Tag_View{set = tag_bit(2) | tag_bit(5)}
	testing.expect(t, tag_view_on(type_view, 2) && tag_view_on(type_view, 5) && !tag_view_on(type_view, 3))
	inst := Tag_View{set = tag_bit(1), cleared = tag_bit(2), inherited = tag_bit(2) | tag_bit(3), instance = true}
	testing.expect(t, tag_view_on(inst, 1)) // its own: on
	testing.expect(t, !tag_view_on(inst, 2)) // its own: off, though the type has it
	testing.expect(t, tag_view_on(inst, 3)) // inherited
	testing.expect(t, !tag_view_on(inst, 4))
	testing.expect_value(t, tag_source_text(inst, 1), "OWN ON")
	testing.expect_value(t, tag_source_text(inst, 2), "OWN OFF")
	testing.expect_value(t, tag_source_text(inst, 3), "TYPE ON")
	testing.expect_value(t, tag_source_text(inst, 4), "TYPE OFF")
	testing.expect_value(t, tag_source_text(type_view, 1), "")
	for text in ([]string{"OWN ON", "OWN OFF", "TYPE ON", "TYPE OFF"}) {
		testing.expect(t, text_is_drawable(text))
	}
}

@(test)
test_the_tag_list_draws_inside_its_area_and_summarises_tags :: proc(t: ^testing.T) {
	log: Tag_Draw_Log
	defer delete(log.rects)
	r := tag_draw_renderer(&log)
	w := new(World)
	defer free(w)
	world_reset(w)
	for w.tag_count < WORLD_MAX_TAGS {
		world_add_tag(w, "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW")
	}
	l := Tag_List{sel = 20}
	tag_list_fix(&l, w.tag_count)
	view := Tag_View{set = tag_bit(20), cleared = tag_bit(21), inherited = tag_bit(22), instance = true}
	for focused in ([]bool{true, false}) {
		clear(&log.rects)
		tag_list_draw(&r, w, &l, view, focused)
		testing.expect(t, len(log.rects) > TAG_LIST_ROWS)
		for rc in log.rects {
			testing.expect(t, rc.x >= TAG_LIST_X && rc.y >= TAG_LIST_Y && rc.x + rc.w <= TAG_LIST_X + TAG_LIST_W && rc.y + rc.h <= TAG_LIST_Y + TAG_LIST_ROWS * TAG_LIST_PITCH)
		}
	}
	// The longest name and source fit one row.
	testing.expect(t, 14 + text_width("WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW") + text_width("TYPE OFF") + 6 <= TAG_LIST_W)
	// A tag list can scroll past an empty world's few tags without trouble.
	e := new(World)
	defer free(e)
	world_reset(e)
	clear(&log.rects)
	tag_list_draw(&r, e, &Tag_List{}, Tag_View{}, true)
	testing.expect(t, len(log.rects) > 0)
	// Summaries.
	testing.expect_value(t, tag_count_text(e, Tag_View{}), "NO TAGS")
	testing.expect_value(t, tag_count_text(e, Tag_View{set = 1}), "1 TAG")
	world_add_tag(e, "water")
	testing.expect_value(t, tag_count_text(e, Tag_View{set = 3}), "2 TAGS")
	testing.expect_value(t, tag_names_text(e, Tag_View{set = 3}), "SOLID,WATER")
	testing.expect_value(t, tag_names_text(e, Tag_View{}), "NONE")
	testing.expect(t, text_is_drawable("NO TAGS") && text_is_drawable("1 TAG") && text_is_drawable("SOLID,WATER"))
}
