package core

import "core:fmt"

// The nil option isn't explicit, an union in odin
// can take the nil value if not #no_nil tagged
Value :: union {
	bool,
	f64,
}

print_value :: proc(value: Value) {
	switch v in value {
	case bool:
		if v {fmt.print("true")} else {fmt.print("false")}
	case f64:
		fmt.printf("%v", v)
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
	case nil:
		return true
	}

	unreachable()
}

