package common

// Which keyboard keys are down right now, so a game can repeat a held direction itself (no OS
// initial-repeat pause, same behaviour as a held pad button). Frontends call `keys_down` / `keys_up`
// from their key events (the OS repeat flag is ignored: a key already down stays one entry) and
// `keys_clear` when the window loses focus, then hand the tool `keys_held` once a frame through
// `tool_update_keys`. Command delivery is unchanged: the keyboard still sends a Command per press and
// per OS repeat; this is only an extra snapshot.

MAX_HELD_KEYS :: 16

// The commands any held key is bound to, through the Input_Map.
Held_Keys :: [Action]bool

Key_Tracker :: struct {
	codes: [MAX_HELD_KEYS]Key_Name, // KeyboardEvent.code names of the keys held (bound or not)
	count: int,
}

// A key went down (also true for an OS repeat: a key already held is not added twice).
keys_down :: proc(k: ^Key_Tracker, code: string) {
	if code == "" || k.count >= MAX_HELD_KEYS {
		return
	}
	for i in 0 ..< k.count {
		if key_name(&k.codes[i]) == code {
			return
		}
	}
	set_key_name(&k.codes[k.count], code)
	k.count += 1
}

// A key went up (a key that was never seen going down is ignored).
keys_up :: proc(k: ^Key_Tracker, code: string) {
	for i in 0 ..< k.count {
		if key_name(&k.codes[i]) == code {
			k.count -= 1
			k.codes[i] = k.codes[k.count]
			k.codes[k.count] = {}
			return
		}
	}
}

// Forget every held key (the window lost focus, so no key-up will arrive).
keys_clear :: proc(k: ^Key_Tracker) {
	k^ = {}
}

// The commands held by keyboard now. Two keys bound to one command keep it held until both are up;
// the lookup is made now, so a rebind takes effect on the next frame.
keys_held :: proc(k: ^Key_Tracker, m: ^Input_Map) -> (held: Held_Keys) {
	for i in 0 ..< k.count {
		if a, ok := action_for_key(m, key_name(&k.codes[i])); ok {
			held[a] = true
		}
	}
	return
}

// Per-frame keyboard update: gives the tool the held commands if it wants them.
tool_update_keys :: proc(t: ^Tool, k: ^Key_Tracker, m: ^Input_Map) {
	if t.update_keys != nil {
		held := keys_held(k, m)
		t.update_keys(t.data, &held)
	}
}
