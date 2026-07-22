package main

import "core:os"
import "core:strings"
import "core:testing"

@(test, require)
test_validate_required_runtime_files_accepts_complete_distribution :: proc(t: ^testing.T) {
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
	validate_required_runtime_files(&env, temp_dir)

	testing.expect_value(t, len(env.errors), 0)
}

@(test, require)
test_validate_required_runtime_files_reports_missing_file :: proc(t: ^testing.T) {
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
		"tools/pngquant/COPYRIGHT",
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
	testing.expect(t, strings.contains(env.errors[0], "tools/pngquant/COPYRIGHT"))
}

@(test, require)
test_validate_required_runtime_files_reports_missing_executable :: proc(t: ^testing.T) {
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
		"tools/mozjpeg/mozjpeg.exe",
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
	testing.expect(t, strings.contains(env.errors[0], "MozJPEG executable"))
	testing.expect(t, strings.contains(env.errors[0], "tools/mozjpeg/mozjpeg.exe"))
}

@(test, require)
test_resolve_output_root_ignores_in_place_mode :: proc(t: ^testing.T) {
	config := default_config()
	defer destroy_config(&config)

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
	testing.expect_value(t, len(result.warnings), 0)
}

@(test, require)
test_resolve_output_root_falls_back_to_default_output :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	default_output := resolve_app_relative_path(
		temp_dir,
		RUNTIME_DEFAULT_OUTPUT_DIR,
		context.temp_allocator,
	)
	mkdir_err := os.make_directory(default_output)
	if !testing.expect_value(t, mkdir_err, nil) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	config.output_mode = .Dir
	replace_config_string(&config.out_dir, "typo-output")

	result := resolve_output_root(temp_dir, config)
	defer destroy_output_root_result(&result)

	testing.expect_value(t, result.err, Output_Root_Error.None)
	testing.expect_value(t, result.path, default_output)
	testing.expect_value(t, len(result.warnings), 1)
	testing.expect(t, strings.contains(result.warnings[0], "falling back"))
}

@(test, require)
test_resolve_output_root_errors_when_default_output_missing :: proc(t: ^testing.T) {
	temp_dir := make_temp_runtime_root(t)
	if len(temp_dir) == 0 {
		return
	}
	defer cleanup_test_directory(temp_dir)

	config := default_config()
	defer destroy_config(&config)
	config.output_mode = .Dir

	result := resolve_output_root(temp_dir, config)
	defer destroy_output_root_result(&result)

	testing.expect_value(t, result.err, Output_Root_Error.Default_Root_Missing)
	testing.expect_value(t, result.path, "")
}

@(test, require)
test_version_output_has_opencl_case_insensitive :: proc(t: ^testing.T) {
	testing.expect(t, version_output_has_opencl("Features: Cipher DPC HDRI OpenCL OpenMP"))
	testing.expect(t, version_output_has_opencl("features: opencl"))
	testing.expect(t, !version_output_has_opencl("Features: Cipher DPC HDRI OpenMP"))
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
	testing.expect_value(t, env.magick_use_gpu, false)
}

@(test, require)
test_load_runtime_environment_enables_gpu_after_successful_probe :: proc(t: ^testing.T) {
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

	env := load_runtime_environment_with_probe(temp_dir, config, test_gpu_probe_success)
	defer destroy_runtime_environment(&env)

	testing.expect_value(t, env.ok, true)
	testing.expect_value(t, env.gpu_status, Runtime_GPU_Status.Enabled)
	testing.expect_value(t, env.magick_use_gpu, true)
	testing.expect_value(t, len(env.warnings), 0)
}

@(test, require)
test_load_runtime_environment_warns_when_gpu_probe_fails :: proc(t: ^testing.T) {
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
	testing.expect_value(t, env.gpu_status, Runtime_GPU_Status.Probe_Failed)
	testing.expect_value(t, env.magick_use_gpu, false)
	testing.expect_value(t, len(env.warnings), 1)
	testing.expect(t, strings.contains(env.warnings[0], "GPU probe failed"))
}

make_temp_runtime_root :: proc(t: ^testing.T) -> string {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-runtime-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return ""
	}
	return temp_dir
}

write_required_runtime_tree :: proc(t: ^testing.T, app_root: string) -> bool {
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

test_gpu_probe_success :: proc(magick_path: string) -> bool {
	return len(magick_path) > 0
}
