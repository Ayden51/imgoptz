package main

import "core:os"

cleanup_test_directory :: proc(path: string) {
	remove_test_directory_tree(path)
	delete(path)
}

cleanup_test_file :: proc(path: string) {
	os.remove(path)
	delete(path)
}

remove_test_directory_tree :: proc(path: string) {
	entries, entries_err := os.read_directory_by_path(path, 0, context.allocator)
	if entries_err == nil {
		for entry in entries {
			child_path := entry.fullpath
			if len(child_path) == 0 {
				parts := [?]string{path, entry.name}
				joined_path, joined_err := os.join_path(parts[:], context.temp_allocator)
				if joined_err != nil {
					continue
				}
				child_path = joined_path
			}

			#partial switch entry.type {
			case .Directory:
				remove_test_directory_tree(child_path)
			case:
				os.remove(child_path)
			}
		}
		os.file_info_slice_delete(entries, context.allocator)
	}
	os.remove(path)
}
