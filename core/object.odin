package core

import "core:fmt"

ObjType :: enum {
	String,
}

Obj :: struct {
	type: ObjType,
}

ObjString :: struct {
	obj:  Obj,
	data: string,
	hash: u32,
}

ObjAllocTrack :: proc(_: ^Obj)

is_obj_type :: proc(value: Value, type: ObjType) -> bool {
	obj, ok := value.(^Obj)

	return ok && obj.type == type
}

obj_string_copy :: proc(data: string, strings: ^Table, cb: ObjAllocTrack) -> ^ObjString {
	hash := hash_string(data)

	maybe_interned := table_find_string(strings, data, hash)
	interned, ok := maybe_interned.?
	if ok {return interned}

	buf := make([]u8, len(data))
	copy(buf, data)

	return obj_string_new(string(buf), hash, strings, cb)
}

obj_string_take :: proc(data: string, strings: ^Table, cb: ObjAllocTrack) -> ^ObjString {
	hash := hash_string(data)

	maybe_interned := table_find_string(strings, data, hash)
	interned, ok := maybe_interned.?
	if ok {
		delete(data)
		return interned
	}

	return obj_string_new(data, hash, strings, cb)
}

obj_string_new :: proc(data: string, hash: u32, strings: ^Table, cb: ObjAllocTrack) -> ^ObjString {
	obj := cast(^ObjString)obj_allocate(.String, cb)
	obj.data = data
	obj.hash = hash

	table_set(strings, obj, nil)

	return obj
}

@(private = "file")
obj_allocate :: proc(otype: ObjType, cb: ObjAllocTrack) -> ^Obj {
	obj := new(Obj)
	obj.type = otype

	cb(obj)

	return obj
}

obj_free :: proc(obj: ^Obj) {
	switch obj.type {
	case .String:
		o := cast(^ObjString)obj
		delete(o.data)
		free(o)
	}
}

obj_print :: proc(value: Value) {
	// invariant: value is of type ^Obj here
	obj := value.(^Obj)

	switch obj.type {
	case .String:
		v := cast(^ObjString)obj
		fmt.printf("%v", v.data)
	}
}


@(private = "file")
hash_string :: proc(data: string) -> u32 {
	hash: u32 = 2166136261

	bytes := transmute([]u8)data

	for b in bytes {
		hash ~= u32(b)
		hash *= 16777619
	}

	return hash
}

