package main

import "core:log"

print_ui_line :: proc(line: string) {
	log.info(line)
}

print_ui_linef :: proc($format: string, args: ..any) {
	log.infof(format, ..args)
}

print_ui_blank :: proc() {
	log.info("")
}

print_ui_section :: proc(title: string) {
	print_ui_blank()
	print_ui_linef(">_ %s", title)
}

print_ui_warning :: proc(message: string) {
	print_ui_linef("⚠️  %s", message)
}

print_ui_error :: proc(message: string) {
	print_ui_linef("❌ ERROR  %s", message)
}

print_ui_errorf :: proc($format: string, args: ..any) {
	log.infof("❌ ERROR  " + format, ..args)
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
	print_ui_linef("│ App root   \"%s\"", app_root_path)
	print_ui_linef("│ Config     %s", config_status_ui_summary(config_result.status))
	print_ui_linef("│ GPU        %s", runtime_gpu_status_ui_summary(runtime_env.gpu_status))
	print_ui_linef("│ Workers    %s", config_workers_summary(config_result.config.workers))
	if runtime_env.output_mode == .Dir {
		print_ui_linef("│ Output     dir -> \"%s\"", runtime_env.output_root)
	} else {
		print_ui_linef("│ Output     %s", config_output_mode_summary(runtime_env.output_mode))
	}
	print_ui_line("└")
}

print_input_header :: proc() {
	print_ui_section("INPUT")
	print_ui_blank()
	print_ui_line("Paste one image directory path, or type 'exit':")
}

print_input_accepted :: proc(path: string) {
	print_ui_blank()
	print_ui_linef("✅ Accepted: %s", path)
}

print_discovery_summary :: proc(result: Discovery_Result, recursive: bool) {
	print_ui_section("DISCOVERY")
	print_ui_line("┌")
	print_ui_linef("│ Found      %d images", len(result.items))
	print_ui_linef("│ JPEG       %d", result.jpeg_count)
	print_ui_linef("│ PNG        %d", result.png_count)
	print_ui_linef("│ Recursive  %v", recursive)
	print_ui_line("└")
}

print_discovery_error :: proc(result: Discovery_Result) {
	print_ui_section("DISCOVERY")
	print_ui_errorf("%s %s", discovery_error_summary(result.err), result.err_path)
}

print_progress_header :: proc() {
	print_ui_section("PROGRESS")
	print_ui_blank()
}

print_progress_ok :: proc(index, total: int, relative_path: string) {
	print_ui_linef("[%d/%d] ✅ OK     %s", index, total, relative_path)
}

print_progress_error :: proc(
	index, total: int,
	relative_path: string,
	err: Image_Process_Error,
	detail: string,
) {
	print_ui_linef("[%d/%d] ❌ ERROR  %s", index, total, relative_path)
	print_ui_linef("      ❌ ERROR  %s", image_process_error_summary(err))
	if len(detail) > 0 {
		print_ui_linef("      ❌ ERROR  %s", detail)
	}
	print_ui_line("      ℹ️ INFO   Kept original unchanged; no optimized output was written.")
}

print_progress_skip :: proc(index, total: int, relative_path, detail: string) {
	print_ui_linef("[%d/%d] ⚠️ SKIP   %s", index, total, relative_path)
	print_ui_line("      ⚠️ SKIP   Optimized output was not smaller")
	if len(detail) > 0 {
		print_ui_linef("      ℹ️ INFO   %s", detail)
	}
	print_ui_line("      ℹ️ INFO   Kept original unchanged; no optimized output was written.")
}

print_progress_empty :: proc() {
	print_ui_line("ℹ️ INFO   No supported images to process.")
}

print_processing_summary :: proc(succeeded, skipped, failed: int) {
	print_ui_section("SUMMARY")
	print_ui_line("┌")
	print_ui_linef("│ Succeeded  %d", succeeded)
	print_ui_linef("│ Skipped    %d", skipped)
	print_ui_linef("│ Failed     %d", failed)
	print_ui_linef("│ Result     %s", processing_result_summary(succeeded, skipped, failed))
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
