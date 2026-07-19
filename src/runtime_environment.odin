package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

Runtime_GPU_Status :: enum {
	Disabled_By_Config,
	Enabled,
	Probe_Failed,
}

Runtime_GPU_Probe :: proc(magick_path: string) -> bool

Runtime_Required_File :: struct {
	relative_path: string,
	label:         string,
}

Runtime_Environment :: struct {
	ok:             bool,
	output_mode:    Config_Output_Mode,
	output_root:    string,
	gpu_status:     Runtime_GPU_Status,
	magick_use_gpu: bool,
	warnings:       [dynamic]string,
	errors:         [dynamic]string,
}

Output_Root_Error :: enum {
	None,
	Resolve_Failed,
	Default_Root_Missing,
}

Output_Root_Result :: struct {
	path:     string,
	err:      Output_Root_Error,
	warnings: [dynamic]string,
}

RUNTIME_DEFAULT_OUTPUT_DIR :: "output"

RUNTIME_REQUIRED_FILES :: [?]Runtime_Required_File {
	{relative_path = "tools/mozjpeg/mozjpeg.exe", label = "MozJPEG executable"},
	{relative_path = "tools/mozjpeg/LICENSE.md", label = "MozJPEG license"},
	{relative_path = "tools/mozjpeg/README.ijg", label = "MozJPEG IJG notice"},
	{relative_path = "tools/mozjpeg/README-mozilla.txt", label = "MozJPEG Mozilla notice"},
	{relative_path = "tools/oxipng/oxipng.exe", label = "Oxipng executable"},
	{relative_path = "tools/oxipng/LICENSE", label = "Oxipng license"},
	{relative_path = "tools/pngquant/pngquant.exe", label = "pngquant executable"},
	{relative_path = "tools/pngquant/COPYRIGHT", label = "pngquant copyright notice"},
	{relative_path = "tools/imagemagick/magick.exe", label = "ImageMagick executable"},
	{relative_path = "tools/imagemagick/LICENSE.txt", label = "ImageMagick license"},
	{relative_path = "tools/imagemagick/NOTICE.txt", label = "ImageMagick notice"},
	{relative_path = "tools/imagemagick/policy.xml", label = "ImageMagick policy"},
	{relative_path = "profiles/sRGB2014.icc", label = "sRGB ICC profile"},
	{relative_path = "profiles/sRGB2014.LICENSE.txt", label = "sRGB ICC profile license"},
}

load_runtime_environment :: proc(app_root: string, config: App_Config) -> Runtime_Environment {
	return load_runtime_environment_with_probe(app_root, config, probe_imagemagick_opencl)
}

load_runtime_environment_with_probe :: proc(
	app_root: string,
	config: App_Config,
	probe: Runtime_GPU_Probe,
) -> Runtime_Environment {
	env := Runtime_Environment {
		ok          = true,
		output_mode = config.output_mode,
		gpu_status  = .Disabled_By_Config,
	}

	validate_required_runtime_files(&env, app_root)

	output_root := resolve_output_root(app_root, config)
	defer destroy_output_root_result(&output_root)
	for warning in output_root.warnings {
		add_runtime_warning(&env, warning)
	}
	if output_root.err != .None {
		add_runtime_error(&env, output_root_error_summary(output_root.err))
	} else if len(output_root.path) > 0 {
		env.output_root = strings.clone(output_root.path)
	}

	if config.gpu {
		magick_path := resolve_app_relative_path(
			app_root,
			"tools/imagemagick/magick.exe",
			context.temp_allocator,
		)
		if os.is_file(magick_path) {
			if probe(magick_path) {
				env.gpu_status = .Enabled
				env.magick_use_gpu = true
			} else {
				env.gpu_status = .Probe_Failed
				add_runtime_warning(
					&env,
					"ImageMagick OpenCL GPU probe failed; falling back to CPU.",
				)
			}
		}
	}

	env.ok = len(env.errors) == 0
	return env
}

destroy_runtime_environment :: proc(env: ^Runtime_Environment) {
	delete(env.output_root)
	for warning in env.warnings {
		delete(warning)
	}
	delete(env.warnings)
	for err in env.errors {
		delete(err)
	}
	delete(env.errors)
	env^ = {}
}

validate_required_runtime_files :: proc(env: ^Runtime_Environment, app_root: string) {
	for required in RUNTIME_REQUIRED_FILES {
		path := resolve_app_relative_path(app_root, required.relative_path, context.temp_allocator)
		if !os.is_file(path) {
			add_runtime_error(
				env,
				fmt.tprintf("Missing %s: %s", required.label, required.relative_path),
			)
		}
	}
}

resolve_output_root :: proc(app_root: string, config: App_Config) -> Output_Root_Result {
	result: Output_Root_Result
	if config.output_mode != .Dir {
		return result
	}

	configured_path := resolve_app_relative_path(app_root, config.out_dir, context.allocator)
	if len(configured_path) == 0 {
		result.err = .Resolve_Failed
		return result
	}
	defer delete(configured_path)

	if os.is_directory(configured_path) {
		result.path = strings.clone(configured_path)
		return result
	}

	if config.out_dir != RUNTIME_DEFAULT_OUTPUT_DIR {
		append(
			&result.warnings,
			fmt.aprintf(
				"Configured out_dir does not exist; falling back to %s.",
				RUNTIME_DEFAULT_OUTPUT_DIR,
			),
		)
	}

	default_path := resolve_app_relative_path(
		app_root,
		RUNTIME_DEFAULT_OUTPUT_DIR,
		context.allocator,
	)
	if len(default_path) == 0 {
		result.err = .Resolve_Failed
		return result
	}
	defer delete(default_path)

	if !os.is_directory(default_path) {
		result.err = .Default_Root_Missing
		return result
	}

	result.path = strings.clone(default_path)
	return result
}

destroy_output_root_result :: proc(result: ^Output_Root_Result) {
	delete(result.path)
	for warning in result.warnings {
		delete(warning)
	}
	delete(result.warnings)
	result^ = {}
}

resolve_app_relative_path :: proc(
	app_root, path: string,
	allocator := context.allocator,
) -> string {
	if os.is_absolute_path(path) {
		absolute_path, absolute_path_err := os.get_absolute_path(path, allocator)
		if absolute_path_err != os.ERROR_NONE {
			return ""
		}
		return absolute_path
	}

	parts := [?]string{app_root, path}
	joined, join_err := os.join_path(parts[:], allocator)
	if join_err != nil {
		return ""
	}
	return joined
}

probe_imagemagick_opencl :: proc(magick_path: string) -> bool {
	command := [?]string{magick_path, "-version"}
	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = command[:]},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil || !state.exited || state.exit_code != 0 {
		return false
	}

	if !(version_output_has_opencl(string(stdout)) || version_output_has_opencl(string(stderr))) {
		return false
	}

	return probe_imagemagick_gpu_resize(magick_path)
}

probe_imagemagick_gpu_resize :: proc(magick_path: string) -> bool {
	command := [?]string {
		magick_path,
		"-size",
		"8x8",
		"xc:white",
		"-filter",
		"Lanczos",
		"-resize",
		"4x4",
		"null:",
	}
	environment, environment_ok := probe_imagemagick_gpu_environment(context.temp_allocator)
	if !environment_ok {
		return false
	}

	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = command[:], env = environment},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	return err == nil && state.exited && state.exit_code == 0
}

probe_imagemagick_gpu_environment :: proc(allocator := context.allocator) -> ([]string, bool) {
	inherited, inherited_err := os.environ(allocator)
	if inherited_err != nil {
		return nil, false
	}

	environment: [dynamic]string
	environment.allocator = allocator
	for entry in inherited {
		append(&environment, entry)
	}
	append(&environment, "MAGICK_OCL_DEVICE=GPU")
	return environment[:], true
}

version_output_has_opencl :: proc(text: string) -> bool {
	lower, lower_err := strings.to_lower(text, context.temp_allocator)
	if lower_err != nil {
		return false
	}
	return strings.contains(lower, "opencl")
}

output_root_error_summary :: proc(err: Output_Root_Error) -> string {
	switch err {
	case .None:
		return ""
	case .Resolve_Failed:
		return "Failed to resolve output directory path."
	case .Default_Root_Missing:
		return "Output mode is dir, but the accepted output root does not exist: output"
	}
	return "Failed to resolve output directory path."
}

add_runtime_warning :: proc(env: ^Runtime_Environment, warning: string) {
	append(&env.warnings, strings.clone(warning))
}

add_runtime_error :: proc(env: ^Runtime_Environment, err: string) {
	append(&env.errors, strings.clone(err))
}

print_runtime_warnings :: proc(env: Runtime_Environment) {
	for warning in env.warnings {
		log.warn(warning)
	}
}

print_runtime_errors :: proc(env: Runtime_Environment) {
	for err in env.errors {
		log.error(err)
	}
}

print_runtime_summary :: proc(env: Runtime_Environment) {
	log.info("GPU:", runtime_gpu_status_summary(env.gpu_status))
	if env.output_mode == .Dir {
		log.info("Output root:", env.output_root)
	}
}

runtime_gpu_status_summary :: proc(status: Runtime_GPU_Status) -> string {
	switch status {
	case .Disabled_By_Config:
		return "disabled by config"
	case .Enabled:
		return "enabled via ImageMagick OpenCL"
	case .Probe_Failed:
		return "disabled; ImageMagick OpenCL probe failed"
	}
	return "disabled"
}
