package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"

Package_Options :: struct {
	package_path:                 string `usage:"Release app zip path."`,
	pngquant_source_package_path: string `usage:"pngquant corresponding-source zip path."`,
}

Package_State :: struct {
	setup:                       Setup_State,
	package_output_path:         string,
	pngquant_source_output_path: string,
	bundle_work_dir:             string,
	package_root:                string,
	pngquant_source_root:        string,
}

PACKAGE_SCRIPT := Script {
	name    = "package",
	summary = "Build and package the distributable app archive.",
	enabled = true,
	run     = run_package_script,
}

@(init)
register_package_script :: proc "contextless" () {
	register_script(&PACKAGE_SCRIPT)
}

run_package_script :: proc(args: []string, ctx: ^Script_Context) -> int {
	options := Package_Options {
		package_path                 = "dist/imgoptz-v0.1.0-windows-x64.zip",
		pngquant_source_package_path = "dist/pngquant-3.0.3-source.zip",
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
	state.setup.root_dir = ctx.root_dir
	if !load_setup_manifest(&state.setup) {
		return 1
	}
	if !initialize_setup_paths(&state.setup) {
		return 1
	}
	if !initialize_package_paths(&state, &options) {
		return 1
	}

	if !dependency_files_present(&state.setup) {
		fmt.println("Runtime dependencies are incomplete; running setup.")
		if setup_code := run_setup_script(nil, ctx); setup_code != 0 {
			return setup_code
		}
	}

	if build_code := run_build_script(nil, ctx); build_code != 0 {
		return build_code
	}

	if !assert_package_required_files(&state) {
		return 1
	}

	for &dependency in state.setup.manifest.dependencies {
		if !assert_installed_files(&state.setup, &dependency) {
			return 1
		}
		if !invoke_version_check(&state.setup, &dependency) {
			return 1
		}
	}

	if !write_app_package(&state) {
		return 1
	}
	if !write_pngquant_source_package(&state) {
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
	state.package_output_path = join_path_or_report(
		{state.setup.root_dir, native_manifest_path(options.package_path)},
	) or_return
	state.pngquant_source_output_path = join_path_or_report(
		{state.setup.root_dir, native_manifest_path(options.pngquant_source_package_path)},
	) or_return
	state.bundle_work_dir = join_path_or_report({state.setup.dist_dir, ".bundle"}) or_return
	state.package_root = join_path_or_report({state.bundle_work_dir, "imgoptz"}) or_return
	state.pngquant_source_root = join_path_or_report(
		{state.bundle_work_dir, "pngquant-source"},
	) or_return
	return true
}

dependency_files_present :: proc(state: ^Setup_State) -> bool {
	for &dependency in state.manifest.dependencies {
		if !os.exists(join_dist_path_temp(state, dependency.dist_exe_path)) {
			return false
		}
		for relative_path in dependency.dist_license_paths {
			if !os.exists(join_dist_path_temp(state, relative_path)) {
				return false
			}
		}
	}
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
		if !assert_required_file(join_dist_path_temp(&state.setup, relative_path)) {
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
		"schema",
		"profiles",
		"tools",
	}
	for item in bundle_items {
		if !copy_bundle_item(state, item) {
			return false
		}
	}

	if !remove_gitkeep_files(state.package_root) {
		return false
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

	return run_tool(
		{"tar", "-a", "-cf", state.package_output_path, "-C", state.bundle_work_dir, "imgoptz"},
		"Creating app package",
	)
}

copy_bundle_item :: proc(state: ^Package_State, item: string) -> bool {
	source_path := join_dist_path_temp(&state.setup, item)
	destination_path := join_temp_path(state.package_root, item)
	if os.is_dir(source_path) {
		if copy_err := os.copy_directory_all(destination_path, source_path); copy_err != nil {
			fmt.eprintf(
				"Failed to copy directory %s to %s: %v\n",
				source_path,
				destination_path,
				copy_err,
			)
			return false
		}
		return true
	}
	return copy_required_file(source_path, destination_path)
}

remove_gitkeep_files :: proc(root: string) -> bool {
	walker := os.walker_create(root)
	defer os.walker_destroy(&walker)
	for info in os.walker_walk(&walker) {
		if _, err := os.walker_error(&walker); err != nil {
			continue
		}
		if info.type == .Regular && filepath.base(info.fullpath) == ".gitkeep" {
			if remove_err := os.remove(info.fullpath); remove_err != nil {
				fmt.eprintf("Failed to remove %s: %v\n", info.fullpath, remove_err)
				return false
			}
		}
	}
	if path, err := os.walker_error(&walker); err != nil {
		fmt.eprintf("Failed while removing .gitkeep files under %s: %v\n", path, err)
		return false
	}
	return true
}

write_pngquant_source_package :: proc(state: ^Package_State) -> bool {
	dependency := get_dependency(&state.setup, "pngquant")
	if dependency == nil {
		return false
	}

	archive_path := download_pinned_file(&state.setup, dependency) or_return
	defer delete(archive_path)

	source_parent, _ := filepath.split(state.pngquant_source_output_path)
	if source_parent != "" && !ensure_directory(source_parent) {
		return false
	}

	if os.exists(state.pngquant_source_output_path) {
		if remove_err := os.remove(state.pngquant_source_output_path); remove_err != nil {
			fmt.eprintf(
				"Failed to remove existing source package %s: %v\n",
				state.pngquant_source_output_path,
				remove_err,
			)
			return false
		}
	}

	if os.exists(state.pngquant_source_root) {
		if remove_err := os.remove_all(state.pngquant_source_root); remove_err != nil {
			fmt.eprintf("Failed to remove %s: %v\n", state.pngquant_source_root, remove_err)
			return false
		}
	}
	if !ensure_directory(state.pngquant_source_root) {
		return false
	}

	if !run_tool(
		{"tar", "-xf", archive_path, "-C", state.pngquant_source_root},
		"Extracting pngquant source",
	) {
		return false
	}

	source_root := get_top_extract_directory(state.pngquant_source_root) or_return
	defer delete(source_root)
	source_notice := fmt.aprintf(
		"pngquant %s corresponding source for imgoptz distribution\n\n" +
		"Source URL: %s\n" +
		"Source SHA-256: %s\n" +
		"This archive was prepared by scripts.exe package from the verified crates.io source package.\n",
		dependency.version,
		dependency.source_url,
		dependency.source_sha256,
	)
	defer delete(source_notice)
	if !write_text_file(join_temp_path(source_root, "IMGOPTZ-SOURCE.txt"), source_notice) {
		return false
	}

	source_root_parent, source_root_name := filepath.split(source_root)
	if source_root_parent == "" || source_root_name == "" {
		fmt.eprintf("Failed to determine source package root for %s.\n", source_root)
		return false
	}

	if !run_tool(
		{
			"tar",
			"-a",
			"-cf",
			state.pngquant_source_output_path,
			"-C",
			source_root_parent,
			source_root_name,
		},
		"Creating pngquant source package",
	) {
		return false
	}
	fmt.printf("pngquant source package written to %s\n", state.pngquant_source_output_path)
	return true
}
