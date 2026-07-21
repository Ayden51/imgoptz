package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

IMAGE_PROCESS_MAGICK_THREAD_LIMIT :: "2"

Image_Process_Error :: enum {
	None,
	Disabled_File_Type,
	Temp_Path_Failed,
	Identify_Failed,
	Icc_Extract_Failed,
	Magick_Failed,
	Mozjpeg_Failed,
	Pngquant_Failed,
	Oxipng_Failed,
	Empty_Output,
}

Jpeg_Icc_Mode :: enum {
	None,
	Embed_Source,
	Convert_To_Srgb,
}

Process_Image_Result :: struct {
	output_path: string,
	err:         Image_Process_Error,
	detail:      string,
}

process_temp_counter: u64

process_discovered_images :: proc(
	discovery: Discovery_Result,
	config: App_Config,
	runtime_env: Runtime_Environment,
) {
	if len(discovery.items) == 0 {
		return
	}

	failed := 0
	for item, index in discovery.items {
		result := process_image_to_temp(item, config, runtime_env)
		if result.err == .None {
			log.info(
				fmt.tprintf(
					"[%d/%d] OK   %s",
					index + 1,
					len(discovery.items),
					item.relative_path,
				),
			)
		} else {
			failed += 1
			log.error(
				fmt.tprintf(
					"[%d/%d] ERR  %s  %s",
					index + 1,
					len(discovery.items),
					item.relative_path,
					image_process_error_summary(result.err),
				),
			)
			if len(result.detail) > 0 {
				log.error(result.detail)
			}
		}
		cleanup_process_image_result(&result)
	}

	if failed == 0 {
		log.info("Optimization pipelines completed; safe output handling is not implemented yet.")
	} else {
		log.warn(fmt.tprintf("Optimization pipelines completed with %d failure(s).", failed))
	}
}

process_image_to_temp :: proc(
	item: Image_Work_Item,
	config: App_Config,
	runtime_env: Runtime_Environment,
) -> Process_Image_Result {
	switch item.kind {
	case .Jpeg:
		return process_jpeg_to_temp(item, config, runtime_env)
	case .Png:
		return process_png_to_temp(item, config, runtime_env)
	}
	return Process_Image_Result{err = .Disabled_File_Type}
}

destroy_process_image_result :: proc(result: ^Process_Image_Result) {
	delete(result.output_path)
	delete(result.detail)
	result^ = {}
}

cleanup_process_image_result :: proc(result: ^Process_Image_Result) {
	if len(result.output_path) > 0 {
		remove_if_exists(result.output_path)
	}
	destroy_process_image_result(result)
}

process_jpeg_to_temp :: proc(
	item: Image_Work_Item,
	config: App_Config,
	runtime_env: Runtime_Environment,
) -> Process_Image_Result {
	if !config.jpeg.enabled {
		return Process_Image_Result{err = .Disabled_File_Type}
	}

	ppm_path, ppm_ok := make_process_temp_path(item.source_path, "resized.ppm")
	if !ppm_ok {
		return Process_Image_Result{err = .Temp_Path_Failed}
	}
	defer delete(ppm_path)
	defer remove_if_exists(ppm_path)

	output_path, output_ok := make_process_temp_path(item.source_path, "optimized.jpg")
	if !output_ok {
		return Process_Image_Result{err = .Temp_Path_Failed}
	}

	icc_mode := Jpeg_Icc_Mode.None
	embed_icc_path := ""
	convert_icc_path := ""
	if config.jpeg.preserve_profiles {
		icc_result := determine_jpeg_icc_mode(item.source_path, runtime_env)
		defer delete(icc_result.detail)
		if icc_result.err != .None {
			delete(output_path)
			return Process_Image_Result {
				err = icc_result.err,
				detail = strings.clone(icc_result.detail),
			}
		}

		icc_mode = icc_result.mode
		switch icc_mode {
		case .Embed_Source:
			source_icc_path, source_icc_ok := make_process_temp_path(
				item.source_path,
				"source.icc",
			)
			if !source_icc_ok {
				delete(output_path)
				return Process_Image_Result{err = .Temp_Path_Failed}
			}
			defer delete(source_icc_path)
			defer remove_if_exists(source_icc_path)

			command := build_jpeg_icc_extract_command(
				runtime_env.magick_path,
				item.source_path,
				source_icc_path,
			)
			if detail, ok := run_tool(
				command,
				imagemagick_process_environment(runtime_env),
				"ImageMagick ICC extract",
			); !ok {
				delete(output_path)
				return Process_Image_Result{err = .Icc_Extract_Failed, detail = detail}
			}
			embed_icc_path = source_icc_path
		case .Convert_To_Srgb:
			embed_icc_path = runtime_env.srgb_profile
			convert_icc_path = runtime_env.srgb_profile
		case .None:
		}
	}

	resize_command := build_jpeg_magick_resize_command(
		runtime_env.magick_path,
		item.source_path,
		config.max_dimension,
		convert_icc_path,
		ppm_path,
	)
	if detail, ok := run_tool(
		resize_command,
		imagemagick_process_environment(runtime_env),
		"ImageMagick JPEG resize",
	); !ok {
		delete(output_path)
		return Process_Image_Result{err = .Magick_Failed, detail = detail}
	}
	if !file_is_non_empty(ppm_path) {
		delete(output_path)
		return Process_Image_Result {
			err = .Empty_Output,
			detail = strings.clone("ImageMagick did not produce a resized PPM."),
		}
	}

	mozjpeg_command := build_mozjpeg_command(
		runtime_env.mozjpeg_path,
		config.jpeg,
		output_path,
		ppm_path,
		embed_icc_path,
	)
	if detail, ok := run_tool(mozjpeg_command, nil, "MozJPEG"); !ok {
		remove_if_exists(output_path)
		delete(output_path)
		return Process_Image_Result{err = .Mozjpeg_Failed, detail = detail}
	}
	if !file_is_non_empty(output_path) {
		remove_if_exists(output_path)
		delete(output_path)
		return Process_Image_Result {
			err = .Empty_Output,
			detail = strings.clone("MozJPEG did not produce an optimized JPEG."),
		}
	}

	return Process_Image_Result{output_path = output_path}
}

process_png_to_temp :: proc(
	item: Image_Work_Item,
	config: App_Config,
	runtime_env: Runtime_Environment,
) -> Process_Image_Result {
	if !config.png.enabled {
		return Process_Image_Result{err = .Disabled_File_Type}
	}

	resized_path, resized_ok := make_process_temp_path(item.source_path, "resized.png")
	if !resized_ok {
		return Process_Image_Result{err = .Temp_Path_Failed}
	}
	defer delete(resized_path)
	defer remove_if_exists(resized_path)

	quant_path, quant_ok := make_process_temp_path(item.source_path, "quant.png")
	if !quant_ok {
		return Process_Image_Result{err = .Temp_Path_Failed}
	}
	defer delete(quant_path)
	defer remove_if_exists(quant_path)

	output_path, output_ok := make_process_temp_path(item.source_path, "optimized.png")
	if !output_ok {
		return Process_Image_Result{err = .Temp_Path_Failed}
	}

	resize_command := build_png_magick_resize_command(
		runtime_env.magick_path,
		item.source_path,
		config.max_dimension,
		resized_path,
	)
	if detail, ok := run_tool(
		resize_command,
		imagemagick_process_environment(runtime_env),
		"ImageMagick PNG resize",
	); !ok {
		delete(output_path)
		return Process_Image_Result{err = .Magick_Failed, detail = detail}
	}
	if !file_is_non_empty(resized_path) {
		delete(output_path)
		return Process_Image_Result {
			err = .Empty_Output,
			detail = strings.clone("ImageMagick did not produce a resized PNG."),
		}
	}

	pngquant_command := build_pngquant_command(
		runtime_env.pngquant_path,
		config.png,
		quant_path,
		resized_path,
	)
	if detail, ok := run_tool(pngquant_command, nil, "pngquant"); !ok {
		remove_if_exists(output_path)
		delete(output_path)
		return Process_Image_Result{err = .Pngquant_Failed, detail = detail}
	}
	if !file_is_non_empty(quant_path) {
		delete(output_path)
		return Process_Image_Result {
			err = .Empty_Output,
			detail = strings.clone("pngquant did not produce a quantized PNG."),
		}
	}

	oxipng_command := build_oxipng_command(
		runtime_env.oxipng_path,
		config.png,
		output_path,
		quant_path,
	)
	if detail, ok := run_tool(oxipng_command, nil, "Oxipng"); !ok {
		remove_if_exists(output_path)
		delete(output_path)
		return Process_Image_Result{err = .Oxipng_Failed, detail = detail}
	}
	if !file_is_non_empty(output_path) {
		remove_if_exists(output_path)
		delete(output_path)
		return Process_Image_Result {
			err = .Empty_Output,
			detail = strings.clone("Oxipng did not produce an optimized PNG."),
		}
	}

	return Process_Image_Result{output_path = output_path}
}

Jpeg_Icc_Result :: struct {
	mode:   Jpeg_Icc_Mode,
	err:    Image_Process_Error,
	detail: string,
}

determine_jpeg_icc_mode :: proc(
	source_path: string,
	runtime_env: Runtime_Environment,
) -> Jpeg_Icc_Result {
	command := build_jpeg_icc_identify_command(runtime_env.magick_path, source_path)
	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = command, env = imagemagick_process_environment(runtime_env)},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil || !state.exited || state.exit_code != 0 {
		return Jpeg_Icc_Result {
			err = .Identify_Failed,
			detail = tool_failure_detail("ImageMagick ICC identify", state, stderr, err),
		}
	}

	if len(stdout) > 0 && jpeg_icc_profile_is_retained(string(stdout)) {
		return Jpeg_Icc_Result{mode = .Embed_Source}
	}
	return Jpeg_Icc_Result{mode = .Convert_To_Srgb}
}

make_process_temp_path :: proc(source_path, suffix: string) -> (string, bool) {
	pid := os.get_pid()
	for attempt in 0 ..< 1024 {
		process_temp_counter += 1
		candidate := fmt.aprintf(
			"%s.imgoptz.%d.%d.%s",
			source_path,
			pid,
			process_temp_counter,
			suffix,
		)
		if !os.exists(candidate) {
			return candidate, true
		}
		delete(candidate)
		_ = attempt
	}
	return "", false
}

build_jpeg_icc_identify_command :: proc(magick_path, source_path: string) -> []string {
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, magick_path)
	append(&command, "identify")
	append(&command, "-quiet")
	append(&command, "-format")
	append(&command, "%[profile:icc]")
	append(&command, source_path)
	return command[:]
}

build_jpeg_icc_extract_command :: proc(magick_path, source_path, output_path: string) -> []string {
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, magick_path)
	append(&command, source_path)
	append(&command, fmt.tprintf("icc:%s", output_path))
	return command[:]
}

build_jpeg_magick_resize_command :: proc(
	magick_path, source_path: string,
	max_dimension: int,
	convert_profile_path, output_path: string,
) -> []string {
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, magick_path)
	append(&command, source_path)
	append_magick_resize_args(&command, max_dimension)
	if len(convert_profile_path) > 0 {
		append(&command, "-profile")
		append(&command, convert_profile_path)
	}
	append(&command, fmt.tprintf("ppm:%s", output_path))
	return command[:]
}

build_png_magick_resize_command :: proc(
	magick_path, source_path: string,
	max_dimension: int,
	output_path: string,
) -> []string {
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, magick_path)
	append(&command, source_path)
	append_magick_resize_args(&command, max_dimension)
	append(&command, output_path)
	return command[:]
}

append_magick_resize_args :: proc(command: ^[dynamic]string, max_dimension: int) {
	append(command, "-auto-orient")
	append(command, "-filter")
	append(command, "Lanczos")
	append(command, "-resize")
	append(command, fmt.tprintf("%dx%d>", max_dimension, max_dimension))
}

build_mozjpeg_command :: proc(
	mozjpeg_path: string,
	jpeg: Jpeg_Config,
	output_path, input_path, icc_path: string,
) -> []string {
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, mozjpeg_path)
	append(&command, "-quality")
	append(&command, fmt.tprintf("%d", jpeg.quality))
	if jpeg.progressive {
		append(&command, "-progressive")
	}
	if jpeg.optimize {
		append(&command, "-optimize")
	}
	append(&command, "-sample")
	append(&command, jpeg.sample)
	append(&command, "-quant-table")
	append(&command, fmt.tprintf("%d", jpeg.quant_table))
	if jpeg.tune == "ms-ssim" {
		append(&command, "-tune-ms-ssim")
	}
	if len(icc_path) > 0 {
		append(&command, "-icc")
		append(&command, icc_path)
	}
	append(&command, "-outfile")
	append(&command, output_path)
	append(&command, input_path)
	return command[:]
}

build_pngquant_command :: proc(
	pngquant_path: string,
	png: Png_Config,
	output_path, input_path: string,
) -> []string {
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, pngquant_path)
	append(&command, "--force")
	append(&command, "--output")
	append(&command, output_path)
	append(&command, "--quality")
	append(&command, png.pngquant_quality)
	append(&command, "--speed")
	append(&command, fmt.tprintf("%d", png.pngquant_speed))
	if !png.pngquant_dither {
		append(&command, "--nofs")
	}
	append(&command, "--strip")
	append(&command, "--")
	append(&command, input_path)
	return command[:]
}

build_oxipng_command :: proc(
	oxipng_path: string,
	png: Png_Config,
	output_path, input_path: string,
) -> []string {
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, oxipng_path)
	append(&command, "--force")
	append(&command, "-o")
	append(&command, fmt.tprintf("%d", png.oxipng_level))
	if png.strip != "none" {
		append(&command, "--strip")
		append(&command, png.strip)
	}
	if png.alpha {
		append(&command, "--alpha")
	}
	append(&command, "--interlace")
	if png.interlace {
		append(&command, "on")
	} else {
		append(&command, "off")
	}
	append(&command, "--out")
	append(&command, output_path)
	append(&command, input_path)
	return command[:]
}

imagemagick_process_environment :: proc(runtime_env: Runtime_Environment) -> []string {
	inherited, inherited_err := os.environ(context.temp_allocator)
	if inherited_err != nil {
		return nil
	}

	environment: [dynamic]string
	environment.allocator = context.temp_allocator
	for entry in inherited {
		if imagemagick_environment_entry_is_managed(entry) {
			continue
		}
		append(&environment, entry)
	}
	append(&environment, fmt.tprintf("MAGICK_THREAD_LIMIT=%s", IMAGE_PROCESS_MAGICK_THREAD_LIMIT))
	if runtime_env.magick_use_gpu {
		append(&environment, "MAGICK_OCL_DEVICE=GPU")
	}
	return environment[:]
}

imagemagick_environment_entry_is_managed :: proc(entry: string) -> bool {
	return(
		environment_entry_name_equals(entry, "MAGICK_THREAD_LIMIT") ||
		environment_entry_name_equals(entry, "MAGICK_OCL_DEVICE") \
	)
}

environment_entry_name_equals :: proc(entry, name: string) -> bool {
	if len(entry) <= len(name) || entry[len(name)] != '=' {
		return false
	}

	for i in 0 ..< len(name) {
		if ascii_lower(entry[i]) != ascii_lower(name[i]) {
			return false
		}
	}
	return true
}

run_tool :: proc(command: []string, environment: []string, label: string) -> (string, bool) {
	state, stdout, stderr, err := os.process_exec(
		os.Process_Desc{command = command, env = environment},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if err == nil && state.exited && state.exit_code == 0 {
		return "", true
	}
	return tool_failure_detail(label, state, stderr, err), false
}

tool_failure_detail :: proc(
	label: string,
	state: os.Process_State,
	stderr: []byte,
	err: os.Error,
) -> string {
	if err != nil {
		return fmt.aprintf("%s failed to start or run: %v", label, err)
	}
	if !state.exited {
		return fmt.aprintf("%s did not exit cleanly.", label)
	}
	if len(stderr) > 0 {
		return fmt.aprintf("%s exited with code %d: %s", label, state.exit_code, string(stderr))
	}
	return fmt.aprintf("%s exited with code %d.", label, state.exit_code)
}

jpeg_icc_profile_is_retained :: proc(profile_text: string) -> bool {
	checks := [?]string {
		"sRGB",
		"IEC 61966-2-1",
		"IEC61966-2.1",
		"IEC61966-2-1",
		"Display P3",
		"DCI-P3 D65 Gamut with sRGB Transfer",
		"P3",
	}
	for check in checks {
		if strings.contains(profile_text, check) {
			return true
		}
	}
	return false
}

file_is_non_empty :: proc(path: string) -> bool {
	file, open_err := os.open(path)
	if open_err != nil {
		return false
	}
	defer os.close(file)

	size, size_err := os.file_size(file)
	return size_err == nil && size > 0
}

remove_if_exists :: proc(path: string) {
	if len(path) > 0 && os.exists(path) {
		_ = os.remove(path)
	}
}

image_process_error_summary :: proc(err: Image_Process_Error) -> string {
	switch err {
	case .None:
		return ""
	case .Disabled_File_Type:
		return "image type is disabled by config"
	case .Temp_Path_Failed:
		return "failed to create temporary file path"
	case .Identify_Failed:
		return "failed to inspect JPEG ICC profile"
	case .Icc_Extract_Failed:
		return "failed to extract JPEG ICC profile"
	case .Magick_Failed:
		return "ImageMagick failed"
	case .Mozjpeg_Failed:
		return "MozJPEG failed"
	case .Pngquant_Failed:
		return "pngquant failed"
	case .Oxipng_Failed:
		return "Oxipng failed"
	case .Empty_Output:
		return "tool produced an empty output"
	}
	return "image processing failed"
}
