package common

// Whole-map operations for the map editor, on a World_Map's visible cells (columns x rows). Each
// returns true if any cell changed, like the matching image4_* procs. A cell is a terrain index.

map_get :: proc(m: ^World_Map, x, y: int) -> u8 {
	if x < 0 || y < 0 || x >= m.width || y >= m.height {
		return 0
	}
	return m.cells[y][x]
}

map_set :: proc(m: ^World_Map, x, y: int, terrain: int) -> bool {
	if x < 0 || y < 0 || x >= m.width || y >= m.height || terrain < 0 || terrain >= TERRAIN_MAX {
		return false
	}
	if int(m.cells[y][x]) == terrain {
		return false
	}
	m.cells[y][x] = u8(terrain)
	return true
}

map_flip_horizontal :: proc(m: ^World_Map) -> (changed: bool) {
	for y in 0 ..< m.height {
		for x in 0 ..< m.width / 2 {
			a, b := &m.cells[y][x], &m.cells[y][m.width - 1 - x]
			if a^ != b^ {
				a^, b^ = b^, a^
				changed = true
			}
			ca, cb := &m.characters[y][x], &m.characters[y][m.width - 1 - x]
			if ca^ != cb^ { 	// characters move with their cells
				ca^, cb^ = cb^, ca^
				changed = true
			}
		}
	}
	return
}

map_flip_vertical :: proc(m: ^World_Map) -> (changed: bool) {
	for y in 0 ..< m.height / 2 {
		for x in 0 ..< m.width {
			a, b := &m.cells[y][x], &m.cells[m.height - 1 - y][x]
			if a^ != b^ {
				a^, b^ = b^, a^
				changed = true
			}
			ca, cb := &m.characters[y][x], &m.characters[m.height - 1 - y][x]
			if ca^ != cb^ {
				ca^, cb^ = cb^, ca^
				changed = true
			}
		}
	}
	return
}

map_rotate_180 :: proc(m: ^World_Map) -> bool {
	a := map_flip_horizontal(m)
	b := map_flip_vertical(m)
	return a || b
}

@(private = "file")
rotate :: proc(m: ^World_Map, clockwise: bool) -> (changed: bool) {
	if m.width != m.height {
		return false // a quarter turn would change the map's size: not offered
	}
	n := m.width
	old := m.cells
	old_chars := m.characters
	for y in 0 ..< n {
		for x in 0 ..< n {
			v := clockwise ? old[n - 1 - x][y] : old[x][n - 1 - y]
			if m.cells[y][x] != v {
				m.cells[y][x] = v
				changed = true
			}
			c := clockwise ? old_chars[n - 1 - x][y] : old_chars[x][n - 1 - y]
			if m.characters[y][x] != c {
				m.characters[y][x] = c
				changed = true
			}
		}
	}
	return
}

// Square maps only. Clockwise: the top row becomes the right column.
map_rotate_right :: proc(m: ^World_Map) -> bool {
	return rotate(m, true)
}

map_rotate_left :: proc(m: ^World_Map) -> bool {
	return rotate(m, false)
}

map_clear :: proc(m: ^World_Map, terrain: int) -> (changed: bool) {
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if map_set(m, x, y, terrain) {
				changed = true
			}
		}
	}
	return
}

map_replace :: proc(m: ^World_Map, from, to: int) -> (changed: bool) {
	if from == to {
		return false
	}
	for y in 0 ..< m.height {
		for x in 0 ..< m.width {
			if int(m.cells[y][x]) == from && map_set(m, x, y, to) {
				changed = true
			}
		}
	}
	return
}

// The connected region (rows and columns, not diagonals) of cells equal to the one at (x, y)
// becomes `terrain`.
map_flood_fill :: proc(m: ^World_Map, x, y: int, terrain: int) -> bool {
	if x < 0 || y < 0 || x >= m.width || y >= m.height || terrain < 0 || terrain >= TERRAIN_MAX {
		return false
	}
	c := u8(terrain)
	target := m.cells[y][x]
	if target == c {
		return false
	}
	stack: [MAP_MAX * MAP_MAX][2]u8
	n := 0
	m.cells[y][x] = c
	stack[n] = {u8(x), u8(y)}
	n += 1
	for n > 0 {
		n -= 1
		px, py := int(stack[n][0]), int(stack[n][1])
		for d in ([4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
			nx, ny := px + d.x, py + d.y
			if nx >= 0 && ny >= 0 && nx < m.width && ny < m.height && m.cells[ny][nx] == target {
				m.cells[ny][nx] = c
				stack[n] = {u8(nx), u8(ny)}
				n += 1
			}
		}
	}
	return true
}

// Sets the shape's cells (corners in any order, clamped to the map) to `terrain`.
map_draw_shape :: proc(m: ^World_Map, shape: Shape, x0, y0, x1, y1: int, terrain: int) -> (changed: bool) {
	cx0, cx1 := clamp(x0, 0, m.width - 1), clamp(x1, 0, m.width - 1)
	cy0, cy1 := clamp(y0, 0, m.height - 1), clamp(y1, 0, m.height - 1)
	for y in min(cy0, cy1) ..= max(cy0, cy1) {
		for x in min(cx0, cx1) ..= max(cx0, cx1) {
			if shape_has_cell(shape, cx0, cy0, cx1, cy1, x, y) && map_set(m, x, y, terrain) {
				changed = true
			}
		}
	}
	return
}

// True if the visible cells of both maps are equal (and the sizes).
map_visible_equal :: proc(a, b: ^World_Map) -> bool {
	if a.width != b.width || a.height != b.height {
		return false
	}
	for y in 0 ..< a.height {
		for x in 0 ..< a.width {
			if a.cells[y][x] != b.cells[y][x] {
				return false
			}
		}
	}
	return true
}
