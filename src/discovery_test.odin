package main

import "core:os"
import "core:strings"
import "core:testing"

@(test, require)
test_discover_images_non_recursive_case_insensitive :: proc(t: ^testing.T) {
	temp_dir := make_temp_discovery_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer delete(temp_dir)
	defer os.remove_all(temp_dir)

	if !write_discovery_file(t, temp_dir, "a.jpg") ||
	   !write_discovery_file(t, temp_dir, "b.JPEG") ||
	   !write_discovery_file(t, temp_dir, "c.PNG") ||
	   !write_discovery_file(t, temp_dir, "ignored.gif") ||
	   !write_discovery_file(t, temp_dir, "nested/d.jpg") {
		return
	}

	env := Runtime_Environment {
		output_mode = .In_Place,
	}
	result := discover_image_work(temp_dir, env)
	defer destroy_discovery_result(&result)

	testing.expect_value(t, result.err, Discovery_Error.None)
	testing.expect_value(t, len(result.items), 3)
	testing.expect_value(t, result.jpeg_count, 2)
	testing.expect_value(t, result.png_count, 1)
	testing.expect(t, discovery_has_relative_path(result, "a.jpg"))
	testing.expect(t, discovery_has_relative_path(result, "b.JPEG"))
	testing.expect(t, discovery_has_relative_path(result, "c.PNG"))
	testing.expect(t, !discovery_has_relative_path(result, "d.jpg"))
	for item in result.items {
		testing.expect_value(t, item.destination_path, item.source_path)
	}
}

@(test, require)
test_discover_images_recursive_includes_nested_files :: proc(t: ^testing.T) {
	temp_dir := make_temp_discovery_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer delete(temp_dir)
	defer os.remove_all(temp_dir)

	if !write_discovery_file(t, temp_dir, "root.jpeg") ||
	   !write_discovery_file(t, temp_dir, "nested/a.png") ||
	   !write_discovery_file(t, temp_dir, "nested/deep/b.JPG") ||
	   !write_discovery_file(t, temp_dir, "nested/deep/ignored.txt") {
		return
	}

	env := Runtime_Environment {
		recursive   = true,
		output_mode = .In_Place,
	}
	result := discover_image_work(temp_dir, env)
	defer destroy_discovery_result(&result)

	testing.expect_value(t, result.err, Discovery_Error.None)
	testing.expect_value(t, len(result.items), 3)
	testing.expect_value(t, result.jpeg_count, 2)
	testing.expect_value(t, result.png_count, 1)
	testing.expect(t, discovery_has_relative_path(result, discovery_join(t, "nested", "a.png")))
	testing.expect(
		t,
		discovery_has_relative_path(result, discovery_join(t, "nested/deep", "b.JPG")),
	)
}

@(test, require)
test_discover_images_dir_output_preserves_recursive_relative_paths :: proc(t: ^testing.T) {
	temp_dir := make_temp_discovery_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer delete(temp_dir)
	defer os.remove_all(temp_dir)

	input_dir := discovery_join(t, temp_dir, "input")
	output_dir := discovery_join(t, temp_dir, "output")
	if len(input_dir) == 0 || len(output_dir) == 0 {
		return
	}

	if !testing.expect_value(t, os.make_directory_all(input_dir), nil) ||
	   !testing.expect_value(t, os.make_directory_all(output_dir), nil) ||
	   !write_discovery_file(t, input_dir, "sub/A.JPG") ||
	   !write_discovery_file(t, input_dir, "sub/deep/B.png") {
		return
	}

	env := Runtime_Environment {
		recursive   = true,
		output_mode = .Dir,
		output_root = output_dir,
	}
	result := discover_image_work(input_dir, env)
	defer destroy_discovery_result(&result)

	first_relative := discovery_join(t, "sub", "A.JPG")
	first_destination := discovery_join(t, output_dir, first_relative)
	second_relative := discovery_join(t, "sub/deep", "B.png")
	second_destination := discovery_join(t, output_dir, second_relative)

	testing.expect_value(t, result.err, Discovery_Error.None)
	testing.expect_value(t, len(result.items), 2)
	testing.expect(t, discovery_has_plan(result, first_relative, first_destination))
	testing.expect(t, discovery_has_plan(result, second_relative, second_destination))
}

@(test, require)
test_discover_images_empty_folder_succeeds :: proc(t: ^testing.T) {
	temp_dir := make_temp_discovery_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer delete(temp_dir)
	defer os.remove_all(temp_dir)

	env := Runtime_Environment {
		output_mode = .In_Place,
	}
	result := discover_image_work(temp_dir, env)
	defer destroy_discovery_result(&result)

	testing.expect_value(t, result.err, Discovery_Error.None)
	testing.expect_value(t, len(result.items), 0)
	testing.expect_value(t, result.jpeg_count, 0)
	testing.expect_value(t, result.png_count, 0)
}

@(test, require)
test_sort_discovered_work_items_orders_by_relative_path :: proc(t: ^testing.T) {
	result: Discovery_Result
	append(
		&result.items,
		Image_Work_Item{relative_path = strings.clone("z.png")},
		Image_Work_Item{relative_path = strings.clone("a.jpg")},
		Image_Work_Item{relative_path = strings.clone("nested/b.png")},
	)
	defer destroy_discovery_result(&result)

	sort_discovered_work_items(&result)

	testing.expect_value(t, result.items[0].relative_path, "a.jpg")
	testing.expect_value(t, result.items[1].relative_path, "nested/b.png")
	testing.expect_value(t, result.items[2].relative_path, "z.png")
}

make_temp_discovery_root :: proc(t: ^testing.T) -> string {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-discovery-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return ""
	}
	return temp_dir
}

write_discovery_file :: proc(t: ^testing.T, root, relative_path: string) -> bool {
	path := discovery_join(t, root, relative_path)
	if len(path) == 0 {
		return false
	}
	dir, _ := os.split_path(path)
	if !testing.expect_value(t, os.make_directory_all(dir), nil) {
		return false
	}
	return testing.expect_value(t, os.write_entire_file(path, "test"), nil)
}

discovery_join :: proc(t: ^testing.T, first, second: string) -> string {
	parts := [?]string{first, second}
	path, err := os.join_path(parts[:], context.temp_allocator)
	if !testing.expect_value(t, err, nil) {
		return ""
	}
	return path
}

discovery_has_relative_path :: proc(result: Discovery_Result, relative_path: string) -> bool {
	for item in result.items {
		if item.relative_path == relative_path {
			return true
		}
	}
	return false
}

discovery_has_plan :: proc(
	result: Discovery_Result,
	relative_path, destination_path: string,
) -> bool {
	for item in result.items {
		if item.relative_path == relative_path && item.destination_path == destination_path {
			return true
		}
	}
	return false
}
