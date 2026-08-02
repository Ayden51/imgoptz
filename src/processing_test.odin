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
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "Photo 1.jpg")
	if len(source_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "source"), nil) {
		return
	}

	first_path, first_ok := make_process_temp_path(source_path, "optimized.jpg")
	if !testing.expect_value(t, first_ok, true) {
		return
	}
	defer cleanup_test_file(first_path)

	if !testing.expect_value(t, os.write_entire_file(first_path, "existing temp"), nil) {
		return
	}

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
test_jpeg_pipe_commands_use_stdout_and_stdin :: proc(t: ^testing.T) {
	config := default_config()
	defer destroy_config(&config)

	resize_command := build_jpeg_magick_resize_command(
		"magick.exe",
		"source.jpg",
		1920,
		"srgb.icc",
		"-",
	)
	mozjpeg_command := build_mozjpeg_command("mozjpeg.exe", config.jpeg, "", "", "profile.icc")

	testing.expect(t, command_has_sequence(resize_command, []string{"-profile", "srgb.icc"}))
	testing.expect_value(t, resize_command[len(resize_command) - 1], "ppm:-")
	testing.expect(t, command_has_sequence(mozjpeg_command, []string{"-icc", "profile.icc"}))
	testing.expect(t, !command_contains(mozjpeg_command, "-outfile"))
	testing.expect(t, !command_contains(mozjpeg_command, "in.ppm"))
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
	testing.expect(t, !command_contains(pngquant_command, "--strip"))
	testing.expect_value(t, pngquant_command[len(pngquant_command) - 1], "resized.png")

	oxipng_command := build_oxipng_command("oxipng.exe", config.png, "out.png", "quant.png")
	testing.expect(t, command_has_sequence(oxipng_command, []string{"-o", "4"}))
	testing.expect(t, command_has_sequence(oxipng_command, []string{"--strip", "safe"}))
	testing.expect(t, command_contains(oxipng_command, "--alpha"))
	testing.expect(t, command_has_sequence(oxipng_command, []string{"--interlace", "off"}))
	testing.expect(t, !command_contains(oxipng_command, "--threads"))
	testing.expect(t, command_has_sequence(oxipng_command, []string{"--out", "out.png"}))
	testing.expect_value(t, oxipng_command[len(oxipng_command) - 1], "quant.png")
}

@(test, require)
test_oxipng_command_limits_threads_when_app_workers_are_parallel :: proc(t: ^testing.T) {
	config := default_config()
	defer destroy_config(&config)

	command := build_oxipng_command("oxipng.exe", config.png, "out.png", "quant.png", 2)

	testing.expect(t, command_has_sequence(command, []string{"--threads", "1"}))
}

@(test, require)
test_png_resize_command_converts_to_profile_when_requested :: proc(t: ^testing.T) {
	command := build_png_magick_resize_command(
		"magick.exe",
		"source.png",
		1920,
		"srgb.icc",
		"resized.png",
	)

	testing.expect(t, command_has_sequence(command, []string{"-profile", "srgb.icc"}))
	testing.expect_value(t, command[len(command) - 1], "resized.png")
}

@(test, require)
test_shared_icc_profile_family_detection_covers_srgb_and_p3 :: proc(t: ^testing.T) {
	testing.expect(t, icc_profile_family_is_retained("IEC 61966-2-1 default RGB profile"))
	testing.expect(t, icc_profile_family_is_retained("Display P3 color profile"))
	testing.expect(t, !icc_profile_family_is_retained("Generic CMYK profile"))
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
	defer cleanup_test_directory(temp_dir)

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
	defer cleanup_process_image_result(&result)

	testing.expect(t, result.err != .None)
	testing.expect(t, !processing_temp_artifacts_exist(source_path))
}

@(test, require)
test_process_png_preserves_source_srgb_icc_profile :: proc(t: ^testing.T) {
	runtime_env := processing_test_runtime_environment(t)
	if !processing_runtime_tools_exist(runtime_env) {
		return
	}

	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-png-icc-retain-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "srgb.png")
	if len(source_path) == 0 {
		return
	}
	create_detail, create_ok := run_tool(
		[]string {
			runtime_env.magick_path,
			"-size",
			"64x64",
			"gradient:red-blue",
			"-profile",
			runtime_env.srgb_profile,
			source_path,
		},
		imagemagick_process_environment(runtime_env),
		"ImageMagick test PNG create",
	)
	defer delete(create_detail)
	if !testing.expect_value(t, create_ok, true) {
		return
	}

	icc_result := determine_icc_profile_mode(source_path, runtime_env)
	defer destroy_icc_profile_result(&icc_result)
	if !testing.expect_value(t, icc_result.err, Image_Process_Error.None) ||
	   !testing.expect_value(t, icc_result.mode, Icc_Profile_Mode.Embed_Source) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	item := Image_Work_Item {
		source_path   = source_path,
		relative_path = "srgb.png",
		kind          = .Png,
	}
	result := process_image_to_temp(item, config, runtime_env)
	defer cleanup_process_image_result(&result)

	testing.expectf(
		t,
		result.err == .None,
		"expected no PNG processing error, got %v: %s",
		result.err,
		result.detail,
	)
}

@(test, require)
test_process_png_converts_missing_icc_profile_to_srgb :: proc(t: ^testing.T) {
	runtime_env := processing_test_runtime_environment(t)
	if !processing_runtime_tools_exist(runtime_env) {
		return
	}

	temp_dir, temp_err := os.make_directory_temp(
		"",
		"imgoptz-png-icc-convert-*",
		context.allocator,
	)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "unprofiled.png")
	if len(source_path) == 0 {
		return
	}
	create_detail, create_ok := run_tool(
		[]string{runtime_env.magick_path, "-size", "64x64", "gradient:red-blue", source_path},
		imagemagick_process_environment(runtime_env),
		"ImageMagick test PNG create",
	)
	defer delete(create_detail)
	if !testing.expect_value(t, create_ok, true) {
		return
	}

	icc_result := determine_icc_profile_mode(source_path, runtime_env)
	defer destroy_icc_profile_result(&icc_result)
	if !testing.expect_value(t, icc_result.err, Image_Process_Error.None) ||
	   !testing.expect_value(t, icc_result.mode, Icc_Profile_Mode.Convert_To_Srgb) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	item := Image_Work_Item {
		source_path   = source_path,
		relative_path = "unprofiled.png",
		kind          = .Png,
	}
	result := process_image_to_temp(item, config, runtime_env)
	defer cleanup_process_image_result(&result)

	if !testing.expectf(
		t,
		result.err == .None,
		"expected no PNG processing error, got %v: %s",
		result.err,
		result.detail,
	) {
		return
	}
	verify_detail, verify_ok := verify_png_icc_profile(
		runtime_env.magick_path,
		result.output_path,
		"",
		false,
		runtime_env,
	)
	defer delete(verify_detail)
	testing.expect_value(t, verify_ok, true)
}

@(test, require)
test_process_jpeg_unicode_source_uses_workspace_and_cleans_artifacts :: proc(t: ^testing.T) {
	runtime_env := processing_test_runtime_environment(t)
	if !processing_runtime_tools_exist(runtime_env) {
		return
	}

	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-jpeg-unicode-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	input_dir := processing_join(t, temp_dir, "Ảnh Unicode & (test)")
	if len(input_dir) == 0 || !testing.expect_value(t, os.make_directory_all(input_dir), nil) {
		return
	}
	source_path := processing_join(t, input_dir, "Ảnh Đẹp.jpg")
	if len(source_path) == 0 {
		return
	}
	create_detail, create_ok := run_tool(
		[]string {
			runtime_env.magick_path,
			"-size",
			"128x128",
			"gradient:red-blue",
			"-profile",
			runtime_env.srgb_profile,
			source_path,
		},
		imagemagick_process_environment(runtime_env),
		"ImageMagick test JPEG create",
	)
	defer delete(create_detail)
	if !testing.expect_value(t, create_ok, true) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	item := Image_Work_Item {
		source_path   = source_path,
		relative_path = "Ảnh Đẹp.jpg",
		kind          = .Jpeg,
	}
	result := process_image_to_temp(item, config, runtime_env)
	if !testing.expectf(
		t,
		result.err == .None,
		"expected no JPEG processing error, got %v: %s",
		result.err,
		result.detail,
	) {
		cleanup_process_image_result(&result)
		return
	}

	workspace_path := strings.clone(result.cleanup_path)
	output_path := strings.clone(result.output_path)
	defer delete(workspace_path)
	defer delete(output_path)
	_, output_name := os.split_path(result.output_path)
	testing.expect_value(t, output_name, "optimized.jpg")
	testing.expect(t, !strings.has_prefix(result.output_path, source_path))
	testing.expect(t, os.exists(result.output_path))
	testing.expect(t, os.exists(result.cleanup_path))

	cleanup_process_image_result(&result)
	testing.expect(t, !os.exists(output_path))
	testing.expect(t, !os.exists(workspace_path))
	testing.expect(t, !processing_temp_artifacts_exist(source_path))
}

@(test, require)
test_jpeg_pipe_retries_without_icc_when_mozjpeg_rejects_profile_path :: proc(t: ^testing.T) {
	testing.expect(t, jpeg_pipe_should_retry_without_icc(.Mozjpeg_Failed, false, "profile.icc"))
	testing.expect(t, !jpeg_pipe_should_retry_without_icc(.None, true, "profile.icc"))
	testing.expect(t, !jpeg_pipe_should_retry_without_icc(.Magick_Failed, false, "profile.icc"))
	testing.expect(t, !jpeg_pipe_should_retry_without_icc(.Mozjpeg_Failed, false, ""))
}

@(test, require)
test_finalize_output_skips_when_not_smaller :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-finalize-skip-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "Photo.JPG")
	temp_output_path := processing_join(t, temp_dir, "optimized.tmp")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "small"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "larger"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "Photo.JPG",
		destination_path = source_path,
		kind             = .Jpeg,
	}
	result := finalize_optimized_output(item, temp_output_path, .In_Place)
	defer destroy_finalize_output_result(&result)

	testing.expect_value(t, result.err, Image_Process_Error.Optimized_Not_Smaller)
	testing.expect(t, os.exists(source_path))
	testing.expect(t, os.exists(temp_output_path))
	testing.expect(t, processing_file_has_contents(t, source_path, "small"))
}

@(test, require)
test_finalize_in_place_replaces_smaller_output_and_slugifies_name :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp(
		"",
		"imgoptz-finalize-in-place-*",
		context.allocator,
	)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "Ảnh Đẹp.JPG")
	temp_output_path := processing_join(t, temp_dir, "optimized.tmp")
	final_path := processing_join(t, temp_dir, "anh-dep.jpg")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   len(final_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "Ảnh Đẹp.JPG",
		destination_path = source_path,
		kind             = .Jpeg,
	}
	result := finalize_optimized_output(item, temp_output_path, .In_Place)
	defer destroy_finalize_output_result(&result)

	testing.expect_value(t, result.err, Image_Process_Error.None)
	testing.expect_value(t, result.output_path, final_path)
	testing.expect_value(t, result.original_size, 14)
	testing.expect_value(t, result.optimized_size, 4)
	testing.expect_value(t, result.reduction_percent, -71)
	testing.expect(t, !os.exists(source_path))
	testing.expect(t, !os.exists(temp_output_path))
	testing.expect(t, os.exists(final_path))
	testing.expect(t, processing_file_has_contents(t, final_path, "tiny"))
	testing.expect(t, !processing_temp_artifacts_exist(source_path))
}

@(test, require)
test_dry_run_decline_cleanup_removes_retained_temp_without_writing :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp(
		"",
		"imgoptz-dry-run-decline-*",
		context.allocator,
	)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "Photo.JPG")
	temp_output_path := processing_join(t, temp_dir, "optimized.tmp")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "Photo.JPG",
		destination_path = source_path,
		kind             = .Jpeg,
	}
	preview := evaluate_optimized_output(item, temp_output_path)
	dry_run: Dry_Run_Process_Result
	append(
		&dry_run.previews,
		Preview_Image_Result {
			item = item,
			temp = Process_Image_Result{output_path = strings.clone(temp_output_path)},
			preview = preview,
		},
	)

	destroy_dry_run_process_result(&dry_run)

	testing.expect(t, processing_file_has_contents(t, source_path, "original-large"))
	testing.expect(t, !os.exists(temp_output_path))
}

@(test, require)
test_dry_run_approval_finalizes_retained_temp_without_rerunning :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp(
		"",
		"imgoptz-dry-run-approve-*",
		context.allocator,
	)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "Ảnh Đẹp.JPG")
	temp_output_path := processing_join(t, temp_dir, "optimized.tmp")
	final_path := processing_join(t, temp_dir, "anh-dep.jpg")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   len(final_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "Ảnh Đẹp.JPG",
		destination_path = source_path,
		kind             = .Jpeg,
	}
	preview := evaluate_optimized_output(item, temp_output_path)
	dry_run: Dry_Run_Process_Result
	append(
		&dry_run.previews,
		Preview_Image_Result {
			item = item,
			temp = Process_Image_Result{output_path = strings.clone(temp_output_path)},
			preview = preview,
		},
	)
	defer destroy_dry_run_process_result(&dry_run)

	summary := finalize_dry_run_outputs(&dry_run, .In_Place)

	testing.expect_value(t, summary.succeeded, 1)
	testing.expect_value(t, summary.failed, 0)
	testing.expect(t, !os.exists(source_path))
	testing.expect(t, !os.exists(temp_output_path))
	testing.expect(t, processing_file_has_contents(t, final_path, "tiny"))
}

@(test, require)
test_finalize_in_place_applies_case_only_slugified_name :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp(
		"",
		"imgoptz-finalize-in-place-case-*",
		context.allocator,
	)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "Photo.JPG")
	temp_output_path := processing_join(t, temp_dir, "optimized.tmp")
	final_path := processing_join(t, temp_dir, "photo.jpg")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   len(final_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "Photo.JPG",
		destination_path = source_path,
		kind             = .Jpeg,
	}
	result := finalize_optimized_output(item, temp_output_path, .In_Place)
	defer destroy_finalize_output_result(&result)

	testing.expect_value(t, result.err, Image_Process_Error.None)
	testing.expect_value(t, result.output_path, final_path)
	testing.expect(t, !processing_directory_contains_name(t, temp_dir, "Photo.JPG"))
	testing.expect(t, processing_directory_contains_name(t, temp_dir, "photo.jpg"))
	testing.expect(t, os.exists(final_path))
	testing.expect(t, processing_file_has_contents(t, final_path, "tiny"))
}

@(test, require)
test_finalize_dir_copies_smaller_output_with_slug_collision_suffix :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-finalize-dir-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	input_dir := processing_join(t, temp_dir, "input")
	output_dir := processing_join(t, temp_dir, "output")
	if len(input_dir) == 0 ||
	   len(output_dir) == 0 ||
	   !testing.expect_value(t, os.make_directory_all(input_dir), nil) ||
	   !testing.expect_value(t, os.make_directory_all(output_dir), nil) {
		return
	}

	source_path := processing_join(t, input_dir, "Ảnh Đẹp.PNG")
	temp_output_path := processing_join(t, input_dir, "optimized.tmp")
	pre_slug_destination := processing_join(t, output_dir, "nested/Ảnh Đẹp.PNG")
	collision_path := processing_join(t, output_dir, "nested/anh-dep.png")
	final_path := processing_join(t, output_dir, "nested/anh-dep-1.png")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   len(pre_slug_destination) == 0 ||
	   len(collision_path) == 0 ||
	   len(final_path) == 0 {
		return
	}
	collision_dir, _ := os.split_path(collision_path)
	if !testing.expect_value(t, os.make_directory_all(collision_dir), nil) ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(collision_path, "existing"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "nested/Ảnh Đẹp.PNG",
		destination_path = pre_slug_destination,
		kind             = .Png,
	}
	result := finalize_optimized_output(item, temp_output_path, .Dir)
	defer destroy_finalize_output_result(&result)

	testing.expect_value(t, result.err, Image_Process_Error.None)
	testing.expect_value(t, result.output_path, final_path)
	testing.expect(t, os.exists(source_path))
	testing.expect(t, os.exists(temp_output_path))
	testing.expect(t, processing_file_has_contents(t, source_path, "original-large"))
	testing.expect(t, processing_file_has_contents(t, collision_path, "existing"))
	testing.expect(t, processing_file_has_contents(t, final_path, "tiny"))
}

@(test, require)
test_finalize_dir_creates_missing_target_relative_output_root_when_writing :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp(
		"",
		"imgoptz-finalize-target-output-*",
		context.allocator,
	)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	input_dir := processing_join(t, temp_dir, "input")
	output_dir := processing_join(t, input_dir, "imgoptz-output")
	if len(input_dir) == 0 ||
	   len(output_dir) == 0 ||
	   !testing.expect_value(t, os.make_directory_all(input_dir), nil) {
		return
	}

	source_path := processing_join(t, input_dir, "Photo.JPG")
	temp_output_path := processing_join(t, input_dir, "optimized.tmp")
	destination_path := processing_join(t, output_dir, "Photo.JPG")
	final_path := processing_join(t, output_dir, "photo.jpg")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   len(destination_path) == 0 ||
	   len(final_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "Photo.JPG",
		destination_path = destination_path,
		kind             = .Jpeg,
	}
	result := finalize_optimized_output(item, temp_output_path, .Dir)
	defer destroy_finalize_output_result(&result)

	testing.expect_value(t, result.err, Image_Process_Error.None)
	testing.expect(t, os.exists(output_dir))
	testing.expect(t, processing_file_has_contents(t, final_path, "tiny"))
}

@(test, require)
test_finalize_dir_does_not_ignore_existing_destination_matching_source :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp(
		"",
		"imgoptz-finalize-overlap-*",
		context.allocator,
	)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "photo.jpg")
	temp_output_path := processing_join(t, temp_dir, "optimized.tmp")
	final_path := processing_join(t, temp_dir, "photo-1.jpg")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   len(final_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "photo.jpg",
		destination_path = source_path,
		kind             = .Jpeg,
	}
	result := finalize_optimized_output(item, temp_output_path, .Dir)
	defer destroy_finalize_output_result(&result)

	testing.expect_value(t, result.err, Image_Process_Error.None)
	testing.expect_value(t, result.output_path, final_path)
	testing.expect(t, processing_file_has_contents(t, source_path, "original-large"))
	testing.expect(t, processing_file_has_contents(t, final_path, "tiny"))
}

@(test, require)
test_replace_in_place_failure_restores_original :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-replace-fail-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	source_path := processing_join(t, temp_dir, "Photo.JPG")
	temp_output_path := processing_join(t, temp_dir, "optimized.tmp")
	final_path := processing_join(t, temp_dir, "missing/photo.jpg")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   len(final_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "Photo.JPG",
		destination_path = source_path,
		kind             = .Jpeg,
	}
	detail, ok := replace_in_place_with_slugged_output(item, temp_output_path, final_path)
	defer delete(detail)

	testing.expect_value(t, ok, false)
	testing.expect(t, len(detail) > 0)
	testing.expect(t, processing_file_has_contents(t, source_path, "original-large"))
	testing.expect(t, !os.exists(temp_output_path))
	testing.expect(t, !processing_temp_artifacts_exist(source_path))
}

@(test, require)
test_finalize_dir_copy_failure_preserves_source_and_temp :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-copy-fail-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	input_dir := processing_join(t, temp_dir, "input")
	blocking_path := processing_join(t, temp_dir, "blocking")
	if len(input_dir) == 0 ||
	   len(blocking_path) == 0 ||
	   !testing.expect_value(t, os.make_directory_all(input_dir), nil) ||
	   !testing.expect_value(t, os.write_entire_file(blocking_path, "not a directory"), nil) {
		return
	}

	source_path := processing_join(t, input_dir, "Photo.JPG")
	temp_output_path := processing_join(t, input_dir, "optimized.tmp")
	destination_path := processing_join(t, blocking_path, "Photo.JPG")
	if len(source_path) == 0 ||
	   len(temp_output_path) == 0 ||
	   len(destination_path) == 0 ||
	   !testing.expect_value(t, os.write_entire_file(source_path, "original-large"), nil) ||
	   !testing.expect_value(t, os.write_entire_file(temp_output_path, "tiny"), nil) {
		return
	}

	item := Image_Work_Item {
		source_path      = source_path,
		relative_path    = "Photo.JPG",
		destination_path = destination_path,
		kind             = .Jpeg,
	}
	result := finalize_optimized_output(item, temp_output_path, .Dir)
	defer destroy_finalize_output_result(&result)

	testing.expect_value(t, result.err, Image_Process_Error.Copy_Failed)
	testing.expect(t, processing_file_has_contents(t, source_path, "original-large"))
	testing.expect(t, processing_file_has_contents(t, temp_output_path, "tiny"))
}

@(test, require)
test_imagemagick_environment_filters_managed_entries :: proc(t: ^testing.T) {
	testing.expect(t, imagemagick_environment_entry_is_managed("MAGICK_THREAD_LIMIT=8"))
	testing.expect(t, imagemagick_environment_entry_is_managed("magick_ocl_device=CPU"))
	testing.expect(t, !imagemagick_environment_entry_is_managed("PATH=C:/Tools"))
	testing.expect(t, !imagemagick_environment_entry_is_managed("MAGICK_OCL_DEVICE_EXTRA=GPU"))
	testing.expect(t, !imagemagick_environment_entry_is_managed("MAGICK_OCL_DEVICE"))
}

@(test, require)
test_imagemagick_thread_limit_tracks_app_worker_count :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		imagemagick_thread_limit(Runtime_Environment{worker_count = 1}),
		IMAGE_PROCESS_MAGICK_THREAD_LIMIT_SINGLE_WORKER,
	)
	testing.expect_value(
		t,
		imagemagick_thread_limit(Runtime_Environment{worker_count = 4}),
		IMAGE_PROCESS_MAGICK_THREAD_LIMIT_MULTI_WORKER,
	)
}

processing_join :: proc(t: ^testing.T, first, second: string) -> string {
	parts := [?]string{first, second}
	path, err := os.join_path(parts[:], context.temp_allocator)
	if !testing.expect_value(t, err, nil) {
		return ""
	}
	return path
}

processing_test_runtime_environment :: proc(t: ^testing.T) -> Runtime_Environment {
	return Runtime_Environment {
		magick_path = processing_join(t, "dist/tools/imagemagick", "magick.exe"),
		mozjpeg_path = processing_join(t, "dist/tools/mozjpeg", "mozjpeg.exe"),
		pngquant_path = processing_join(t, "dist/tools/pngquant", "pngquant.exe"),
		oxipng_path = processing_join(t, "dist/tools/oxipng", "oxipng.exe"),
		srgb_profile = processing_join(t, "dist/profiles", "sRGB2014.icc"),
	}
}

processing_runtime_tools_exist :: proc(runtime_env: Runtime_Environment) -> bool {
	return(
		len(runtime_env.magick_path) > 0 &&
		len(runtime_env.mozjpeg_path) > 0 &&
		len(runtime_env.pngquant_path) > 0 &&
		len(runtime_env.oxipng_path) > 0 &&
		len(runtime_env.srgb_profile) > 0 &&
		os.exists(runtime_env.magick_path) &&
		os.exists(runtime_env.mozjpeg_path) &&
		os.exists(runtime_env.pngquant_path) &&
		os.exists(runtime_env.oxipng_path) &&
		os.exists(runtime_env.srgb_profile) \
	)
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

processing_file_has_contents :: proc(t: ^testing.T, path, expected: string) -> bool {
	data, read_err := os.read_entire_file(path, context.allocator)
	if !testing.expect_value(t, read_err, nil) {
		return false
	}
	defer delete(data)

	return testing.expect_value(t, string(data), expected)
}

processing_directory_contains_name :: proc(t: ^testing.T, dir, name: string) -> bool {
	entries, entries_err := os.read_directory_by_path(dir, 0, context.allocator)
	if !testing.expect_value(t, entries_err, nil) {
		return false
	}
	defer os.file_info_slice_delete(entries, context.allocator)

	for entry in entries {
		if entry.name == name {
			return true
		}
	}
	return false
}
