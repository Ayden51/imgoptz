package main

import "core:os"
import "core:strings"

Image_File_Kind :: enum {
	Jpeg,
	Png,
}

Discovery_Error :: enum {
	None,
	Read_Failed,
	Relative_Path_Failed,
	Destination_Path_Failed,
}

Image_Work_Item :: struct {
	source_path:      string,
	relative_path:    string,
	destination_path: string,
	kind:             Image_File_Kind,
}

Discovery_Result :: struct {
	items:      [dynamic]Image_Work_Item,
	jpeg_count: int,
	png_count:  int,
	err:        Discovery_Error,
	err_path:   string,
}

discover_image_work :: proc(
	input_root: string,
	runtime_env: Runtime_Environment,
) -> Discovery_Result {
	result: Discovery_Result
	discover_directory(
		&result,
		input_root,
		input_root,
		runtime_env.recursive,
		runtime_env.output_mode,
		runtime_env.output_root,
	)
	return result
}

destroy_discovery_result :: proc(result: ^Discovery_Result) {
	for item in result.items {
		delete(item.source_path)
		delete(item.relative_path)
		delete(item.destination_path)
	}
	delete(result.items)
	delete(result.err_path)
	result^ = {}
}

discovery_error_summary :: proc(err: Discovery_Error) -> string {
	switch err {
	case .None:
		return ""
	case .Read_Failed:
		return "Failed to read image directory."
	case .Relative_Path_Failed:
		return "Failed to plan relative output path."
	case .Destination_Path_Failed:
		return "Failed to plan destination output path."
	}
	return "Failed to discover images."
}

discover_directory :: proc(
	result: ^Discovery_Result,
	input_root, current_dir: string,
	recursive: bool,
	output_mode: Config_Output_Mode,
	output_root: string,
) {
	entries, entries_err := os.read_directory_by_path(current_dir, 0, context.allocator)
	if entries_err != nil {
		set_discovery_error(result, .Read_Failed, current_dir)
		return
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if result.err != .None {
			return
		}

		entry_path := entry.fullpath
		if len(entry_path) == 0 {
			parts := [?]string{current_dir, entry.name}
			joined_path, joined_err := os.join_path(parts[:], context.temp_allocator)
			if joined_err != nil {
				set_discovery_error(result, .Destination_Path_Failed, current_dir)
				return
			}
			entry_path = joined_path
		}

		#partial switch entry.type {
		case .Directory:
			if recursive {
				discover_directory(
					result,
					input_root,
					entry_path,
					recursive,
					output_mode,
					output_root,
				)
			}
		case .Regular:
			add_image_work_item(
				result,
				input_root,
				entry_path,
				recursive,
				output_mode,
				output_root,
			)
		case:
		}
	}
}

add_image_work_item :: proc(
	result: ^Discovery_Result,
	input_root, source_path: string,
	recursive: bool,
	output_mode: Config_Output_Mode,
	output_root: string,
) {
	kind, ok := image_file_kind(source_path)
	if !ok {
		return
	}

	relative_path, relative_ok := image_relative_path(input_root, source_path, recursive)
	if !relative_ok {
		set_discovery_error(result, .Relative_Path_Failed, source_path)
		return
	}

	destination_path, destination_ok := planned_destination_path(
		source_path,
		relative_path,
		output_mode,
		output_root,
	)
	if !destination_ok {
		delete(relative_path)
		set_discovery_error(result, .Destination_Path_Failed, source_path)
		return
	}

	append(
		&result.items,
		Image_Work_Item {
			source_path = strings.clone(source_path),
			relative_path = relative_path,
			destination_path = destination_path,
			kind = kind,
		},
	)

	switch kind {
	case .Jpeg:
		result.jpeg_count += 1
	case .Png:
		result.png_count += 1
	}
}

image_relative_path :: proc(input_root, source_path: string, recursive: bool) -> (string, bool) {
	if !recursive {
		_, filename := os.split_path(source_path)
		return strings.clone(filename), true
	}

	relative_path, relative_err := os.get_relative_path(input_root, source_path, context.allocator)
	if relative_err != nil {
		return "", false
	}
	return relative_path, true
}

planned_destination_path :: proc(
	source_path, relative_path: string,
	output_mode: Config_Output_Mode,
	output_root: string,
) -> (
	string,
	bool,
) {
	if output_mode == .In_Place {
		return strings.clone(source_path), true
	}

	parts := [?]string{output_root, relative_path}
	destination_path, destination_err := os.join_path(parts[:], context.allocator)
	if destination_err != nil {
		return "", false
	}
	return destination_path, true
}

image_file_kind :: proc(path: string) -> (Image_File_Kind, bool) {
	_, ext := os.split_filename(path)
	switch {
	case ascii_equal_fold(ext, "jpg"), ascii_equal_fold(ext, "jpeg"):
		return .Jpeg, true
	case ascii_equal_fold(ext, "png"):
		return .Png, true
	}
	return .Jpeg, false
}

ascii_equal_fold :: proc(a, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		if ascii_lower(a[i]) != ascii_lower(b[i]) {
			return false
		}
	}
	return true
}

ascii_lower :: proc(c: byte) -> byte {
	if c >= 'A' && c <= 'Z' {
		return c + ('a' - 'A')
	}
	return c
}

set_discovery_error :: proc(result: ^Discovery_Result, err: Discovery_Error, path: string) {
	if result.err != .None {
		return
	}
	result.err = err
	result.err_path = strings.clone(path)
}
