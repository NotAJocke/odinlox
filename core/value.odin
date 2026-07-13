package core

import "core:fmt"
Value :: f64

print_value :: proc(value: Value) {
	fmt.printf("%v", value)
}

