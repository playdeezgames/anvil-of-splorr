#+build !js
package common

import "core:testing"

// A map whose cells hold the numbers 0.. in reading order (mod 256).
numbered_map :: proc(w, h: int) -> ^World_Map {
	m := new(World_Map)
	m.width, m.height = w, h
	for y in 0 ..< h {
		for x in 0 ..< w {
			m.cells[y][x] = u8(y * w + x)
		}
	}
	return m
}

@(test)
test_map_cells_read_and_write_inside_only :: proc(t: ^testing.T) {
	m := numbered_map(3, 2)
	defer free(m)
	testing.expect_value(t, map_get(m, 2, 1), 5)
	testing.expect_value(t, map_get(m, 3, 0), 0)
	testing.expect_value(t, map_get(m, -1, 0), 0)
	testing.expect(t, map_set(m, 0, 0, 9) && !map_set(m, 0, 0, 9))
	testing.expect(t, !map_set(m, 3, 0, 1) && !map_set(m, 0, 0, 256) && !map_set(m, 0, 0, -1))
	testing.expect(t, map_set(m, 0, 0, 255) && m.cells[0][0] == 255)
}

@(test)
test_map_flips :: proc(t: ^testing.T) {
	m := numbered_map(3, 2) // 0 1 2 / 3 4 5
	defer free(m)
	testing.expect(t, map_flip_horizontal(m))
	testing.expect(t, m.cells[0][0] == 2 && m.cells[0][1] == 1 && m.cells[1][2] == 3)
	map_flip_horizontal(m)
	testing.expect(t, map_flip_vertical(m))
	testing.expect(t, m.cells[0][0] == 3 && m.cells[1][0] == 0)
	one := numbered_map(1, 1)
	defer free(one)
	testing.expect(t, !map_flip_horizontal(one) && !map_flip_vertical(one) && !map_rotate_180(one))
	m.cells[0][5] = 77 // cells outside the visible region are left alone
	map_flip_horizontal(m)
	testing.expect_value(t, m.cells[0][5], 77)
}

@(test)
test_map_rotation_needs_a_square_map :: proc(t: ^testing.T) {
	m := numbered_map(3, 3) // 0 1 2 / 3 4 5 / 6 7 8
	defer free(m)
	testing.expect(t, map_rotate_right(m))
	testing.expect(t, m.cells[0][0] == 6 && m.cells[0][2] == 0 && m.cells[2][2] == 2) // top row became the right column
	testing.expect(t, map_rotate_left(m))
	testing.expect(t, visible_is_numbered(m))
	testing.expect(t, map_rotate_180(m) && m.cells[0][0] == 8 && m.cells[2][2] == 0)
	map_rotate_180(m)
	for _ in 0 ..< 4 {
		map_rotate_right(m)
	}
	testing.expect(t, visible_is_numbered(m))
	wide := numbered_map(3, 2)
	defer free(wide)
	testing.expect(t, !map_rotate_right(wide) && !map_rotate_left(wide) && wide.width == 3)
	testing.expect(t, map_rotate_180(wide)) // half turns always fit
}

visible_is_numbered :: proc(m: ^World_Map) -> bool {
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if int(m.cells[y][x]) != y * m.width + x {
				return false
			}
		}
	}
	return true
}

@(test)
test_map_clear_replace_flood :: proc(t: ^testing.T) {
	m := new(World_Map)
	defer free(m)
	m.width, m.height = 4, 3
	// 1 1 0 0 / 1 0 0 1 / 0 0 1 1
	for row, y in ([3][4]u8{{1, 1, 0, 0}, {1, 0, 0, 1}, {0, 0, 1, 1}}) {
		for v, x in row {
			m.cells[y][x] = v
		}
	}
	testing.expect(t, map_flood_fill(m, 2, 0, 7)) // the connected 0s
	testing.expect(t, m.cells[0][2] == 7 && m.cells[1][1] == 7 && m.cells[2][0] == 7 && m.cells[1][3] == 1 && m.cells[0][0] == 1)
	testing.expect(t, !map_flood_fill(m, 2, 0, 7) && !map_flood_fill(m, 9, 0, 7) && !map_flood_fill(m, 0, 0, 300))
	testing.expect(t, map_replace(m, 1, 5) && m.cells[0][0] == 5 && m.cells[2][3] == 5 && m.cells[1][1] == 7)
	testing.expect(t, !map_replace(m, 1, 5) && !map_replace(m, 5, 5))
	testing.expect(t, map_clear(m, 2) && m.cells[2][3] == 2 && m.cells[0][0] == 2)
	testing.expect(t, !map_clear(m, 2))
	testing.expect(t, map_flood_fill(m, 0, 0, 255) && m.cells[2][3] == 255) // the whole map is one region
}

@(test)
test_map_shapes :: proc(t: ^testing.T) {
	m := new(World_Map)
	defer free(m)
	m.width, m.height = 5, 4
	testing.expect(t, map_draw_shape(m, .Frame, 3, 2, 0, 0, 4)) // corners in any order
	testing.expect(t, m.cells[0][0] == 4 && m.cells[0][3] == 4 && m.cells[2][0] == 4 && m.cells[1][1] == 0 && m.cells[1][2] == 0)
	testing.expect(t, map_draw_shape(m, .Fill, 0, 0, 1, 1, 6) && m.cells[1][1] == 6)
	testing.expect(t, map_draw_shape(m, .Fill, 3, 3, 99, 99, 8)) // clamped to the map
	testing.expect(t, m.cells[3][4] == 8 && m.cells[3][3] == 8 && m.cells[2][3] == 4)
	testing.expect(t, !map_draw_shape(m, .None, 0, 0, 3, 3, 1))
	a, b := numbered_map(2, 2), numbered_map(2, 2)
	defer free(a)
	defer free(b)
	testing.expect(t, map_visible_equal(a, b))
	b.cells[1][1] = 99
	testing.expect(t, !map_visible_equal(a, b))
}
