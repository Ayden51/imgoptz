package main

import "core:bufio"
import "core:os"
import "core:strings"
import win "core:sys/windows"
import "core:unicode/utf16"

run_runtime_error_loop :: proc(app_root: string, config: App_Config) {
	when ODIN_OS == .Windows {
		if stdin_is_windows_console() {
			for {
				if !runtime_error_prompt_once_windows_console(app_root, config) {
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
		if !runtime_error_prompt_once(&sc, app_root, config) {
			break
		}
	}
}

runtime_error_prompt_once :: proc(
	sc: ^bufio.Scanner,
	app_root: string,
	config: App_Config,
) -> bool {
	print_runtime_recovery_prompt()

	if !bufio.scan(sc) {
		return false
	}

	return handle_runtime_recovery_input(bufio.scanner_text(sc), app_root, config)
}

runtime_error_prompt_once_windows_console :: proc(app_root: string, config: App_Config) -> bool {
	print_runtime_recovery_prompt()

	raw, ok := read_windows_console_line_utf8()
	if !ok {
		return false
	}
	defer delete(raw)

	return handle_runtime_recovery_input(raw, app_root, config)
}

handle_runtime_recovery_input :: proc(raw, app_root: string, config: App_Config) -> bool {
	switch parse_runtime_recovery_input(raw) {
	case .Exit:
		return false
	case .Other_Input:
		print_ui_warning(
			"Image folders cannot be processed until required dependencies are installed. Press Enter to check again, or type exit to close.",
		)
		return true
	case .Retry:
	}

	runtime_env := load_runtime_environment(app_root, config)
	defer destroy_runtime_environment(&runtime_env)
	debug_log_runtime_environment(runtime_env)
	print_runtime_warnings(runtime_env)
	if !runtime_env.ok {
		print_runtime_errors(runtime_env)
		print_runtime_setup_guidance()
		return true
	}

	print_ui_blank()
	print_ui_linef("%s Runtime dependencies found. You can process images now.", UI_OK)
	run_prompt_loop(runtime_env, config)
	return false
}

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
		process_input_directory(input.path, runtime_env, config, sc)
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
		process_input_directory(input.path, runtime_env, config, nil)
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
	approval_sc: ^bufio.Scanner,
) {
	debug_log_infof("accept directory input: \"%s\"", input_path)
	absolute_path, input_dir_err := accept_input_directory(input_path)
	switch input_dir_err {
	case .None:
		debug_log_infof("accepted directory absolute path: \"%s\"", absolute_path)
		print_input_accepted()
		effective_runtime_env := runtime_env
		resolved_output_root, output_root_ok := resolve_runtime_output_root_for_input(
			runtime_env,
			absolute_path,
		)
		if !output_root_ok {
			debug_log_errorf("output root rejected for input: \"%s\"", absolute_path)
			print_ui_error(
				"Could not prepare the output folder. Please check imgoptz.json and try again.",
			)
			return
		}
		defer delete(resolved_output_root)
		if runtime_env.output_mode == .Dir {
			effective_runtime_env.output_root = resolved_output_root
		}

		result := discover_image_work(absolute_path, effective_runtime_env)
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
			effective_runtime_env.recursive,
		)
		print_discovery_summary(result, effective_runtime_env.recursive)
		if len(result.items) == 0 {
			debug_log_info("processing skipped: no supported images")
			print_progress_header()
			print_progress_empty()
			return
		}
		if config.dry_run {
			print_dry_run_mode(effective_runtime_env.output_mode)
			dry_run_result := process_discovered_images_dry_run(
				result,
				config,
				effective_runtime_env,
			)
			defer destroy_dry_run_process_result(&dry_run_result)
			if !handle_dry_run_approval(&dry_run_result, effective_runtime_env, approval_sc) {
				pause_after_processing_summary()
			}
		} else {
			process_discovered_images(result, config, effective_runtime_env)
		}
	case .Not_Directory:
		debug_log_warnf("directory rejected: not a directory path=\"%s\"", input_path)
		print_ui_errorf(
			"Folder not found or not readable: %s. Please check the path and try again.",
			input_path,
		)
	case .Resolve_Failed:
		debug_log_errorf("directory rejected: resolve failed path=\"%s\"", input_path)
		print_ui_error("Could not read that folder path. Please check it and try again.")
	}
}

handle_dry_run_approval :: proc(
	result: ^Dry_Run_Process_Result,
	runtime_env: Runtime_Environment,
	approval_sc: ^bufio.Scanner,
) -> bool {
	if result.summary.succeeded == 0 {
		print_dry_run_nothing_to_save()
		debug_log_info("dry-run approval skipped: no successful temp outputs")
		return false
	}

	approval := prompt_for_dry_run_approval(approval_sc, runtime_env.output_mode)
	switch approval {
	case .Approve:
		debug_log_info("dry-run approved by user")
		final_summary := finalize_dry_run_outputs(
			result,
			runtime_env.output_mode,
			runtime_env.output_root_kind,
			runtime_env.output_root,
		)
		print_dry_run_saved(final_summary, runtime_env)
	case .Decline:
		debug_log_info("dry-run declined by user")
		print_dry_run_declined()
	case .Invalid:
		debug_log_warnf("dry-run approval unavailable; treating as declined")
		print_dry_run_declined()
	}
	return true
}

prompt_for_dry_run_approval :: proc(
	approval_sc: ^bufio.Scanner,
	output_mode: Config_Output_Mode,
) -> Approval_Input_Kind {
	for {
		print_dry_run_approval_prompt(output_mode)
		raw, ok := read_approval_line(approval_sc)
		if !ok {
			return .Invalid
		}

		approval := parse_approval_input(raw)
		delete(raw)
		if approval != .Invalid {
			return approval
		}
		print_dry_run_approval_invalid()
	}
}

read_approval_line :: proc(approval_sc: ^bufio.Scanner) -> (string, bool) {
	if approval_sc != nil {
		if !bufio.scan(approval_sc) {
			return "", false
		}
		line := bufio.scanner_text(approval_sc)
		cloned, clone_err := strings.clone(line)
		if clone_err != nil {
			return "", false
		}
		return cloned, true
	}

	when ODIN_OS == .Windows {
		if stdin_is_windows_console() {
			return read_windows_console_line_utf8()
		}
	}

	sc: bufio.Scanner
	bufio.scanner_init(&sc, os.to_stream(os.stdin))
	defer bufio.scanner_destroy(&sc)
	sc.split = bufio.scan_lines
	if !bufio.scan(&sc) {
		return "", false
	}
	line := bufio.scanner_text(&sc)
	cloned, clone_err := strings.clone(line)
	if clone_err != nil {
		return "", false
	}
	return cloned, true
}
