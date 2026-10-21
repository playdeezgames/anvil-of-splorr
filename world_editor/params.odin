package world_editor

import cm "../common"
import "core:fmt"

// The value screen of a game parameter (Mode.Value): a number is changed with left/right (1) and
// up/down (10) or typed with the keypad (green); a text is typed with the keypad (green); yellow
// switches between number and text (the other value is kept); red goes back to the list. The mouse
// has -10 -1 +1 +10 buttons for a number, EDIT (the keypad), KIND and BACK.

// What the keypad is typing: a name (the list's rename), or the value of a parameter.
Text_Target :: enum {
	Name,
	Number,
	Text_Value,
}

NOTE_NOT_A_NUMBER :: "NOT A WHOLE NUMBER"
NOTE_OUT_OF_RANGE :: "TOO BIG: 32 BITS AT MOST"
NOTE_TEXT_BAD :: "UNUSABLE CHARACTER IN TEXT"
NOTE_PARAM_NOTHING :: "NOTHING TO EDIT: USE NEW"

// The parameter being edited (the selected one of the Params list).
@(private = "file")
param_index :: proc(e: ^Editor) -> int {
	return e.sel[.Params]
}

begin_value :: proc(e: ^Editor) {
	if e.world.param_count == 0 {
		e.note = NOTE_PARAM_NOTHING
		return
	}
	e.mode = .Value
}

@(private = "file")
step_number :: proc(e: ^Editor, delta: int) {
	p := &e.world.params[param_index(e)]
	if p.kind != .Number {
		return
	}
	if cm.world_set_param_number(&e.world, param_index(e), p.number + delta) {
		touched(e)
	}
}

@(private = "file")
toggle_kind :: proc(e: ^Editor) {
	if cm.world_toggle_param_kind(&e.world, param_index(e)) {
		touched(e)
	}
}

// Opens the keypad on the value: a number's digits, or the text.
@(private = "file")
edit_value :: proc(e: ^Editor) {
	p := &e.world.params[param_index(e)]
	if p.kind == .Number {
		e.text_target = .Number
		cm.text_entry_begin(&e.entry, "NUMBER", cm.param_value_text(p), cm.PARAM_TEXT_MAX)
	} else {
		e.text_target = .Text_Value
		cm.text_entry_begin(&e.entry, "TEXT", cm.param_value_text(p), cm.PARAM_TEXT_MAX)
	}
	e.mode = .Text
}

// The whole number in `s` ("-12", "007"), if it is one that fits 32 bits. `ok` false means it is not
// a whole number at all; `fits` false means it is one but too big (value is then 0). (Worked out in
// 64 bits: `int` is only 32 bits wide in the web build.)
parse_whole_number :: proc(s: string) -> (value: int, ok, fits: bool) {
	if len(s) == 0 {
		return 0, false, true
	}
	i, negative := 0, false
	if s[0] == '-' {
		negative, i = true, 1
		if len(s) == 1 {
			return 0, false, true
		}
	}
	for k in i ..< len(s) {
		if s[k] < '0' || s[k] > '9' {
			return 0, false, true
		}
	}
	big: i64
	for ; i < len(s); i += 1 {
		big = big * 10 + i64(s[i] - '0')
		if big > 1 << 40 { 	// far past 32 bits: no need to read on
			return 0, true, false
		}
	}
	if negative {
		big = -big
	}
	if big < i64(cm.PARAM_NUMBER_MIN) || big > i64(cm.PARAM_NUMBER_MAX) {
		return 0, true, false
	}
	return int(big), true, true
}

// The keypad for a value: Done sets it (or resumes with a note), Cancel goes back to the value screen.
handle_value_text :: proc(e: ^Editor, ev: cm.Input_Event) {
	switch cm.text_entry_handle(&e.entry, ev) {
	case .Editing:
	case .Cancelled:
		e.text_target = .Name
		e.mode = .Value
	case .Done:
		text := cm.text_entry_text(&e.entry)
		i := param_index(e)
		if e.text_target == .Number {
			value, ok, fits := parse_whole_number(text)
			switch {
			case !ok:
				cm.text_entry_resume(&e.entry, NOTE_NOT_A_NUMBER)
				return
			case !fits:
				cm.text_entry_resume(&e.entry, NOTE_OUT_OF_RANGE)
				return
			}
			cm.world_set_param_number(&e.world, i, value)
		} else if problem := cm.world_set_param_text(&e.world, i, text); problem != .None {
			cm.text_entry_resume(&e.entry, NOTE_TEXT_BAD)
			return
		}
		touched(e)
		e.text_target = .Name
		e.mode = .Value
	}
}

// Commands and the mouse on the value screen.
handle_value :: proc(e: ^Editor, ev: cm.Input_Event) {
	#partial switch v in ev {
	case cm.Command:
		e.note = ""
	case cm.Mouse_Button_Event:
		if v.down {
			e.note = ""
		}
	}
	switch v in ev {
	case cm.Command:
		#partial switch v.action {
		case .Left:
			step_number(e, -1)
		case .Right:
			step_number(e, 1)
		case .Up:
			step_number(e, 10)
		case .Down:
			step_number(e, -10)
		case .Green:
			edit_value(e)
		case .Yellow:
			toggle_kind(e)
		case .Red:
			e.mode = .List
		}
	case cm.Mouse_Move:
	case cm.Mouse_Button_Event:
		if v.button == .Left && v.down {
			switch {
			case rect_contains(VALUE_MINUS10, v.x, v.y):
				step_number(e, -10)
			case rect_contains(VALUE_MINUS1, v.x, v.y):
				step_number(e, -1)
			case rect_contains(VALUE_PLUS1, v.x, v.y):
				step_number(e, 1)
			case rect_contains(VALUE_PLUS10, v.x, v.y):
				step_number(e, 10)
			case rect_contains(VALUE_EDIT, v.x, v.y):
				edit_value(e)
			case rect_contains(VALUE_KIND, v.x, v.y):
				toggle_kind(e)
			case rect_contains(VALUE_BACK, v.x, v.y):
				e.mode = .List
			}
		}
	case cm.Mouse_Wheel:
		step_number(e, v.dy)
	}
}

value_banner_text :: proc(e: ^Editor) -> string {
	return fmt.tprintf("VALUE   %s: TYPE IT  %s: NUMBER / TEXT", label(e, .Green), label(e, .Yellow))
}

value_help_lines :: proc(e: ^Editor) -> (lines: [MAX_HELP_LINES]string, n: int) {
	l :: label
	lines = {
		fmt.tprintf("%s/%s: -/+ 1 (NUMBERS)", l(e, .Left), l(e, .Right)),
		fmt.tprintf("%s/%s: +/- 10 (NUMBERS)", l(e, .Up), l(e, .Down)),
		fmt.tprintf("%s: TYPE THE VALUE  %s: NUMBER / TEXT", l(e, .Green), l(e, .Yellow)),
		fmt.tprintf("%s: BACK  MOUSE: THE BUTTONS AND THE WHEEL", l(e, .Red)),
	}
	return lines, 4
}

// Cut so a long text stays on its line at double size (32 characters fit).
value_text :: proc(p: ^cm.Param) -> string {
	return cm.param_value_text(p)
}

draw_value :: proc(e: ^Editor, r: ^cm.Renderer) {
	cm.renderer_clear(r, BG)
	i := param_index(e)
	p := &e.world.params[i]
	fill(r, BANNER, HILITE)
	cm.draw_text(r, BANNER.x + 4, BANNER.y + 3, value_banner_text(e), BG)
	if e.note != "" {
		cm.draw_text(r, INFO_X, INFO_Y, e.note, WARN)
	} else {
		cm.draw_text(r, INFO_X, INFO_Y, fmt.tprintf("%d OF %d%s", i + 1, e.world.param_count, e.dirty ? "  *" : ""), TEXT)
	}
	cm.draw_text(r, VALUE_X, 32, cm.name_str(&p.name), HILITE)
	cm.draw_text(r, VALUE_X, 44, p.kind == .Number ? "A WHOLE NUMBER" : "A SHORT TEXT", DIM)
	shown := value_text(p)
	if p.kind == .Text && shown == "" {
		cm.draw_text(r, VALUE_X, 62, "(EMPTY)", DIM, 2)
	} else {
		cm.draw_text(r, VALUE_X, 62, shown, TEXT, 2)
	}
	numeric := p.kind == .Number
	for b in ([4]struct {
			rc:  Rect,
			txt: string,
		}{{VALUE_MINUS10, "-10"}, {VALUE_MINUS1, "-1"}, {VALUE_PLUS1, "+1"}, {VALUE_PLUS10, "+10"}}) {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + 3, b.txt, numeric ? TEXT : DIM)
	}
	for b in ([3]struct {
			rc:  Rect,
			txt: string,
		}{{VALUE_EDIT, "EDIT"}, {VALUE_KIND, "KIND"}, {VALUE_BACK, "BACK"}}) {
		fill(r, b.rc, PANEL)
		cm.draw_text(r, b.rc.x + (b.rc.w - cm.text_width(b.txt)) / 2, b.rc.y + (b.rc.h - cm.GLYPH_H) / 2, b.txt, TEXT)
	}
	lines, n := value_help_lines(e)
	for line, k in lines[:n] {
		cm.draw_text(r, 8, HELP_Y + k * cm.LINE_ADVANCE, line, TEXT)
	}
	cm.renderer_present(r)
}
