package main

import "core:bufio"
import "core:log"
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
	log.info("Paste one image directory path, or type 'exit':")

	if !bufio.scan(sc) {
		return false
	}

	input := parse_prompt_input(bufio.scanner_text(sc))
	switch input.kind {
	case .Invalid:
		log.error("Please paste one directory path.")
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
		log.info("Accepted directory:", absolute_path)
		if runtime_env.output_mode == .Dir {
			log.info("Accepted output root:", runtime_env.output_root)
		}
		result := discover_image_work(absolute_path, runtime_env)
		defer destroy_discovery_result(&result)
		if result.err != .None {
			log.error(discovery_error_summary(result.err), result.err_path)
			return
		}
		print_discovery_summary(result)
		process_discovered_images(result, config, runtime_env)
	case .Not_Directory:
		log.error("Not a directory:", input_path)
	case .Resolve_Failed:
		log.error("Failed to resolve directory path.")
	}
}
