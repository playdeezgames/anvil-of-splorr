package common

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// Numeric properties: a short list of named 32-bit whole numbers. Item types are the first to have
// them (a sword's damage, a coin's value); characters and features can adopt the same Prop_Set later.
// A Prop_Set holds the names and default values; a Prop_Overrides holds the values one thing (an
// inventory entry) has changed, by position in the set.

PROP_MAX :: 16

Prop_Set :: struct {
	count:  int, // 0..PROP_MAX
	names:  [PROP_MAX]Name, // unique within the set
	values: [PROP_MAX]i32, // the defaults
}

// Which properties an owner has changed (bit i = property i of its Prop_Set) and to what. A value that
// equals the default is never kept as an override (see prop_override_set), so two owners that end up
// with the same numbers also have the same overrides.
Prop_Overrides :: struct {
	mask:   u16,
	values: [PROP_MAX]i32,
}

prop_set_find :: proc(s: ^Prop_Set, name: string, except := -1) -> int {
	for i in 0 ..< s.count {
		if i != except && name_str(&s.names[i]) == name {
			return i
		}
	}
	return -1
}

prop_set_check_name :: proc(s: ^Prop_Set, index: int, name: string) -> Name_Problem {
	if p := name_text_problem(name); p != .None {
		return p
	}
	return prop_set_find(s, name, index) >= 0 ? .In_Use : .None
}

@(private = "file")
prop_set_names :: proc(s: ^Prop_Set) -> []string {
	out := make([]string, s.count, context.temp_allocator)
	for i in 0 ..< s.count {
		out[i] = name_str(&s.names[i])
	}
	return out
}

// Adds a property (a unique name made from `base`) with a default value. Returns its index or -1 if full.
prop_set_add :: proc(s: ^Prop_Set, base := "property", value: i32 = 0) -> int {
	if s.count >= PROP_MAX {
		return -1
	}
	i := s.count
	name_assign(&s.names[i], unique_among(base, prop_set_names(s)))
	s.values[i] = value
	s.count += 1
	return i
}

prop_set_rename :: proc(s: ^Prop_Set, i: int, name: string) -> Name_Problem {
	if i < 0 || i >= s.count {
		return .Empty
	}
	if p := prop_set_check_name(s, i, name); p != .None {
		return p
	}
	name_assign(&s.names[i], name)
	return .None
}

// Closes the gap; the caller must run prop_overrides_remove on everything that has overrides for this set.
prop_set_delete :: proc(s: ^Prop_Set, i: int) -> bool {
	if i < 0 || i >= s.count {
		return false
	}
	for k in i ..< s.count - 1 {
		s.names[k] = s.names[k + 1]
		s.values[k] = s.values[k + 1]
	}
	s.names[s.count - 1] = {}
	s.values[s.count - 1] = 0
	s.count -= 1
	return true
}

// The value of property i for something with these overrides: its own, else the default.
prop_value :: proc(s: ^Prop_Set, o: ^Prop_Overrides, i: int) -> i32 {
	if i < 0 || i >= s.count {
		return 0
	}
	if o.mask & (1 << uint(i)) != 0 {
		return o.values[i]
	}
	return s.values[i]
}

// Sets property i to `value`; a value equal to the default drops the override instead.
prop_override_set :: proc(s: ^Prop_Set, o: ^Prop_Overrides, i: int, value: i32) -> bool {
	if i < 0 || i >= s.count {
		return false
	}
	if value == s.values[i] {
		prop_override_clear(o, i)
		return true
	}
	o.mask |= 1 << uint(i)
	o.values[i] = value
	return true
}

// Back to the default.
prop_override_clear :: proc(o: ^Prop_Overrides, i: int) {
	if i >= 0 && i < PROP_MAX {
		o.mask &~= 1 << uint(i)
		o.values[i] = 0
	}
}

// Property i of the set was deleted: the overrides above it move down one place.
prop_overrides_remove :: proc(o: ^Prop_Overrides, i: int) {
	if i < 0 || i >= PROP_MAX {
		return
	}
	for k in i ..< PROP_MAX - 1 {
		o.values[k] = o.values[k + 1]
	}
	o.values[PROP_MAX - 1] = 0
	low := u16(1 << uint(i)) - 1
	o.mask = (o.mask & low) | ((o.mask >> uint(i + 1)) << uint(i))
}

// True if every property has the same value for both (whatever way each got it).
prop_values_equal :: proc(s: ^Prop_Set, a, b: ^Prop_Overrides) -> bool {
	for i in 0 ..< s.count {
		if prop_value(s, a, i) != prop_value(s, b, i) {
			return false
		}
	}
	return true
}

// --- File format -------------------------------------------------------------------------------
//
//   "props": [ { "name": "damage", "value": 5 }, { "name": "durability", "value": 100 } ]   (a Prop_Set)
//   "props": { "durability": 40 }                                                             (overrides)

write_prop_set :: proc(b: ^strings.Builder, s: ^Prop_Set) {
	strings.write_string(b, "[")
	for i in 0 ..< s.count {
		fmt.sbprintf(b, "%s{{\"name\": \"%s\", \"value\": %d}}", i == 0 ? "" : ", ", escape_name(name_str(&s.names[i])), s.values[i])
	}
	strings.write_string(b, "]")
}

write_prop_overrides :: proc(b: ^strings.Builder, s: ^Prop_Set, o: ^Prop_Overrides) {
	strings.write_string(b, "{")
	first := true
	for i in 0 ..< s.count {
		if o.mask & (1 << uint(i)) != 0 {
			fmt.sbprintf(b, "%s\"%s\": %d", first ? "" : ", ", escape_name(name_str(&s.names[i])), o.values[i])
			first = false
		}
	}
	strings.write_string(b, "}")
}

// "props" in a type object: optional, a list of {name, value}. `what` names the owner in errors.
read_prop_set :: proc(obj: json.Object, s: ^Prop_Set, what: string) -> (err: string) {
	v, present := obj["props"]
	if !present {
		return ""
	}
	list, is_list := v.(json.Array)
	if !is_list {
		return fmt.tprintf(`%s: "props" must be a list`, what)
	}
	if len(list) > PROP_MAX {
		return fmt.tprintf("%s: %d properties is more than the %d allowed", what, len(list), PROP_MAX)
	}
	for item, i in list {
		e, ok := item.(json.Object)
		if !ok {
			return fmt.tprintf("%s: property %d must be an object", what, i)
		}
		name, name_ok := e["name"].(json.String)
		if !name_ok {
			return fmt.tprintf(`%s: property %d needs a "name" in text`, what, i)
		}
		if p := prop_set_check_name(s, -1, name); p != .None {
			return fmt.tprintf(`%s: the property name "%s" is %v`, what, name, name_problem_text(p))
		}
		n, n_ok := e["value"].(json.Integer)
		if !n_ok || n < i64(min(i32)) || n > i64(max(i32)) {
			return fmt.tprintf(`%s: property "%s" needs a whole "value" that fits in 32 bits`, what, name)
		}
		name_assign(&s.names[s.count], name)
		s.values[s.count] = i32(n)
		s.count += 1
	}
	return ""
}

// "props" in an entry object: optional, an object of name -> whole number; every name must be one of s.
read_prop_overrides :: proc(obj: json.Object, s: ^Prop_Set, o: ^Prop_Overrides, what: string) -> (err: string) {
	v, present := obj["props"]
	if !present {
		return ""
	}
	e, is_obj := v.(json.Object)
	if !is_obj {
		return fmt.tprintf(`%s: "props" must be an object of name: number`, what)
	}
	for key, val in e {
		i := prop_set_find(s, key)
		if i < 0 {
			return fmt.tprintf(`%s: there is no property "%s"`, what, key)
		}
		n, n_ok := val.(json.Integer)
		if !n_ok || n < i64(min(i32)) || n > i64(max(i32)) {
			return fmt.tprintf(`%s: property "%s" must be a whole number that fits in 32 bits`, what, key)
		}
		prop_override_set(s, o, i, i32(n))
	}
	return ""
}
