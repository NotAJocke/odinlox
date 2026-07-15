package core

import "core:hash"
TABLE_MAX_LOAD :: 0.75

Entry :: struct {
	key:   ^ObjString,
	value: Value,
}

Table :: struct {
	//Capacity == len(entries)
	count:   int,
	entries: [dynamic]Entry,
}

table_init :: proc(t: ^Table) {
	t.count = 0
	t.entries = make([dynamic]Entry, 0)
}

table_free :: proc(t: ^Table) {
	delete(t.entries)
	// table_init(t)
}

table_get :: proc(t: ^Table, key: ^ObjString) -> Maybe(^Value) {
	if t.count == 0 {return nil}

	entry := find_entry(t.entries, capacity(t), key)
	if entry.key == nil {return nil}

	return &entry.value
}

table_set :: proc(t: ^Table, key: ^ObjString, value: Value) -> bool {
	if f32(t.count + 1) > f32(capacity(t)) * TABLE_MAX_LOAD {
		current_cap := capacity(t)
		new_cap := current_cap < 8 ? 8 : current_cap * 2
		adjust_capacity(t, new_cap)
	}

	entry := find_entry(t.entries, capacity(t), key)

	is_new := entry.key == nil
	if is_new && entry.value == nil {t.count += 1}

	entry.key = key
	entry.value = value

	return is_new
}

table_add_all :: proc(from: ^Table, to: ^Table) {
	for &e in from.entries {
		if e.key != nil {
			table_set(to, e.key, e.value)
		}
	}
}

table_delete :: proc(t: ^Table, key: ^ObjString) -> bool {
	if t.count == 0 {return false}

	entry := find_entry(t.entries, capacity(t), key)
	if entry.key == nil {return false}

	entry.key = nil
	entry.value = true

	return true
}

table_find_string :: proc(t: ^Table, query: string, hash: u32) -> Maybe(^ObjString) {
	if t.count == 0 {return nil}

	index := hash % u32(capacity(t))

	for {
		entry := t.entries[index]

		if entry.key == nil {
			if entry.value == nil {return nil}
		} else if entry.key.data == query {
			return entry.key
		}

		index = (index + 1) % u32(capacity(t))
	}
}

@(private = "file")
find_entry :: proc(entries: [dynamic]Entry, capacity: int, key: ^ObjString) -> ^Entry {
	index := key.hash % u32(capacity)
	tombstone: ^Entry = nil

	for {
		entry := &entries[index]

		if entry.key == nil {
			if entry.value == nil {
				// empty entry
				return tombstone != nil ? tombstone : entry
			} else {
				// found tombstone
				if tombstone == nil {tombstone = entry}
			}
		} else if entry.key == key {
			// we found the key
			return entry
		}

		index = (index + 1) % u32(capacity)
	}
}


@(private = "file")
capacity :: proc(t: ^Table) -> int {
	return len(t.entries)
}


@(private = "file")
adjust_capacity :: proc(t: ^Table, new_capacity: int) {
	entries := make([dynamic]Entry, new_capacity)
	for &e in entries {
		e.key = nil
		e.value = nil
	}

	t.count = 0
	for &e in t.entries {
		if e.key == nil {continue}

		dest := find_entry(entries, new_capacity, e.key)
		dest.key = e.key
		dest.value = e.value
		t.count += 1
	}

	delete(t.entries)
	t.entries = entries
}

