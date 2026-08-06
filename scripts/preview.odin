package main

import "core:fmt"
import "core:os"

PREVIEW_SCRIPT := Script {
	name    = "preview",
	summary = "Launch dist/imgoptz.exe; run build first if it is missing.",
	enabled = true,
	run     = run_preview_script,
}

@(init)
register_preview_script :: proc "contextless" () {
	register_script(&PREVIEW_SCRIPT)
}

run_preview_script :: proc(args: []string, ctx: ^Script_Context) -> int {
	if !os.exists("dist/imgoptz.exe") {
		fmt.eprintln(
			"dist/imgoptz.exe is missing. Run `scripts.exe build` before `scripts.exe preview`.",
		)
		return 1
	}

	command := []string{"dist/imgoptz.exe"}
	return run_command(command)
}
