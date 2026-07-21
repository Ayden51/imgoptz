package main

import "core:bufio"
import "core:os"

run_prompt_loop :: proc(runtime_env: Runtime_Environment, config: App_Config) {
	sc: bufio.Scanner
	bufio.scanner_init(&sc, os.to_stream(os.stdin))
	defer bufio.scanner_destroy(&sc)
	sc.split = bufio.scan_lines

	for {
		if !prompt_once(&sc, runtime_env, config) {
			break
		}
	}
}

prompt_once :: proc(
	sc: ^bufio.Scanner,
	runtime_env: Runtime_Environment,
	config: App_Config,
) -> bool {
	print_input_header()

	if !bufio.scan(sc) {
		return false
	}

	input := parse_prompt_input(bufio.scanner_text(sc))
	switch input.kind {
	case .Invalid:
		print_ui_error("Please paste one directory path.")
		return true
	case .Exit:
		return false
	case .Directory_Path:
		process_input_directory(input.path, runtime_env, config)
		return true
	}

	return true
}

process_input_directory :: proc(
	input_path: string,
	runtime_env: Runtime_Environment,
	config: App_Config,
) {
	absolute_path, input_dir_err := accept_input_directory(input_path)
	switch input_dir_err {
	case .None:
		print_input_accepted(absolute_path)
		result := discover_image_work(absolute_path, runtime_env)
		defer destroy_discovery_result(&result)
		if result.err != .None {
			print_discovery_error(result)
			return
		}
		print_discovery_summary(result, runtime_env.recursive)
		process_discovered_images(result, config, runtime_env)
	case .Not_Directory:
		print_ui_errorf("Not a directory: %s", input_path)
	case .Resolve_Failed:
		print_ui_error("Failed to resolve directory path.")
	}
}
