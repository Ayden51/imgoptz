package main

import "core:bufio"
import "core:os"
import "core:strings"
import win "core:sys/windows"
import "core:unicode/utf16"

run_prompt_loop :: proc(runtime_env: Runtime_Environment, config: App_Config) {
	when ODIN_OS == .Windows {
		if stdin_is_windows_console() {
			for {
				if !prompt_once_windows_console(runtime_env, config) {
					break
				}
			}
			return
		}
	}

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
	debug_log_prompt_input(bufio.scanner_text(sc), input)
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

stdin_is_windows_console :: proc() -> bool {
	handle := win.GetStdHandle(win.STD_INPUT_HANDLE)
	if handle == win.INVALID_HANDLE || handle == nil {
		return false
	}

	mode: win.DWORD
	return win.GetConsoleMode(handle, &mode) != win.FALSE
}

prompt_once_windows_console :: proc(runtime_env: Runtime_Environment, config: App_Config) -> bool {
	print_input_header()

	raw, ok := read_windows_console_line_utf8()
	if !ok {
		return false
	}
	defer delete(raw)

	input := parse_prompt_input(raw)
	debug_log_prompt_input(raw, input)
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

read_windows_console_line_utf8 :: proc(allocator := context.allocator) -> (string, bool) {
	handle := win.GetStdHandle(win.STD_INPUT_HANDLE)
	if handle == win.INVALID_HANDLE || handle == nil {
		return "", false
	}

	UTF16_CAP :: 32 * 1024
	buf16: [UTF16_CAP]u16
	chars_read: win.DWORD
	if win.ReadConsoleW(handle, &buf16[0], win.DWORD(len(buf16)), &chars_read, nil) == win.FALSE {
		return "", false
	}
	if chars_read == 0 {
		return "", false
	}

	line16 := buf16[:int(chars_read)]
	if len(line16) > 0 && line16[len(line16) - 1] == '\n' {
		line16 = line16[:len(line16) - 1]
	}
	if len(line16) > 0 && line16[len(line16) - 1] == '\r' {
		line16 = line16[:len(line16) - 1]
	}

	buf8: [UTF16_CAP * 4]u8
	bytes_read := utf16.decode_to_utf8(buf8[:], line16)
	line := string(buf8[:bytes_read])
	cloned, clone_err := strings.clone(line, allocator)
	if clone_err != nil {
		return "", false
	}
	return cloned, true
}

process_input_directory :: proc(
	input_path: string,
	runtime_env: Runtime_Environment,
	config: App_Config,
) {
	debug_log_infof("accept directory input: \"%s\"", input_path)
	absolute_path, input_dir_err := accept_input_directory(input_path)
	switch input_dir_err {
	case .None:
		debug_log_infof("accepted directory absolute path: \"%s\"", absolute_path)
		print_input_accepted()
		result := discover_image_work(absolute_path, runtime_env)
		defer destroy_discovery_result(&result)
		if result.err != .None {
			debug_log_errorf("discovery failed: err=%v path=\"%s\"", result.err, result.err_path)
			print_discovery_error(result)
			return
		}
		debug_log_infof(
			"discovery accepted: total=%d jpeg=%d png=%d recursive=%v",
			len(result.items),
			result.jpeg_count,
			result.png_count,
			runtime_env.recursive,
		)
		print_discovery_summary(result, runtime_env.recursive)
		process_discovered_images(result, config, runtime_env)
	case .Not_Directory:
		debug_log_warnf("directory rejected: not a directory path=\"%s\"", input_path)
		print_ui_errorf("Not a directory: %s", input_path)
	case .Resolve_Failed:
		debug_log_errorf("directory rejected: resolve failed path=\"%s\"", input_path)
		print_ui_error("Failed to resolve directory path.")
	}
}
