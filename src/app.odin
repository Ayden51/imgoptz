package main

import "core:log"

run_imgoptz :: proc() {
	if !configure_console_utf8() {
		log.warn(
			"Failed to set console code page to UTF-8; Unicode pasted paths may not work correctly.",
		)
	}

	app_root := initialize_app_root()
	if app_root.err != .None {
		print_app_root_error(app_root)
		return
	}
	defer delete(app_root.path)

	config_result := load_app_config()
	defer destroy_config_load_result(&config_result)

	print_startup_summary(app_root.path, config_result)
	print_config_warnings(config_result)

	runtime_env := load_runtime_environment(app_root.path, config_result.config)
	defer destroy_runtime_environment(&runtime_env)
	print_runtime_warnings(runtime_env)
	if !runtime_env.ok {
		print_runtime_errors(runtime_env)
		return
	}
	print_runtime_summary(runtime_env)
	run_prompt_loop(runtime_env, config_result.config)
}

print_app_root_error :: proc(app_root: App_Root) {
	switch app_root.err {
	case .None:
	case .Get_Executable_Directory_Failed:
		log.error("Failed to get executable directory:", app_root.os_err)
	case .Change_Directory_Failed:
		log.error("Failed to change directory to executable directory:", app_root.os_err)
	}
}

print_startup_summary :: proc(app_root_path: string, config_result: Config_Load_Result) {
	log.info("== imgoptz ==")
	log.info("Working directory:", app_root_path)
	log.info("Config:", config_status_summary(config_result.status))
	print_debug_startup_config(config_result.config)
}

print_debug_startup_config :: proc(config: App_Config) {
	if !config.debug_log {
		return
	}

	log.info("")
	log.info("-- Debug config --")
	log.info("Recursive:", config.recursive)
	log.info("Max dimension:", config.max_dimension)
	log.info("Workers:", config_workers_summary(config.workers))
	log.info("GPU:", config.gpu)
	log.info("Output mode:", config_output_mode_summary(config.output_mode))
	log.info("JPEG:", config_jpeg_summary(config.jpeg))
	log.info("PNG:", config_png_summary(config.png))
	log.info("-- End debug config --")
	log.info("")
}
