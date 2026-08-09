package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

Debug_Log_Init_Result :: struct {
	enabled: bool,
	path:    string,
	err:     os.Error,
}

debug_log_enabled: bool
debug_log_path: string
debug_log_logger: log.Logger
debug_log_mutex: sync.Mutex

init_debug_logging :: proc(app_root: string, config: App_Config) -> Debug_Log_Init_Result {
	if !config.debug_log {
		return Debug_Log_Init_Result{}
	}

	path := resolve_debug_log_path(app_root, config.debug_log_file)
	if len(path) == 0 {
		return Debug_Log_Init_Result{}
	}

	file, open_err := os.open(path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
	if open_err != nil {
		delete(path)
		return Debug_Log_Init_Result{err = open_err}
	}

	logger := log.create_file_logger(file, log.Level.Debug, log.Options{.Level, .Date, .Time})
	if sync.mutex_guard(&debug_log_mutex) {
		debug_log_logger = logger
		debug_log_enabled = true
		debug_log_path = strings_clone_or_empty(path)
	}

	debug_log_section("APP")
	debug_log_infof("debug logging enabled: path=\"%s\"", path)
	delete(path)
	return Debug_Log_Init_Result{enabled = true, path = strings_clone_or_empty(debug_log_path)}
}

destroy_debug_logging :: proc() {
	if sync.mutex_guard(&debug_log_mutex) {
		if !debug_log_enabled {
			return
		}

		debug_log_logger.procedure(
			debug_log_logger.data,
			log.Level.Info,
			"debug logging disabled",
			debug_log_logger.options,
		)
		debug_log_enabled = false
		log.destroy_file_logger(debug_log_logger)
		delete(debug_log_path)
		debug_log_path = ""
		debug_log_logger = {}
	}
}

destroy_debug_log_init_result :: proc(result: ^Debug_Log_Init_Result) {
	delete(result.path)
	result^ = {}
}

resolve_debug_log_path :: proc(
	app_root, debug_log_file: string,
	allocator := context.allocator,
) -> string {
	return resolve_debug_log_path_at(app_root, debug_log_file, time.now(), allocator)
}

resolve_debug_log_path_at :: proc(
	app_root, debug_log_file: string,
	timestamp: time.Time,
	allocator := context.allocator,
) -> string {
	base_path := resolve_app_relative_path(app_root, debug_log_file, context.temp_allocator)
	if len(base_path) == 0 {
		return ""
	}

	dir, filename := os.split_path(base_path)
	timestamp_prefix := debug_log_timestamp_prefix(timestamp)
	log_filename := fmt.tprintf("%s-%s", timestamp_prefix, filename)
	parts := [?]string{dir, log_filename}
	path, join_err := os.join_path(parts[:], allocator)
	if join_err != nil {
		return ""
	}
	return path
}

debug_log_timestamp_prefix :: proc(timestamp: time.Time) -> string {
	datetime, ok := time.time_to_datetime(timestamp)
	if !ok {
		return fmt.tprintf("%d", time.time_to_unix_nano(timestamp))
	}

	return fmt.tprintf(
		"%04d%02d%02d-%02d%02d%02d-%09d",
		datetime.year,
		datetime.month,
		datetime.day,
		datetime.hour,
		datetime.minute,
		datetime.second,
		datetime.nano,
	)
}

debug_log_section :: proc(title: string) {
	debug_log_infof("=== %s ===", title)
}

debug_log_write :: proc(level: log.Level, message: string, location := #caller_location) {
	if !debug_log_enabled {
		return
	}
	if sync.mutex_guard(&debug_log_mutex) {
		if !debug_log_enabled {
			return
		}
		debug_log_logger.procedure(
			debug_log_logger.data,
			level,
			message,
			debug_log_logger.options,
			location,
		)
	}
}

debug_log_info :: proc(message: string, location := #caller_location) {
	debug_log_write(.Info, message, location)
}

debug_log_infof :: proc($format: string, args: ..any, location := #caller_location) {
	if !debug_log_enabled {
		return
	}
	debug_log_write(.Info, fmt.tprintf(format, ..args), location)
}

debug_log_debugf :: proc($format: string, args: ..any, location := #caller_location) {
	if !debug_log_enabled {
		return
	}
	debug_log_write(.Debug, fmt.tprintf(format, ..args), location)
}

debug_log_warnf :: proc($format: string, args: ..any, location := #caller_location) {
	if !debug_log_enabled {
		return
	}
	debug_log_write(.Warning, fmt.tprintf(format, ..args), location)
}

debug_log_errorf :: proc($format: string, args: ..any, location := #caller_location) {
	if !debug_log_enabled {
		return
	}
	debug_log_write(.Error, fmt.tprintf(format, ..args), location)
}

debug_log_config_result :: proc(result: Config_Load_Result) {
	debug_log_section("APP SETTINGS")
	debug_log_infof("config status: %v", result.status)
	debug_log_infof("config warnings: %d", len(result.warnings))
	for warning in result.warnings {
		debug_log_warnf("config warning: %s", warning)
	}
	debug_log_config(result.config)
}

debug_log_config :: proc(config: App_Config) {
	debug_log_debugf("recursive=%v", config.recursive)
	debug_log_debugf("max_dimension=%d", config.max_dimension)
	debug_log_debugf("workers=%s", debug_log_workers(config.workers))
	debug_log_debugf("gpu=%v", config.gpu)
	debug_log_debugf("debug_log=%v", config.debug_log)
	debug_log_debugf("debug_log_file=\"%s\"", config.debug_log_file)
	debug_log_debugf("dry_run=%v", config.dry_run)
	debug_log_debugf("output_mode=%s", debug_log_output_mode(config.output_mode))
	debug_log_debugf("out_dir=\"%s\"", config.out_dir)
	debug_log_debugf(
		"jpeg: enabled=%v quality=%d progressive=%v optimize=%v sample=%s quant_table=%d tune=%s preserve_profiles=%v",
		config.jpeg.enabled,
		config.jpeg.quality,
		config.jpeg.progressive,
		config.jpeg.optimize,
		config.jpeg.sample,
		config.jpeg.quant_table,
		config.jpeg.tune,
		config.jpeg.preserve_profiles,
	)
	debug_log_debugf(
		"png: enabled=%v pngquant_quality=%s pngquant_speed=%d pngquant_dither=%v oxipng_level=%d interlace=%v strip=%s alpha=%v preserve_profiles=%v",
		config.png.enabled,
		config.png.pngquant_quality,
		config.png.pngquant_speed,
		config.png.pngquant_dither,
		config.png.oxipng_level,
		config.png.interlace,
		config.png.strip,
		config.png.alpha,
		config.png.preserve_profiles,
	)
}

debug_log_runtime_environment :: proc(env: Runtime_Environment) {
	debug_log_section("RUNTIME")
	debug_log_infof(
		"runtime ok=%v warnings=%d errors=%d",
		env.ok,
		len(env.warnings),
		len(env.errors),
	)
	debug_log_debugf("worker_count=%d", env.worker_count)
	debug_log_debugf("output_mode=%s", debug_log_output_mode(env.output_mode))
	debug_log_debugf("output_root=\"%s\"", env.output_root)
	debug_log_debugf("mozjpeg_path=\"%s\"", env.mozjpeg_path)
	debug_log_debugf("oxipng_path=\"%s\"", env.oxipng_path)
	debug_log_debugf("pngquant_path=\"%s\"", env.pngquant_path)
	debug_log_debugf("vips_path=\"%s\"", env.vips_path)
	debug_log_debugf("vipsheader_path=\"%s\"", env.vipsheader_path)
	debug_log_debugf("srgb_profile=\"%s\"", env.srgb_profile)
	debug_log_debugf("gpu_status=%v", env.gpu_status)
	for warning in env.warnings {
		debug_log_warnf("runtime warning: %s", warning)
	}
	for err in env.errors {
		debug_log_errorf("runtime error: %s", err)
	}
}

debug_log_prompt_input :: proc(raw: string, input: Prompt_Input) {
	debug_log_section("INPUT")
	debug_log_infof("raw input: \"%s\"", raw)
	debug_log_infof("parsed input kind=%v path=\"%s\"", input.kind, input.path)
}

debug_log_process_start :: proc(label: string, command: []string, environment: []string) {
	debug_log_section("PROCESS")
	debug_log_infof("start: %s", label)
	debug_log_debugf("command args: %v", command)
	if environment == nil {
		debug_log_debugf("environment: inherited default")
		return
	}
	debug_log_debugf("environment entries: %d", len(environment))
	for entry in environment {
		if debug_log_environment_entry_is_relevant(entry) {
			debug_log_debugf("environment override: %s", entry)
		}
	}
}

debug_log_process_finish :: proc(
	label: string,
	state: os.Process_State,
	stdout, stderr: []byte,
	err: os.Error,
) {
	if err != nil {
		debug_log_errorf("finish: %s run error=%v", label, err)
	} else {
		debug_log_infof(
			"finish: %s exited=%v exit_code=%d stdout_bytes=%d stderr_bytes=%d",
			label,
			state.exited,
			state.exit_code,
			len(stdout),
			len(stderr),
		)
	}
	if len(stdout) > 0 {
		debug_log_debugf("stdout: %s", string(stdout))
	}
	if len(stderr) > 0 {
		debug_log_debugf("stderr: %s", string(stderr))
	}
}

process_exec_logged :: proc(
	command: []string,
	environment: []string,
	label: string,
) -> (
	os.Process_State,
	[]byte,
	[]byte,
	os.Error,
) {
	debug_log_process_start(label, command, environment)
	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = command, env = environment},
		context.allocator,
	)
	debug_log_process_finish(label, state, stdout, stderr, err)
	return state, stdout, stderr, err
}

debug_log_environment_entry_is_relevant :: proc(entry: string) -> bool {
	return environment_entry_name_equals(entry, "VIPS_CONCURRENCY")
}

debug_log_workers :: proc(workers: Config_Workers) -> string {
	switch workers.kind {
	case .Auto:
		return "auto"
	case .Explicit:
		return fmt.tprintf("%d", workers.count)
	}
	return "auto"
}

debug_log_output_mode :: proc(mode: Config_Output_Mode) -> string {
	switch mode {
	case .In_Place:
		return "in-place"
	case .Dir:
		return "dir"
	}
	return "in-place"
}

strings_clone_or_empty :: proc(value: string) -> string {
	if len(value) == 0 {
		return ""
	}
	return strings.clone(value)
}
