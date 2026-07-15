package core

import "core:fmt"
import "core:strings"

InterpretResult :: enum {
	Ok,
	CompileError,
	RuntimeError,
}

STACK_MAX :: 256

VM :: struct {
	chunk:   ^Chunk,
	ip:      int,
	debug:   bool,
	stack:   [dynamic; STACK_MAX]Value,
	strings: Table,
	globals: Table,
}

new_vm :: proc(debug: bool) -> VM {
	strings: Table
	table_init(&strings)

	globals: Table
	table_init(&globals)

	return VM {
		chunk = nil,
		ip = 0,
		debug = debug,
		stack = [dynamic; STACK_MAX]Value{},
		strings = strings,
		globals = globals,
	}
}

free_vm :: proc(vm: ^VM) {
	table_free(&vm.strings)
	table_free(&vm.globals)
	obj_pool_free()
	delete(obj_pool)
}

interpret :: proc(vm: ^VM, source: string) -> InterpretResult {
	chunk: Chunk
	init_chunk(&chunk)

	r := compile(source, &chunk, &vm.strings)
	if r != .Ok {
		free_chunk(&chunk)
		return r
	}

	vm.chunk = &chunk
	vm.ip = 0

	result := run(vm)

	free_chunk(&chunk)

	return result
}

@(private)
run :: proc(vm: ^VM) -> InterpretResult {

	for {
		if vm.debug {
			fmt.printf("          ")
			for slot in vm.stack {
				fmt.printf("[ ")
				print_value(slot)
				fmt.printf(" ]")
			}


			fmt.println()

			disassemble_instruction(vm.chunk, vm.ip)
		}

		instruction := OpCode(read_byte(vm))
		switch instruction {
		case .CONSTANT:
			constant := read_constant(vm)
			append(&vm.stack, constant)
		case .RETURN:
			return .Ok
		case .NEGATE:
			value := pop(&vm.stack)
			#partial switch v in value {
			case f64:
				append(&vm.stack, -v)
			case:
				runtime_error(vm, "Operand must be a number.")
			}
		case .ADD:
			v1 := peek(vm, 0)
			v2 := peek(vm, 1)

			n1, is_n1 := v1.(f64)
			n2, is_n2 := v2.(f64)

			if is_obj_type(v1, .String) && is_obj_type(v2, .String) {
				pop(&vm.stack) // s1
				pop(&vm.stack) // s2

				s1 := cast(^ObjString)v1.(^Obj)
				s2 := cast(^ObjString)v2.(^Obj)
				concatenate(vm, s2, s1)
			} else if is_n1 && is_n2 {
				pop(&vm.stack) // n1
				pop(&vm.stack) // n2

				append(&vm.stack, n1 + n2)
			} else {
				runtime_error(vm, "Operands must be two numbers or two strings.")
				return .RuntimeError
			}
		case .SUBTRACT, .MULTIPLY, .DIVIDE, .GREATER, .LESS:
			binary_op(vm, instruction)
		case .NIL:
			append(&vm.stack, nil)
		case .TRUE:
			append(&vm.stack, true)
		case .FALSE:
			append(&vm.stack, false)
		case .NOT:
			append(&vm.stack, is_falsey(pop(&vm.stack)))
		case .EQUAL:
			b := pop(&vm.stack)
			a := pop(&vm.stack)
			append(&vm.stack, values_equal(a, b))
		case .PRINT:
			print_value(pop(&vm.stack))
			fmt.println()
		case .POP:
			pop(&vm.stack)
		case .DEFINE_GLOBAL:
			name := read_string(vm)
			table_set(&vm.globals, name, peek(vm, 0))
			pop(&vm.stack)
		case .GET_GLOBAL:
			name := read_string(vm)
			value, ok := table_get(&vm.globals, name).?

			if !ok {
				runtime_error(vm, "Undefined variable '%s'.", name.data)
				return .RuntimeError
			}

			append(&vm.stack, value^)
		case .SET_GLOBAL:
			name := read_string(vm)

			if table_set(&vm.globals, name, peek(vm, 0)) {
				table_delete(&vm.globals, name)
				runtime_error(vm, "Undefined variable '%s'.", name.data)
				return .RuntimeError
			}
		case .GET_LOCAL:
			slot := read_byte(vm)
			append(&vm.stack, vm.stack[slot])
		case .SET_LOCAL:
			slot := read_byte(vm)
			vm.stack[slot] = peek(vm, 0)
		}
	}
}

@(private)
read_byte :: proc(vm: ^VM) -> u8 {
	vm.ip += 1
	return vm.chunk.code[vm.ip - 1]
}

@(private)
read_constant :: proc(vm: ^VM) -> Value {
	return vm.chunk.constants[read_byte(vm)]
}

@(private = "file")
read_string :: proc(vm: ^VM) -> ^ObjString {
	return cast(^ObjString)read_constant(vm).(^Obj)
}

@(private)
reset_stack :: proc(vm: ^VM) {
	clear(&vm.stack)
}

@(private)
binary_op :: proc(vm: ^VM, instruction: OpCode) -> InterpretResult {
	x := peek(vm, 0)
	y := peek(vm, 1)

	b, ok := x.(f64)
	a, ok2 := y.(f64)

	if !ok || !ok2 {
		runtime_error(vm, "Operands must be numbers.")
		return .RuntimeError
	}

	_ = pop(&vm.stack) // b
	_ = pop(&vm.stack) // a

	#partial switch instruction {
	case .ADD:
		append(&vm.stack, a + b)
	case .SUBTRACT:
		append(&vm.stack, a - b)
	case .MULTIPLY:
		append(&vm.stack, a * b)
	case .DIVIDE:
		append(&vm.stack, a / b)
	case .GREATER:
		append(&vm.stack, a > b)
	case .LESS:
		append(&vm.stack, a < b)
	case:
		fmt.printfln("Got impossible binary op: %v", instruction)
	}

	return .Ok
}

@(private = "file")
peek :: proc(vm: ^VM, distance: int) -> Value {
	return vm.stack[len(vm.stack) - 1 - distance]
}

@(private = "file")
runtime_error :: proc(vm: ^VM, message: string, args: ..any) {
	fmt.eprintfln(message, args)

	instruction := vm.ip - 1
	line := vm.chunk.lines[instruction]

	fmt.eprintfln("[line %d] in script", line)

	reset_stack(vm)
}

@(private = "file")
is_falsey :: proc(value: Value) -> bool {
	b, is_bool := value.(bool)
	return value == nil || (is_bool && !b)
}


@(private = "file")
concatenate :: proc(vm: ^VM, s1: ^ObjString, s2: ^ObjString) {
	new_string := strings.concatenate({s1.data, s2.data})
	new_obj := obj_string_take(new_string, &vm.strings, obj_allocated_cb)

	append(&vm.stack, cast(^Obj)new_obj)
}


obj_pool: [dynamic]^Obj
@(private = "file")
obj_pool_free :: proc() {
	for obj in obj_pool {
		obj_free(obj)
	}
}
obj_allocated_cb :: proc(obj: ^Obj) {
	append(&obj_pool, obj)
}

