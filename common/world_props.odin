package common

// Numeric properties of character types and feature types, and the values of their characters and
// features (the same Prop_Set / Prop_Overrides item types use, see prop_set.odin). A type has the
// properties with their defaults; a character or feature has its own values only where they differ
// from the defaults (an override equal to the default is never kept, so equal values are equal data).
// Changing a character's or feature's type forgets its values (they belonged to the old type's
// properties); deleting a property shifts the values of everything of that type.

// --- Character types ---

// Adds a property to character type i (a unique name made from `base`, default `value`). Returns its
// index or -1 if the type has 16.
world_char_type_add_prop :: proc(w: ^World, i: int, base := "property", value: i32 = 0) -> int {
	if i < 0 || i >= w.char_type_count {
		return -1
	}
	return prop_set_add(&w.char_types[i].props, base, value)
}

// Deletes property p of character type i; its characters lose their value of it and the ones above shift down.
world_char_type_delete_prop :: proc(w: ^World, i, p: int) -> bool {
	if i < 0 || i >= w.char_type_count || !prop_set_delete(&w.char_types[i].props, p) {
		return false
	}
	name := name_str(&w.char_types[i].name)
	for c in 0 ..< w.character_count {
		if name_str(&w.characters[c].type) == name {
			prop_overrides_remove(&w.characters[c].overrides, p)
		}
	}
	return true
}

// The character type of character ci, or -1.
@(private = "file")
char_type_of :: proc(w: ^World, ci: int) -> int {
	if ci < 0 || ci >= w.character_count {
		return -1
	}
	return world_find_char_type(w, name_str(&w.characters[ci].type))
}

// The value of property p for character ci: its own, else its type's default (0 if there is none).
world_character_value :: proc(w: ^World, ci, p: int) -> i32 {
	ti := char_type_of(w, ci)
	if ti < 0 {
		return 0
	}
	return prop_value(&w.char_types[ti].props, &w.characters[ci].overrides, p)
}

// Sets property p of character ci (a value equal to the default drops the override).
world_character_set_value :: proc(w: ^World, ci, p: int, value: i32) -> bool {
	ti := char_type_of(w, ci)
	return ti >= 0 && prop_override_set(&w.char_types[ti].props, &w.characters[ci].overrides, p, value)
}

// --- Feature types ---

world_feature_type_add_prop :: proc(w: ^World, i: int, base := "property", value: i32 = 0) -> int {
	if i < 0 || i >= w.feature_type_count {
		return -1
	}
	return prop_set_add(&w.feature_types[i].props, base, value)
}

world_feature_type_delete_prop :: proc(w: ^World, i, p: int) -> bool {
	if i < 0 || i >= w.feature_type_count || !prop_set_delete(&w.feature_types[i].props, p) {
		return false
	}
	name := name_str(&w.feature_types[i].name)
	for f in 0 ..< w.feature_count {
		if name_str(&w.features[f].type) == name {
			prop_overrides_remove(&w.features[f].overrides, p)
		}
	}
	return true
}

@(private = "file")
feature_type_of :: proc(w: ^World, fi: int) -> int {
	if fi < 0 || fi >= w.feature_count {
		return -1
	}
	return world_find_feature_type(w, name_str(&w.features[fi].type))
}

world_feature_value :: proc(w: ^World, fi, p: int) -> i32 {
	ti := feature_type_of(w, fi)
	if ti < 0 {
		return 0
	}
	return prop_value(&w.feature_types[ti].props, &w.features[fi].overrides, p)
}

world_feature_set_value :: proc(w: ^World, fi, p: int, value: i32) -> bool {
	ti := feature_type_of(w, fi)
	return ti >= 0 && prop_override_set(&w.feature_types[ti].props, &w.features[fi].overrides, p, value)
}
