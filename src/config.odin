package main

import json "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strconv"
import "core:strings"

CONFIG_FILE_NAME :: "imgoptz.json"

Config_Output_Mode :: enum {
	In_Place,
	Dir,
}

Config_Workers_Kind :: enum {
	Auto,
	Explicit,
}

Config_Workers :: struct {
	kind:  Config_Workers_Kind,
	count: int,
}

Jpeg_Config :: struct {
	enabled:           bool,
	quality:           int,
	progressive:       bool,
	optimize:          bool,
	sample:            string,
	quant_table:       int,
	tune:              string,
	preserve_profiles: bool,
}

Png_Config :: struct {
	enabled:           bool,
	pngquant_quality: string,
	pngquant_speed:   int,
	pngquant_dither:  bool,
	oxipng_level:     int,
	interlace:        bool,
	strip:            string,
	alpha:            bool,
}

App_Config :: struct {
	recursive:      bool,
	max_dimension:  int,
	workers:        Config_Workers,
	gpu:            bool,
	debug_log:      bool,
	debug_log_file: string,
	output_mode:    Config_Output_Mode,
	out_dir:        string,
	jpeg:           Jpeg_Config,
	png:            Png_Config,
}

Config_Load_Status :: enum {
	Missing,
	Loaded,
	Invalid_JSON,
	Read_Failed,
	Invalid_Root,
}

Config_Load_Result :: struct {
	config:   App_Config,
	status:   Config_Load_Status,
	warnings: [dynamic]string,
}

default_config :: proc() -> App_Config {
	return App_Config {
		recursive = false,
		max_dimension = 1920,
		workers = Config_Workers{kind = .Auto},
		gpu = true,
		debug_log = false,
		debug_log_file = strings.clone("imgoptz.log"),
		output_mode = .In_Place,
		out_dir = strings.clone("output"),
		jpeg = Jpeg_Config {
			enabled = true,
			quality = 78,
			progressive = true,
			optimize = true,
			sample = strings.clone("2x2"),
			quant_table = 2,
			tune = strings.clone("ms-ssim"),
			preserve_profiles = true,
		},
		png = Png_Config {
			enabled = true,
			pngquant_quality = strings.clone("80-95"),
			pngquant_speed = 1,
			pngquant_dither = false,
			oxipng_level = 4,
			interlace = false,
			strip = strings.clone("safe"),
			alpha = true,
		},
	}
}

destroy_config :: proc(config: ^App_Config) {
	delete(config.debug_log_file)
	delete(config.out_dir)
	delete(config.jpeg.sample)
	delete(config.jpeg.tune)
	delete(config.png.pngquant_quality)
	delete(config.png.strip)
	config^ = {}
}

destroy_config_load_result :: proc(result: ^Config_Load_Result) {
	destroy_config(&result.config)
	for warning in result.warnings {
		delete(warning)
	}
	delete(result.warnings)
	result^ = {}
}

load_app_config :: proc() -> Config_Load_Result {
	if !os.exists(CONFIG_FILE_NAME) {
		return missing_config_result()
	}

	data, read_err := os.read_entire_file(CONFIG_FILE_NAME, context.allocator)
	if read_err != nil {
		result := Config_Load_Result{config = default_config(), status = .Read_Failed}
		add_config_warning(&result, fmt.aprintf(
			"Failed to read %s; using default config.",
			CONFIG_FILE_NAME,
		))
		return result
	}
	defer delete(data)

	return parse_config_text(string(data))
}

missing_config_result :: proc() -> Config_Load_Result {
	return Config_Load_Result{config = default_config(), status = .Missing}
}

parse_config_text :: proc(text: string) -> Config_Load_Result {
	result := Config_Load_Result{config = default_config(), status = .Loaded}

	root, parse_err := parse_strict_json(text)
	if parse_err != .None {
		result.status = .Invalid_JSON
		add_config_warning(&result, fmt.aprintf(
			"Invalid %s; using default config.",
			CONFIG_FILE_NAME,
		))
		return result
	}
	defer json.destroy_value(root)

	#partial switch object in root {
	case json.Object:
		apply_config_object(&result, object)
	case:
		result.status = .Invalid_Root
		add_config_warning(&result, fmt.aprintf(
			"%s must contain a JSON object; using default config.",
			CONFIG_FILE_NAME,
		))
	}

	return result
}

parse_strict_json :: proc(text: string) -> (json.Value, json.Error) {
	parser := json.make_parser_from_string(text, .JSON, true, context.allocator)
	value, err := json.parse_value(&parser)
	if err != .None {
		return value, err
	}
	if parser.curr_token.kind != .EOF {
		json.destroy_value(value)
		return value, .Unexpected_Token
	}
	return value, .None
}

apply_config_object :: proc(result: ^Config_Load_Result, object: json.Object) {
	for key, value in object {
		switch key {
		case "recursive":
			if value, ok := config_json_bool(value); ok {
				result.config.recursive = value
			} else {
				warn_invalid_config_value(result, "recursive")
			}
		case "max_dimension":
			if value, ok := config_json_positive_int(value); ok {
				result.config.max_dimension = value
			} else {
				warn_invalid_config_value(result, "max_dimension")
			}
		case "workers":
			apply_workers_config(result, value)
		case "gpu":
			if value, ok := config_json_bool(value); ok {
				result.config.gpu = value
			} else {
				warn_invalid_config_value(result, "gpu")
			}
		case "debug_log":
			if value, ok := config_json_bool(value); ok {
				result.config.debug_log = value
			} else {
				warn_invalid_config_value(result, "debug_log")
			}
		case "debug_log_file":
			if value, ok := config_json_non_empty_string(value); ok {
				replace_config_string(&result.config.debug_log_file, value)
			} else {
				warn_invalid_config_value(result, "debug_log_file")
			}
		case "output_mode":
			apply_output_mode_config(result, value)
		case "out_dir":
			if value, ok := config_json_non_empty_string(value); ok {
				replace_config_string(&result.config.out_dir, value)
			} else {
				warn_invalid_config_value(result, "out_dir")
			}
		case "jpeg":
			apply_jpeg_config(result, value)
		case "png":
			apply_png_config(result, value)
		case:
			warn_unknown_config_option(result, key)
		}
	}
}

apply_workers_config :: proc(result: ^Config_Load_Result, value: json.Value) {
	#partial switch typed in value {
	case json.String:
		if typed == "auto" {
			result.config.workers = Config_Workers{kind = .Auto}
			return
		}
	case json.Integer:
		if typed > 0 && typed <= i64(max(int)) {
			result.config.workers = Config_Workers{kind = .Explicit, count = int(typed)}
			return
		}
	}
	warn_invalid_config_value(result, "workers")
}

apply_output_mode_config :: proc(result: ^Config_Load_Result, value: json.Value) {
	#partial switch typed in value {
	case json.String:
		switch typed {
		case "in-place":
			result.config.output_mode = .In_Place
			return
		case "dir":
			result.config.output_mode = .Dir
			return
		}
	}
	warn_invalid_config_value(result, "output_mode")
}

apply_jpeg_config :: proc(result: ^Config_Load_Result, value: json.Value) {
	#partial switch object in value {
	case json.Object:
		for key, item in object {
			switch key {
			case "enabled":
				if value, ok := config_json_bool(item); ok {
					result.config.jpeg.enabled = value
				} else {
					warn_invalid_config_value(result, "jpeg.enabled")
				}
			case "quality":
				if value, ok := config_json_int_in_range(item, 0, 100); ok {
					result.config.jpeg.quality = value
				} else {
					warn_invalid_config_value(result, "jpeg.quality")
				}
			case "progressive":
				if value, ok := config_json_bool(item); ok {
					result.config.jpeg.progressive = value
				} else {
					warn_invalid_config_value(result, "jpeg.progressive")
				}
			case "optimize":
				if value, ok := config_json_bool(item); ok {
					result.config.jpeg.optimize = value
				} else {
					warn_invalid_config_value(result, "jpeg.optimize")
				}
			case "sample":
				if value, ok := config_json_jpeg_sample(item); ok {
					replace_config_string(&result.config.jpeg.sample, value)
				} else {
					warn_invalid_config_value(result, "jpeg.sample")
				}
			case "quant_table":
				if value, ok := config_json_int_in_range(item, 0, 8); ok {
					result.config.jpeg.quant_table = value
				} else {
					warn_invalid_config_value(result, "jpeg.quant_table")
				}
			case "tune":
				if value, ok := config_json_jpeg_tune(item); ok {
					replace_config_string(&result.config.jpeg.tune, value)
				} else {
					warn_invalid_config_value(result, "jpeg.tune")
				}
			case "preserve_profiles":
				if value, ok := config_json_bool(item); ok {
					result.config.jpeg.preserve_profiles = value
				} else {
					warn_invalid_config_value(result, "jpeg.preserve_profiles")
				}
			case:
				warn_unknown_config_option(result, fmt.tprintf("jpeg.%s", key))
			}
		}
	case:
		warn_invalid_config_value(result, "jpeg")
	}
}

apply_png_config :: proc(result: ^Config_Load_Result, value: json.Value) {
	#partial switch object in value {
	case json.Object:
		for key, item in object {
			switch key {
			case "enabled":
				if value, ok := config_json_bool(item); ok {
					result.config.png.enabled = value
				} else {
					warn_invalid_config_value(result, "png.enabled")
				}
			case "pngquant_quality":
				if value, ok := config_json_pngquant_quality(item); ok {
					replace_config_string(&result.config.png.pngquant_quality, value)
				} else {
					warn_invalid_config_value(result, "png.pngquant_quality")
				}
			case "pngquant_speed":
				if value, ok := config_json_int_in_range(item, 1, 11); ok {
					result.config.png.pngquant_speed = value
				} else {
					warn_invalid_config_value(result, "png.pngquant_speed")
				}
			case "pngquant_dither":
				if value, ok := config_json_bool(item); ok {
					result.config.png.pngquant_dither = value
				} else {
					warn_invalid_config_value(result, "png.pngquant_dither")
				}
			case "oxipng_level":
				if value, ok := config_json_int_in_range(item, 0, 6); ok {
					result.config.png.oxipng_level = value
				} else {
					warn_invalid_config_value(result, "png.oxipng_level")
				}
			case "interlace":
				if value, ok := config_json_bool(item); ok {
					result.config.png.interlace = value
				} else {
					warn_invalid_config_value(result, "png.interlace")
				}
			case "strip":
				if value, ok := config_json_png_strip(item); ok {
					replace_config_string(&result.config.png.strip, value)
				} else {
					warn_invalid_config_value(result, "png.strip")
				}
			case "alpha":
				if value, ok := config_json_bool(item); ok {
					result.config.png.alpha = value
				} else {
					warn_invalid_config_value(result, "png.alpha")
				}
			case:
				warn_unknown_config_option(result, fmt.tprintf("png.%s", key))
			}
		}
	case:
		warn_invalid_config_value(result, "png")
	}
}

config_json_jpeg_sample :: proc(value: json.Value) -> (string, bool) {
	sample, ok := config_json_non_empty_string(value)
	if !ok {
		return "", false
	}

	parts := strings.split(sample, "x", context.temp_allocator)
	defer delete(parts, context.temp_allocator)
	if len(parts) != 2 {
		return "", false
	}

	for part in parts {
		if _, part_ok := parse_positive_config_int(part); !part_ok {
			return "", false
		}
	}

	return sample, true
}

config_json_jpeg_tune :: proc(value: json.Value) -> (string, bool) {
	tune, ok := config_json_non_empty_string(value)
	if ok && tune == "ms-ssim" {
		return tune, true
	}
	return "", false
}

config_json_pngquant_quality :: proc(value: json.Value) -> (string, bool) {
	quality, ok := config_json_non_empty_string(value)
	if !ok {
		return "", false
	}

	parts := strings.split(quality, "-", context.temp_allocator)
	defer delete(parts, context.temp_allocator)
	if len(parts) != 2 {
		return "", false
	}

	min_quality, min_ok := parse_config_int_in_range(parts[0], 0, 100)
	max_quality, max_ok := parse_config_int_in_range(parts[1], 0, 100)
	if !min_ok || !max_ok || min_quality > max_quality {
		return "", false
	}

	return quality, true
}

config_json_png_strip :: proc(value: json.Value) -> (string, bool) {
	strip, ok := config_json_non_empty_string(value)
	if !ok {
		return "", false
	}

	switch strip {
	case "safe", "all", "none":
		return strip, true
	}

	chunks := strings.split(strip, ",", context.temp_allocator)
	defer delete(chunks, context.temp_allocator)
	for chunk in chunks {
		if len(chunk) != 4 {
			return "", false
		}
	}

	return strip, true
}

config_json_bool :: proc(value: json.Value) -> (bool, bool) {
	#partial switch typed in value {
	case json.Boolean:
		return bool(typed), true
	}
	return false, false
}

config_json_positive_int :: proc(value: json.Value) -> (int, bool) {
	return config_json_int_in_range(value, 1, max(int))
}

config_json_int_in_range :: proc(value: json.Value, min_value, max_value: int) -> (int, bool) {
	#partial switch typed in value {
	case json.Integer:
		if typed >= i64(min_value) && typed <= i64(max_value) {
			return int(typed), true
		}
	}
	return 0, false
}

config_json_non_empty_string :: proc(value: json.Value) -> (string, bool) {
	#partial switch typed in value {
	case json.String:
		if len(typed) > 0 {
			return string(typed), true
		}
	}
	return "", false
}

parse_positive_config_int :: proc(text: string) -> (int, bool) {
	return parse_config_int_in_range(text, 1, max(int))
}

parse_config_int_in_range :: proc(text: string, min_value, max_value: int) -> (int, bool) {
	value, ok := strconv.parse_int(text)
	if !ok || value < min_value || value > max_value {
		return 0, false
	}
	return value, true
}

replace_config_string :: proc(slot: ^string, value: string) {
	delete(slot^)
	slot^ = strings.clone(value)
}

warn_invalid_config_value :: proc(result: ^Config_Load_Result, path: string) {
	add_config_warning(result, fmt.aprintf(
		"Invalid config value for %s; using default.",
		path,
	))
}

warn_unknown_config_option :: proc(result: ^Config_Load_Result, path: string) {
	add_config_warning(result, fmt.aprintf(
		"Unknown config option %s; ignoring.",
		path,
	))
}

add_config_warning :: proc(result: ^Config_Load_Result, warning: string) {
	append(&result.warnings, warning)
}

print_config_warnings :: proc(result: Config_Load_Result) {
	for warning in result.warnings {
		log.warn(warning)
	}
}

config_status_summary :: proc(status: Config_Load_Status) -> string {
	switch status {
	case .Missing:
		return "defaults (imgoptz.json not found)"
	case .Loaded:
		return "imgoptz.json loaded"
	case .Invalid_JSON:
		return "defaults (invalid imgoptz.json)"
	case .Read_Failed:
		return "defaults (failed to read imgoptz.json)"
	case .Invalid_Root:
		return "defaults (invalid imgoptz.json root)"
	}
	return "defaults"
}

config_output_mode_summary :: proc(mode: Config_Output_Mode) -> string {
	switch mode {
	case .In_Place:
		return "in-place"
	case .Dir:
		return "dir"
	}
	return "in-place"
}

config_workers_summary :: proc(workers: Config_Workers) -> string {
	switch workers.kind {
	case .Auto:
		return "auto"
	case .Explicit:
		return fmt.tprintf("%d", workers.count)
	}
	return "auto"
}

config_jpeg_summary :: proc(jpeg: Jpeg_Config) -> string {
	if !jpeg.enabled {
		return "disabled"
	}

	return fmt.tprintf(
		"enabled quality=%d progressive=%v optimize=%v sample=%s quant_table=%d tune=%s preserve_profiles=%v",
		jpeg.quality,
		jpeg.progressive,
		jpeg.optimize,
		jpeg.sample,
		jpeg.quant_table,
		jpeg.tune,
		jpeg.preserve_profiles,
	)
}

config_png_summary :: proc(png: Png_Config) -> string {
	if !png.enabled {
		return "disabled"
	}

	return fmt.tprintf(
		"enabled pngquant_quality=%s pngquant_speed=%d pngquant_dither=%v oxipng_level=%d interlace=%v strip=%s alpha=%v",
		png.pngquant_quality,
		png.pngquant_speed,
		png.pngquant_dither,
		png.oxipng_level,
		png.interlace,
		png.strip,
		png.alpha,
	)
}
