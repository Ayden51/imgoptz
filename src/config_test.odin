package main

import "core:os"
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
test_load_app_config_missing_file_uses_embedded_defaults :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-config-missing-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	result := load_app_config_from_directory(temp_dir)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Missing)
	testing.expect_value(t, len(result.warnings), 0)
	expect_default_config(t, result.config)
}

@(test, require)
test_load_app_config_reads_real_imgoptz_json_file :: proc(t: ^testing.T) {
	temp_dir, temp_err := os.make_directory_temp("", "imgoptz-config-loaded-*", context.allocator)
	if !testing.expect_value(t, temp_err, nil) {
		return
	}
	defer cleanup_test_directory(temp_dir)

	write_err := os.write_entire_file(
		config_file_path(temp_dir),
		`{
			"recursive": true,
			"workers": 2,
			"jpeg": {"quality": 82},
			"png": {"pngquant_quality": "70-90", "oxipng_level": 5}
		}`,
	)
	if !testing.expect_value(t, write_err, nil) {
		return
	}

	result := load_app_config_from_directory(temp_dir)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(result.warnings), 0)
	testing.expect_value(t, result.config.recursive, true)
	testing.expect_value(t, result.config.workers.kind, Config_Workers_Kind.Explicit)
	testing.expect_value(t, result.config.workers.count, 2)
	testing.expect_value(t, result.config.jpeg.quality, 82)
	testing.expect_value(t, result.config.png.pngquant_quality, "70-90")
	testing.expect_value(t, result.config.png.oxipng_level, 5)
}

@(test, require)
test_dist_default_config_file_matches_embedded_defaults :: proc(t: ^testing.T) {
	data, read_err := os.read_entire_file("dist/imgoptz.json", context.allocator)
	if !testing.expect_value(t, read_err, nil) {
		return
	}
	defer delete(data)

	result := parse_config_text(string(data))
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Loaded)
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
	result := parse_config_text(
		`{
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
				"progressive": false,
				"tune": "ms-ssim",
				"preserve_profiles": false
			},
			"png": {
				"pngquant_quality": "70-90",
				"pngquant_speed": 2,
				"pngquant_dither": true,
				"oxipng_level": 5,
				"strip": "all",
				"alpha": false,
				"preserve_profiles": false
			}
		}`,
	)
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
	testing.expect_value(t, result.config.jpeg.quant_table, 2)
	testing.expect_value(t, result.config.jpeg.tune, "ms-ssim")
	testing.expect_value(t, result.config.jpeg.preserve_profiles, false)
	testing.expect_value(t, result.config.png.enabled, true)
	testing.expect_value(t, result.config.png.pngquant_quality, "70-90")
	testing.expect_value(t, result.config.png.pngquant_speed, 2)
	testing.expect_value(t, result.config.png.pngquant_dither, true)
	testing.expect_value(t, result.config.png.oxipng_level, 5)
	testing.expect_value(t, result.config.png.interlace, false)
	testing.expect_value(t, result.config.png.strip, "all")
	testing.expect_value(t, result.config.png.alpha, false)
	testing.expect_value(t, result.config.png.preserve_profiles, false)
}

@(test, require)
test_parse_config_unknown_options_warn_and_are_ignored :: proc(t: ^testing.T) {
	result := parse_config_text(
		`{
			"recursive": true,
			"not_real": true,
			"jpeg": {"made_up": 1},
			"png": {"surprise": false}
		}`,
	)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(result.warnings), 3)
	testing.expect(t, warning_contains(result, "not_real"))
	testing.expect(t, warning_contains(result, "jpeg.made_up"))
	testing.expect(t, warning_contains(result, "png.surprise"))
	testing.expect_value(t, result.config.recursive, true)
	testing.expect_value(t, result.config.jpeg.quality, 78)
	testing.expect_value(t, result.config.png.oxipng_level, 4)
}

@(test, require)
test_parse_config_invalid_values_fall_back_per_option :: proc(t: ^testing.T) {
	result := parse_config_text(
		`{
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
				"quality": -1,
				"progressive": "no",
				"optimize": 1,
				"sample": "2",
				"quant_table": 9,
				"tune": "hvs-psnr",
				"preserve_profiles": "true"
			},
			"png": {
				"enabled": "yes",
				"pngquant_quality": "95-80",
				"pngquant_speed": 12,
				"pngquant_dither": "false",
				"oxipng_level": 7,
				"interlace": "off",
				"strip": "abc",
				"alpha": "false",
				"preserve_profiles": "true"
			}
		}`,
	)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(result.warnings), 24)
	testing.expect_value(t, result.config.recursive, true)
	testing.expect_value(t, result.config.max_dimension, 1920)
	testing.expect_value(t, result.config.workers.kind, Config_Workers_Kind.Auto)
	testing.expect_value(t, result.config.gpu, true)
	testing.expect_value(t, result.config.debug_log, false)
	testing.expect_value(t, result.config.debug_log_file, "imgoptz.log")
	testing.expect_value(t, result.config.output_mode, Config_Output_Mode.In_Place)
	testing.expect_value(t, result.config.out_dir, "output")
	testing.expect_value(t, result.config.jpeg.enabled, true)
	testing.expect_value(t, result.config.jpeg.quality, 78)
	testing.expect_value(t, result.config.jpeg.progressive, true)
	testing.expect_value(t, result.config.jpeg.optimize, true)
	testing.expect_value(t, result.config.jpeg.sample, "2x2")
	testing.expect_value(t, result.config.jpeg.quant_table, 2)
	testing.expect_value(t, result.config.jpeg.tune, "ms-ssim")
	testing.expect_value(t, result.config.jpeg.preserve_profiles, true)
	testing.expect_value(t, result.config.png.enabled, true)
	testing.expect_value(t, result.config.png.pngquant_quality, "40-95")
	testing.expect_value(t, result.config.png.pngquant_speed, 1)
	testing.expect_value(t, result.config.png.pngquant_dither, false)
	testing.expect_value(t, result.config.png.oxipng_level, 4)
	testing.expect_value(t, result.config.png.interlace, false)
	testing.expect_value(t, result.config.png.strip, "safe")
	testing.expect_value(t, result.config.png.alpha, true)
	testing.expect_value(t, result.config.png.preserve_profiles, true)
}

@(test, require)
test_parse_config_accepts_new_pipeline_options :: proc(t: ^testing.T) {
	result := parse_config_text(
		`{
			"jpeg": {
				"quality": 0,
				"sample": "1x1",
				"quant_table": 0,
				"tune": "ms-ssim",
				"preserve_profiles": true
			},
			"png": {
				"pngquant_quality": "0-100",
				"pngquant_speed": 11,
				"pngquant_dither": false,
				"oxipng_level": 0,
				"strip": "iCCP,tEXt",
				"alpha": true,
				"preserve_profiles": false
			}
		}`,
	)
	defer destroy_config_load_result(&result)

	testing.expect_value(t, result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(result.warnings), 0)
	testing.expect_value(t, result.config.jpeg.quality, 0)
	testing.expect_value(t, result.config.jpeg.sample, "1x1")
	testing.expect_value(t, result.config.jpeg.quant_table, 0)
	testing.expect_value(t, result.config.jpeg.tune, "ms-ssim")
	testing.expect_value(t, result.config.jpeg.preserve_profiles, true)
	testing.expect_value(t, result.config.png.pngquant_quality, "0-100")
	testing.expect_value(t, result.config.png.pngquant_speed, 11)
	testing.expect_value(t, result.config.png.pngquant_dither, false)
	testing.expect_value(t, result.config.png.oxipng_level, 0)
	testing.expect_value(t, result.config.png.strip, "iCCP,tEXt")
	testing.expect_value(t, result.config.png.alpha, true)
	testing.expect_value(t, result.config.png.preserve_profiles, false)
}

@(test, require)
test_parse_config_rejects_profile_removing_png_strip_when_preserving_profiles :: proc(
	t: ^testing.T,
) {
	all_result := parse_config_text(`{"png": {"strip": "all", "preserve_profiles": true}}`)
	defer destroy_config_load_result(&all_result)

	testing.expect_value(t, all_result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(all_result.warnings), 1)
	testing.expect(t, warning_contains(all_result, "png.strip"))
	testing.expect_value(t, all_result.config.png.strip, "safe")
	testing.expect_value(t, all_result.config.png.preserve_profiles, true)

	chunk_result := parse_config_text(`{"png": {"strip": "iCCP,tEXt"}}`)
	defer destroy_config_load_result(&chunk_result)

	testing.expect_value(t, chunk_result.status, Config_Load_Status.Loaded)
	testing.expect_value(t, len(chunk_result.warnings), 1)
	testing.expect(t, warning_contains(chunk_result, "png.strip"))
	testing.expect_value(t, chunk_result.config.png.strip, "safe")
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
	testing.expect_value(t, config.jpeg.quality, 78)
	testing.expect_value(t, config.jpeg.progressive, true)
	testing.expect_value(t, config.jpeg.optimize, true)
	testing.expect_value(t, config.jpeg.sample, "2x2")
	testing.expect_value(t, config.jpeg.quant_table, 2)
	testing.expect_value(t, config.jpeg.tune, "ms-ssim")
	testing.expect_value(t, config.jpeg.preserve_profiles, true)
	testing.expect_value(t, config.png.enabled, true)
	testing.expect_value(t, config.png.pngquant_quality, "40-95")
	testing.expect_value(t, config.png.pngquant_speed, 1)
	testing.expect_value(t, config.png.pngquant_dither, false)
	testing.expect_value(t, config.png.oxipng_level, 4)
	testing.expect_value(t, config.png.interlace, false)
	testing.expect_value(t, config.png.strip, "safe")
	testing.expect_value(t, config.png.alpha, true)
	testing.expect_value(t, config.png.preserve_profiles, true)
}

warning_contains :: proc(result: Config_Load_Result, needle: string) -> bool {
	for warning in result.warnings {
		if strings.contains(warning, needle) {
			return true
		}
	}
	return false
}
