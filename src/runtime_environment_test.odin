package main

import "core:os"
import "core:strings"
import "core:testing"

@(test, require)
test_resolve_runtime_tool_paths_accepts_complete_tools_folder :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	if !write_required_runtime_tree(t, temp_dir) {
		return
	}

	env: Runtime_Environment
	defer destroy_runtime_environment(&env)
	resolve_runtime_tool_paths_from_path_env(&env, temp_dir, "")

	testing.expect_value(t, len(env.errors), 0)
	testing.expect_value(
		t,
		env.mozjpeg_path,
		resolve_app_relative_path(temp_dir, RUNTIME_MOZJPEG_PATH, context.temp_allocator),
	)
	testing.expect_value(
		t,
		env.oxipng_path,
		resolve_app_relative_path(temp_dir, RUNTIME_OXIPNG_PATH, context.temp_allocator),
	)
	testing.expect_value(
		t,
		env.pngquant_path,
		resolve_app_relative_path(temp_dir, RUNTIME_PNGQUANT_PATH, context.temp_allocator),
	)
	testing.expect_value(
		t,
		env.vips_path,
		resolve_app_relative_path(temp_dir, RUNTIME_VIPS_PATH, context.temp_allocator),
	)
	testing.expect_value(
		t,
		env.vipsheader_path,
		resolve_app_relative_path(temp_dir, RUNTIME_VIPSHEADER_PATH, context.temp_allocator),
	)
}

@(test, require)
test_resolve_runtime_tool_paths_accepts_versioned_tools_folder :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	if !write_required_runtime_tree_with_folder_names(
		t,
		temp_dir,
		[]string {
			"mozjpeg-v4.1.0-win-x64",
			"oxipng-12.0.0-x86_64-pc-windows-msvc",
			"pngquant-3.0.0",
			"vips-dev-9.0",
		},
	) {
		return
	}

	env: Runtime_Environment
	defer destroy_runtime_environment(&env)
	resolve_runtime_tool_paths_from_path_env(&env, temp_dir, "")

	testing.expect_value(t, len(env.errors), 0)
	testing.expect_value(
		t,
		env.mozjpeg_path,
		test_runtime_tool_path(
			temp_dir,
			"mozjpeg-v4.1.0-win-x64",
			"static/Release/cjpeg-static.exe",
		),
	)
	testing.expect_value(
		t,
		env.oxipng_path,
		test_runtime_tool_path(temp_dir, "oxipng-12.0.0-x86_64-pc-windows-msvc", "oxipng.exe"),
	)
	testing.expect_value(
		t,
		env.pngquant_path,
		test_runtime_tool_path(temp_dir, "pngquant-3.0.0", "pngquant.exe"),
	)
	testing.expect_value(
		t,
		env.vips_path,
		test_runtime_tool_path(temp_dir, "vips-dev-9.0", "bin/vips.exe"),
	)
	testing.expect_value(
		t,
		env.vipsheader_path,
		test_runtime_tool_path(temp_dir, "vips-dev-9.0", "bin/vipsheader.exe"),
	)
}

@(test, require)
test_resolve_runtime_tool_paths_prefers_path_executable :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	if !write_required_runtime_tree(t, temp_dir) {
		return
	}

	path_dir := resolve_app_relative_path(temp_dir, "path-tools", context.temp_allocator)
	if !testing.expect_value(t, os.make_directory(path_dir), nil) {
		return
	}
	path_mozjpeg := resolve_app_relative_path(path_dir, "cjpeg-static.exe", context.temp_allocator)
	if !testing.expect_value(t, os.write_entire_file(path_mozjpeg, "test"), nil) {
		return
	}

	env: Runtime_Environment
	defer destroy_runtime_environment(&env)
	resolve_runtime_tool_paths_from_path_env(&env, temp_dir, path_dir)

	testing.expect_value(t, len(env.errors), 0)
	testing.expect_value(t, env.mozjpeg_path, path_mozjpeg)
	testing.expect_value(
		t,
		env.pngquant_path,
		resolve_app_relative_path(temp_dir, RUNTIME_PNGQUANT_PATH, context.temp_allocator),
	)
}

@(test, require)
test_resolve_runtime_tool_paths_reports_missing_tool :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	if !write_required_runtime_tree(t, temp_dir) {
		return
	}

	missing_path := resolve_app_relative_path(
		temp_dir,
		RUNTIME_MOZJPEG_PATH,
		context.temp_allocator,
	)
	remove_err := os.remove(missing_path)
	if !testing.expect_value(t, remove_err, nil) {
		return
	}

	env: Runtime_Environment
	defer destroy_runtime_environment(&env)
	resolve_runtime_tool_paths_from_path_env(&env, temp_dir, "")

	testing.expect_value(t, len(env.errors), 1)
	testing.expect_value(t, env.mozjpeg_path, "")
	testing.expect_value(t, env.errors[0], "Required tool is missing: MozJPEG.")
}

@(test, require)
test_resolve_runtime_tool_paths_groups_missing_libvips_files :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	if !write_required_runtime_tree(t, temp_dir) {
		return
	}

	vips_path := resolve_app_relative_path(temp_dir, RUNTIME_VIPS_PATH, context.temp_allocator)
	vipsheader_path := resolve_app_relative_path(
		temp_dir,
		RUNTIME_VIPSHEADER_PATH,
		context.temp_allocator,
	)
	if !testing.expect_value(t, os.remove(vips_path), nil) {
		return
	}
	if !testing.expect_value(t, os.remove(vipsheader_path), nil) {
		return
	}

	env: Runtime_Environment
	defer destroy_runtime_environment(&env)
	resolve_runtime_tool_paths_from_path_env(&env, temp_dir, "")

	testing.expect_value(t, len(env.errors), 1)
	testing.expect_value(t, env.errors[0], "Required tool is missing: libvips.")
}

@(test, require)
test_validate_required_runtime_files_reports_missing_profile :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	if !write_required_runtime_tree(t, temp_dir) {
		return
	}

	missing_path := resolve_app_relative_path(
		temp_dir,
		RUNTIME_SRGB_PROFILE_PATH,
		context.temp_allocator,
	)
	remove_err := os.remove(missing_path)
	if !testing.expect_value(t, remove_err, nil) {
		return
	}

	env: Runtime_Environment
	defer destroy_runtime_environment(&env)
	validate_required_runtime_files(&env, temp_dir)

	testing.expect_value(t, len(env.errors), 1)
	testing.expect(t, strings.contains(env.errors[0], "sRGB ICC profile"))
	testing.expect(t, strings.contains(env.errors[0], RUNTIME_SRGB_PROFILE_PATH))
}

@(test, require)
test_resolve_output_root_ignores_in_place_mode :: proc(t: ^testing.T) {
	config := default_config()
	defer destroy_config(&config)
	config.output_mode = .In_Place

	result := resolve_output_root("C:/imgoptz", config)
	defer destroy_output_root_result(&result)

	testing.expect_value(t, result.err, Output_Root_Error.None)
	testing.expect_value(t, result.path, "")
	testing.expect_value(t, len(result.warnings), 0)
}

@(test, require)
test_resolve_output_root_accepts_existing_configured_dir :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	custom_dir := resolve_app_relative_path(temp_dir, "optimized", context.temp_allocator)
	mkdir_err := os.make_directory(custom_dir)
	if !testing.expect_value(t, mkdir_err, nil) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	config.output_mode = .Dir
	replace_config_string(&config.out_dir, "optimized")

	result := resolve_output_root(temp_dir, config)
	defer destroy_output_root_result(&result)

	testing.expect_value(t, result.err, Output_Root_Error.None)
	testing.expect_value(t, result.path, custom_dir)
	testing.expect_value(t, result.kind, Output_Root_Kind.Prechecked)
	testing.expect_value(t, len(result.warnings), 0)
}

@(test, require)
test_resolve_output_root_accepts_existing_absolute_dir :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	custom_dir := resolve_app_relative_path(temp_dir, "absolute-output", context.temp_allocator)
	if !testing.expect_value(t, os.make_directory(custom_dir), nil) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	replace_config_string(&config.out_dir, custom_dir)

	result := resolve_output_root(temp_dir, config)
	defer destroy_output_root_result(&result)

	testing.expect_value(t, result.err, Output_Root_Error.None)
	testing.expect_value(t, result.path, custom_dir)
	testing.expect_value(t, result.kind, Output_Root_Kind.Prechecked)
	testing.expect_value(t, len(result.warnings), 0)
}

@(test, require)
test_resolve_output_root_treats_rooted_path_as_app_relative :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	output_dir := resolve_app_relative_path(temp_dir, "rooted-output", context.temp_allocator)
	if !testing.expect_value(t, os.make_directory(output_dir), nil) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	replace_config_string(&config.out_dir, "/rooted-output")

	result := resolve_output_root(temp_dir, config)
	defer destroy_output_root_result(&result)

	testing.expect_value(t, result.err, Output_Root_Error.None)
	testing.expect_value(t, result.path, output_dir)
	testing.expect_value(t, result.kind, Output_Root_Kind.Prechecked)
	testing.expect_value(t, len(result.warnings), 0)
}

@(test, require)
test_resolve_output_root_falls_back_to_target_relative_default :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	config := default_config()
	defer destroy_config(&config)
	replace_config_string(&config.out_dir, "typo-output")

	result := resolve_output_root(temp_dir, config)
	defer destroy_output_root_result(&result)

	testing.expect_value(t, result.err, Output_Root_Error.None)
	testing.expect_value(t, result.path, RUNTIME_DEFAULT_OUTPUT_DIR)
	testing.expect_value(t, result.kind, Output_Root_Kind.Target_Relative)
	testing.expect_value(t, len(result.warnings), 1)
	testing.expect(t, strings.contains(result.warnings[0], "Falling back"))
}

@(test, require)
test_resolve_output_root_defers_target_relative_default :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	config := default_config()
	defer destroy_config(&config)

	result := resolve_output_root(temp_dir, config)
	defer destroy_output_root_result(&result)

	testing.expect_value(t, result.err, Output_Root_Error.None)
	testing.expect_value(t, result.path, RUNTIME_DEFAULT_OUTPUT_DIR)
	testing.expect_value(t, result.kind, Output_Root_Kind.Target_Relative)
	testing.expect_value(t, len(result.warnings), 0)
	testing.expect(
		t,
		!os.exists(resolve_app_relative_path(temp_dir, "imgoptz-output", context.temp_allocator)),
	)
}

@(test, require)
test_resolve_runtime_output_root_for_input_uses_target_directory :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	input_dir := resolve_app_relative_path(temp_dir, "photos", context.temp_allocator)
	if !testing.expect_value(t, os.make_directory(input_dir), nil) {
		return
	}
	expected := resolve_app_relative_path(input_dir, "custom-output", context.temp_allocator)

	runtime_env := Runtime_Environment {
		output_mode      = .Dir,
		output_root      = "~/custom-output",
		output_root_kind = .Target_Relative,
	}
	resolved, ok := resolve_runtime_output_root_for_input(runtime_env, input_dir)
	defer delete(resolved)

	testing.expect_value(t, ok, true)
	testing.expect_value(t, resolved, expected)
	testing.expect(t, !os.exists(resolved))
}

@(test, require)
test_load_runtime_environment_skips_gpu_probe_when_disabled :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	if !write_required_runtime_tree(t, temp_dir) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	config.gpu = false

	env := load_runtime_environment(temp_dir, config)
	defer destroy_runtime_environment(&env)

	testing.expect_value(t, env.ok, true)
	testing.expect_value(t, env.gpu_status, Runtime_GPU_Status.Disabled_By_Config)
}

@(test, require)
test_load_runtime_environment_treats_gpu_as_no_op_compatibility_setting :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	if !write_required_runtime_tree(t, temp_dir) {
		return
	}

	config := default_config()
	defer destroy_config(&config)

	env := load_runtime_environment(temp_dir, config)
	defer destroy_runtime_environment(&env)

	testing.expect_value(t, env.ok, true)
	testing.expect_value(t, env.gpu_status, Runtime_GPU_Status.No_Op_Compatibility)
	testing.expect_value(t, len(env.warnings), 0)
}

@(test, require)
test_resolve_auto_worker_count_uses_cpu_and_memory_caps :: proc(t: ^testing.T) {
	GIB :: u64(1024 * 1024 * 1024)

	testing.expect_value(t, resolve_auto_worker_count(4, 32 * GIB), 1)
	testing.expect_value(t, resolve_auto_worker_count(8, 32 * GIB), 2)
	testing.expect_value(t, resolve_auto_worker_count(16, 32 * GIB), 4)
	testing.expect_value(t, resolve_auto_worker_count(24, 32 * GIB), 6)
	testing.expect_value(t, resolve_auto_worker_count(24, 12 * GIB), 4)
	testing.expect_value(t, resolve_auto_worker_count(24, 6 * GIB), 2)
	testing.expect_value(t, resolve_auto_worker_count(0, 0), 1)
}

@(test, require)
test_resolve_worker_count_clamps_explicit_minimum :: proc(t: ^testing.T) {
	workers := Config_Workers {
		kind  = .Explicit,
		count = 0,
	}
	testing.expect_value(t, resolve_worker_count(workers), 1)
}

make_temp_runtime_root :: proc(t: ^testing.T) -> string {
	last_err := os.ERROR_NONE
	for attempt in 0 ..< 8 {
		temp_dir, temp_err := os.make_directory_temp("", "imgoptz-runtime-*", context.allocator)
		if temp_err == nil {
			return temp_dir
		}
		last_err = temp_err
		if temp_err != .Permission_Denied {
			if !testing.expect_value(t, temp_err, nil) {
				return ""
			}
		}
		_ = attempt
	}
	testing.expect_value(t, last_err, nil)
	return ""
}

write_required_runtime_tree :: proc(t: ^testing.T, app_root: string) -> bool {
	for required in RUNTIME_REQUIRED_TOOLS {
		path := resolve_app_relative_path(app_root, required.relative_path, context.temp_allocator)
		dir, _ := os.split_path(path)
		mkdir_err := os.make_directory_all(dir)
		if !testing.expect_value(t, mkdir_err, nil) {
			return false
		}
		write_err := os.write_entire_file(path, "test")
		if !testing.expect_value(t, write_err, nil) {
			return false
		}
	}

	for required in RUNTIME_REQUIRED_FILES {
		path := resolve_app_relative_path(app_root, required.relative_path, context.temp_allocator)
		dir, _ := os.split_path(path)
		mkdir_err := os.make_directory_all(dir)
		if !testing.expect_value(t, mkdir_err, nil) {
			return false
		}
		write_err := os.write_entire_file(path, "test")
		if !testing.expect_value(t, write_err, nil) {
			return false
		}
	}
	return true
}

write_required_runtime_tree_with_folder_names :: proc(
	t: ^testing.T,
	app_root: string,
	folder_names: []string,
) -> bool {
	if !testing.expect_value(t, len(folder_names), len(RUNTIME_REQUIRED_TOOLS) - 1) {
		return false
	}

	for required in RUNTIME_REQUIRED_TOOLS {
		folder_name := required.folder_name
		switch required.label {
		case "MozJPEG":
			folder_name = folder_names[0]
		case "Oxipng":
			folder_name = folder_names[1]
		case "pngquant":
			folder_name = folder_names[2]
		case "libvips", "libvips header":
			folder_name = folder_names[3]
		}

		path := test_runtime_tool_path(app_root, folder_name, required.executable_path)
		dir, _ := os.split_path(path)
		mkdir_err := os.make_directory_all(dir)
		if !testing.expect_value(t, mkdir_err, nil) {
			return false
		}
		write_err := os.write_entire_file(path, "test")
		if !testing.expect_value(t, write_err, nil) {
			return false
		}
	}

	for required in RUNTIME_REQUIRED_FILES {
		path := resolve_app_relative_path(app_root, required.relative_path, context.temp_allocator)
		dir, _ := os.split_path(path)
		mkdir_err := os.make_directory_all(dir)
		if !testing.expect_value(t, mkdir_err, nil) {
			return false
		}
		write_err := os.write_entire_file(path, "test")
		if !testing.expect_value(t, write_err, nil) {
			return false
		}
	}
	return true
}

test_runtime_tool_path :: proc(app_root, folder_name, executable_path: string) -> string {
	parts := [?]string{app_root, RUNTIME_TOOLS_DIR, folder_name, executable_path}
	path, path_err := os.join_path(parts[:], context.temp_allocator)
	if path_err != nil {
		return ""
	}
	return path
}
