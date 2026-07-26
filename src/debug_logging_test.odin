package main

import "core:os"
import "core:strings"
import "core:testing"

@(test, require)
test_resolve_debug_log_path_resolves_relative_to_app_root :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-debug-log-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	path := resolve_debug_log_path(temp_dir, "logs/imgoptz.log")
	defer delete(path)

	expected := resolve_app_relative_path(temp_dir, "logs/imgoptz.log", context.temp_allocator)
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
