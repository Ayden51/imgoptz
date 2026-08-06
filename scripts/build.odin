package main

BUILD_SCRIPT := Script {
	name    = "build",
	summary = "Build dist/imgoptz.exe for release.",
	enabled = true,
	run     = run_build_script,
}

@(init)
register_build_script :: proc "contextless" () {
	register_script(&BUILD_SCRIPT)
}

run_build_script :: proc(args: []string, ctx: ^Script_Context) -> int {
	base := []string {
		"odin",
		"build",
		"src",
		"-out:dist/imgoptz.exe",
		"-target:windows_amd64",
		"-subsystem:console",
		"-o:speed",
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
