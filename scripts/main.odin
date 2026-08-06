package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:strings"

MAX_REGISTERED_SCRIPTS :: 32

Script_Run_Proc :: proc(args: []string, ctx: ^Script_Context) -> int

Script :: struct {
	name:    string,
	summary: string,
	enabled: bool,
	run:     Script_Run_Proc,
}

Script_Context :: struct {
	root_dir: string,
}

Launcher_Options :: struct {
	list:   bool `usage:"List registered scripts."`,
	script: string `args:"pos=0" usage:"Script to run."`,
}

registered_scripts: [MAX_REGISTERED_SCRIPTS]^Script
registered_script_count: int

register_script :: proc "contextless" (script: ^Script) {
	if registered_script_count >= MAX_REGISTERED_SCRIPTS {
		return
	}

	registered_scripts[registered_script_count] = script
	registered_script_count += 1
}

main :: proc() {
	exit_code := run_launcher()
	os.exit(exit_code)
}

run_launcher :: proc() -> int {
	when ODIN_OS != .Windows {
		fmt.eprintln("scripts.exe targets Windows developer environments only.")
		return 1
	}

	root_dir, root_err := os.get_executable_directory(context.allocator)
	if root_err != os.ERROR_NONE {
		fmt.eprintf("Failed to resolve launcher directory: %v\n", root_err)
		return 1
	}
	defer delete(root_dir)

	if change_err := os.change_directory(root_dir); change_err != os.ERROR_NONE {
		fmt.eprintf("Failed to change to repo root %q: %v\n", root_dir, change_err)
		return 1
	}

	ctx := Script_Context {
		root_dir = root_dir,
	}
	options: Launcher_Options
	launcher_args, script_args := split_launcher_args(os.args[1:])
	parse_err := flags.parse(&options, launcher_args, .Unix)
	if parse_err != nil {
		if _, was_help_request := parse_err.(flags.Help_Request); was_help_request {
			print_help()
			return 0
		}

		flags.print_errors(Launcher_Options, parse_err, "scripts.exe", .Unix)
		return 1
	}

	if options.list {
		print_scripts()
		return 0
	}

	if options.script == "" {
		print_help()
		return 0
	}

	if options.script == "list" {
		print_scripts()
		return 0
	}

	script := find_script(options.script)
	if script == nil {
		fmt.eprintf("Unknown script: %s\n\n", options.script)
		print_scripts()
		return 1
	}

	if !script.enabled {
		fmt.eprintf("Script is registered but disabled: %s\n", script.name)
		fmt.eprintf("%s\n", script.summary)
		return 1
	}

	if script.run == nil {
		fmt.eprintf("Script has no runner: %s\n", script.name)
		return 1
	}

	return script.run(script_args, &ctx)
}

split_launcher_args :: proc(args: []string) -> (launcher_args: []string, script_args: []string) {
	for arg, i in args {
		if arg == "--" {
			return args[:i], args[i + 1:]
		}
	}
	return args, nil
}

find_script :: proc(name: string) -> ^Script {
	for script in registered_scripts[:registered_script_count] {
		if script != nil && script.name == name {
			return script
		}
	}
	return nil
}

print_help :: proc() {
	fmt.println("imgoptz script launcher")
	fmt.println("")
	fmt.println("Usage:")
	fmt.println("  scripts.exe <script> [-- <args>]")
	fmt.println("")
	print_scripts()
	fmt.println("")
	fmt.println("Forward script arguments after -- when they begin with '-'.")
	fmt.println("Example:")
	fmt.println(
		"  scripts.exe test -- \"-define:ODIN_TEST_NAMES=main.test_parse_prompt_input_normalizes_directory_path\"",
	)
	fmt.println("")
}

print_scripts :: proc() {
	fmt.println("Scripts:")
	for script in registered_scripts[:registered_script_count] {
		if script == nil {
			continue
		}

		status := "enabled"
		if !script.enabled {
			status = "disabled"
		}
		fmt.printf("  %-16s %-8s %s\n", script.name, status, script.summary)
	}
}

run_command :: proc(command: []string) -> int {
	fmt.printf("> %s\n", strings.join(command, " ", context.temp_allocator))

	process, start_err := os.process_start(
		os.Process_Desc {
			command = command,
			stdin = os.stdin,
			stdout = os.stdout,
			stderr = os.stderr,
		},
	)
	if start_err != nil {
		fmt.eprintf("Failed to start %s: %v\n", command[0], start_err)
		return 1
	}

	state, wait_err := os.process_wait(process)
	if wait_err != nil {
		fmt.eprintf("Failed while waiting for %s: %v\n", command[0], wait_err)
		return 1
	}

	if !state.exited {
		fmt.eprintf("%s did not exit normally.\n", command[0])
		return 1
	}

	return state.exit_code
}

append_args :: proc(base: []string, extra: []string, allocator := context.allocator) -> []string {
	command := make([dynamic]string, 0, len(base) + len(extra), allocator)
	for arg in base {
		append(&command, arg)
	}
	for arg in extra {
		append(&command, arg)
	}
	return command[:]
}
