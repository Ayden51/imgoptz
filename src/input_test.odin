package main

import "core:testing"

@(test, require)
test_parse_prompt_input_normalizes_directory_path :: proc(t: ^testing.T) {
	input := parse_prompt_input("  \"photos & (trip)\"  ")

	testing.expect_value(t, input.kind, Prompt_Input_Kind.Directory_Path)
	testing.expect_value(t, input.path, "photos & (trip)")
}

@(test, require)
test_parse_prompt_input_preserves_unicode_and_brackets :: proc(t: ^testing.T) {
	raw_path := "\"C:\\Users\\admin\\Drive - Organization\\[03] Folder\\DIRECTORY 2026-0-32\""
	input := parse_prompt_input(raw_path)

	testing.expect_value(t, input.kind, Prompt_Input_Kind.Directory_Path)
	testing.expect_value(t, input.path, "C:\\Users\\admin\\Drive - Organization\\[03] Folder\\DIRECTORY 2026-0-32")
}

@(test, require)
test_parse_prompt_input_detects_exit_after_trimming :: proc(t: ^testing.T) {
	input := parse_prompt_input("  ExIt  ")

	testing.expect_value(t, input.kind, Prompt_Input_Kind.Exit)
	testing.expect_value(t, input.path, "")
}

@(test, require)
test_parse_prompt_input_rejects_empty_path :: proc(t: ^testing.T) {
	input := parse_prompt_input(" \t \r ")

	testing.expect_value(t, input.kind, Prompt_Input_Kind.Invalid)
	testing.expect_value(t, input.path, "")
}
