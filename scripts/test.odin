package main

TEST_SCRIPT := Script {
	name    = "test",
	summary = "Run Odin tests for src.",
	enabled = true,
	run     = run_test_script,
}

@(init)
register_test_script :: proc "contextless" () {
	register_script(&TEST_SCRIPT)
}

run_test_script :: proc(args: []string, ctx: ^Script_Context) -> int {
	base := []string{"odin", "test", "src"}
	command := append_args(base, args, context.temp_allocator)
	return run_command(command)
}
