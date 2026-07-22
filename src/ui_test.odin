package main

import "core:strings"
import "core:testing"

@(test, require)
test_progress_started_line_describes_worker_count :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		progress_started_line(5, 4),
		"ℹ️ INFO   Optimizing 5 images with 4 workers...",
	)
	testing.expect_value(
		t,
		progress_started_line(1, 1),
		"ℹ️ INFO   Optimizing 1 image with 1 worker...",
	)
}

@(test, require)
test_progress_active_line_shows_live_file_activity :: proc(t: ^testing.T) {
	line := progress_active_line(2, 5, "Demo 2.png")

	testing.expect_value(t, line, "[2/5] ℹ️ INFO   Optimizing Demo 2.png")
}

@(test, require)
test_progress_done_line_shows_live_optimization_completion :: proc(t: ^testing.T) {
	success_line := progress_done_line(2, 5, "Demo 2.png", .None)
	error_line := progress_done_line(3, 5, "Broken.png", .Pngquant_Failed)

	testing.expect_value(t, success_line, "[2/5] ✅ DONE   Demo 2.png optimized")
	testing.expect_value(t, error_line, "[3/5] ❌ ERROR  Broken.png optimization failed")
}

@(test, require)
test_progress_ok_line_includes_size_reduction :: proc(t: ^testing.T) {
	line := progress_ok_line(3, 5, "Demo 1.png", 1_048_576, 225_280, -78)

	testing.expect_value(t, line, "[3/5] ✅ OK     Demo 1.png  1.00 MB -> 220 KB (-78%)")
}

@(test, require)
test_progress_ok_line_uses_windows_shell_size_format :: proc(t: ^testing.T) {
	line := progress_ok_line(1, 2, "Wide.jpg", 2_621_440, 1_153_433, -56)

	testing.expect_value(t, line, "[1/2] ✅ OK     Wide.jpg  2.50 MB -> 1.09 MB (-56%)")
}

@(test, require)
test_progress_ok_line_omits_output_path_detail :: proc(t: ^testing.T) {
	line := progress_ok_line(1, 1, "Ảnh Đẹp.JPG", 2_048, 1_024, -50)

	testing.expect(t, !strings.contains(line, "anh-dep.jpg"))
	testing.expect(t, !strings.contains(line, "\n"))
	testing.expect(t, !strings.contains(line, "      ℹ️ INFO"))
}
