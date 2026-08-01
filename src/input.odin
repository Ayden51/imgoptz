package main

import "core:strings"

Prompt_Input_Kind :: enum {
	Invalid,
	Exit,
	Directory_Path,
}

Prompt_Input :: struct {
	kind: Prompt_Input_Kind,
	path: string,
}

Approval_Input_Kind :: enum {
	Invalid,
	Approve,
	Decline,
}

parse_prompt_input :: proc(raw: string) -> Prompt_Input {
	path := normalize_input_path(raw)
	if is_exit_command(path) {
		return Prompt_Input{kind = .Exit}
	}
	if len(path) == 0 {
		return Prompt_Input{kind = .Invalid}
	}
	return Prompt_Input{kind = .Directory_Path, path = path}
}

normalize_input_path :: proc(raw: string) -> string {
	path := strings.trim_space(raw)
	if len(path) >= 2 && path[0] == '"' && path[len(path) - 1] == '"' {
		path = path[1:len(path) - 1]
		path = strings.trim_space(path)
	}
	return path
}

is_exit_command :: proc(s: string) -> bool {
	return(
		len(s) == 4 &&
		(s[0] == 'e' || s[0] == 'E') &&
		(s[1] == 'x' || s[1] == 'X') &&
		(s[2] == 'i' || s[2] == 'I') &&
		(s[3] == 't' || s[3] == 'T') \
	)
}

parse_approval_input :: proc(raw: string) -> Approval_Input_Kind {
	if raw == "y" || ascii_equal_fold(raw, "yes") {
		return .Approve
	}
	if raw == "N" || ascii_equal_fold(raw, "no") {
		return .Decline
	}
	return .Invalid
}
