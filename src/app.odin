package main

import "core:fmt"

run_imgoptz :: proc() {
	if !configure_console_utf8() {
		print_ui_warning(
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

	print_startup_banner()
	print_config_warnings(config_result)

	runtime_env := load_runtime_environment(app_root.path, config_result.config)
	defer destroy_runtime_environment(&runtime_env)
	print_runtime_warnings(runtime_env)
	print_app_settings(app_root.path, config_result, runtime_env)
	if !runtime_env.ok {
		print_runtime_errors(runtime_env)
		return
	}
	run_prompt_loop(runtime_env, config_result.config)
}

print_app_root_error :: proc(app_root: App_Root) {
	switch app_root.err {
	case .None:
	case .Get_Executable_Directory_Failed:
		print_ui_error(fmt.tprintf("Failed to get executable directory: %v", app_root.os_err))
	case .Change_Directory_Failed:
		print_ui_error(fmt.tprintf("Failed to change directory to executable directory: %v", app_root.os_err))
	}
}
