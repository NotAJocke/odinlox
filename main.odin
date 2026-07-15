#+feature using-stmt

package main

import "core:os"
import "core:strings"

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
	args := os.args

	if len(args) == 1 {
		repl(&vm)
	} else if len(args) == 2 {
		run_file(&vm, args[1])
	} else {
		fmt.eprintfln("Usage: odinlox [path]")
		os.exit(1)
	}

	free_vm()
}

@(private)
repl :: proc(vm: ^core.VM) {
	using core

	buf: [1024]u8

	for {
		fmt.print("> ")
		read, _ := os.read(os.stdin, buf[:])

		if read > 0 {
			line := strings.trim_right(string(buf[:read]), "\t\r\n")

			switch line {
			case ":q":
				return
			}

			interpret(vm, line)
		}

	}

}

@(private)
run_file :: proc(vm: ^core.VM, path: string) {
	using core

	data, err := os.read_entire_file_from_path(path, context.temp_allocator)

	if err != nil {
		fmt.eprintfln("Error reading file '%v'", path)
	}

	result := interpret(vm, string(data))

	free_all(context.temp_allocator)

	if result != .Ok {
		os.exit(1)
	}}

