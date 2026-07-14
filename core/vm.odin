package core

import "core:fmt"

InterpretResult :: enum {
	Ok,
	CompileError,
	RuntimeError,
}

STACK_MAX :: 256

VM :: struct {
	chunk: ^Chunk,
	ip:    int,
	debug: bool,
	stack: [dynamic; STACK_MAX]Value,
}

new_vm :: proc(debug: bool) -> VM {
	return VM{chunk = nil, ip = 0, debug = debug, stack = [dynamic; STACK_MAX]Value{}}
}

free_vm :: proc() {}

interpret :: proc(vm: ^VM, source: string) -> InterpretResult {
	chunk: Chunk
	init_chunk(&chunk)

	r := compile(source, &chunk)
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
			print_value(pop(&vm.stack))
			fmt.println()
			return .Ok
		case .NEGATE:
			value := pop(&vm.stack)
			#partial switch v in value {
			case f64:
				append(&vm.stack, -v)
			case:
				runtime_error(vm, "Operand must be a number.")
			}
		case .ADD, .SUBTRACT, .MULTIPLY, .DIVIDE, .GREATER, .LESS:
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

