package main

import "core:os"

Input_Directory_Error :: enum {
	None,
	Not_Directory,
	Resolve_Failed,
}

accept_input_directory :: proc(path: string) -> (string, Input_Directory_Error) {
	if !os.is_directory(path) {
		return "", .Not_Directory
	}

	absolute_path, absolute_path_err := os.get_absolute_path(path, context.temp_allocator)
	if absolute_path_err != os.ERROR_NONE {
		return "", .Resolve_Failed
	}

	return absolute_path, .None
}
