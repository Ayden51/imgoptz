package main

run_imgoptz :: proc() {
	if !configure_console_utf8() {
		print_ui_warning(
			"Could not enable UTF-8 console input. Unicode pasted paths may not work correctly.",
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
	debug_log_result := init_debug_logging(app_root.path, config_result.config)
	defer destroy_debug_log_init_result(&debug_log_result)
	defer destroy_debug_logging()
	debug_log_infof("app root: \"%s\"", app_root.path)
	debug_log_config_result(config_result)

	print_startup_banner()
	print_config_warnings(config_result)

	runtime_env := load_runtime_environment(app_root.path, config_result.config)
	defer destroy_runtime_environment(&runtime_env)
	debug_log_runtime_environment(runtime_env)
	print_runtime_warnings(runtime_env)
	if !runtime_env.ok {
		print_runtime_errors(runtime_env)
		print_runtime_setup_guidance()
		run_runtime_error_loop()
		return
	}
	run_prompt_loop(runtime_env, config_result.config)
}

print_app_root_error :: proc(app_root: App_Root) {
	switch app_root.err {
	case .None:
	case .Get_Executable_Directory_Failed:
		print_ui_errorf("Could not find the imgoptz app folder: %v", app_root.os_err)
	case .Change_Directory_Failed:
		print_ui_errorf("Could not open the imgoptz app folder: %v", app_root.os_err)
	}
}
