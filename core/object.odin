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
}

ObjAllocTrack :: proc(_: ^Obj)

is_obj_type :: proc(value: Value, type: ObjType) -> bool {
	obj, ok := value.(^Obj)

	return ok && obj.type == type
}

obj_string_copy :: proc(data: string, cb: ObjAllocTrack) -> ^ObjString {
	buf := make([]u8, len(data))
	copy(buf, data)
	return obj_string_new(string(buf), cb)
}

obj_string_take :: proc(data: string, cb: ObjAllocTrack) -> ^ObjString {
	return obj_string_new(data, cb)
}

obj_string_new :: proc(data: string, cb: ObjAllocTrack) -> ^ObjString {
	obj := cast(^ObjString)obj_allocate(.String, cb)

	obj.data = data

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

