package main

import "core:log"

run_imgoptz :: proc() {
	app_root := initialize_app_root()
	if app_root.err != .None {
		print_app_root_error(app_root)
		return
	}
	defer delete(app_root.path)

	print_startup_summary(app_root.path)
	run_prompt_loop()
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

print_startup_summary :: proc(app_root_path: string) {
	log.info("== imgoptz ==")
	log.info("Working directory:", app_root_path)
}
