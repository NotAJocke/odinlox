package core

import "core:fmt"

// The nil option isn't explicit, an union in odin
// can take the nil value if not #no_nil tagged
Value :: union {
	bool,
	f64,
	^Obj,
}

print_value :: proc(value: Value) {
	switch v in value {
	case bool:
		if v {fmt.print("true")} else {fmt.print("false")}
	case f64:
		fmt.printf("%v", v)
	case ^Obj:
		obj_print(v)
	case nil:
		fmt.printf("nil")
	}
}

values_equal :: proc(lhs: Value, rhs: Value) -> bool {
	switch v in lhs {
	case bool:
		w, ok := rhs.(bool)
		if !ok {return false}

		return v == w
	case f64:
		w, ok := rhs.(f64)
		if !ok {return false}

		return v == w
	case ^Obj:
		w, ok := rhs.(^Obj)
		if !ok {return false}

		s1 := cast(^ObjString)v
		s2 := cast(^ObjString)w

		return s1 == s2
	case nil:
		return true
	}

	unreachable()
}

