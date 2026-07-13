package main

import "core:os"
import win "core:sys/windows"

App_Root_Error :: enum {
	None,
	Get_Executable_Directory_Failed,
	Change_Directory_Failed,
}

App_Root :: struct {
	path:   string,
	err:    App_Root_Error,
	os_err: os.Error,
}

initialize_app_root :: proc() -> App_Root {
	exe_dir, exe_dir_err := os.get_executable_directory(context.allocator)
	if exe_dir_err != os.ERROR_NONE {
		return App_Root {err = .Get_Executable_Directory_Failed, os_err = exe_dir_err}
	}

	if change_dir_err := os.change_directory(exe_dir); change_dir_err != os.ERROR_NONE {
		delete(exe_dir)
		return App_Root {err = .Change_Directory_Failed, os_err = change_dir_err}
	}

	return App_Root {path = exe_dir, err = .None}
}

configure_console_utf8 :: proc() -> bool {
	when ODIN_OS != .Windows {
		return true
	}

	input_ok := win.SetConsoleCP(.UTF8) != win.FALSE
	output_ok := win.SetConsoleOutputCP(.UTF8) != win.FALSE
	return input_ok && output_ok
}
