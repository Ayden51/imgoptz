package main

import "core:crypto/sha2"
import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

Setup_Options :: struct {
	force: bool `usage:"Redownload dependency archives even when cached files exist."`,
}

Setup_Manifest :: struct {
	schema_version: int,
	cache_dir:      string,
	dependencies:   [dynamic]Setup_Dependency,
}

Setup_Dependency :: struct {
	name:                   string,
	version:                string,
	download_url:           string,
	download_file:          string,
	sha256:                 string,
	archive_type:           string,
	expected_version_regex: string,
	source_url:             string,
	source_sha256:          string,
	license_urls:           [dynamic]string,
	install_exe_name:       string,
	dist_exe_path:          string,
	dist_license_paths:     [dynamic]string,
}

Setup_State :: struct {
	force:        bool,
	root_dir:     string,
	manifest:     Setup_Manifest,
	dist_dir:     string,
	cache_dir:    string,
	download_dir: string,
	extract_dir:  string,
	build_dir:    string,
}

SETUP_SCRIPT := Script {
	name    = "setup",
	summary = "Install pinned runtime dependencies into dist/.",
	enabled = true,
	run     = run_setup_script,
}

@(init)
register_setup_script :: proc "contextless" () {
	register_script(&SETUP_SCRIPT)
}

run_setup_script :: proc(args: []string, ctx: ^Script_Context) -> int {
	options: Setup_Options
	parse_err := flags.parse(&options, args, .Unix)
	if parse_err != nil {
		if _, was_help_request := parse_err.(flags.Help_Request); was_help_request {
			flags.print_errors(Setup_Options, parse_err, "scripts.exe setup", .Unix)
			return 0
		}
		flags.print_errors(Setup_Options, parse_err, "scripts.exe setup", .Unix)
		return 1
	}

	state: Setup_State
	state.force = options.force
	state.root_dir = ctx.root_dir

	if !load_setup_manifest(&state) {
		return 1
	}

	if !initialize_setup_paths(&state) {
		return 1
	}

	if !assert_setup_prerequisites() {
		return 1
	}

	if !ensure_directory(state.dist_dir) ||
	   !ensure_directory(state.download_dir) ||
	   !ensure_directory(state.extract_dir) ||
	   !ensure_directory(state.build_dir) {
		return 1
	}

	if !install_imagemagick(&state, get_dependency(&state, "imagemagick")) {
		return 1
	}
	if !install_mozjpeg(&state, get_dependency(&state, "mozjpeg")) {
		return 1
	}
	if !install_oxipng(&state, get_dependency(&state, "oxipng")) {
		return 1
	}
	if !install_pngquant(&state, get_dependency(&state, "pngquant")) {
		return 1
	}
	if !install_srgb_profile(&state, get_dependency(&state, "srgb2014")) {
		return 1
	}

	for &dependency in state.manifest.dependencies {
		if !assert_installed_files(&state, &dependency) {
			return 1
		}
		if !invoke_version_check(&state, &dependency) {
			return 1
		}
	}

	fmt.println("Dependency setup complete. Runtime tools are installed under dist/.")
	return 0
}

load_setup_manifest :: proc(state: ^Setup_State) -> bool {
	manifest_path := join_path_or_report(
		{state.root_dir, "scripts", "dependencies.json"},
	) or_return
	defer delete(manifest_path)

	data, read_err := os.read_entire_file(manifest_path, context.allocator)
	if read_err != nil {
		fmt.eprintf("Failed to read dependency manifest %q: %v\n", manifest_path, read_err)
		return false
	}
	defer delete(data)

	unmarshal_err := json.unmarshal(data, &state.manifest)
	if unmarshal_err != nil {
		fmt.eprintf("Failed to parse dependency manifest %q: %v\n", manifest_path, unmarshal_err)
		return false
	}

	if state.manifest.schema_version != 1 {
		fmt.eprintf(
			"Unsupported dependency manifest schema version: %d\n",
			state.manifest.schema_version,
		)
		return false
	}

	return true
}

initialize_setup_paths :: proc(state: ^Setup_State) -> bool {
	state.dist_dir = join_path_or_report({state.root_dir, "dist"}) or_return
	state.cache_dir = join_path_or_report(
		{state.root_dir, native_manifest_path(state.manifest.cache_dir)},
	) or_return
	state.download_dir = join_path_or_report({state.cache_dir, "downloads"}) or_return
	state.extract_dir = join_path_or_report({state.cache_dir, "extract"}) or_return
	state.build_dir = join_path_or_report({state.cache_dir, "build"}) or_return
	return true
}

assert_setup_prerequisites :: proc() -> bool {
	fmt.println("Checking dependency setup prerequisites")
	if !assert_any_command_available({"7z", "tar"}, "extracting ImageMagick's pinned 7z archive") {
		return false
	}
	if !assert_command_available("curl", "downloading pinned dependency files") {
		return false
	}
	if !assert_command_available("tar", "extracting pngquant's crates.io source package") {
		return false
	}
	if !assert_command_available("cmake", "building MozJPEG from source") {
		return false
	}
	if !assert_command_available("nasm", "building MozJPEG SIMD code") {
		return false
	}
	if !assert_command_available("ninja", "building MozJPEG with Visual Studio C++ tools") {
		return false
	}
	if !assert_command_available("cargo", "building pngquant from crates.io source") {
		return false
	}
	if !assert_command_available("rustc", "building pngquant from crates.io source") {
		return false
	}

	dev_cmd_path, ok := get_visual_studio_dev_cmd()
	if !ok {
		return false
	}
	delete(dev_cmd_path)
	return true
}

install_imagemagick :: proc(state: ^Setup_State, dependency: ^Setup_Dependency) -> bool {
	archive_path := download_pinned_file(state, dependency) or_return
	defer delete(archive_path)
	extract_path := join_path_or_report({state.extract_dir, dependency.name}) or_return
	defer delete(extract_path)
	if !expand_pinned_archive(archive_path, dependency.archive_type, extract_path) {
		return false
	}

	destination := join_dist_path(state, "tools/imagemagick") or_return
	defer delete(destination)
	if !reset_runtime_directory(destination) {
		return false
	}

	return(
		copy_from_extract(extract_path, "magick.exe", join_temp_path(destination, "magick.exe")) &&
		copy_from_extract(
			extract_path,
			"LICENSE.txt",
			join_temp_path(destination, "LICENSE.txt"),
		) &&
		copy_from_extract(extract_path, "NOTICE.txt", join_temp_path(destination, "NOTICE.txt")) &&
		copy_from_extract(extract_path, "policy.xml", join_temp_path(destination, "policy.xml")) \
	)
}

install_mozjpeg :: proc(state: ^Setup_State, dependency: ^Setup_Dependency) -> bool {
	dev_cmd_path, dev_cmd_ok := get_visual_studio_dev_cmd()
	if !dev_cmd_ok {
		return false
	}
	defer delete(dev_cmd_path)

	archive_path := download_pinned_file(state, dependency) or_return
	defer delete(archive_path)
	extract_path := join_path_or_report({state.extract_dir, dependency.name}) or_return
	defer delete(extract_path)
	if !expand_pinned_archive(archive_path, dependency.archive_type, extract_path) {
		return false
	}

	source_path := get_top_extract_directory(extract_path) or_return
	defer delete(source_path)
	moz_build_dir := join_path_or_report({state.build_dir, "mozjpeg"}) or_return
	defer delete(moz_build_dir)
	if !reset_directory(moz_build_dir) {
		return false
	}

	configure_script := join_temp_path(moz_build_dir, "configure-mozjpeg.cmd")
	configure_body := fmt.tprintf(
		"@echo off\r\n" +
		"call %s -arch=x64 -host_arch=x64\r\n" +
		"if errorlevel 1 exit /b %%errorlevel%%\r\n" +
		"cmake -S %s -B %s -G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_SHARED=FALSE -DWITH_JPEG8=1 -DPNG_SUPPORTED=FALSE\r\n" +
		"exit /b %%errorlevel%%\r\n",
		quote_cmd_argument(dev_cmd_path),
		quote_cmd_argument(source_path),
		quote_cmd_argument(moz_build_dir),
	)
	if !write_text_file(configure_script, configure_body) {
		return false
	}
	if !run_tool({"cmd.exe", "/d", "/c", configure_script}, "Configuring MozJPEG") {
		return false
	}

	build_script := join_temp_path(moz_build_dir, "build-mozjpeg.cmd")
	build_body := fmt.tprintf(
		"@echo off\r\n" +
		"call %s -arch=x64 -host_arch=x64\r\n" +
		"if errorlevel 1 exit /b %%errorlevel%%\r\n" +
		"cmake --build %s --target cjpeg-static\r\n" +
		"exit /b %%errorlevel%%\r\n",
		quote_cmd_argument(dev_cmd_path),
		quote_cmd_argument(moz_build_dir),
	)
	if !write_text_file(build_script, build_body) {
		return false
	}
	if !run_tool({"cmd.exe", "/d", "/c", build_script}, "Building MozJPEG cjpeg-static") {
		return false
	}

	cjpeg_path := find_required_file(moz_build_dir, "cjpeg-static.exe") or_return
	defer delete(cjpeg_path)
	destination := join_dist_path(state, "tools/mozjpeg") or_return
	defer delete(destination)
	if !reset_runtime_directory(destination) {
		return false
	}

	return(
		copy_required_file(cjpeg_path, join_temp_path(destination, "mozjpeg.exe")) &&
		copy_required_file(
			join_temp_path(source_path, "LICENSE.md"),
			join_temp_path(destination, "LICENSE.md"),
		) &&
		copy_required_file(
			join_temp_path(source_path, "README.ijg"),
			join_temp_path(destination, "README.ijg"),
		) &&
		copy_required_file(
			join_temp_path(source_path, "README-mozilla.txt"),
			join_temp_path(destination, "README-mozilla.txt"),
		) \
	)
}

install_oxipng :: proc(state: ^Setup_State, dependency: ^Setup_Dependency) -> bool {
	archive_path := download_pinned_file(state, dependency) or_return
	defer delete(archive_path)
	extract_path := join_path_or_report({state.extract_dir, dependency.name}) or_return
	defer delete(extract_path)
	if !expand_pinned_archive(archive_path, dependency.archive_type, extract_path) {
		return false
	}

	destination := join_dist_path(state, "tools/oxipng") or_return
	defer delete(destination)
	if !reset_runtime_directory(destination) {
		return false
	}

	return(
		copy_from_extract(extract_path, "oxipng.exe", join_temp_path(destination, "oxipng.exe")) &&
		copy_from_extract(extract_path, "LICENSE.txt", join_temp_path(destination, "LICENSE")) \
	)
}

install_pngquant :: proc(state: ^Setup_State, dependency: ^Setup_Dependency) -> bool {
	archive_path := download_pinned_file(state, dependency) or_return
	defer delete(archive_path)
	extract_path := join_path_or_report({state.extract_dir, dependency.name}) or_return
	defer delete(extract_path)
	if !expand_pinned_archive(archive_path, dependency.archive_type, extract_path) {
		return false
	}

	source_path := get_top_extract_directory(extract_path) or_return
	defer delete(source_path)
	cargo_manifest := join_temp_path(source_path, "Cargo.toml")
	if !run_tool(
		{"cargo", "build", "--release", "--manifest-path", cargo_manifest},
		"Building pngquant",
	) {
		return false
	}

	binary_path := join_temp_path(source_path, "target/release/pngquant.exe")
	if !os.exists(binary_path) {
		fmt.eprintf(
			"pngquant build completed but pngquant.exe was not found at %s.\n",
			binary_path,
		)
		return false
	}

	destination := join_dist_path(state, "tools/pngquant") or_return
	defer delete(destination)
	if !reset_runtime_directory(destination) {
		return false
	}

	if !copy_required_file(binary_path, join_temp_path(destination, "pngquant.exe")) ||
	   !copy_required_file(
			   join_temp_path(source_path, "COPYRIGHT"),
			   join_temp_path(destination, "COPYRIGHT"),
		   ) {
		return false
	}

	source_notice := fmt.aprintf(
		"pngquant %s corresponding source\n\n" +
		"Source URL: %s\n" +
		"Source SHA-256: %s\n" +
		"Downloaded by: scripts.exe setup using scripts/dependencies.json\n" +
		"Build command: cargo build --release --manifest-path <extracted-source>/Cargo.toml\n" +
		"Bundled binary: tools/pngquant/pngquant.exe\n" +
		"License notice: tools/pngquant/COPYRIGHT copied from the same verified source package.\n" +
		"Release source archive: scripts.exe package prepares pngquant-%s-source.zip beside the imgoptz app bundle.\n",
		dependency.version,
		dependency.source_url,
		dependency.source_sha256,
		dependency.version,
	)
	defer delete(source_notice)
	return write_text_file(join_temp_path(destination, "SOURCE.txt"), source_notice)
}

install_srgb_profile :: proc(state: ^Setup_State, dependency: ^Setup_Dependency) -> bool {
	download_path := download_pinned_file(state, dependency) or_return
	defer delete(download_path)
	destination := join_dist_path(state, "profiles") or_return
	defer delete(destination)
	if !reset_runtime_directory(destination) {
		return false
	}

	if !copy_required_file(download_path, join_temp_path(destination, "sRGB2014.icc")) {
		return false
	}

	license_notice := fmt.aprintf(
		"Copyright (c) 2015 International Color Consortium\n\n" +
		"This profile is made available by the International Color Consortium, and may be copied, distributed, embedded, made,\n" +
		"used, and sold without restriction. Altered versions of this profile shall have the original identification and\n" +
		"copyright information removed and shall not be misrepresented as the original profile.\n\n" +
		"Source: %s\n" +
		"SHA-256: %s\n" +
		"License reference: https://registry.color.org/profile-library/\n",
		dependency.source_url,
		dependency.source_sha256,
	)
	defer delete(license_notice)
	return write_text_file(join_temp_path(destination, "sRGB2014.LICENSE.txt"), license_notice)
}

download_pinned_file :: proc(
	state: ^Setup_State,
	dependency: ^Setup_Dependency,
) -> (
	path: string,
	ok: bool,
) {
	download_path, join_ok := join_path_or_report({state.download_dir, dependency.download_file})
	if !join_ok {
		return "", false
	}
	if state.force && os.exists(download_path) {
		if remove_err := os.remove(download_path); remove_err != nil {
			fmt.eprintf("Failed to remove cached download %q: %v\n", download_path, remove_err)
			delete(download_path)
			return "", false
		}
	}

	if !os.exists(download_path) {
		fmt.printf("Downloading %s %s\n", dependency.name, dependency.version)
		if !run_tool(
			{
				"curl",
				"--fail",
				"--location",
				"--show-error",
				"--retry",
				"3",
				"--output",
				download_path,
				dependency.download_url,
			},
			fmt.tprintf("Downloading %s", dependency.name),
		) {
			delete(download_path)
			return "", false
		}
	}

	if !assert_file_hash(download_path, dependency.sha256) {
		delete(download_path)
		return "", false
	}

	return download_path, true
}

expand_pinned_archive :: proc(archive_path, archive_type, destination_path: string) -> bool {
	if !reset_directory(destination_path) {
		return false
	}

	switch archive_type {
	case "zip":
		return run_tool(
			{"tar", "-xf", archive_path, "-C", destination_path},
			fmt.tprintf("Extracting %s", archive_path),
		)
	case "7z":
		if command_available("7z") {
			return run_tool(
				{"7z", "x", archive_path, fmt.tprintf("-o%s", destination_path), "-y"},
				fmt.tprintf("Extracting %s with 7z", archive_path),
			)
		}
		return run_tool(
			{"tar", "-xf", archive_path, "-C", destination_path},
			fmt.tprintf("Extracting %s with tar", archive_path),
		)
	case "crate":
		return run_tool(
			{"tar", "-xf", archive_path, "-C", destination_path},
			fmt.tprintf("Extracting %s", archive_path),
		)
	case:
		fmt.eprintf("Unsupported archive type %q.\n", archive_type)
		return false
	}
}

invoke_version_check :: proc(state: ^Setup_State, dependency: ^Setup_Dependency) -> bool {
	if dependency.expected_version_regex == "" {
		return true
	}

	exe_path := join_dist_path(state, dependency.dist_exe_path) or_return
	defer delete(exe_path)
	if !os.exists(exe_path) {
		fmt.eprintf("Missing installed executable: %s\n", exe_path)
		return false
	}

	version_args: []string
	switch dependency.name {
	case "imagemagick", "mozjpeg":
		version_args = {"-version"}
	case "oxipng", "pngquant":
		version_args = {"--version"}
	case:
		version_args = {}
	}

	command := append_args([]string{exe_path}, version_args, context.temp_allocator)
	state_result, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = command},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)
	if err != nil || !state_result.exited || state_result.exit_code != 0 {
		fmt.eprintf(
			"%s version check failed with exit code %d.\n%s%s",
			dependency.name,
			state_result.exit_code,
			string(stdout),
			string(stderr),
		)
		return false
	}

	text := strings.trim_space(fmt.tprintf("%s%s", string(stdout), string(stderr)))
	if !version_output_matches(dependency.name, text) {
		fmt.eprintf(
			"%s version output did not match expected pinned version:\n%s\n",
			dependency.name,
			text,
		)
		return false
	}

	fmt.printf("Verified %s %s\n", dependency.name, dependency.version)
	return true
}

version_output_matches :: proc(name, text: string) -> bool {
	switch name {
	case "imagemagick":
		return(
			strings.contains(text, "ImageMagick 7.1.2-29") &&
			strings.contains(text, "Q16-HDRI x64") \
		)
	case "mozjpeg":
		return strings.contains(text, "mozjpeg version 4.1.5")
	case "oxipng":
		return strings.has_prefix(text, "oxipng 10.1.1")
	case "pngquant":
		return strings.has_prefix(text, "3.0.3")
	}
	return true
}

assert_installed_files :: proc(state: ^Setup_State, dependency: ^Setup_Dependency) -> bool {
	if !assert_required_file(join_dist_path_temp(state, dependency.dist_exe_path)) {
		return false
	}
	for relative_path in dependency.dist_license_paths {
		if !assert_required_file(join_dist_path_temp(state, relative_path)) {
			return false
		}
	}
	return true
}

assert_file_hash :: proc(path, expected_sha256: string) -> bool {
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		fmt.eprintf("Failed to read %q for checksum: %v\n", path, read_err)
		return false
	}
	defer delete(data)

	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	digest: [sha2.DIGEST_SIZE_256]byte
	sha2.final(&ctx, digest[:])
	actual := hex_encode(digest[:], context.temp_allocator)
	if !strings.equal_fold(actual, expected_sha256) {
		fmt.eprintf(
			"Checksum mismatch for %s. Expected %s, got %s.\n",
			path,
			expected_sha256,
			actual,
		)
		return false
	}
	return true
}

hex_encode :: proc(bytes: []byte, allocator := context.allocator) -> string {
	hex := "0123456789abcdef"
	out := make([]byte, len(bytes) * 2, allocator)
	for b, i in bytes {
		out[i * 2] = hex[b >> 4]
		out[i * 2 + 1] = hex[b & 0x0f]
	}
	return string(out)
}

get_dependency :: proc(state: ^Setup_State, name: string) -> ^Setup_Dependency {
	for &dependency in state.manifest.dependencies {
		if dependency.name == name {
			return &dependency
		}
	}
	fmt.eprintf("Dependency %q is missing from scripts/dependencies.json.\n", name)
	return nil
}

get_visual_studio_dev_cmd :: proc() -> (path: string, ok: bool) {
	program_files_x86, found := os.lookup_env("ProgramFiles(x86)", context.temp_allocator)
	if !found {
		fmt.eprintln(
			"ProgramFiles(x86) is not set. Install Visual Studio with C++ build tools, then rerun scripts.exe setup.",
		)
		return "", false
	}

	vswhere_path, vswhere_join_ok := join_path_or_report(
		{program_files_x86, "Microsoft Visual Studio", "Installer", "vswhere.exe"},
	)
	if !vswhere_join_ok {
		return "", false
	}
	if !os.exists(vswhere_path) {
		fmt.eprintln(
			"vswhere.exe was not found. Install Visual Studio with C++ build tools or add vswhere to its standard Visual Studio Installer path, then rerun scripts.exe setup.",
		)
		delete(vswhere_path)
		return "", false
	}

	command := []string {
		vswhere_path,
		"-latest",
		"-products",
		"*",
		"-requires",
		"Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
		"-property",
		"installationPath",
	}
	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = command},
		context.allocator,
	)
	defer delete(stderr)
	delete(vswhere_path)
	if err != nil || !state.exited || state.exit_code != 0 {
		fmt.eprintf(
			"Visual Studio discovery failed. Install C++ build tools and Windows SDK, then rerun scripts.exe setup.\n%s",
			string(stderr),
		)
		delete(stdout)
		return "", false
	}

	installation_path := strings.trim_space(string(stdout))
	if installation_path == "" {
		fmt.eprintln(
			"Visual Studio with the C++ x64 toolchain was not found. Install the C++ build tools and Windows SDK, then rerun scripts.exe setup.",
		)
		delete(stdout)
		return "", false
	}

	dev_cmd_path, dev_cmd_join_ok := join_path_or_report(
		{installation_path, "Common7", "Tools", "VsDevCmd.bat"},
	)
	if !dev_cmd_join_ok {
		delete(stdout)
		return "", false
	}
	delete(stdout)
	if !os.exists(dev_cmd_path) {
		fmt.eprintf(
			"Visual Studio developer command script was not found at %s. Repair Visual Studio C++ tools, then rerun scripts.exe setup.\n",
			dev_cmd_path,
		)
		delete(dev_cmd_path)
		return "", false
	}

	return dev_cmd_path, true
}

assert_any_command_available :: proc(names: []string, purpose: string) -> bool {
	for name in names {
		if command_available(name) {
			return true
		}
	}
	fmt.eprintf(
		"%s is required for %s. Install it or add it to PATH, then rerun scripts.exe setup.\n",
		strings.join(names, " or ", context.temp_allocator),
		purpose,
	)
	return false
}

assert_command_available :: proc(name, purpose: string) -> bool {
	if command_available(name) {
		return true
	}
	fmt.eprintf(
		"%s is required for %s. Install it or add it to PATH, then rerun scripts.exe setup.\n",
		name,
		purpose,
	)
	return false
}

command_available :: proc(name: string) -> bool {
	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = {"where.exe", name}},
		context.temp_allocator,
	)
	_ = stdout
	_ = stderr
	return err == nil && state.exited && state.exit_code == 0
}

run_tool :: proc(command: []string, action: string) -> bool {
	process, start_err := os.process_start(
		os.Process_Desc {
			command = command,
			stdin = os.stdin,
			stdout = os.stdout,
			stderr = os.stderr,
		},
	)
	if start_err != nil {
		fmt.eprintf("%s failed to start: %v\n", action, start_err)
		return false
	}
	state, wait_err := os.process_wait(process)
	if wait_err != nil || !state.exited || state.exit_code != 0 {
		fmt.eprintf("%s failed with exit code %d.\n", action, state.exit_code)
		return false
	}
	return true
}

find_required_file :: proc(root, file_name: string) -> (string, bool) {
	walker := os.walker_create(root)
	defer os.walker_destroy(&walker)
	for info in os.walker_walk(&walker) {
		if _, err := os.walker_error(&walker); err != nil {
			continue
		}
		if info.type == .Regular && strings.equal_fold(filepath.base(info.fullpath), file_name) {
			return strings.clone(info.fullpath), true
		}
	}
	if path, err := os.walker_error(&walker); err != nil {
		fmt.eprintf("Failed to search %s: %v\n", path, err)
		return "", false
	}
	fmt.eprintf("Could not find %s under %s.\n", file_name, root)
	return "", false
}

copy_from_extract :: proc(extract_root, file_name, destination_path: string) -> bool {
	source_path := find_required_file(extract_root, file_name) or_return
	defer delete(source_path)
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

write_text_file :: proc(path, text: string) -> bool {
	parent, _ := filepath.split(path)
	if parent != "" && !ensure_directory(parent) {
		return false
	}
	if write_err := os.write_entire_file(path, transmute([]byte)text); write_err != nil {
		fmt.eprintf("Failed to write %s: %v\n", path, write_err)
		return false
	}
	return true
}

assert_required_file :: proc(path: string) -> bool {
	if !os.exists(path) {
		fmt.eprintf("Missing required runtime file: %s\n", path)
		return false
	}
	return true
}

get_top_extract_directory :: proc(extract_root: string) -> (string, bool) {
	entries, read_err := os.read_all_directory_by_path(extract_root, context.allocator)
	if read_err != nil {
		fmt.eprintf("Failed to read extract directory %s: %v\n", extract_root, read_err)
		return "", false
	}
	defer {
		for entry in entries {
			os.file_info_delete(entry, context.allocator)
		}
		delete(entries)
	}

	count := 0
	top_directory := ""
	for entry in entries {
		if entry.name == "." || entry.name == ".." {
			continue
		}
		if entry.type == .Directory {
			count += 1
			top_directory = entry.fullpath
		}
	}
	if count == 1 {
		return strings.clone(top_directory), true
	}
	return strings.clone(extract_root), true
}

reset_directory :: proc(path: string) -> bool {
	if os.exists(path) {
		if remove_err := os.remove_all(path); remove_err != nil {
			fmt.eprintf("Failed to remove %s: %v\n", path, remove_err)
			return false
		}
	}
	return ensure_directory(path)
}

reset_runtime_directory :: proc(path: string) -> bool {
	if !ensure_directory(path) {
		return false
	}
	entries, read_err := os.read_all_directory_by_path(path, context.allocator)
	if read_err != nil {
		fmt.eprintf("Failed to read runtime directory %s: %v\n", path, read_err)
		return false
	}
	defer {
		for entry in entries {
			os.file_info_delete(entry, context.allocator)
		}
		delete(entries)
	}

	for entry in entries {
		if entry.name == ".gitkeep" || entry.name == "." || entry.name == ".." {
			continue
		}
		if remove_err := os.remove_all(entry.fullpath); remove_err != nil {
			fmt.eprintf("Failed to remove %s: %v\n", entry.fullpath, remove_err)
			return false
		}
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

join_dist_path :: proc(state: ^Setup_State, relative_path: string) -> (string, bool) {
	return join_path_or_report({state.dist_dir, native_manifest_path(relative_path)})
}

join_dist_path_temp :: proc(state: ^Setup_State, relative_path: string) -> string {
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

quote_cmd_argument :: proc(value: string) -> string {
	escaped, _ := strings.replace_all(value, "\"", "\"\"", context.temp_allocator)
	return fmt.tprintf("\"%s\"", escaped)
}
