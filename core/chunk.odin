package core

import "core:fmt"

OpCode :: enum u8 {
	SET_GLOBAL,
	GET_GLOBAL,
	DEFINE_GLOBAL,
	CONSTANT,
	NIL,
	TRUE,
	FALSE,
	EQUAL,
	GREATER,
	LESS,
	NEGATE,
	PRINT,
	POP,
	NOT,
	ADD,
	SUBTRACT,
	MULTIPLY,
	DIVIDE,
	RETURN,
}

Chunk :: struct {
	code:      [dynamic]u8,
	constants: [dynamic]Value,
	lines:     [dynamic]int,
}

OpCodeByte :: union {
	OpCode,
	byte,
}

init_chunk :: proc(c: ^Chunk) {
	c.code = make([dynamic]u8)
	c.constants = make([dynamic]Value)
	c.lines = make([dynamic]int)
}

free_chunk :: proc(c: ^Chunk) {
	delete(c.code)
	delete(c.constants)
	delete(c.lines)
}


write_chunk :: proc(c: ^Chunk, opCodeByte: OpCodeByte, line: int) {
	b: byte

	switch ocb in opCodeByte {
	case byte:
		b = ocb
	case OpCode:
		b = u8(ocb)
	}

	append(&c.code, b)
	append(&c.lines, line)
}

add_constant :: proc(c: ^Chunk, value: Value) -> int {
	append(&c.constants, value)
	return len(c.constants) - 1
}

disassemble_chunk :: proc(c: ^Chunk, name: string) {
	fmt.printfln("== %v ==", name)

	for offset := 0; offset < len(c.code); {
		offset = disassemble_instruction(c, offset)
	}
}

@(private)
disassemble_instruction :: proc(c: ^Chunk, offset: int) -> int {
	fmt.printf("%04d ", offset)

	if offset > 0 && c.lines[offset] == c.lines[offset - 1] {
		fmt.printf("   | ")
	} else {
		fmt.printf("%4d ", c.lines[offset])
	}

	instruction := c.code[offset]
	switch OpCode(instruction) {
	case .RETURN:
		return simple_instruction("OP_RETURN", offset)
	case .CONSTANT:
		return constant_instruction("OP_CONSTANT", c, offset)
	case .NEGATE:
		return simple_instruction("OP_NEGATE", offset)
	case:
		fmt.printfln("Unknown OpCode %d\n", instruction)
		unreachable()
	case .ADD:
		return simple_instruction("OP_ADD", offset)
	case .SUBTRACT:
		return simple_instruction("OP_SUBSTRACT", offset)
	case .MULTIPLY:
		return simple_instruction("OP_MULTIPLY", offset)
	case .DIVIDE:
		return simple_instruction("OP_DIVIDE", offset)
	case .NIL:
		return simple_instruction("OP_NIL", offset)
	case .TRUE:
		return simple_instruction("OP_TRUE", offset)
	case .FALSE:
		return simple_instruction("OP_FALSE", offset)
	case .NOT:
		return simple_instruction("OP_NOT", offset)
	case .EQUAL:
		return simple_instruction("OP_EQUAL", offset)
	case .GREATER:
		return simple_instruction("OP_GREATER", offset)
	case .LESS:
		return simple_instruction("OP_LESS", offset)
	case .PRINT:
		return simple_instruction("OP_PRINT", offset)
	case .POP:
		return simple_instruction("OP_POP", offset)
	case .DEFINE_GLOBAL:
		return constant_instruction("OP_DEFINE_GLOBAL", c, offset)
	case .GET_GLOBAL:
		return constant_instruction("OP_GET_GLOBAL", c, offset)
	case .SET_GLOBAL:
		return constant_instruction("OP_SET_GLOBAL", c, offset)
	}

	return 0
}

@(private)
constant_instruction :: proc(name: string, chunk: ^Chunk, offset: int) -> int {
	constant := chunk.code[offset + 1]
	fmt.printf("%-16s %4d '", name, constant)
	print_value(chunk.constants[constant])
	fmt.println("'")
	return offset + 2
}

@(private)
simple_instruction :: proc(name: string, offset: int) -> int {
	fmt.printfln("%s", name)
	return offset + 1
}

