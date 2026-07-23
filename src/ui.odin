package main

import "core:fmt"
import win "core:sys/windows"
import "core:time"

foreign import shlwapi "system:shlwapi.lib"

@(default_calling_convention = "system")
foreign shlwapi {
	StrFormatByteSizeW :: proc(file_size: i64, buffer: win.PWSTR, buffer_size: win.UINT) -> win.PWSTR ---
}

UI_OK :: "√"
UI_ERROR :: "X"
UI_INFO :: "?"
UI_SKIP :: "-"
UI_WARN :: "!"

CONSOLE_PROGRESS_ROW_DELAY :: 90 * time.Millisecond
CONSOLE_SUMMARY_READ_DELAY :: 1500 * time.Millisecond

Console_Pacer :: struct {
	delay:           time.Duration,
	has_printed:     bool,
	last_printed_at: time.Time,
	slept:           time.Duration,
}

console_pacer_init :: proc(delay: time.Duration) -> Console_Pacer {
	return Console_Pacer{delay = delay}
}

pace_console_row :: proc(pacer: ^Console_Pacer) {
	if pacer.delay <= 0 {
		return
	}

	if pacer.has_printed {
		elapsed := time.since(pacer.last_printed_at)
		if elapsed < pacer.delay {
			sleep_for := pacer.delay - elapsed
			slept_at := time.now()
			time.sleep(sleep_for)
			pacer.slept += time.since(slept_at)
		}
	}

	pacer.has_printed = true
	pacer.last_printed_at = time.now()
}

console_pacer_slept :: proc(pacer: ^Console_Pacer) -> time.Duration {
	return pacer.slept
}

pause_after_processing_summary :: proc() {
	time.sleep(CONSOLE_SUMMARY_READ_DELAY)
}

print_ui_line :: proc(line: string) {
	fmt.println(line)
}

print_ui_linef :: proc($format: string, args: ..any) {
	fmt.printfln(format, ..args)
}

print_ui_blank :: proc() {
	fmt.println()
}

print_ui_section :: proc(title: string) {
	print_ui_blank()
	print_ui_linef(">_ %s", title)
}

print_ui_warning :: proc(message: string) {
	print_ui_linef("%s %s", UI_WARN, message)
}

print_ui_error :: proc(message: string) {
	print_ui_linef("%s %s", UI_ERROR, message)
}

print_ui_errorf :: proc($format: string, args: ..any) {
	fmt.printfln(UI_ERROR + " " + format, ..args)
}

print_startup_banner :: proc() {
	print_ui_blank()
	print_ui_line(
		"  ██╗███╗   ███╗ ██████╗  ██████╗ ██████╗ ████████╗███████╗ ",
	)
	print_ui_line(
		"  ██║████╗ ████║██╔════╝ ██╔═══██╗██╔══██╗╚══██╔══╝╚══███╔╝ ",
	)
	print_ui_line(
		"  ██║██╔████╔██║██║  ███╗██║   ██║██████╔╝   ██║     ███╔╝  ",
	)
	print_ui_line(
		"  ██║██║╚██╔╝██║██║   ██║██║   ██║██╔═══╝    ██║    ███╔╝   ",
	)
	print_ui_line(
		"  ██║██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║        ██║   ███████╗ ",
	)
	print_ui_line(
		"  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝        ╚═╝   ╚══════╝ ",
	)
}

print_input_header :: proc() {
	print_ui_section("INPUT")
	print_ui_line("Paste one image directory path, or type 'exit':")
}

print_input_accepted :: proc() {
	print_ui_blank()
	print_ui_linef("%s Valid path", UI_OK)
}

print_discovery_summary :: proc(result: Discovery_Result, recursive: bool) {
	mode := "non-recursive"
	if recursive {
		mode = "recursive"
	}
	print_ui_linef(
		"%s Found %d images (%d JPG, %d PNG) - %s",
		UI_INFO,
		len(result.items),
		result.jpeg_count,
		result.png_count,
		mode,
	)
}

print_discovery_error :: proc(result: Discovery_Result) {
	print_ui_errorf("%s %s", discovery_error_summary(result.err), result.err_path)
}

print_progress_header :: proc() {
	print_ui_blank()
}

print_progress_ok :: proc(
	relative_path: string,
	original_size, optimized_size, reduction_percent: i64,
) {
	print_ui_line(
		progress_ok_line(relative_path, original_size, optimized_size, reduction_percent),
	)
}

progress_ok_line :: proc(
	relative_path: string,
	original_size, optimized_size, reduction_percent: i64,
) -> string {
	return fmt.tprintf(
		"%s %s  %s -> %s (%d%%)",
		UI_OK,
		relative_path,
		format_progress_size(original_size),
		format_progress_size(optimized_size),
		reduction_percent,
	)
}

format_progress_size :: proc(size: i64) -> string {
	when ODIN_OS == .Windows {
		buffer: [64]u16
		if StrFormatByteSizeW(size, win.PWSTR(&buffer[0]), win.UINT(len(buffer))) != nil {
			formatted, err := win.wstring_to_utf8(
				win.wstring(&buffer[0]),
				-1,
				context.temp_allocator,
			)
			if err == nil && len(formatted) > 0 {
				return formatted
			}
		}
	}
	return fmt.tprintf("%d bytes", size)
}

progress_reduction_percent :: proc(original_size, optimized_size: i64) -> i64 {
	if original_size <= 0 || optimized_size >= original_size {
		return 0
	}
	saved_size := original_size - optimized_size
	return -((saved_size * 100) / original_size)
}

print_progress_error :: proc(relative_path: string, err: Image_Process_Error) {
	print_ui_line(progress_error_line(relative_path, err))
}

progress_error_line :: proc(relative_path: string, err: Image_Process_Error) -> string {
	return fmt.tprintf("%s %s  %s", UI_ERROR, relative_path, image_process_error_summary(err))
}

print_progress_skip :: proc(relative_path: string) {
	print_ui_line(progress_skip_line(relative_path))
}

progress_skip_line :: proc(relative_path: string) -> string {
	return fmt.tprintf("%s %s  Optimized output was not smaller", UI_SKIP, relative_path)
}

print_progress_empty :: proc() {
	print_ui_linef("%s No supported images to process.", UI_INFO)
}

print_processing_summary :: proc(summary: Processing_Summary, elapsed: time.Duration) {
	print_ui_section("SUMMARY")
	print_ui_linef(
		"Files:  %d Succeeded - %d Skipped - %d Failed",
		summary.succeeded,
		summary.skipped,
		summary.failed,
	)
	print_ui_linef(
		"Saved:  %s -> %s (%.1f%%) - Completed in %.1fs",
		format_progress_size(summary.original_total),
		format_progress_size(summary.optimized_total),
		summary_reduction_percent(summary.original_total, summary.optimized_total),
		time.duration_seconds(elapsed),
	)
}

summary_reduction_percent :: proc(original_size, optimized_size: i64) -> f64 {
	if original_size <= 0 || optimized_size >= original_size {
		return 0
	}
	saved_size := original_size - optimized_size
	return -(f64(saved_size) * 100.0 / f64(original_size))
}
