package main

import "core:strings"
import "core:testing"

@(test, require)
test_progress_ok_line_includes_size_reduction :: proc(t: ^testing.T) {
	line := progress_ok_line("Demo 1.png", 1_048_576, 225_280, -78)

	testing.expect_value(t, line, "√ Demo 1.png  1.00 MB -> 220 KB (-78%)")
}

@(test, require)
test_progress_ok_line_uses_windows_shell_size_format :: proc(t: ^testing.T) {
	line := progress_ok_line("Wide.jpg", 2_621_440, 1_153_433, -56)

	testing.expect_value(t, line, "√ Wide.jpg  2.50 MB -> 1.09 MB (-56%)")
}

@(test, require)
test_progress_ok_line_omits_output_path_detail :: proc(t: ^testing.T) {
	line := progress_ok_line("Ảnh Đẹp.JPG", 2_048, 1_024, -50)

	testing.expect(t, !strings.contains(line, "anh-dep.jpg"))
	testing.expect(t, !strings.contains(line, "\n"))
	testing.expect(t, !strings.contains(line, "INFO"))
}

@(test, require)
test_progress_error_line_is_compact :: proc(t: ^testing.T) {
	line := progress_error_line("Broken.png", .Pngquant_Failed)

	testing.expect_value(t, line, "X Broken.png  pngquant compression failed")
}

@(test, require)
test_progress_skip_line_is_compact :: proc(t: ^testing.T) {
	line := progress_skip_line("Large.png")

	testing.expect_value(t, line, "- Large.png  Optimized output was not smaller")
}

@(test, require)
test_summary_reduction_percent_uses_one_decimal_value :: proc(t: ^testing.T) {
	reduction := summary_reduction_percent(10_000, 750)

	testing.expect_value(t, reduction, -92.5)
}
