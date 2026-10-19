package gamepad_tester

import cm "../common"
import "core:fmt"

BG :: cm.Color{28, 28, 36}
PANEL :: cm.Color{64, 64, 76}
TEXT :: cm.Color{200, 200, 210}
HILITE :: cm.Color{255, 220, 80}
DIM :: cm.Color{120, 120, 134}

BUTTON_ROWS :: 9 // buttons per column
BUTTON_COL_W :: 76
BUTTON_Y :: 30
ROW_H :: 8
STICK_SIZE :: 44
STICK_Y :: 110
AXIS_X :: 120
AXIS_BAR_W :: 100
AXIS_BAR_X :: 156

fill_rect :: proc(r: ^cm.Renderer, rc: [4]int, c: cm.Color) {
	cm.renderer_fill_rect(r, rc[0], rc[1], rc[2], rc[3], c)
}

tester_draw :: proc(t: ^Tester, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	cm.draw_text(r, 8, 4, "GAMEPAD TESTER", HILITE)

	// Way out: the MENU button (mouse) and the keyboard's red command.
	fill_rect(r, MENU_BUTTON, PANEL)
	cm.draw_text(r, MENU_BUTTON[0] + (MENU_BUTTON[2] - cm.text_width("MENU")) / 2, MENU_BUTTON[1] + 3, "MENU", TEXT)
	hint := fmt.tprintf("KEYBOARD %s: MENU", cm.action_label(t.labels, .Red))
	cm.draw_text(r, MENU_BUTTON[0] - 6 - cm.text_width(hint), MENU_BUTTON[1] + 3, hint, DIM)

	n := connected_count(t)
	if n == 0 {
		msg := "NO GAMEPAD DETECTED"
		cm.draw_text(r, (cm.SCREEN_W - cm.text_width(msg)) / 2, 80, msg, TEXT)
		msg = "CONNECT ONE AND PRESS A BUTTON"
		cm.draw_text(r, (cm.SCREEN_W - cm.text_width(msg)) / 2, 90, msg, DIM)
		cm.renderer_present(r)
		return
	}

	p := &t.pads[t.selected]
	buf: [96]u8

	info := fmt.bprintf(buf[:], "PAD %d  (%d CONNECTED%s)", t.selected + 1, n, n > 1 ? ", CLICK: NEXT" : "")
	cm.draw_text(r, cm.SCREEN_W - 8 - cm.text_width(info), 4, info, TEXT)
	cm.draw_text(r, 8, 12, cm.pad_name(p), TEXT)
	layout := p.standard ? "STANDARD LAYOUT" : "NON-STANDARD: RAW INDICES"
	cm.draw_text(r, 8, 20, fmt.bprintf(buf[:], "%s  %d BUTTONS  %d AXES", layout, p.button_count, p.axis_count), DIM)

	fill :: proc(r: ^cm.Renderer, x, y, w, h: int, c: cm.Color) {
		cm.renderer_fill_rect(r, x, y, w, h, c)
	}

	// Buttons, in columns of BUTTON_ROWS.
	for i in 0 ..< min(p.button_count, cm.MAX_PAD_BUTTONS) {
		x := 8 + (i / BUTTON_ROWS) * BUTTON_COL_W
		y := BUTTON_Y + (i % BUTTON_ROWS) * ROW_H
		b := p.buttons[i]
		fill(r, x, y, 5, 5, b.down ? HILITE : PANEL)
		label: string
		if p.standard && i < cm.STANDARD_BUTTON_COUNT {
			label = fmt.bprintf(buf[:], "%02d %s", i, cm.STANDARD_BUTTON_NAMES[i])
		} else {
			label = fmt.bprintf(buf[:], "%02d", i)
		}
		cm.draw_text(r, x + 8, y, label, b.down ? HILITE : TEXT)
		if p.standard && (i == 6 || i == 7) { 	// analog triggers
			fill(r, x + 44, y + 1, 24, 3, PANEL)
			fill(r, x + 44, y + 1, int(b.value * 24), 3, HILITE)
		}
	}

	// Stick squares: axes 0/1 and 2/3.
	for s in 0 ..< 2 {
		x := 8 + s * (STICK_SIZE + 8)
		fill(r, x, STICK_Y, STICK_SIZE, STICK_SIZE, PANEL)
		fill(r, x + 1, STICK_Y + 1, STICK_SIZE - 2, STICK_SIZE - 2, BG)
		fill(r, x + STICK_SIZE / 2, STICK_Y + 1, 1, STICK_SIZE - 2, PANEL)
		fill(r, x + 1, STICK_Y + STICK_SIZE / 2, STICK_SIZE - 2, 1, PANEL)
		if p.axis_count >= s * 2 + 2 {
			half := f32(STICK_SIZE / 2 - 3)
			dx := int(p.axes[s * 2] * half)
			dy := int(p.axes[s * 2 + 1] * half)
			fill(r, x + STICK_SIZE / 2 + dx - 1, STICK_Y + STICK_SIZE / 2 + dy - 1, 3, 3, HILITE)
		}
		stick_label := p.standard ? (s == 0 ? "LEFT" : "RIGHT") : (s == 0 ? "AX 0/1" : "AX 2/3")
		cm.draw_text(r, x, STICK_Y + STICK_SIZE + 4, stick_label, DIM)
	}

	// Axis bars with numbers.
	for i in 0 ..< min(p.axis_count, cm.MAX_PAD_AXES) {
		y := STICK_Y + i * ROW_H
		name: string
		if p.standard && i < cm.STANDARD_AXIS_COUNT {
			name = fmt.bprintf(buf[:], "%d %s", i, cm.STANDARD_AXIS_NAMES[i])
		} else {
			name = fmt.bprintf(buf[:], "%d", i)
		}
		cm.draw_text(r, AXIS_X, y, name, TEXT)
		fill(r, AXIS_BAR_X, y, AXIS_BAR_W, 5, PANEL)
		mid := AXIS_BAR_X + AXIS_BAR_W / 2
		w := int(p.axes[i] * f32(AXIS_BAR_W / 2))
		if w >= 0 {
			fill(r, mid, y, w, 5, HILITE)
		} else {
			fill(r, mid + w, y, -w, 5, HILITE)
		}
		fill(r, mid, y - 1, 1, 7, TEXT)
		cm.draw_text(r, AXIS_BAR_X + AXIS_BAR_W + 6, y, fmt.bprintf(buf[:], "%+.2f", p.axes[i]), TEXT)
	}

	// Last pressed.
	last := "LAST PRESSED: -"
	if k := t.last[t.selected]; k > 0 {
		idx := k - 1
		if p.standard && idx < cm.STANDARD_BUTTON_COUNT {
			last = fmt.bprintf(buf[:], "LAST PRESSED: %s  (BUTTON %d)", cm.STANDARD_BUTTON_NAMES[idx], idx)
		} else {
			last = fmt.bprintf(buf[:], "LAST PRESSED: BUTTON %d", idx)
		}
	}
	cm.draw_text(r, 8, 172, last, HILITE)

	cm.renderer_present(r)
}
