package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Sprite sets of a world: named sets of named sprites, each a tile (tileset + image, by name) with
// a transparent colour index (or none). Sprites are not placed anywhere yet; creatures, items and
// features will use them. See world.odin for the types and the file format around this.

world_find_sprite_set :: proc(w: ^World, name: string, except := -1) -> int {
	for i in 0 ..< w.sprite_set_count {
		if i != except && name_str(&w.sprite_sets[i].name) == name {
			return i
		}
	}
	return -1
}

sprite_set_find :: proc(s: ^Sprite_Set, name: string, except := -1) -> int {
	for i in 0 ..< s.count {
		if i != except && name_str(&s.sprites[i].name) == name {
			return i
		}
	}
	return -1
}

world_check_sprite_set_name :: proc(w: ^World, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return world_find_sprite_set(w, name, index) >= 0 ? .In_Use : .None
}

sprite_check_name :: proc(s: ^Sprite_Set, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return sprite_set_find(s, name, index) >= 0 ? .In_Use : .None
}

@(private = "file")
sprite_set_names :: proc(w: ^World) -> []string {
	out := make([]string, w.sprite_set_count, context.temp_allocator)
	for i in 0 ..< w.sprite_set_count {
		out[i] = name_str(&w.sprite_sets[i].name)
	}
	return out
}

@(private = "file")
sprite_names :: proc(s: ^Sprite_Set) -> []string {
	out := make([]string, s.count, context.temp_allocator)
	for i in 0 ..< s.count {
		out[i] = name_str(&s.sprites[i].name)
	}
	return out
}

// The image a sprite draws, or nil while it is not set (or points at nothing).
world_sprite_image :: proc(w: ^World, sp: ^Sprite) -> ^Image4 {
	ti := world_find_tileset(w, name_str(&sp.tileset))
	if ti < 0 {
		return nil
	}
	ii := tileset_find(&w.tilesets[ti], name_str(&sp.image))
	return ii >= 0 ? &w.tilesets[ti].images[ii] : nil
}

// --- Sets --------------------------------------------------------------------------------------

// Adds an empty sprite set. Returns its index, or -1 if the world has 16.
world_add_sprite_set :: proc(w: ^World, base := "sprites") -> int {
	if w.sprite_set_count >= WORLD_MAX_SPRITE_SETS {
		return -1
	}
	i := w.sprite_set_count
	w.sprite_sets[i] = {}
	name_assign(&w.sprite_sets[i].name, unique_among(base, sprite_set_names(w)))
	w.sprite_set_count += 1
	return i
}

// Copies set i right after itself as "<name>_copy". Returns the new index or -1 if full.
world_duplicate_sprite_set :: proc(w: ^World, i: int) -> int {
	if i < 0 || i >= w.sprite_set_count || w.sprite_set_count >= WORLD_MAX_SPRITE_SETS {
		return -1
	}
	at := i + 1
	for k := w.sprite_set_count; k > at; k -= 1 {
		w.sprite_sets[k] = w.sprite_sets[k - 1]
	}
	w.sprite_sets[at] = w.sprite_sets[i]
	name_assign(&w.sprite_sets[at].name, unique_among(fmt.tprintf("%s_copy", name_str(&w.sprite_sets[i].name)), sprite_set_names(w)))
	w.sprite_set_count += 1
	return at
}

// How many character types draw sprites of this set.
world_sprite_set_uses :: proc(w: ^World, set: string) -> int {
	return world_sprite_set_char_type_uses(w, set) + world_sprite_set_feature_type_uses(w, set) + world_sprite_set_item_type_uses(w, set)
}

// How many character types draw this sprite.
world_sprite_uses :: proc(w: ^World, set, sprite: string) -> int {
	return world_sprite_char_type_uses(w, set, sprite) + world_sprite_feature_type_uses(w, set, sprite) + world_sprite_item_type_uses(w, set, sprite)
}

// Deletes set i unless a character type draws one of its sprites. Returns false if it is in use
// (or i is out of range): ask world_sprite_set_uses for the count first.
world_delete_sprite_set :: proc(w: ^World, i: int) -> bool {
	if i < 0 || i >= w.sprite_set_count || world_sprite_set_uses(w, name_str(&w.sprite_sets[i].name)) > 0 {
		return false
	}
	for k in i ..< w.sprite_set_count - 1 {
		w.sprite_sets[k] = w.sprite_sets[k + 1]
	}
	w.sprite_sets[w.sprite_set_count - 1] = {}
	w.sprite_set_count -= 1
	return true
}

world_rename_sprite_set :: proc(w: ^World, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= w.sprite_set_count {
		return .Empty
	}
	if p := world_check_sprite_set_name(w, i, name); p != .None {
		return p
	}
	char_types_follow_sprite_set(w, name_str(&w.sprite_sets[i].name), name)
	feature_types_follow_sprite_set(w, name_str(&w.sprite_sets[i].name), name)
	item_types_follow_sprite_set(w, name_str(&w.sprite_sets[i].name), name)
	name_assign(&w.sprite_sets[i].name, name)
	return .None
}

// --- Sprites -----------------------------------------------------------------------------------

// Adds a sprite to set si: "sprite", pointing at the first image of the first tileset that has
// one (not set if there is none), transparent colour 0. Returns its index or -1 if the set is full.
world_add_sprite :: proc(w: ^World, si: int) -> int {
	if si < 0 || si >= w.sprite_set_count || w.sprite_sets[si].count >= SPRITE_MAX {
		return -1
	}
	s := &w.sprite_sets[si]
	i := s.count
	s.sprites[i] = {
		transparent = 0,
	}
	name_assign(&s.sprites[i].name, unique_among("sprite", sprite_names(s)))
	for t in 0 ..< w.tileset_count {
		if w.tilesets[t].count > 0 {
			s.sprites[i].tileset = w.tileset_names[t]
			name_assign(&s.sprites[i].image, tileset_name(&w.tilesets[t], 0))
			break
		}
	}
	s.count += 1
	return i
}

// Appends a copy of sprite i of set si as "<name>_copy". Returns its index or -1 if full.
world_duplicate_sprite :: proc(w: ^World, si, i: int) -> int {
	if si < 0 || si >= w.sprite_set_count {
		return -1
	}
	s := &w.sprite_sets[si]
	if i < 0 || i >= s.count || s.count >= SPRITE_MAX {
		return -1
	}
	n := s.count
	s.sprites[n] = s.sprites[i]
	name_assign(&s.sprites[n].name, unique_among(fmt.tprintf("%s_copy", name_str(&s.sprites[i].name)), sprite_names(s)))
	s.count += 1
	return n
}

// Deletes sprite i of set si unless a character type draws it (then false: ask world_sprite_uses).
world_delete_sprite :: proc(w: ^World, si, i: int) -> bool {
	if si < 0 || si >= w.sprite_set_count {
		return false
	}
	s := &w.sprite_sets[si]
	if i < 0 || i >= s.count || world_sprite_uses(w, name_str(&s.name), name_str(&s.sprites[i].name)) > 0 {
		return false
	}
	for k in i ..< s.count - 1 {
		s.sprites[k] = s.sprites[k + 1]
	}
	s.sprites[s.count - 1] = {}
	s.count -= 1
	return true
}

// --- References --------------------------------------------------------------------------------

world_tileset_sprite_uses :: proc(w: ^World, tileset: string) -> (n: int) {
	for si in 0 ..< w.sprite_set_count {
		for i in 0 ..< w.sprite_sets[si].count {
			if name_str(&w.sprite_sets[si].sprites[i].tileset) == tileset {
				n += 1
			}
		}
	}
	return
}

world_image_sprite_uses :: proc(w: ^World, tileset, image: string) -> (n: int) {
	for si in 0 ..< w.sprite_set_count {
		for i in 0 ..< w.sprite_sets[si].count {
			sp := &w.sprite_sets[si].sprites[i]
			if name_str(&sp.tileset) == tileset && name_str(&sp.image) == image {
				n += 1
			}
		}
	}
	return
}

// A tileset was renamed: its sprites follow.
sprites_follow_tileset :: proc(w: ^World, old, new: string) {
	for si in 0 ..< w.sprite_set_count {
		for i in 0 ..< w.sprite_sets[si].count {
			sp := &w.sprite_sets[si].sprites[i]
			if name_str(&sp.tileset) == old {
				name_assign(&sp.tileset, new)
			}
		}
	}
}

// An image was renamed: its sprites follow.
sprites_follow_image :: proc(w: ^World, tileset, old, new: string) {
	for si in 0 ..< w.sprite_set_count {
		for i in 0 ..< w.sprite_sets[si].count {
			sp := &w.sprite_sets[si].sprites[i]
			if name_str(&sp.tileset) == tileset && name_str(&sp.image) == old {
				name_assign(&sp.image, new)
			}
		}
	}
}

// "3 TERRAINS" or "3 TERRAINS AND 2 SPRITES": what stands in the way of deleting a tileset or image.
uses_text :: proc(terrains, sprites: int) -> string {
	if sprites == 0 {
		return fmt.tprintf("%d TERRAIN%s", terrains, terrains == 1 ? "" : "S")
	}
	return fmt.tprintf("%d TERRAIN%s AND %d SPRITE%s", terrains, terrains == 1 ? "" : "S", sprites, sprites == 1 ? "" : "S")
}

// --- File format -------------------------------------------------------------------------------
//
//   "sprite_sets": [ { "name": "creatures",
//                      "sprites": [ { "name": "slime", "tileset": "ground", "image": "g3",
//                                     "transparent": 0 } ] } ]
// "transparent" is a palette index 0..15, or null for none. "tileset" and "image" follow the
// terrain rules (both "" for not set, otherwise they must exist). The whole "sprite_sets" list is
// optional when reading.

write_sprite_sets :: proc(b: ^strings.Builder, w: ^World) {
	strings.write_string(b, "  \"sprite_sets\": [")
	for si in 0 ..< w.sprite_set_count {
		s := &w.sprite_sets[si]
		strings.write_string(b, si == 0 ? "\n" : ",\n")
		fmt.sbprintf(b, "    {{\"name\": \"%s\", \"sprites\": [", escape_name(name_str(&s.name)))
		for i in 0 ..< s.count {
			sp := &s.sprites[i]
			strings.write_string(b, i == 0 ? "\n" : ",\n")
			transparent := "null"
			if sp.transparent >= 0 {
				transparent = fmt.tprintf("%d", sp.transparent)
			}
			fmt.sbprintf(
				b,
				"      {{\"name\": \"%s\", \"tileset\": \"%s\", \"image\": \"%s\", \"transparent\": %s}}",
				escape_name(name_str(&sp.name)),
				escape_name(name_str(&sp.tileset)),
				escape_name(name_str(&sp.image)),
				transparent,
			)
		}
		strings.write_string(b, s.count == 0 ? "]}" : "\n    ]}")
	}
	strings.write_string(b, w.sprite_set_count == 0 ? "],\n" : "\n  ],\n")
}

read_sprite_sets :: proc(root: json.Object, tmp: ^World) -> (err: string) {
	list, present := root["sprite_sets"]
	if !present {
		return ""
	}
	sets, is_list := list.(json.Array)
	if !is_list {
		return `"sprite_sets" must be a list`
	}
	if len(sets) > WORLD_MAX_SPRITE_SETS {
		return fmt.tprintf("%d sprite sets is more than the %d allowed", len(sets), WORLD_MAX_SPRITE_SETS)
	}
	for item, si in sets {
		obj, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("sprite set %d must be an object", si)
		}
		name, name_ok := obj["name"].(json.String)
		if !name_ok {
			return fmt.tprintf(`sprite set %d: "name" must be text`, si)
		}
		if p := world_check_sprite_set_name(tmp, -1, name); p != .None {
			return fmt.tprintf(`sprite set %d: the name "%s" is %v`, si, name, name_problem_text(p))
		}
		s := &tmp.sprite_sets[si]
		name_assign(&s.name, name)
		sprites, _ := obj["sprites"].(json.Array)
		if len(sprites) > SPRITE_MAX {
			return fmt.tprintf(`sprite set "%s": more than %d sprites`, name, SPRITE_MAX)
		}
		for sitem, i in sprites {
			sobj, sok := sitem.(json.Object)
			if !sok {
				return fmt.tprintf(`sprite set "%s": sprite %d must be an object`, name, i)
			}
			sname, sname_ok := sobj["name"].(json.String)
			if !sname_ok {
				return fmt.tprintf(`sprite set "%s": sprite %d needs a "name"`, name, i)
			}
			s.count = i // uniqueness is checked against the earlier sprites only
			if p := sprite_check_name(s, -1, sname); p != .None {
				return fmt.tprintf(`sprite set "%s": the sprite name "%s" is %v`, name, sname, name_problem_text(p))
			}
			sp := &s.sprites[i]
			name_assign(&sp.name, sname)
			#partial switch t in sobj["transparent"] {
			case json.Integer:
				if t < 0 || t >= IMAGE_COLORS {
					return fmt.tprintf(`sprite "%s": "transparent" must be 0 to %d or null`, sname, IMAGE_COLORS - 1)
				}
				sp.transparent = int(t)
			case json.Null:
				sp.transparent = SPRITE_NO_TRANSPARENT
			case:
				return fmt.tprintf(`sprite "%s": "transparent" must be 0 to %d or null`, sname, IMAGE_COLORS - 1)
			}
			ts_name, ts_ok := sobj["tileset"].(json.String)
			img_name, img_ok := sobj["image"].(json.String)
			if !ts_ok || !img_ok {
				return fmt.tprintf(`sprite "%s": "tileset" and "image" must be text ("" for not set)`, sname)
			}
			if (len(ts_name) == 0) != (len(img_name) == 0) {
				return fmt.tprintf(`sprite "%s": "tileset" and "image" must both be set or both be ""`, sname)
			}
			if len(ts_name) > 0 {
				k := world_find_tileset(tmp, ts_name)
				if k < 0 {
					return fmt.tprintf(`sprite "%s": there is no tileset "%s"`, sname, ts_name)
				}
				if tileset_find(&tmp.tilesets[k], img_name) < 0 {
					return fmt.tprintf(`sprite "%s": tileset "%s" has no image "%s"`, sname, ts_name, img_name)
				}
				name_assign(&sp.tileset, ts_name)
				name_assign(&sp.image, img_name)
			}
		}
		s.count = len(sprites)
		tmp.sprite_set_count += 1
	}
	return ""
}

// Renames sprite i of set si; the character types drawing it follow.
world_rename_sprite :: proc(w: ^World, si, i: int, name: string) -> Name_Problem {
	if si < 0 || si >= w.sprite_set_count || i < 0 || i >= w.sprite_sets[si].count {
		return .Empty
	}
	s := &w.sprite_sets[si]
	if p := sprite_check_name(s, i, name); p != .None {
		return p
	}
	char_types_follow_sprite(w, name_str(&s.name), name_str(&s.sprites[i].name), name)
	feature_types_follow_sprite(w, name_str(&s.name), name_str(&s.sprites[i].name), name)
	item_types_follow_sprite(w, name_str(&s.name), name_str(&s.sprites[i].name), name)
	name_assign(&s.sprites[i].name, name)
	return .None
}
