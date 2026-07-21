package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test, require)
test_process_temp_paths_are_unique_and_beside_source :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-processing-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer delete(temp_dir)
	defer os.remove_all(temp_dir)

	source_path := processing_join(t, temp_dir, "Photo 1.jpg")
	if len(source_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "source"), nil) {
		return
	}

	first_path, first_ok := make_process_temp_path(source_path, "optimized.jpg")
	if !testing.expect_value(t, first_ok, true) {
		return
	}
	defer delete(first_path)

	if !testing.expect_value(t, os.write_entire_file(first_path, "existing temp"), nil) {
		return
	}
	defer os.remove(first_path)

	second_path, second_ok := make_process_temp_path(source_path, "optimized.jpg")
	if !testing.expect_value(t, second_ok, true) {
		return
	}
	defer delete(second_path)

	testing.expect(t, first_path != second_path)
	testing.expect(t, strings.has_prefix(first_path, source_path))
	testing.expect(t, strings.contains(first_path, ".imgoptz."))
	testing.expect(t, strings.has_suffix(first_path, ".optimized.jpg"))
	testing.expect(t, !os.exists(second_path))
}

@(test, require)
test_mozjpeg_command_maps_config_flags :: proc(t: ^testing.T) {
	config := default_config()
	defer destroy_config(&config)

	command := build_mozjpeg_command(
		"mozjpeg.exe",
		config.jpeg,
		"out.jpg",
		"in.ppm",
		"profile.icc",
	)

	testing.expect_value(t, command[0], "mozjpeg.exe")
	testing.expect(t, command_has_sequence(command, []string{"-quality", "78"}))
	testing.expect(t, command_contains(command, "-progressive"))
	testing.expect(t, command_contains(command, "-optimize"))
	testing.expect(t, command_has_sequence(command, []string{"-sample", "2x2"}))
	testing.expect(t, command_has_sequence(command, []string{"-quant-table", "2"}))
	testing.expect(t, command_contains(command, "-tune-ms-ssim"))
	testing.expect(t, command_has_sequence(command, []string{"-icc", "profile.icc"}))
	testing.expect(t, command_has_sequence(command, []string{"-outfile", "out.jpg"}))
	testing.expect_value(t, command[len(command) - 1], "in.ppm")
}

@(test, require)
test_png_commands_map_config_flags :: proc(t: ^testing.T) {
	config := default_config()
	defer destroy_config(&config)

	pngquant_command := build_pngquant_command(
		"pngquant.exe",
		config.png,
		"quant.png",
		"resized.png",
	)
	testing.expect(t, command_has_sequence(pngquant_command, []string{"--output", "quant.png"}))
	testing.expect(t, command_has_sequence(pngquant_command, []string{"--quality", "40-95"}))
	testing.expect(t, command_has_sequence(pngquant_command, []string{"--speed", "1"}))
	testing.expect(t, command_contains(pngquant_command, "--nofs"))
	testing.expect(t, command_contains(pngquant_command, "--strip"))
	testing.expect_value(t, pngquant_command[len(pngquant_command) - 1], "resized.png")

	oxipng_command := build_oxipng_command("oxipng.exe", config.png, "out.png", "quant.png")
	testing.expect(t, command_has_sequence(oxipng_command, []string{"-o", "4"}))
	testing.expect(t, command_has_sequence(oxipng_command, []string{"--strip", "safe"}))
	testing.expect(t, command_contains(oxipng_command, "--alpha"))
	testing.expect(t, command_has_sequence(oxipng_command, []string{"--interlace", "off"}))
	testing.expect(t, command_has_sequence(oxipng_command, []string{"--out", "out.png"}))
	testing.expect_value(t, oxipng_command[len(oxipng_command) - 1], "quant.png")
}

@(test, require)
test_jpeg_command_disables_profile_work_when_configured :: proc(t: ^testing.T) {
	config := default_config()
	defer destroy_config(&config)
	config.jpeg.preserve_profiles = false

	command := build_mozjpeg_command("mozjpeg.exe", config.jpeg, "out.jpg", "in.ppm", "")
	testing.expect(t, !command_contains(command, "-icc"))
}

@(test, require)
test_corrupt_png_failure_cleans_intermediate_temps :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp(
		"",
		"imgoptz-processing-fail-*",
		context.allocator,
	)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer delete(temp_dir)
	defer os.remove_all(temp_dir)

	source_path := processing_join(t, temp_dir, "bad.png")
	if len(source_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "not a png"), nil) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	runtime_env := Runtime_Environment {
		magick_path   = processing_join(t, "dist/tools/imagemagick", "magick.exe"),
		pngquant_path = processing_join(t, "dist/tools/pngquant", "pngquant.exe"),
		oxipng_path   = processing_join(t, "dist/tools/oxipng", "oxipng.exe"),
	}
	if len(runtime_env.magick_path) == 0 ||
	   len(runtime_env.pngquant_path) == 0 ||
	   len(runtime_env.oxipng_path) == 0 {
		return
	}

	item := Image_Work_Item {
		source_path   = source_path,
		relative_path = "bad.png",
		kind          = .Png,
	}
	result := process_image_to_temp(item, config, runtime_env)
	defer destroy_process_image_result(&result)

	testing.expect(t, result.err != .None)
	testing.expect(t, !processing_temp_artifacts_exist(source_path))
}

@(test, require)
test_imagemagick_environment_filters_managed_entries :: proc(t: ^testing.T) {
	testing.expect(t, imagemagick_environment_entry_is_managed("MAGICK_THREAD_LIMIT=8"))
	testing.expect(t, imagemagick_environment_entry_is_managed("magick_ocl_device=CPU"))
	testing.expect(t, !imagemagick_environment_entry_is_managed("PATH=C:/Tools"))
	testing.expect(t, !imagemagick_environment_entry_is_managed("MAGICK_OCL_DEVICE_EXTRA=GPU"))
	testing.expect(t, !imagemagick_environment_entry_is_managed("MAGICK_OCL_DEVICE"))
}

processing_join :: proc(t: ^testing.T, first, second: string) -> string {
	parts := [?]string{first, second}
	path, err := os.join_path(parts[:], context.temp_allocator)
	if !testing.expect_value(t, err, nil) {
		return ""
	}
	return path
}

command_contains :: proc(command: []string, value: string) -> bool {
	for arg in command {
		if arg == value {
			return true
		}
	}
	return false
}

command_has_sequence :: proc(command: []string, sequence: []string) -> bool {
	if len(sequence) == 0 || len(sequence) > len(command) {
		return false
	}
	for start in 0 ..= len(command) - len(sequence) {
		matched := true
		for offset in 0 ..< len(sequence) {
			if command[start + offset] != sequence[offset] {
				matched = false
				break
			}
		}
		if matched {
			return true
		}
	}
	return false
}

processing_temp_artifacts_exist :: proc(source_path: string) -> bool {
	dir, name := os.split_path(source_path)
	entries, entries_err := os.read_directory_by_path(dir, 0, context.allocator)
	if entries_err != nil {
		return false
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	prefix := fmt.tprintf("%s.imgoptz.", name)
	for entry in entries {
		if strings.has_prefix(entry.name, prefix) {
			return true
		}
	}
	return false
}
