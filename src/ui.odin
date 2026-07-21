package main

import "core:fmt"
import "core:log"

print_ui_line :: proc(line: string) {
	log.info(line)
}

print_ui_blank :: proc() {
	log.info("")
}

print_ui_section :: proc(title: string) {
	print_ui_blank()
	print_ui_line(fmt.tprintf(">_ %s", title))
}

print_ui_warning :: proc(message: string) {
	log.warn(fmt.tprintf("⚠️  %s", message))
}

print_ui_error :: proc(message: string) {
	log.error(fmt.tprintf("❌ ERROR  %s", message))
}

print_startup_banner :: proc() {
	print_ui_line(
		"  ██╗███╗   ███╗ ██████╗  ██████╗ ██████╗ ████████╗███████╗   ┌──────────────────────────────┐",
	)
	print_ui_line(
		"  ██║████╗ ████║██╔════╝ ██╔═══██╗██╔══██╗╚══██╔══╝╚══███╔╝   │ >_ Imgoptz                   │",
	)
	print_ui_line(
		"  ██║██╔████╔██║██║  ███╗██║   ██║██████╔╝   ██║     ███╔╝    │                              │",
	)
	print_ui_line(
		"  ██║██║╚██╔╝██║██║   ██║██║   ██║██╔═══╝    ██║    ███╔╝     │ Folder image optimizer       │",
	)
	print_ui_line(
		"  ██║██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║        ██║   ███████╗   │ JPEG + PNG optimizer         │",
	)
	print_ui_line(
		"  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝        ╚═╝   ╚══════╝   └──────────────────────────────┘",
	)
}

print_app_settings :: proc(
	app_root_path: string,
	config_result: Config_Load_Result,
	runtime_env: Runtime_Environment,
) {
	print_ui_section("APP SETTINGS")
	print_ui_line("┌")
	print_ui_line(fmt.tprintf("│ App root   \"%s\"", app_root_path))
	print_ui_line(fmt.tprintf("│ Config     %s", config_status_ui_summary(config_result.status)))
	print_ui_line(
		fmt.tprintf("│ GPU        %s", runtime_gpu_status_ui_summary(runtime_env.gpu_status)),
	)
	print_ui_line(
		fmt.tprintf("│ Workers    %s", config_workers_summary(config_result.config.workers)),
	)
	print_ui_line(fmt.tprintf("│ Output     %s", runtime_output_ui_summary(runtime_env)))
	print_ui_line("└")
}

print_input_header :: proc() {
	print_ui_section("INPUT")
	print_ui_blank()
	print_ui_line("Paste one image directory path, or type 'exit':")
}

print_input_accepted :: proc(path: string) {
	print_ui_blank()
	print_ui_line(fmt.tprintf("✅ Accepted: %s", path))
}

print_discovery_summary :: proc(result: Discovery_Result, recursive: bool) {
	print_ui_section("DISCOVERY")
	print_ui_line("┌")
	print_ui_line(fmt.tprintf("│ Found      %d images", len(result.items)))
	print_ui_line(fmt.tprintf("│ JPEG       %d", result.jpeg_count))
	print_ui_line(fmt.tprintf("│ PNG        %d", result.png_count))
	print_ui_line(fmt.tprintf("│ Recursive  %v", recursive))
	print_ui_line("└")
}

print_discovery_error :: proc(result: Discovery_Result) {
	print_ui_section("DISCOVERY")
	print_ui_error(fmt.tprintf("%s %s", discovery_error_summary(result.err), result.err_path))
}

print_progress_header :: proc() {
	print_ui_section("PROGRESS")
	print_ui_blank()
}

print_progress_ok :: proc(index, total: int, relative_path: string) {
	print_ui_line(fmt.tprintf("[%d/%d] ✅ OK     %s", index, total, relative_path))
}

print_progress_error :: proc(
	index, total: int,
	relative_path: string,
	err: Image_Process_Error,
	detail: string,
) {
	print_ui_line(fmt.tprintf("[%d/%d] ❌ ERROR  %s", index, total, relative_path))
	print_ui_line(fmt.tprintf("      ❌ ERROR  %s", image_process_error_summary(err)))
	if len(detail) > 0 {
		print_ui_line(fmt.tprintf("      ❌ ERROR  %s", detail))
	}
	print_ui_line("      ℹ️ INFO   Kept original unchanged; no optimized output was written.")
}

print_progress_empty :: proc() {
	print_ui_line("ℹ️ INFO   No supported images to process.")
}

print_processing_summary :: proc(succeeded, skipped, failed: int) {
	print_ui_section("SUMMARY")
	print_ui_line("┌")
	print_ui_line(fmt.tprintf("│ Succeeded  %d", succeeded))
	print_ui_line(fmt.tprintf("│ Skipped    %d", skipped))
	print_ui_line(fmt.tprintf("│ Failed     %d", failed))
	print_ui_line(
		fmt.tprintf("│ Result     %s", processing_result_summary(succeeded, skipped, failed)),
	)
	print_ui_line("└")
}

processing_result_summary :: proc(succeeded, skipped, failed: int) -> string {
	if failed > 0 {
		return "Completed with failures"
	}
	if succeeded == 0 && skipped == 0 {
		return "No images found"
	}
	return "Completed"
}

config_status_ui_summary :: proc(status: Config_Load_Status) -> string {
	switch status {
	case .Missing:
		return "✅ built-in defaults"
	case .Loaded:
		return "✅ imgoptz.json loaded"
	case .Invalid_JSON:
		return "⚠️ defaults (invalid imgoptz.json)"
	case .Read_Failed:
		return "⚠️ defaults (failed to read imgoptz.json)"
	case .Invalid_Root:
		return "⚠️ defaults (invalid imgoptz.json root)"
	}
	return "✅ built-in defaults"
}

runtime_gpu_status_ui_summary :: proc(status: Runtime_GPU_Status) -> string {
	switch status {
	case .Disabled_By_Config:
		return "off by config"
	case .Enabled:
		return "✅ ImageMagick OpenCL"
	case .Probe_Failed:
		return "⚠️ CPU fallback (OpenCL probe failed)"
	}
	return "off"
}

runtime_output_ui_summary :: proc(env: Runtime_Environment) -> string {
	if env.output_mode == .Dir {
		return fmt.tprintf("dir -> \"%s\"", env.output_root)
	}
	return config_output_mode_summary(env.output_mode)
}
