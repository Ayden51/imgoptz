package main

DEV_SCRIPT := Script {
	name    = "dev",
	summary = "Build dist/imgoptz_dev.exe with debug tracking, then run it.",
	enabled = true,
	run     = run_dev_script,
}

@(init)
register_dev_script :: proc "contextless" () {
	register_script(&DEV_SCRIPT)
}

run_dev_script :: proc(args: []string, ctx: ^Script_Context) -> int {
	build_code := build_debug_app(args)
	if build_code != 0 {
		return build_code
	}

	command := []string{"dist/imgoptz_dev.exe"}
	return run_command(command)
}

build_debug_app :: proc(args: []string) -> int {
	base := []string {
		"odin",
		"build",
		"src",
		"-out:dist/imgoptz_dev.exe",
		"-target:windows_amd64",
		"-subsystem:console",
		"-debug",
		"-strict-style",
		"-vet",
		"-vet-packages:main",
		"-vet-unused-procedures",
		"-vet-tabs",
		"-disallow-do",
		"-warnings-as-errors",
	}
	command := append_args(base, args, context.temp_allocator)
	return run_command(command)
}
