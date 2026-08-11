package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"

Package_Options :: struct {
	package_path: string `usage:"Release app zip path."`,
}

Package_State :: struct {
	root_dir:            string,
	dist_dir:            string,
	package_output_path: string,
	bundle_work_dir:     string,
	package_root:        string,
}

PACKAGE_SCRIPT := Script {
	name    = "package",
	summary = "Build and package the dependency-free app archive.",
	enabled = true,
	run     = run_package_script,
}

@(init)
register_package_script :: proc "contextless" () {
	register_script(&PACKAGE_SCRIPT)
}

run_package_script :: proc(args: []string, ctx: ^Script_Context) -> int {
	options := Package_Options {
		package_path = "dist/imgoptz-v0.1.0-windows-x64.zip",
	}
	parse_err := flags.parse(&options, args, .Unix)
	if parse_err != nil {
		if _, was_help_request := parse_err.(flags.Help_Request); was_help_request {
			flags.print_errors(Package_Options, parse_err, "scripts.exe package", .Unix)
			return 0
		}
		flags.print_errors(Package_Options, parse_err, "scripts.exe package", .Unix)
		return 1
	}

	state: Package_State
	state.root_dir = ctx.root_dir
	if !initialize_package_paths(&state, &options) {
		return 1
	}

	if build_code := run_build_script(nil, ctx); build_code != 0 {
		return build_code
	}

	if !assert_package_required_files(&state) {
		return 1
	}

	if !write_app_package(&state) {
		return 1
	}

	if remove_err := os.remove_all(state.bundle_work_dir); remove_err != nil {
		fmt.eprintf(
			"Failed to remove bundle work directory %s: %v\n",
			state.bundle_work_dir,
			remove_err,
		)
		return 1
	}

	fmt.printf("Bundle written to %s\n", state.package_output_path)
	return 0
}

initialize_package_paths :: proc(state: ^Package_State, options: ^Package_Options) -> bool {
	state.dist_dir = join_path_or_report({state.root_dir, "dist"}) or_return
	state.package_output_path = join_path_or_report(
		{state.root_dir, native_manifest_path(options.package_path)},
	) or_return
	state.bundle_work_dir = join_path_or_report({state.dist_dir, ".bundle"}) or_return
	state.package_root = join_path_or_report({state.bundle_work_dir, "imgoptz"}) or_return
	return true
}

assert_package_required_files :: proc(state: ^Package_State) -> bool {
	required_files := []string {
		"imgoptz.exe",
		"imgoptz.json",
		"LICENSE.txt",
		"README.txt",
		"schema/imgoptz.schema.json",
	}
	for relative_path in required_files {
		if !assert_required_file(join_dist_path_temp(state, relative_path)) {
			return false
		}
	}
	return true
}

write_app_package :: proc(state: ^Package_State) -> bool {
	if os.exists(state.bundle_work_dir) {
		if remove_err := os.remove_all(state.bundle_work_dir); remove_err != nil {
			fmt.eprintf("Failed to remove %s: %v\n", state.bundle_work_dir, remove_err)
			return false
		}
	}
	if !ensure_directory(state.package_root) {
		return false
	}

	bundle_items := []string {
		"imgoptz.exe",
		"imgoptz.json",
		"LICENSE.txt",
		"README.txt",
		"schema/imgoptz.schema.json",
	}
	for item in bundle_items {
		if !copy_bundle_item(state, item) {
			return false
		}
	}

	if os.exists(state.package_output_path) {
		if remove_err := os.remove(state.package_output_path); remove_err != nil {
			fmt.eprintf(
				"Failed to remove existing package %s: %v\n",
				state.package_output_path,
				remove_err,
			)
			return false
		}
	}
	package_parent, _ := filepath.split(state.package_output_path)
	if package_parent != "" && !ensure_directory(package_parent) {
		return false
	}

	return(
		run_command(
			{
				"tar",
				"-a",
				"-cf",
				state.package_output_path,
				"-C",
				state.bundle_work_dir,
				"imgoptz",
			},
		) ==
		0 \
	)
}

copy_bundle_item :: proc(state: ^Package_State, item: string) -> bool {
	source_path := join_dist_path_temp(state, item)
	destination_path := join_temp_path(state.package_root, item)
	return copy_required_file(source_path, destination_path)
}

copy_required_file :: proc(source_path, destination_path: string) -> bool {
	parent, _ := filepath.split(destination_path)
	if parent != "" && !ensure_directory(parent) {
		return false
	}
	if copy_err := os.copy_file(destination_path, source_path); copy_err != nil {
		fmt.eprintf("Failed to copy %s to %s: %v\n", source_path, destination_path, copy_err)
		return false
	}
	return true
}

assert_required_file :: proc(path: string) -> bool {
	if !os.is_file(path) {
		fmt.eprintf("Missing required package file: %s\n", path)
		return false
	}
	return true
}

ensure_directory :: proc(path: string) -> bool {
	if os.exists(path) {
		return true
	}
	if err := os.make_directory_all(path); err != nil && err != .Exist {
		fmt.eprintf("Failed to create directory %s: %v\n", path, err)
		return false
	}
	return true
}

join_dist_path_temp :: proc(state: ^Package_State, relative_path: string) -> string {
	path, ok := join_path_or_report({state.dist_dir, native_manifest_path(relative_path)})
	if !ok {
		return ""
	}
	return path
}

join_temp_path :: proc(a, b: string) -> string {
	path, err := filepath.join({a, native_manifest_path(b)}, context.temp_allocator)
	if err != nil {
		return ""
	}
	return path
}

join_path_or_report :: proc(parts: []string) -> (string, bool) {
	path, err := filepath.join(parts)
	if err != nil {
		fmt.eprintf("Failed to join path %v: %v\n", parts, err)
		return "", false
	}
	return path, true
}

native_manifest_path :: proc(path: string) -> string {
	native_path, err := filepath.replace_separators(
		path,
		os.Path_Separator,
		context.temp_allocator,
	)
	if err != nil {
		return path
	}
	return native_path
}
