package main

import "core:fmt"
import "core:os"
import "core:strings"
import win "core:sys/windows"

Runtime_GPU_Status :: enum {
	Disabled_By_Config,
	No_Op_Compatibility,
}

Output_Root_Kind :: enum {
	None,
	Prechecked,
	Target_Relative,
}

Runtime_Required_File :: struct {
	relative_path: string,
	label:         string,
}

Runtime_Required_Tool :: struct {
	executable_name: string,
	relative_path:   string,
	label:           string,
}

Runtime_Environment :: struct {
	ok:               bool,
	recursive:        bool,
	output_mode:      Config_Output_Mode,
	output_root:      string,
	output_root_kind: Output_Root_Kind,
	worker_count:     int,
	mozjpeg_path:     string,
	oxipng_path:      string,
	pngquant_path:    string,
	vips_path:        string,
	vipsheader_path:  string,
	srgb_profile:     string,
	gpu_status:       Runtime_GPU_Status,
	warnings:         [dynamic]string,
	errors:           [dynamic]string,
}

Output_Root_Error :: enum {
	None,
	Resolve_Failed,
	Default_Root_Missing,
}

Output_Root_Result :: struct {
	path:     string,
	kind:     Output_Root_Kind,
	err:      Output_Root_Error,
	warnings: [dynamic]string,
}

RUNTIME_DEFAULT_OUTPUT_DIR :: "~/imgoptz-output"
RUNTIME_TARGET_RELATIVE_OUTPUT_PREFIX :: "~/"
RUNTIME_MOZJPEG_PATH :: "tools/mozjpeg/static/Release/cjpeg-static.exe"
RUNTIME_OXIPNG_PATH :: "tools/oxipng-10.1.1-x86_64-pc-windows-msvc/oxipng.exe"
RUNTIME_PNGQUANT_PATH :: "tools/pngquant/pngquant.exe"
RUNTIME_VIPS_PATH :: "tools/vips-dev-8.18/bin/vips.exe"
RUNTIME_VIPSHEADER_PATH :: "tools/vips-dev-8.18/bin/vipsheader.exe"
RUNTIME_SRGB_PROFILE_PATH :: "profiles/sRGB2014.icc"

RUNTIME_REQUIRED_TOOLS :: [?]Runtime_Required_Tool {
	{
		executable_name = "cjpeg-static.exe",
		relative_path = RUNTIME_MOZJPEG_PATH,
		label = "MozJPEG",
	},
	{executable_name = "oxipng.exe", relative_path = RUNTIME_OXIPNG_PATH, label = "Oxipng"},
	{executable_name = "pngquant.exe", relative_path = RUNTIME_PNGQUANT_PATH, label = "pngquant"},
	{executable_name = "vips.exe", relative_path = RUNTIME_VIPS_PATH, label = "libvips"},
	{
		executable_name = "vipsheader.exe",
		relative_path = RUNTIME_VIPSHEADER_PATH,
		label = "libvips header",
	},
}

RUNTIME_REQUIRED_FILES :: [?]Runtime_Required_File {
	{relative_path = RUNTIME_SRGB_PROFILE_PATH, label = "sRGB ICC profile"},
}

load_runtime_environment :: proc(app_root: string, config: App_Config) -> Runtime_Environment {
	debug_log_section("RUNTIME")
	debug_log_infof("load runtime environment: app_root=\"%s\"", app_root)
	env := Runtime_Environment {
		ok           = true,
		recursive    = config.recursive,
		output_mode  = config.output_mode,
		worker_count = resolve_worker_count(config.workers),
		gpu_status   = .Disabled_By_Config,
	}

	resolve_runtime_tool_paths(&env, app_root)
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
		env.output_root_kind = output_root.kind
	}

	if config.gpu {
		env.gpu_status = .No_Op_Compatibility
		debug_log_info("gpu requested: ignored by libvips pipeline compatibility setting")
	} else {
		debug_log_info("gpu disabled by config")
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
	delete(env.vips_path)
	delete(env.vipsheader_path)
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
	path_env, path_found := os.lookup_env("PATH", context.temp_allocator)
	if !path_found {
		path_env = ""
	}
	resolve_runtime_tool_paths_from_path_env(env, app_root, path_env)
}

resolve_runtime_tool_paths_from_path_env :: proc(
	env: ^Runtime_Environment,
	app_root, path_env: string,
) {
	env.mozjpeg_path = resolve_runtime_tool_path(
		env,
		app_root,
		path_env,
		RUNTIME_REQUIRED_TOOLS[0],
	)
	env.oxipng_path = resolve_runtime_tool_path(env, app_root, path_env, RUNTIME_REQUIRED_TOOLS[1])
	env.pngquant_path = resolve_runtime_tool_path(
		env,
		app_root,
		path_env,
		RUNTIME_REQUIRED_TOOLS[2],
	)
	env.vips_path = resolve_runtime_tool_path(env, app_root, path_env, RUNTIME_REQUIRED_TOOLS[3])
	env.vipsheader_path = resolve_runtime_tool_path(
		env,
		app_root,
		path_env,
		RUNTIME_REQUIRED_TOOLS[4],
	)
	env.srgb_profile = resolve_app_relative_path(app_root, RUNTIME_SRGB_PROFILE_PATH)
	debug_log_debugf("resolved MozJPEG path: \"%s\"", env.mozjpeg_path)
	debug_log_debugf("resolved Oxipng path: \"%s\"", env.oxipng_path)
	debug_log_debugf("resolved pngquant path: \"%s\"", env.pngquant_path)
	debug_log_debugf("resolved libvips path: \"%s\"", env.vips_path)
	debug_log_debugf("resolved vipsheader path: \"%s\"", env.vipsheader_path)
	debug_log_debugf("resolved sRGB profile path: \"%s\"", env.srgb_profile)
}

resolve_runtime_tool_path :: proc(
	env: ^Runtime_Environment,
	app_root, path_env: string,
	tool: Runtime_Required_Tool,
) -> string {
	path_tool := find_executable_on_path(tool.executable_name, path_env)
	if len(path_tool) > 0 {
		debug_log_infof("runtime tool found on PATH: label=%s path=\"%s\"", tool.label, path_tool)
		return path_tool
	}

	fallback_path := resolve_app_relative_path(app_root, tool.relative_path)
	if os.is_file(fallback_path) {
		debug_log_infof(
			"runtime tool found in app tools folder: label=%s path=\"%s\"",
			tool.label,
			fallback_path,
		)
		return fallback_path
	}
	defer delete(fallback_path)

	debug_log_errorf(
		"missing runtime tool: label=%s executable=%s fallback=\"%s\"",
		tool.label,
		tool.executable_name,
		fallback_path,
	)
	add_runtime_error(
		env,
		fmt.tprintf("Required tool is missing: %s.", runtime_tool_error_label(tool)),
	)
	return ""
}

runtime_tool_error_label :: proc(tool: Runtime_Required_Tool) -> string {
	if tool.label == "libvips header" {
		return "libvips"
	}
	return tool.label
}

find_executable_on_path :: proc(
	executable_name, path_env: string,
	allocator := context.allocator,
) -> string {
	path_dirs, split_err := os.split_path_list(path_env, context.temp_allocator)
	if split_err != nil {
		return ""
	}

	for path_dir in path_dirs {
		parts := [?]string{path_dir, executable_name}
		candidate, join_err := os.join_path(parts[:], context.temp_allocator)
		if join_err != nil || !os.is_file(candidate) {
			continue
		}

		absolute_candidate, absolute_err := os.get_absolute_path(candidate, allocator)
		if absolute_err == os.ERROR_NONE {
			return absolute_candidate
		}
		return strings.clone(candidate, allocator)
	}
	return ""
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

	if output_path_is_target_relative(config.out_dir) {
		debug_log_infof("target-relative output root deferred: \"%s\"", config.out_dir)
		result.path = strings.clone(config.out_dir)
		result.kind = .Target_Relative
		return result
	}

	configured_path := resolve_app_output_path(app_root, config.out_dir, context.allocator)
	if len(configured_path) == 0 {
		debug_log_errorf("configured output root resolve failed: out_dir=\"%s\"", config.out_dir)
		result.err = .Resolve_Failed
		return result
	}
	defer delete(configured_path)

	if os.is_directory(configured_path) {
		debug_log_infof("configured output root accepted: \"%s\"", configured_path)
		result.path = strings.clone(configured_path)
		result.kind = .Prechecked
		return result
	}

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
	result.path = strings.clone(RUNTIME_DEFAULT_OUTPUT_DIR)
	result.kind = .Target_Relative
	return result
}

resolve_runtime_output_root_for_input :: proc(
	runtime_env: Runtime_Environment,
	input_root: string,
	allocator := context.allocator,
) -> (
	string,
	bool,
) {
	if runtime_env.output_mode != .Dir {
		return "", true
	}

	switch runtime_env.output_root_kind {
	case .Target_Relative:
		return resolve_target_relative_output_root(input_root, runtime_env.output_root, allocator)
	case .Prechecked:
		cloned, clone_err := strings.clone(runtime_env.output_root, allocator)
		return cloned, clone_err == nil
	case .None:
	}
	return "", false
}

resolve_target_relative_output_root :: proc(
	input_root, out_dir: string,
	allocator := context.allocator,
) -> (
	string,
	bool,
) {
	if !output_path_is_target_relative(out_dir) {
		return "", false
	}

	relative := out_dir[len(RUNTIME_TARGET_RELATIVE_OUTPUT_PREFIX):]
	for len(relative) > 0 && os.is_path_separator(relative[0]) {
		relative = relative[1:]
	}
	if len(relative) == 0 {
		cloned, clone_err := strings.clone(input_root, allocator)
		return cloned, clone_err == nil
	}

	parts := [?]string{input_root, relative}
	path, path_err := os.join_path(parts[:], allocator)
	if path_err != nil {
		return "", false
	}
	return path, true
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

resolve_app_output_path :: proc(app_root, path: string, allocator := context.allocator) -> string {
	if output_path_is_rooted_app_relative(path) {
		return resolve_app_relative_path(
			app_root,
			path_without_leading_separators(path),
			allocator,
		)
	}
	return resolve_app_relative_path(app_root, path, allocator)
}

output_path_is_target_relative :: proc(path: string) -> bool {
	return strings.has_prefix(path, RUNTIME_TARGET_RELATIVE_OUTPUT_PREFIX)
}

output_path_is_rooted_app_relative :: proc(path: string) -> bool {
	return(
		len(path) > 0 &&
		os.is_path_separator(path[0]) &&
		!(len(path) > 1 && os.is_path_separator(path[1])) \
	)
}

path_without_leading_separators :: proc(path: string) -> string {
	result := path
	for len(result) > 0 && os.is_path_separator(result[0]) {
		result = result[1:]
	}
	return result
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
	for existing in env.errors {
		if existing == err {
			return
		}
	}
	append(&env.errors, strings.clone(err))
}

print_runtime_setup_guidance :: proc() {
	print_ui_blank()
	print_ui_linef("%s imgoptz cannot process images because required tools are missing.", UI_WARN)
	print_ui_line("Please install the missing image tools before using imgoptz.")
	print_ui_blank()
	print_ui_line("For quick setup, please follow the guide in README.txt.")
	print_ui_line("For a detailed step-by-step guide, please read the online guide:")
	print_ui_line("https://github.com/Ayden51/imgoptz#installation")
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
