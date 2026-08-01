package main

import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"

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
	recursive:      bool,
	output_mode:    Config_Output_Mode,
	output_root:    string,
	worker_count:   int,
	mozjpeg_path:   string,
	oxipng_path:    string,
	pngquant_path:  string,
	magick_path:    string,
	srgb_profile:   string,
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
RUNTIME_MOZJPEG_PATH :: "tools/mozjpeg/mozjpeg.exe"
RUNTIME_OXIPNG_PATH :: "tools/oxipng/oxipng.exe"
RUNTIME_PNGQUANT_PATH :: "tools/pngquant/pngquant.exe"
RUNTIME_MAGICK_PATH :: "tools/imagemagick/magick.exe"
RUNTIME_SRGB_PROFILE_PATH :: "profiles/sRGB2014.icc"

RUNTIME_REQUIRED_FILES :: [?]Runtime_Required_File {
	{relative_path = RUNTIME_MOZJPEG_PATH, label = "MozJPEG executable"},
	{relative_path = "tools/mozjpeg/LICENSE.md", label = "MozJPEG license"},
	{relative_path = "tools/mozjpeg/README.ijg", label = "MozJPEG IJG notice"},
	{relative_path = "tools/mozjpeg/README-mozilla.txt", label = "MozJPEG Mozilla notice"},
	{relative_path = RUNTIME_OXIPNG_PATH, label = "Oxipng executable"},
	{relative_path = "tools/oxipng/LICENSE", label = "Oxipng license"},
	{relative_path = RUNTIME_PNGQUANT_PATH, label = "pngquant executable"},
	{relative_path = "tools/pngquant/COPYRIGHT", label = "pngquant copyright notice"},
	{relative_path = RUNTIME_MAGICK_PATH, label = "ImageMagick executable"},
	{relative_path = "tools/imagemagick/LICENSE.txt", label = "ImageMagick license"},
	{relative_path = "tools/imagemagick/NOTICE.txt", label = "ImageMagick notice"},
	{relative_path = "tools/imagemagick/policy.xml", label = "ImageMagick policy"},
	{relative_path = RUNTIME_SRGB_PROFILE_PATH, label = "sRGB ICC profile"},
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
	debug_log_section("RUNTIME")
	debug_log_infof("load runtime environment: app_root=\"%s\"", app_root)
	env := Runtime_Environment {
		ok           = true,
		recursive    = config.recursive,
		output_mode  = config.output_mode,
		worker_count = resolve_worker_count(config.workers),
		gpu_status   = .Disabled_By_Config,
	}

	validate_required_runtime_files(&env, app_root)
	resolve_runtime_tool_paths(&env, app_root)

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
		debug_log_info("gpu requested: probing ImageMagick OpenCL")
		if os.is_file(env.magick_path) {
			if probe(env.magick_path) {
				env.gpu_status = .Enabled
				env.magick_use_gpu = true
				debug_log_info(
					"gpu probe succeeded: MAGICK_OCL_DEVICE=GPU enabled for ImageMagick",
				)
			} else {
				env.gpu_status = .Probe_Failed
				debug_log_warnf("gpu probe failed for magick_path=\"%s\"", env.magick_path)
				add_runtime_warning(&env, "GPU acceleration is unavailable. Continuing with CPU.")
			}
		}
	} else {
		debug_log_info("gpu disabled by config: skipping ImageMagick OpenCL probe")
	}

	env.ok = len(env.errors) == 0
	return env
}

resolve_worker_count :: proc(workers: Config_Workers) -> int {
	switch workers.kind {
	case .Explicit:
		resolved := max(workers.count, 1)
		debug_log_debugf("resolve workers: explicit=%d resolved=%d", workers.count, resolved)
		return resolved
	case .Auto:
		logical_cores := os.get_processor_core_count()
		memory := available_physical_memory()
		resolved := resolve_auto_worker_count(logical_cores, memory)
		debug_log_debugf(
			"resolve workers: auto logical_cores=%d available_memory=%d resolved=%d",
			logical_cores,
			memory,
			resolved,
		)
		return resolved
	}
	return 1
}

resolve_auto_worker_count :: proc(logical_cores: int, available_memory_bytes: u64) -> int {
	worker_count := 1
	switch {
	case logical_cores <= 4:
		worker_count = 1
	case logical_cores <= 8:
		worker_count = 2
	case logical_cores <= 16:
		worker_count = 4
	case logical_cores >= 24:
		worker_count = 6
	case:
		worker_count = 4
	}

	GIB :: u64(1024 * 1024 * 1024)
	if available_memory_bytes > 0 {
		if available_memory_bytes < 8 * GIB {
			worker_count = min(worker_count, 2)
		} else if available_memory_bytes < 16 * GIB {
			worker_count = min(worker_count, 4)
		}
	}
	return max(worker_count, 1)
}

available_physical_memory :: proc() -> u64 {
	when ODIN_OS == .Windows {
		status: win.MEMORYSTATUSEX
		status.dwLength = size_of(win.MEMORYSTATUSEX)
		if win.GlobalMemoryStatusEx(&status) != win.FALSE {
			return u64(status.ullAvailPhys)
		}
	}
	return 0
}

destroy_runtime_environment :: proc(env: ^Runtime_Environment) {
	delete(env.output_root)
	delete(env.mozjpeg_path)
	delete(env.oxipng_path)
	delete(env.pngquant_path)
	delete(env.magick_path)
	delete(env.srgb_profile)
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

resolve_runtime_tool_paths :: proc(env: ^Runtime_Environment, app_root: string) {
	env.mozjpeg_path = resolve_app_relative_path(app_root, RUNTIME_MOZJPEG_PATH)
	env.oxipng_path = resolve_app_relative_path(app_root, RUNTIME_OXIPNG_PATH)
	env.pngquant_path = resolve_app_relative_path(app_root, RUNTIME_PNGQUANT_PATH)
	env.magick_path = resolve_app_relative_path(app_root, RUNTIME_MAGICK_PATH)
	env.srgb_profile = resolve_app_relative_path(app_root, RUNTIME_SRGB_PROFILE_PATH)
	debug_log_debugf("resolved MozJPEG path: \"%s\"", env.mozjpeg_path)
	debug_log_debugf("resolved Oxipng path: \"%s\"", env.oxipng_path)
	debug_log_debugf("resolved pngquant path: \"%s\"", env.pngquant_path)
	debug_log_debugf("resolved ImageMagick path: \"%s\"", env.magick_path)
	debug_log_debugf("resolved sRGB profile path: \"%s\"", env.srgb_profile)
}

validate_required_runtime_files :: proc(env: ^Runtime_Environment, app_root: string) {
	for required in RUNTIME_REQUIRED_FILES {
		path := resolve_app_relative_path(app_root, required.relative_path, context.temp_allocator)
		if !os.is_file(path) {
			debug_log_errorf("missing runtime file: label=%s path=\"%s\"", required.label, path)
			add_runtime_error(
				env,
				fmt.tprintf(
					"Required file is missing: %s (%s).",
					required.relative_path,
					required.label,
				),
			)
		} else {
			debug_log_debugf("runtime file ok: label=%s path=\"%s\"", required.label, path)
		}
	}
}

resolve_output_root :: proc(app_root: string, config: App_Config) -> Output_Root_Result {
	result: Output_Root_Result
	if config.output_mode != .Dir {
		debug_log_debugf("output root resolution skipped for in-place mode")
		return result
	}

	configured_path := resolve_app_relative_path(app_root, config.out_dir, context.allocator)
	if len(configured_path) == 0 {
		debug_log_errorf("configured output root resolve failed: out_dir=\"%s\"", config.out_dir)
		result.err = .Resolve_Failed
		return result
	}
	defer delete(configured_path)

	if os.is_directory(configured_path) {
		debug_log_infof("configured output root accepted: \"%s\"", configured_path)
		result.path = strings.clone(configured_path)
		return result
	}

	if config.out_dir != RUNTIME_DEFAULT_OUTPUT_DIR {
		debug_log_warnf(
			"configured output root missing: \"%s\"; falling back to %s",
			configured_path,
			RUNTIME_DEFAULT_OUTPUT_DIR,
		)
		append(
			&result.warnings,
			fmt.aprintf(
				"Configured output folder does not exist. Falling back to %s.",
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
		debug_log_errorf("default output root resolve failed")
		result.err = .Resolve_Failed
		return result
	}
	defer delete(default_path)

	if !os.is_directory(default_path) {
		debug_log_errorf("default output root missing: \"%s\"", default_path)
		result.err = .Default_Root_Missing
		return result
	}

	debug_log_infof("default output root accepted: \"%s\"", default_path)
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
	state, stdout, stderr, err := process_exec_logged(
		command[:],
		nil,
		"ImageMagick OpenCL version probe",
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

	state, stdout, stderr, err := process_exec_logged(
		command[:],
		environment,
		"ImageMagick OpenCL resize probe",
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
		return "Could not read the output folder path."
	case .Default_Root_Missing:
		return(
			"Output folder does not exist: output. Please create it or update out_dir in imgoptz.json." \
		)
	}
	return "Could not read the output folder path."
}

add_runtime_warning :: proc(env: ^Runtime_Environment, warning: string) {
	append(&env.warnings, strings.clone(warning))
}

add_runtime_error :: proc(env: ^Runtime_Environment, err: string) {
	append(&env.errors, strings.clone(err))
}

print_runtime_warnings :: proc(env: Runtime_Environment) {
	for warning in env.warnings {
		print_ui_warning(warning)
	}
}

print_runtime_errors :: proc(env: Runtime_Environment) {
	for err in env.errors {
		print_ui_error(err)
	}
}
