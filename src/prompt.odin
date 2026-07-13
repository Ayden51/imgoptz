package main

import "core:bufio"
import "core:log"
import "core:os"

run_prompt_loop :: proc() {
	sc: bufio.Scanner
	bufio.scanner_init(&sc, os.to_stream(os.stdin))
	defer bufio.scanner_destroy(&sc)
	sc.split = bufio.scan_lines

	for {
		if !prompt_once(&sc) {
			break
		}
	}
}

prompt_once :: proc(sc: ^bufio.Scanner) -> bool {
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
		process_input_directory(input.path)
		return true
	}

	return true
}

process_input_directory :: proc(input_path: string) {
	absolute_path, input_dir_err := accept_input_directory(input_path)
	switch input_dir_err {
	case .None:
		log.info("Accepted directory:", absolute_path)
		log.info("Image discovery and optimization are not implemented yet.")
	case .Not_Directory:
		log.error("Not a directory:", input_path)
	case .Resolve_Failed:
		log.error("Failed to resolve directory path.")
	}
}
