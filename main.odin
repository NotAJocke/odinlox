#+feature using-stmt

package main


import "core:fmt"
import "core:mem"

import "core"

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	using core

	vm := new_vm(ODIN_DEBUG)

	chunk := new_chunk()

	constant := add_constant(&chunk, 1.2)
	write_chunk(&chunk, OpCode.CONSTANT, 123)
	write_chunk(&chunk, u8(constant), 123)


	constant = add_constant(&chunk, 3.4)
	write_chunk(&chunk, OpCode.CONSTANT, 123)
	write_chunk(&chunk, u8(constant), 123)

	write_chunk(&chunk, OpCode.ADD, 123)

	constant = add_constant(&chunk, 5.6)
	write_chunk(&chunk, OpCode.CONSTANT, 123)
	write_chunk(&chunk, u8(constant), 123)

	write_chunk(&chunk, OpCode.DIVIDE, 123)


	write_chunk(&chunk, OpCode.NEGATE, 123)
	write_chunk(&chunk, OpCode.RETURN, 123)
	disassemble_chunk(&chunk, "test chunk")

	interpret(&vm, &chunk)

	free_chunk(&chunk)
	free_vm()
}

