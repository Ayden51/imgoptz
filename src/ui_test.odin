package main

import "core:strings"
import "core:testing"

@(test, require)
test_progress_ok_line_includes_size_reduction :: proc(t: ^testing.T) {
	line := progress_ok_line("Demo 1.png", 1_048_576, 225_280, -78)

	testing.expect_value(t, line, "√ Demo 1.png  |  1.00 MB -> 220 KB (-78%)")
}

@(test, require)
test_progress_ok_line_uses_windows_shell_size_format :: proc(t: ^testing.T) {
	line := progress_ok_line("Wide.jpg", 2_621_440, 1_153_433, -56)

	testing.expect_value(t, line, "√ Wide.jpg  |  2.50 MB -> 1.09 MB (-56%)")
}

@(test, require)
test_progress_ok_line_uses_less_than_one_percent_for_small_reductions :: proc(t: ^testing.T) {
	line := progress_ok_line("Tiny.jpg", 1_000, 999, 0)

	testing.expect_value(t, line, "√ Tiny.jpg  |  1000 bytes -> 999 bytes (<1%)")
}

@(test, require)
test_progress_path_truncates_long_unicode_stem_to_last_word :: proc(t: ^testing.T) {
	line := progress_ok_line(
		"Hai trường THCS tại TP.HCM công bố điểm chuẩn lớp 6 và hướng dẫn xác nhận nhập học năm 2026.png",
		702_464,
		307_200,
		-56,
	)

	testing.expect_value(t, line, "√ Hai trường THCS...2026.png  |  686 KB -> 300 KB (-56%)")
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

	testing.expect_value(t, line, "X Broken.png  |  Could not compress this PNG.")
}

@(test, require)
test_progress_skip_line_is_compact :: proc(t: ^testing.T) {
	line := progress_skip_line("Large.png")

	testing.expect_value(t, line, "- Large.png  |  Skipped: optimized file was not smaller.")
}

@(test, require)
test_summary_reduction_percent_uses_one_decimal_value :: proc(t: ^testing.T) {
	reduction := summary_reduction_percent(10_000, 750)

	testing.expect_value(t, reduction, -92.5)
}
