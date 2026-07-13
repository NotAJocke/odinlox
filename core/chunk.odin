package core

import "core:fmt"

OpCode :: enum u8 {
	CONSTANT,
	RETURN,
}

Chunk :: struct {
	code:      [dynamic]u8,
	constants: [dynamic]Value,
	lines:     [dynamic]int,
}

new_chunk :: proc() -> Chunk {
	return Chunk {
		code = make([dynamic]u8),
		constants = make([dynamic]Value),
		lines = make([dynamic]int),
	}
}

free_chunk :: proc(c: ^Chunk) {
	delete(c.code)
	delete(c.constants)
	delete(c.lines)
}


write_chunk_code :: proc(c: ^Chunk, byte: OpCode, line: int) {
	write_chunk_byte(c, u8(byte), line)
}

write_chunk_byte :: proc(c: ^Chunk, byte: u8, line: int) {
	append(&c.code, byte)
	append(&c.lines, line)
}

write_chunk :: proc {
	write_chunk_byte,
	write_chunk_code,
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
	case:
		fmt.printfln("Unknown OpCode %d\n", instruction)
		unreachable()
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

