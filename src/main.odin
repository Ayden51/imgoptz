package main

import "core:bufio"
import "core:fmt"
import "core:os"

main :: proc() {
	when ODIN_OS != .Windows {
		fmt.eprintln("This build targets Windows 10/11 only.")
		return
	}

	exe_dir, exe_dir_err := os.get_executable_directory(context.allocator)
	if exe_dir_err != os.ERROR_NONE {
		fmt.eprintln("Failed to get executable directory:", exe_dir_err)
		return
	}
	defer delete(exe_dir)

	if err := os.change_directory(exe_dir); err != os.ERROR_NONE {
		fmt.eprintln("Failed to change directory to executable directory:", err)
		return
	}

	fmt.println("== Odin Launcher Demo ==")

	// Interactive stdin scanner (line-based)
	sc: bufio.Scanner
	bufio.scanner_init(&sc, os.to_stream(os.stdin))
	defer bufio.scanner_destroy(&sc)
	sc.split = bufio.scan_lines

	for {
		fmt.print("\nPaste a directory path (or type 'exit'): ")

		if !bufio.scan(&sc) {
			// EOF (rare when double-clicked). Exit cleanly.
			break
		}

		raw := bufio.scanner_text(&sc)
		fmt.println("You typed:", raw)

		desc := os.Process_Desc {
			command     = []string{"cmd.exe", "/c", "dir"},
			working_dir = "",
			// Inherit console I/O so tool output appears in real time
			stdout      = os.stdout,
			stderr      = os.stderr,
			stdin       = nil,
		}

		process, process_err := os.process_start(desc)
		if process_err != os.ERROR_NONE {
			fmt.eprintln("[ERROR] process_start:", process_err)
			continue
		}

		process_state, process_wait_err := os.process_wait(process)
		if process_wait_err != os.ERROR_NONE {
			fmt.eprintln("[ERROR] process_wait:", process_wait_err)
			continue
		}
		if process_state.exit_code != 0 {
			fmt.eprintln("[ERROR] child exit code:", process_state.exit_code)
			continue
		}

		fmt.println("Success!")
	}
}
