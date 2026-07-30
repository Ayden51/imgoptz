package main

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

@(test, require)
test_resolve_debug_log_path_prefixes_filename_with_timestamp :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-debug-log-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	timestamp, ok := time.components_to_time(2026, 7, 30, 14, 5, 6, 123456789)
	if !testing.expect_value(t, ok, true) {
		return
	}

	path := resolve_debug_log_path_at(temp_dir, "logs/imgoptz.log", timestamp)
	defer delete(path)

	parts := [?]string{temp_dir, "logs", "20260730-140506-123456789-imgoptz.log"}
	expected, expected_err := os.join_path(parts[:], context.temp_allocator)
	if !testing.expect_value(t, expected_err, nil) {
		return
	}
	testing.expect_value(t, path, expected)
}

@(test, require)
test_debug_logging_writes_level_timestamp_and_message :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-debug-log-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	config := default_config()
	defer destroy_config(&config)
	config.debug_log = true
	replace_config_string(&config.debug_log_file, "debug.log")

	result := init_debug_logging(temp_dir, config)
	defer destroy_debug_log_init_result(&result)
	defer destroy_debug_logging()

	if !testing.expect_value(t, result.enabled, true) {
		return
	}
	debug_log_info("test debug message")
	destroy_debug_logging()

	data, read_err := os.read_entire_file(result.path, context.allocator)
	if !testing.expect_value(t, read_err, nil) {
		return
	}
	defer delete(data)

	text := string(data)
	testing.expect(t, strings.contains(text, "[INFO "))
	testing.expect(t, strings.contains(text, "[") && strings.contains(text, "]"))
	testing.expect(t, strings.contains(text, "test debug message"))
}

@(test, require)
test_debug_logging_writes_new_prefixed_file_without_appending_base_file :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-debug-log-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	base_path := resolve_app_relative_path(temp_dir, "debug.log", context.allocator)
	defer delete(base_path)
	if !testing.expect_value(t, os.write_entire_file(base_path, "old run\n"), nil) {
		return
	}

	config := default_config()
	defer destroy_config(&config)
	config.debug_log = true
	replace_config_string(&config.debug_log_file, "debug.log")

	result := init_debug_logging(temp_dir, config)
	defer destroy_debug_log_init_result(&result)
	defer destroy_debug_logging()

	if !testing.expect_value(t, result.enabled, true) {
		return
	}
	testing.expect(t, result.path != base_path)
	_, filename := os.split_path(result.path)
	testing.expect(t, strings.has_suffix(filename, "-debug.log"))

	debug_log_info("new run")
	destroy_debug_logging()

	base_data, base_read_err := os.read_entire_file(base_path, context.allocator)
	if !testing.expect_value(t, base_read_err, nil) {
		return
	}
	defer delete(base_data)
	testing.expect_value(t, string(base_data), "old run\n")

	new_data, new_read_err := os.read_entire_file(result.path, context.allocator)
	if !testing.expect_value(t, new_read_err, nil) {
		return
	}
	defer delete(new_data)
	new_text := string(new_data)
	testing.expect(t, strings.contains(new_text, "new run"))
	testing.expect(t, !strings.contains(new_text, "old run"))
}
