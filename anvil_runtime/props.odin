package anvil_runtime

import cm "../common"

// Numeric properties of characters and features (design in coxswain task #63 of project `anvil`, file
// format in `WORLD.md`). A character type or feature type has named whole-number properties with
// defaults; a character or feature has its own value only where it differs. A game asks the world
// for what the authors set (`character_value`, `feature_value`) and keeps what happens during play in
// the `Play_State` (`play_character_value`, `play_set_character_value`, and the same for features), so
// the loaded world never changes. Properties are named by position in the type's list: look the name
// up once (`character_prop_index`, `feature_prop_index`) and keep the number.

// --- As authored ---

// The position of a property in a character's type's list, by name.
character_prop_index :: proc(w: ^World, ci: int, name: string) -> (index: int, ok: bool) {
	ct := character_type(w, ci)
	if ct == nil {
		return 0, false
	}
	i := cm.prop_set_find(&ct.props, name)
	return i, i >= 0
}

// The type's default for a property (0 for no such character or property).
character_prop_default :: proc(w: ^World, ci, p: int) -> i32 {
	ct := character_type(w, ci)
	if ct == nil || p < 0 || p >= ct.props.count {
		return 0
	}
	return ct.props.values[p]
}

// What the authors set: the character's own value, else its type's default.
character_value :: proc(w: ^World, ci, p: int) -> i32 {
	return cm.world_character_value(w, ci, p)
}

feature_prop_index :: proc(w: ^World, fi: int, name: string) -> (index: int, ok: bool) {
	ft := feature_type(w, fi)
	if ft == nil {
		return 0, false
	}
	i := cm.prop_set_find(&ft.props, name)
	return i, i >= 0
}

feature_prop_default :: proc(w: ^World, fi, p: int) -> i32 {
	ft := feature_type(w, fi)
	if ft == nil || p < 0 || p >= ft.props.count {
		return 0
	}
	return ft.props.values[p]
}

feature_value :: proc(w: ^World, fi, p: int) -> i32 {
	return cm.world_feature_value(w, fi, p)
}

// --- In play ---

@(private = "package")
play_init_values :: proc(ps: ^Play_State, w: ^World) {
	for ci in 0 ..< w.character_count {
		ps.character_values[ci] = w.characters[ci].overrides
	}
	for fi in 0 ..< w.feature_count {
		ps.feature_values[fi] = w.features[fi].overrides
	}
}

// A character's value now: what the game set, else the authored value, else the type's default.
play_character_value :: proc(ps: ^Play_State, w: ^World, ci, p: int) -> i32 {
	ct := character_type(w, ci)
	if ct == nil || ci >= ps.count {
		return 0
	}
	return cm.prop_value(&ct.props, &ps.character_values[ci], p)
}

// Sets a character's value for the rest of the play (a value equal to the default is the default
// again). False for no such character or property.
play_set_character_value :: proc(ps: ^Play_State, w: ^World, ci, p: int, value: i32) -> bool {
	ct := character_type(w, ci)
	if ct == nil || ci >= ps.count {
		return false
	}
	return cm.prop_override_set(&ct.props, &ps.character_values[ci], p, value)
}

play_feature_value :: proc(ps: ^Play_State, w: ^World, fi, p: int) -> i32 {
	ft := feature_type(w, fi)
	if ft == nil || fi >= ps.feature_count {
		return 0
	}
	return cm.prop_value(&ft.props, &ps.feature_values[fi], p)
}

play_set_feature_value :: proc(ps: ^Play_State, w: ^World, fi, p: int, value: i32) -> bool {
	ft := feature_type(w, fi)
	if ft == nil || fi >= ps.feature_count {
		return false
	}
	return cm.prop_override_set(&ft.props, &ps.feature_values[fi], p, value)
}
