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
			append(&vm.stack, -pop(&vm.stack))
		case .ADD:
			fallthrough
		case .SUBTRACT:
			fallthrough
		case .MULTIPLY:
			fallthrough
		case .DIVIDE:
			binary_op(vm, instruction)
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
binary_op :: proc(vm: ^VM, instruction: OpCode) {
	b := pop(&vm.stack)
	a := pop(&vm.stack)

	#partial switch instruction {
	case .ADD:
		append(&vm.stack, a + b)
	case .SUBTRACT:
		append(&vm.stack, a - b)
	case .MULTIPLY:
		append(&vm.stack, a * b)
	case .DIVIDE:
		append(&vm.stack, a / b)
	case:
		fmt.printfln("Got impossible binary op: %v", instruction)
	}
}

