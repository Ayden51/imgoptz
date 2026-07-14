package main

import "core:strings"
import "core:testing"

@(test, require)
test_missing_config_uses_defaults :: proc(t: ^testing.T) {
	result := missing_config_result()
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Missing)
	testing.expect_value(t, len(result.warnings), 0)
	expect_default_config(t, result.config)
}

@(test, require)
test_parse_config_invalid_json_uses_full_defaults :: proc(t: ^testing.T) {
	result := parse_config_text(`{"recursive": true,`)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Invalid_JSON)
	testing.expect_value(t, len(result.warnings), 1)
	testing.expect(t, strings.contains(result.warnings[0], "Invalid imgoptz.json"))
	expect_default_config(t, result.config)
}

@(test, require)
test_parse_config_partial_file_overrides_only_present_options :: proc(t: ^testing.T) {
	result := parse_config_text(`{
		"recursive": true,
		"max_dimension": 1280,
		"workers": 3,
		"gpu": false,
		"debug_log": true,
		"debug_log_file": "debug.log",
		"output_mode": "dir",
		"out_dir": "optimized",
		"jpeg": {
			"quality": 82,
			"progressive": false
		},
		"png": {
			"level": 4,
			"strip": "all",
			"alpha": true
		}
	}`)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(result.warnings), 0)
	testing.expect_value(t, result.config.recursive, true)
	testing.expect_value(t, result.config.max_dimension, 1280)
	testing.expect_value(t, result.config.workers.kind, Config_Workers_Kind.Explicit)
	testing.expect_value(t, result.config.workers.count, 3)
	testing.expect_value(t, result.config.gpu, false)
	testing.expect_value(t, result.config.debug_log, true)
	testing.expect_value(t, result.config.debug_log_file, "debug.log")
	testing.expect_value(t, result.config.output_mode, Config_Output_Mode.Dir)
	testing.expect_value(t, result.config.out_dir, "optimized")
	testing.expect_value(t, result.config.jpeg.enabled, true)
	testing.expect_value(t, result.config.jpeg.quality, 82)
	testing.expect_value(t, result.config.jpeg.progressive, false)
	testing.expect_value(t, result.config.jpeg.optimize, true)
	testing.expect_value(t, result.config.jpeg.sample, "2x2")
	testing.expect_value(t, result.config.jpeg.quant_table, 3)
	testing.expect_value(t, result.config.png.enabled, true)
	testing.expect_value(t, result.config.png.level, 4)
	testing.expect_value(t, result.config.png.interlace, false)
	testing.expect_value(t, result.config.png.strip, "all")
	testing.expect_value(t, result.config.png.alpha, true)
}

@(test, require)
test_parse_config_unknown_options_warn_and_are_ignored :: proc(t: ^testing.T) {
	result := parse_config_text(`{
		"recursive": true,
		"not_real": true,
		"jpeg": {"made_up": 1},
		"png": {"surprise": false}
	}`)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(result.warnings), 3)
	testing.expect(t, warning_contains(result, "not_real"))
	testing.expect(t, warning_contains(result, "jpeg.made_up"))
	testing.expect(t, warning_contains(result, "png.surprise"))
	testing.expect_value(t, result.config.recursive, true)
	testing.expect_value(t, result.config.jpeg.quality, 100)
	testing.expect_value(t, result.config.png.level, 6)
}

@(test, require)
test_parse_config_invalid_values_fall_back_per_option :: proc(t: ^testing.T) {
	result := parse_config_text(`{
		"recursive": true,
		"max_dimension": 0,
		"workers": 0,
		"gpu": "auto",
		"debug_log": "yes",
		"debug_log_file": "",
		"output_mode": "inplace",
		"out_dir": "",
		"jpeg": {
			"enabled": "yes",
			"quality": 101,
			"progressive": "no",
			"optimize": 1,
			"sample": "",
			"quant_table": 9
		},
		"png": {
			"enabled": "yes",
			"level": 7,
			"interlace": "off",
			"strip": "",
			"alpha": "false"
		}
	}`)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(result.warnings), 18)
	testing.expect_value(t, result.config.recursive, true)
	testing.expect_value(t, result.config.max_dimension, 1920)
	testing.expect_value(t, result.config.workers.kind, Config_Workers_Kind.Auto)
	testing.expect_value(t, result.config.gpu, true)
	testing.expect_value(t, result.config.debug_log, false)
	testing.expect_value(t, result.config.debug_log_file, "imgoptz.log")
	testing.expect_value(t, result.config.output_mode, Config_Output_Mode.In_Place)
	testing.expect_value(t, result.config.out_dir, "output")
	testing.expect_value(t, result.config.jpeg.enabled, true)
	testing.expect_value(t, result.config.jpeg.quality, 100)
	testing.expect_value(t, result.config.jpeg.progressive, true)
	testing.expect_value(t, result.config.jpeg.optimize, true)
	testing.expect_value(t, result.config.jpeg.sample, "2x2")
	testing.expect_value(t, result.config.jpeg.quant_table, 3)
	testing.expect_value(t, result.config.png.enabled, true)
	testing.expect_value(t, result.config.png.level, 6)
	testing.expect_value(t, result.config.png.interlace, false)
	testing.expect_value(t, result.config.png.strip, "safe")
	testing.expect_value(t, result.config.png.alpha, false)
}

@(test, require)
test_parse_config_accepts_workers_auto_only_as_string :: proc(t: ^testing.T) {
	auto_result := parse_config_text(`{"workers": "auto"}`)
	defer destroy_config_load_result(&auto_result)

	testing.expect_value(t, auto_result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(auto_result.warnings), 0)
	testing.expect_value(t, auto_result.config.workers.kind, Config_Workers_Kind.Auto)

	invalid_result := parse_config_text(`{"workers": "4"}`)
	defer destroy_config_load_result(&invalid_result)

	testing.expect_value(t, invalid_result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(invalid_result.warnings), 1)
	testing.expect_value(t, invalid_result.config.workers.kind, Config_Workers_Kind.Auto)
}

expect_default_config :: proc(t: ^testing.T, config: App_Config) {
	testing.expect_value(t, config.recursive, false)
	testing.expect_value(t, config.max_dimension, 1920)
	testing.expect_value(t, config.workers.kind, Config_Workers_Kind.Auto)
	testing.expect_value(t, config.workers.count, 0)
	testing.expect_value(t, config.gpu, true)
	testing.expect_value(t, config.debug_log, false)
	testing.expect_value(t, config.debug_log_file, "imgoptz.log")
	testing.expect_value(t, config.output_mode, Config_Output_Mode.In_Place)
	testing.expect_value(t, config.out_dir, "output")
	testing.expect_value(t, config.jpeg.enabled, true)
	testing.expect_value(t, config.jpeg.quality, 100)
	testing.expect_value(t, config.jpeg.progressive, true)
	testing.expect_value(t, config.jpeg.optimize, true)
	testing.expect_value(t, config.jpeg.sample, "2x2")
	testing.expect_value(t, config.jpeg.quant_table, 3)
	testing.expect_value(t, config.png.enabled, true)
	testing.expect_value(t, config.png.level, 6)
	testing.expect_value(t, config.png.interlace, false)
	testing.expect_value(t, config.png.strip, "safe")
	testing.expect_value(t, config.png.alpha, false)
}

warning_contains :: proc(result: Config_Load_Result, needle: string) -> bool {
	for warning in result.warnings {
		if strings.contains(warning, needle) {
			return true
		}
	}
	return false
}
