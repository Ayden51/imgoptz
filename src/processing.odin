package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

IMAGE_PROCESS_MAGICK_THREAD_LIMIT_SINGLE_WORKER :: "2"
IMAGE_PROCESS_MAGICK_THREAD_LIMIT_MULTI_WORKER :: "1"

Image_Process_Error :: enum {
	None,
	Disabled_File_Type,
	Temp_Path_Failed,
	Identify_Failed,
	Icc_Extract_Failed,
	Icc_Embed_Failed,
	Icc_Verify_Failed,
	Magick_Failed,
	Mozjpeg_Failed,
	Pngquant_Failed,
	Oxipng_Failed,
	Empty_Output,
	Size_Read_Failed,
	Optimized_Not_Smaller,
	Final_Path_Failed,
	Replace_Failed,
	Copy_Failed,
}

Icc_Profile_Mode :: enum {
	None,
	Embed_Source,
	Convert_To_Srgb,
}

Process_Image_Result :: struct {
	output_path: string,
	err:         Image_Process_Error,
	detail:      string,
}

Image_Process_Worker_State :: struct {
	items:          []Image_Work_Item,
	config:         ^App_Config,
	runtime_env:    ^Runtime_Environment,
	next_index:     int,
	progress_mutex: sync.Mutex,
	progress_pacer: ^Console_Pacer,
	summary:        ^Processing_Summary,
}

Processing_Summary :: struct {
	succeeded:       int,
	skipped:         int,
	failed:          int,
	original_total:  i64,
	optimized_total: i64,
}

Finalize_Output_Result :: struct {
	output_path:       string,
	original_size:     i64,
	optimized_size:    i64,
	reduction_percent: i64,
	err:               Image_Process_Error,
	detail:            string,
}

process_temp_counter: u64

process_discovered_images :: proc(
	discovery: Discovery_Result,
	config: App_Config,
	runtime_env: Runtime_Environment,
) {
	print_progress_header()
	started_at := time.now()
	summary: Processing_Summary
	debug_log_section("PROGRESS")
	debug_log_infof(
		"processing start: items=%d worker_count=%d",
		len(discovery.items),
		runtime_env.worker_count,
	)

	if len(discovery.items) == 0 {
		debug_log_info("processing skipped: no supported images")
		debug_log_section("SUMMARY")
		debug_log_info(
			"processing finish: succeeded=0 skipped=0 failed=0 original_total=0 optimized_total=0",
		)
		print_progress_empty()
		print_processing_summary(summary, time.since(started_at))
		pause_after_processing_summary()
		return
	}

	worker_config := config
	worker_runtime_env := runtime_env
	progress_pacer := console_pacer_init(CONSOLE_PROGRESS_ROW_DELAY)
	process_images_parallel(
		discovery.items[:],
		&worker_config,
		&worker_runtime_env,
		&summary,
		&progress_pacer,
	)

	elapsed := elapsed_excluding_ui_delay(started_at, console_pacer_slept(&progress_pacer))
	debug_log_section("SUMMARY")
	debug_log_infof(
		"processing finish: succeeded=%d skipped=%d failed=%d original_total=%d optimized_total=%d elapsed_seconds=%.3f",
		summary.succeeded,
		summary.skipped,
		summary.failed,
		summary.original_total,
		summary.optimized_total,
		time.duration_seconds(elapsed),
	)
	print_processing_summary(summary, elapsed)
	pause_after_processing_summary()
}

process_images_parallel :: proc(
	items: []Image_Work_Item,
	config: ^App_Config,
	runtime_env: ^Runtime_Environment,
	summary: ^Processing_Summary,
	progress_pacer: ^Console_Pacer,
) {
	worker_count := min(max(runtime_env.worker_count, 1), len(items))
	debug_log_infof("worker pool: items=%d active_workers=%d", len(items), worker_count)
	if worker_count <= 1 {
		for item in items {
			finalize := process_image_item_to_final(item, config^, runtime_env^)
			record_finalized_image(summary, item.relative_path, finalize, progress_pacer)
			destroy_finalize_output_result(&finalize)
		}
		return
	}

	worker_allocator: mem.Mutex_Allocator
	mem.mutex_allocator_init(&worker_allocator, context.allocator)
	worker_context := context
	worker_context.allocator = mem.mutex_allocator(&worker_allocator)

	state := Image_Process_Worker_State {
		items          = items,
		config         = config,
		runtime_env    = runtime_env,
		progress_pacer = progress_pacer,
		summary        = summary,
	}
	threads := make([]^thread.Thread, worker_count)
	defer delete(threads)

	for _, index in threads {
		worker := thread.create(process_image_worker)
		worker.init_context = worker_context
		worker.data = &state
		threads[index] = worker
		debug_log_debugf("worker start requested: index=%d", index)
		thread.start(worker)
	}
	for worker in threads {
		thread.join(worker)
		thread.destroy(worker)
	}
}

process_image_worker :: proc(worker: ^thread.Thread) {
	state := cast(^Image_Process_Worker_State)worker.data
	for {
		index := sync.atomic_add(&state.next_index, 1)
		if index >= len(state.items) {
			debug_log_debugf("worker idle: no more items")
			break
		}
		debug_log_debugf(
			"worker picked item: index=%d relative=\"%s\"",
			index,
			state.items[index].relative_path,
		)
		result := process_image_item_to_final(
			state.items[index],
			state.config^,
			state.runtime_env^,
		)
		if sync.mutex_guard(&state.progress_mutex) {
			record_finalized_image(
				state.summary,
				state.items[index].relative_path,
				result,
				state.progress_pacer,
			)
		}
		destroy_finalize_output_result(&result)
	}
}

elapsed_excluding_ui_delay :: proc(
	started_at: time.Time,
	ui_delay: time.Duration,
) -> time.Duration {
	elapsed := time.since(started_at)
	if ui_delay >= elapsed {
		return 0 * time.Millisecond
	}
	return elapsed - ui_delay
}

process_image_item_to_final :: proc(
	item: Image_Work_Item,
	config: App_Config,
	runtime_env: Runtime_Environment,
) -> Finalize_Output_Result {
	debug_log_infof(
		"image start: relative=\"%s\" source=\"%s\" destination=\"%s\" kind=%v",
		item.relative_path,
		item.source_path,
		item.destination_path,
		item.kind,
	)
	result := process_image_to_temp(item, config, runtime_env)
	defer cleanup_process_image_result(&result)

	if result.err != .None {
		debug_log_errorf(
			"image temp failed: relative=\"%s\" err=%v detail=\"%s\"",
			item.relative_path,
			result.err,
			result.detail,
		)
		return Finalize_Output_Result{err = result.err, detail = strings.clone(result.detail)}
	}
	finalize := finalize_optimized_output(item, result.output_path, runtime_env.output_mode)
	debug_log_infof(
		"image finish: relative=\"%s\" err=%v output=\"%s\" original_size=%d optimized_size=%d detail=\"%s\"",
		item.relative_path,
		finalize.err,
		finalize.output_path,
		finalize.original_size,
		finalize.optimized_size,
		finalize.detail,
	)
	return finalize
}

record_finalized_image :: proc(
	summary: ^Processing_Summary,
	relative_path: string,
	finalize: Finalize_Output_Result,
	progress_pacer: ^Console_Pacer,
) {
	pace_console_row(progress_pacer)

	if finalize.err == .None {
		summary.succeeded += 1
		summary.original_total += finalize.original_size
		summary.optimized_total += finalize.optimized_size
		debug_log_infof(
			"progress success: relative=\"%s\" original_size=%d optimized_size=%d reduction_percent=%d output=\"%s\"",
			relative_path,
			finalize.original_size,
			finalize.optimized_size,
			finalize.reduction_percent,
			finalize.output_path,
		)
		print_progress_ok(
			relative_path,
			finalize.original_size,
			finalize.optimized_size,
			finalize.reduction_percent,
		)
	} else if finalize.err == .Optimized_Not_Smaller {
		summary.skipped += 1
		debug_log_warnf(
			"progress skipped: relative=\"%s\" detail=\"%s\"",
			relative_path,
			finalize.detail,
		)
		print_progress_skip(relative_path)
	} else {
		summary.failed += 1
		debug_log_errorf(
			"progress failed: relative=\"%s\" err=%v detail=\"%s\"",
			relative_path,
			finalize.err,
			finalize.detail,
		)
		print_progress_error(relative_path, finalize.err)
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
		debug_log_debugf("cleanup optimized temp output: \"%s\"", result.output_path)
		remove_if_exists(result.output_path)
	}
	destroy_process_image_result(result)
}

cleanup_temp_path_slot :: proc(path: ^string) {
	if len(path^) > 0 {
		debug_log_debugf("cleanup temp path: \"%s\"", path^)
		remove_if_exists(path^)
		delete(path^)
		path^ = ""
	}
}

destroy_finalize_output_result :: proc(result: ^Finalize_Output_Result) {
	delete(result.output_path)
	delete(result.detail)
	result^ = {}
}

finalize_optimized_output :: proc(
	item: Image_Work_Item,
	temp_output_path: string,
	output_mode: Config_Output_Mode,
) -> Finalize_Output_Result {
	debug_log_infof(
		"finalize start: relative=\"%s\" temp_output=\"%s\" output_mode=%s",
		item.relative_path,
		temp_output_path,
		debug_log_output_mode(output_mode),
	)
	original_size, original_size_ok := file_size_by_path(item.source_path)
	optimized_size, optimized_size_ok := file_size_by_path(temp_output_path)
	if !original_size_ok || !optimized_size_ok {
		debug_log_errorf(
			"size comparison failed: source=\"%s\" temp_output=\"%s\" original_ok=%v optimized_ok=%v",
			item.source_path,
			temp_output_path,
			original_size_ok,
			optimized_size_ok,
		)
		return Finalize_Output_Result{err = .Size_Read_Failed}
	}
	result := Finalize_Output_Result {
		original_size     = original_size,
		optimized_size    = optimized_size,
		reduction_percent = progress_reduction_percent(original_size, optimized_size),
	}

	if optimized_size >= original_size {
		debug_log_warnf(
			"size comparison rejected: relative=\"%s\" original_size=%d optimized_size=%d",
			item.relative_path,
			original_size,
			optimized_size,
		)
		result.err = .Optimized_Not_Smaller
		result.detail = fmt.aprintf(
			"Optimized output was not smaller (%d bytes >= %d bytes).",
			optimized_size,
			original_size,
		)
		return result
	}

	final_path, final_path_ok := final_output_path_for_item(item, output_mode)
	if !final_path_ok {
		debug_log_errorf("final output path failed: relative=\"%s\"", item.relative_path)
		result.err = .Final_Path_Failed
		return result
	}
	debug_log_infof("final output path accepted: \"%s\"", final_path)

	switch output_mode {
	case .In_Place:
		if detail, ok := replace_in_place_with_slugged_output(item, temp_output_path, final_path);
		   !ok {
			delete(final_path)
			result.err = .Replace_Failed
			result.detail = detail
			return result
		}
	case .Dir:
		if detail, ok := copy_to_slugged_output(temp_output_path, final_path); !ok {
			delete(final_path)
			result.err = .Copy_Failed
			result.detail = detail
			return result
		}
	}

	result.output_path = final_path
	debug_log_infof(
		"finalize succeeded: relative=\"%s\" output=\"%s\" original_size=%d optimized_size=%d",
		item.relative_path,
		result.output_path,
		result.original_size,
		result.optimized_size,
	)
	return result
}

replace_in_place_with_slugged_output :: proc(
	item: Image_Work_Item,
	temp_output_path, final_path: string,
) -> (
	string,
	bool,
) {
	backup_path, backup_ok := make_process_temp_path(item.source_path, "original.bak")
	if !backup_ok {
		debug_log_errorf("replace failed: backup temp path failed for \"%s\"", item.source_path)
		return "", false
	}
	defer delete(backup_path)
	debug_log_debugf("replace backup path: \"%s\"", backup_path)

	backup_err := os.rename(item.source_path, backup_path)
	if backup_err != nil {
		debug_log_errorf(
			"replace failed moving original: source=\"%s\" backup=\"%s\" err=%v",
			item.source_path,
			backup_path,
			backup_err,
		)
		return fmt.aprintf("Failed to move original aside: %v", backup_err), false
	}
	debug_log_debugf(
		"original moved aside: source=\"%s\" backup=\"%s\"",
		item.source_path,
		backup_path,
	)

	replaced := false
	replace_err := os.rename(temp_output_path, item.source_path)
	if replace_err == nil {
		replaced = true
	}
	if replace_err != nil {
		_ = os.rename(backup_path, item.source_path)
		debug_log_errorf(
			"replace failed moving temp into source: temp=\"%s\" source=\"%s\" err=%v",
			temp_output_path,
			item.source_path,
			replace_err,
		)
		return fmt.aprintf("Failed to replace original with optimized output: %v", replace_err),
			false
	}
	debug_log_debugf(
		"optimized temp moved into source path: temp=\"%s\" source=\"%s\"",
		temp_output_path,
		item.source_path,
	)

	if item.source_path != final_path {
		rename_err := os.rename(item.source_path, final_path)
		if rename_err != nil {
			if replaced {
				remove_if_exists(item.source_path)
			}
			_ = os.rename(backup_path, item.source_path)
			debug_log_errorf(
				"slug rename failed: source=\"%s\" final=\"%s\" err=%v",
				item.source_path,
				final_path,
				rename_err,
			)
			return fmt.aprintf("Failed to rename optimized output: %v", rename_err), false
		}
		debug_log_debugf(
			"slug rename succeeded: source=\"%s\" final=\"%s\"",
			item.source_path,
			final_path,
		)
	}

	remove_if_exists(backup_path)
	debug_log_debugf("backup removed: \"%s\"", backup_path)
	return "", true
}

copy_to_slugged_output :: proc(temp_output_path, final_path: string) -> (string, bool) {
	dir, _ := os.split_path(final_path)
	if len(dir) > 0 {
		mkdir_err := os.make_directory_all(dir)
		if mkdir_err != nil {
			debug_log_errorf(
				"copy failed creating output directory: dir=\"%s\" err=%v",
				dir,
				mkdir_err,
			)
			return fmt.aprintf("Failed to create output directory: %v", mkdir_err), false
		}
		debug_log_debugf("output directory ready: \"%s\"", dir)
	}

	copy_err := os.copy_file(final_path, temp_output_path)
	if copy_err != nil {
		remove_if_exists(final_path)
		debug_log_errorf(
			"copy failed: temp=\"%s\" final=\"%s\" err=%v",
			temp_output_path,
			final_path,
			copy_err,
		)
		return fmt.aprintf("Failed to copy optimized output: %v", copy_err), false
	}
	debug_log_debugf("copy succeeded: temp=\"%s\" final=\"%s\"", temp_output_path, final_path)
	return "", true
}

final_output_path_for_item :: proc(
	item: Image_Work_Item,
	output_mode: Config_Output_Mode,
) -> (
	string,
	bool,
) {
	dir, filename := os.split_path(item.destination_path)
	stem, ext := os.split_filename(filename)

	slug_stem := slugify(stem)
	defer delete(slug_stem)
	effective_stem := slug_stem
	if len(slug_stem) == 0 {
		effective_stem = "image"
	}
	debug_log_debugf(
		"slugify final name: filename=\"%s\" stem=\"%s\" slug=\"%s\" effective=\"%s\" ext=\"%s\"",
		filename,
		stem,
		slug_stem,
		effective_stem,
		ext,
	)

	lower_ext := ascii_lower_clone(ext)
	defer delete(lower_ext)

	ignored_existing_path := ""
	if output_mode == .In_Place {
		ignored_existing_path = item.source_path
	}
	debug_log_debugf(
		"unique output search: dir=\"%s\" stem=\"%s\" ext=\"%s\" ignored=\"%s\"",
		dir,
		effective_stem,
		lower_ext,
		ignored_existing_path,
	)
	return unique_output_path(dir, effective_stem, lower_ext, ignored_existing_path)
}

unique_output_path :: proc(dir, stem, ext, ignored_existing_path: string) -> (string, bool) {
	for suffix in 0 ..< 1024 {
		filename: string
		if suffix == 0 {
			filename = fmt.aprintf("%s.%s", stem, ext)
		} else {
			filename = fmt.aprintf("%s-%d.%s", stem, suffix, ext)
		}

		parts := [?]string{dir, filename}
		candidate, join_err := os.join_path(parts[:], context.allocator)
		delete(filename)
		if join_err != nil {
			return "", false
		}

		if !os.exists(candidate) || output_paths_match(candidate, ignored_existing_path) {
			debug_log_debugf("unique output candidate accepted: \"%s\"", candidate)
			return candidate, true
		}
		debug_log_debugf("unique output candidate exists: \"%s\"", candidate)
		delete(candidate)
	}
	debug_log_errorf(
		"unique output search exhausted: dir=\"%s\" stem=\"%s\" ext=\"%s\"",
		dir,
		stem,
		ext,
	)
	return "", false
}

ascii_lower_clone :: proc(value: string) -> string {
	result := make([]byte, len(value))
	for i in 0 ..< len(value) {
		result[i] = ascii_lower(value[i])
	}
	return string(result)
}

output_paths_match :: proc(a, b: string) -> bool {
	return ascii_equal_fold(a, b)
}

process_jpeg_to_temp :: proc(
	item: Image_Work_Item,
	config: App_Config,
	runtime_env: Runtime_Environment,
) -> Process_Image_Result {
	if !config.jpeg.enabled {
		debug_log_warnf("jpeg skipped: disabled by config source=\"%s\"", item.source_path)
		return Process_Image_Result{err = .Disabled_File_Type}
	}
	debug_log_infof("jpeg pipeline start: source=\"%s\"", item.source_path)

	ppm_path, ppm_ok := make_process_temp_path(item.source_path, "resized.ppm")
	if !ppm_ok {
		debug_log_errorf("jpeg temp path failed: resized ppm source=\"%s\"", item.source_path)
		return Process_Image_Result{err = .Temp_Path_Failed}
	}
	debug_log_debugf("jpeg temp resized ppm: \"%s\"", ppm_path)
	defer delete(ppm_path)
	defer remove_if_exists(ppm_path)

	output_path, output_ok := make_process_temp_path(item.source_path, "optimized.jpg")
	if !output_ok {
		debug_log_errorf("jpeg temp path failed: optimized output source=\"%s\"", item.source_path)
		return Process_Image_Result{err = .Temp_Path_Failed}
	}
	debug_log_debugf("jpeg temp optimized output: \"%s\"", output_path)

	icc_mode := Icc_Profile_Mode.None
	embed_icc_path := ""
	convert_icc_path := ""
	source_icc_path := ""
	defer cleanup_temp_path_slot(&source_icc_path)
	if config.jpeg.preserve_profiles {
		icc_result := determine_icc_profile_mode(item.source_path, runtime_env)
		defer destroy_icc_profile_result(&icc_result)
		debug_log_infof(
			"jpeg ICC decision: source=\"%s\" mode=%v err=%v detail=\"%s\"",
			item.source_path,
			icc_result.mode,
			icc_result.err,
			icc_result.detail,
		)
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
			source_icc_ok: bool
			source_icc_path, source_icc_ok = make_process_temp_path(item.source_path, "source.icc")
			if !source_icc_ok {
				debug_log_errorf(
					"jpeg ICC source temp path failed: source=\"%s\"",
					item.source_path,
				)
				delete(output_path)
				return Process_Image_Result{err = .Temp_Path_Failed}
			}
			debug_log_debugf("jpeg source ICC temp: \"%s\"", source_icc_path)

			command := build_icc_extract_command(
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
		debug_log_errorf("jpeg resized PPM missing or empty: \"%s\"", ppm_path)
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
		debug_log_errorf("jpeg optimized output missing or empty: \"%s\"", output_path)
		delete(output_path)
		return Process_Image_Result {
			err = .Empty_Output,
			detail = strings.clone("MozJPEG did not produce an optimized JPEG."),
		}
	}

	debug_log_infof("jpeg pipeline produced temp output: \"%s\"", output_path)
	return Process_Image_Result{output_path = output_path}
}

process_png_to_temp :: proc(
	item: Image_Work_Item,
	config: App_Config,
	runtime_env: Runtime_Environment,
) -> Process_Image_Result {
	if !config.png.enabled {
		debug_log_warnf("png skipped: disabled by config source=\"%s\"", item.source_path)
		return Process_Image_Result{err = .Disabled_File_Type}
	}
	debug_log_infof("png pipeline start: source=\"%s\"", item.source_path)

	resized_path, resized_ok := make_process_temp_path(item.source_path, "resized.png")
	if !resized_ok {
		debug_log_errorf("png temp path failed: resized source=\"%s\"", item.source_path)
		return Process_Image_Result{err = .Temp_Path_Failed}
	}
	debug_log_debugf("png temp resized: \"%s\"", resized_path)
	defer delete(resized_path)
	defer remove_if_exists(resized_path)

	quant_path, quant_ok := make_process_temp_path(item.source_path, "quant.png")
	if !quant_ok {
		debug_log_errorf("png temp path failed: quant source=\"%s\"", item.source_path)
		return Process_Image_Result{err = .Temp_Path_Failed}
	}
	debug_log_debugf("png temp quant: \"%s\"", quant_path)
	defer delete(quant_path)
	defer remove_if_exists(quant_path)

	output_path, output_ok := make_process_temp_path(item.source_path, "optimized.png")
	if !output_ok {
		debug_log_errorf("png temp path failed: optimized output source=\"%s\"", item.source_path)
		return Process_Image_Result{err = .Temp_Path_Failed}
	}
	debug_log_debugf("png temp optimized output: \"%s\"", output_path)

	convert_icc_path := ""
	embed_icc_path := ""
	expected_icc_profile := ""
	expected_icc_exact := false
	source_icc_path := ""
	profiled_quant_path := ""
	defer cleanup_temp_path_slot(&source_icc_path)
	defer cleanup_temp_path_slot(&profiled_quant_path)
	if config.png.preserve_profiles {
		icc_result := determine_icc_profile_mode(item.source_path, runtime_env)
		defer destroy_icc_profile_result(&icc_result)
		debug_log_infof(
			"png ICC decision: source=\"%s\" mode=%v err=%v detail=\"%s\"",
			item.source_path,
			icc_result.mode,
			icc_result.err,
			icc_result.detail,
		)
		if icc_result.err != .None {
			delete(output_path)
			return Process_Image_Result {
				err = icc_result.err,
				detail = strings.clone(icc_result.detail),
			}
		}

		switch icc_result.mode {
		case .Embed_Source:
			source_icc_ok: bool
			source_icc_path, source_icc_ok = make_process_temp_path(item.source_path, "source.icc")
			if !source_icc_ok {
				debug_log_errorf(
					"png ICC source temp path failed: source=\"%s\"",
					item.source_path,
				)
				delete(output_path)
				return Process_Image_Result{err = .Temp_Path_Failed}
			}
			debug_log_debugf("png source ICC temp: \"%s\"", source_icc_path)

			command := build_icc_extract_command(
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
			expected_icc_profile = source_icc_path
			expected_icc_exact = true
		case .Convert_To_Srgb:
			convert_icc_path = runtime_env.srgb_profile
			embed_icc_path = runtime_env.srgb_profile
		case .None:
		}
	}

	resize_command := build_png_magick_resize_command(
		runtime_env.magick_path,
		item.source_path,
		config.max_dimension,
		convert_icc_path,
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
		debug_log_errorf("png resized output missing or empty: \"%s\"", resized_path)
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
		debug_log_errorf("png quant output missing or empty: \"%s\"", quant_path)
		delete(output_path)
		return Process_Image_Result {
			err = .Empty_Output,
			detail = strings.clone("pngquant did not produce a quantized PNG."),
		}
	}

	oxipng_input_path := quant_path
	if config.png.preserve_profiles {
		profiled_quant_ok: bool
		profiled_quant_path, profiled_quant_ok = make_process_temp_path(
			item.source_path,
			"profiled.png",
		)
		if !profiled_quant_ok {
			debug_log_errorf(
				"png profiled quant temp path failed: source=\"%s\"",
				item.source_path,
			)
			delete(output_path)
			return Process_Image_Result{err = .Temp_Path_Failed}
		}
		debug_log_debugf("png profiled quant temp: \"%s\"", profiled_quant_path)

		profile_command := build_png_profile_command(
			runtime_env.magick_path,
			quant_path,
			embed_icc_path,
			profiled_quant_path,
		)
		if detail, ok := run_tool(
			profile_command,
			imagemagick_process_environment(runtime_env),
			"ImageMagick PNG ICC embed",
		); !ok {
			delete(output_path)
			return Process_Image_Result{err = .Icc_Embed_Failed, detail = detail}
		}
		if !file_is_non_empty(profiled_quant_path) {
			debug_log_errorf("png profiled output missing or empty: \"%s\"", profiled_quant_path)
			delete(output_path)
			return Process_Image_Result {
				err = .Empty_Output,
				detail = strings.clone("ImageMagick did not produce a profiled PNG."),
			}
		}
		oxipng_input_path = profiled_quant_path
	}

	oxipng_command := build_oxipng_command(
		runtime_env.oxipng_path,
		config.png,
		output_path,
		oxipng_input_path,
		runtime_env.worker_count,
	)
	if detail, ok := run_tool(oxipng_command, nil, "Oxipng"); !ok {
		remove_if_exists(output_path)
		delete(output_path)
		return Process_Image_Result{err = .Oxipng_Failed, detail = detail}
	}
	if !file_is_non_empty(output_path) {
		remove_if_exists(output_path)
		debug_log_errorf("png optimized output missing or empty: \"%s\"", output_path)
		delete(output_path)
		return Process_Image_Result {
			err = .Empty_Output,
			detail = strings.clone("Oxipng did not produce an optimized PNG."),
		}
	}

	if config.png.preserve_profiles {
		if detail, ok := verify_png_icc_profile(
			runtime_env.magick_path,
			output_path,
			expected_icc_profile,
			expected_icc_exact,
			runtime_env,
		); !ok {
			remove_if_exists(output_path)
			debug_log_errorf(
				"png ICC verification failed: output=\"%s\" detail=\"%s\"",
				output_path,
				detail,
			)
			delete(output_path)
			return Process_Image_Result{err = .Icc_Verify_Failed, detail = detail}
		}
	}

	debug_log_infof("png pipeline produced temp output: \"%s\"", output_path)
	return Process_Image_Result{output_path = output_path}
}

Icc_Profile_Result :: struct {
	mode:   Icc_Profile_Mode,
	err:    Image_Process_Error,
	detail: string,
}

destroy_icc_profile_result :: proc(result: ^Icc_Profile_Result) {
	delete(result.detail)
	result^ = {}
}

determine_icc_profile_mode :: proc(
	source_path: string,
	runtime_env: Runtime_Environment,
) -> Icc_Profile_Result {
	command := build_icc_identify_command(runtime_env.magick_path, source_path)
	state, stdout, stderr, err := process_exec_logged(
		command,
		imagemagick_process_environment(runtime_env),
		"ImageMagick ICC identify",
	)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil || !state.exited || state.exit_code != 0 {
		return Icc_Profile_Result {
			err = .Identify_Failed,
			detail = tool_failure_detail("ImageMagick ICC identify", state, stderr, err),
		}
	}

	if len(stdout) > 0 && icc_profile_family_is_retained(string(stdout)) {
		debug_log_infof("ICC profile retained: source=\"%s\"", source_path)
		return Icc_Profile_Result{mode = .Embed_Source}
	}
	debug_log_infof("ICC profile requires sRGB conversion: source=\"%s\"", source_path)
	return Icc_Profile_Result{mode = .Convert_To_Srgb}
}

make_process_temp_path :: proc(source_path, suffix: string) -> (string, bool) {
	pid := os.get_pid()
	for attempt in 0 ..< 1024 {
		counter := sync.atomic_add(&process_temp_counter, 1) + 1
		candidate := fmt.aprintf("%s.imgoptz.%d.%d.%s", source_path, pid, counter, suffix)
		if !os.exists(candidate) {
			debug_log_debugf(
				"temp path created: source=\"%s\" suffix=%s path=\"%s\"",
				source_path,
				suffix,
				candidate,
			)
			return candidate, true
		}
		debug_log_debugf("temp path collision: \"%s\"", candidate)
		delete(candidate)
		_ = attempt
	}
	debug_log_errorf("temp path creation exhausted: source=\"%s\" suffix=%s", source_path, suffix)
	return "", false
}

build_icc_identify_command :: proc(magick_path, source_path: string) -> []string {
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

build_icc_extract_command :: proc(magick_path, source_path, output_path: string) -> []string {
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
	convert_profile_path: string,
	output_path: string,
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
	append(&command, "--")
	append(&command, input_path)
	return command[:]
}

build_png_profile_command :: proc(
	magick_path, input_path, icc_path, output_path: string,
) -> []string {
	command: [dynamic]string
	command.allocator = context.temp_allocator
	append(&command, magick_path)
	append(&command, input_path)
	append(&command, "-profile")
	append(&command, icc_path)
	append(&command, output_path)
	return command[:]
}

verify_png_icc_profile :: proc(
	magick_path, output_path, expected_profile: string,
	exact_match: bool,
	runtime_env: Runtime_Environment,
) -> (
	string,
	bool,
) {
	command := build_icc_identify_command(magick_path, output_path)
	state, stdout, stderr, err := process_exec_logged(
		command,
		imagemagick_process_environment(runtime_env),
		"ImageMagick PNG ICC verify",
	)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil || !state.exited || state.exit_code != 0 {
		return tool_failure_detail("ImageMagick PNG ICC verify", state, stderr, err), false
	}
	if len(stdout) == 0 {
		return strings.clone("Optimized PNG is missing the expected ICC profile."), false
	}

	profile_text := string(stdout)
	if exact_match {
		if len(expected_profile) == 0 {
			return strings.clone("Optimized PNG did not preserve the source ICC profile."), false
		}

		actual_profile_path, actual_profile_ok := make_process_temp_path(output_path, "verify.icc")
		if !actual_profile_ok {
			return strings.clone("Failed to create temporary ICC verification path."), false
		}
		defer cleanup_temp_path_slot(&actual_profile_path)

		extract_command := build_icc_extract_command(magick_path, output_path, actual_profile_path)
		extract_state, extract_stdout, extract_stderr, extract_err := process_exec_logged(
			extract_command,
			imagemagick_process_environment(runtime_env),
			"ImageMagick PNG ICC extract",
		)
		defer delete(extract_stdout)
		defer delete(extract_stderr)
		if extract_err != nil || !extract_state.exited || extract_state.exit_code != 0 {
			return tool_failure_detail(
					"ImageMagick PNG ICC extract",
					extract_state,
					extract_stderr,
					extract_err,
				),
				false
		}
		if !files_have_same_contents(expected_profile, actual_profile_path) {
			return strings.clone("Optimized PNG did not preserve the source ICC profile."), false
		}
		return "", true
	}
	if !icc_profile_family_is_retained(profile_text) {
		return strings.clone("Optimized PNG does not contain an sRGB/P3 ICC profile."), false
	}
	return "", true
}

build_oxipng_command :: proc(
	oxipng_path: string,
	png: Png_Config,
	output_path, input_path: string,
	app_worker_count: int = 1,
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
	if app_worker_count > 1 {
		append(&command, "--threads")
		append(&command, "1")
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
	append(
		&environment,
		fmt.tprintf("MAGICK_THREAD_LIMIT=%s", imagemagick_thread_limit(runtime_env)),
	)
	if runtime_env.magick_use_gpu {
		append(&environment, "MAGICK_OCL_DEVICE=GPU")
	}
	return environment[:]
}

imagemagick_thread_limit :: proc(runtime_env: Runtime_Environment) -> string {
	if runtime_env.worker_count > 1 {
		return IMAGE_PROCESS_MAGICK_THREAD_LIMIT_MULTI_WORKER
	}
	return IMAGE_PROCESS_MAGICK_THREAD_LIMIT_SINGLE_WORKER
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
	state, stdout, stderr, err := process_exec_logged(command, environment, label)
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

icc_profile_family_is_retained :: proc(profile_text: string) -> bool {
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

file_size_by_path :: proc(path: string) -> (i64, bool) {
	file, open_err := os.open(path)
	if open_err != nil {
		return 0, false
	}
	defer os.close(file)

	size, size_err := os.file_size(file)
	if size_err != nil {
		return 0, false
	}
	return size, true
}

files_have_same_contents :: proc(a_path, b_path: string) -> bool {
	a, a_err := os.read_entire_file(a_path, context.allocator)
	if a_err != nil {
		return false
	}
	defer delete(a)

	b, b_err := os.read_entire_file(b_path, context.allocator)
	if b_err != nil {
		return false
	}
	defer delete(b)

	if len(a) != len(b) {
		return false
	}
	for value, index in a {
		if value != b[index] {
			return false
		}
	}
	return true
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
		return "Image type is disabled by config"
	case .Temp_Path_Failed:
		return "Failed to create temporary file path"
	case .Identify_Failed:
		return "Failed to inspect ICC profile"
	case .Icc_Extract_Failed:
		return "Failed to extract ICC profile"
	case .Icc_Embed_Failed:
		return "Failed to embed PNG ICC profile"
	case .Icc_Verify_Failed:
		return "Failed to verify PNG ICC profile"
	case .Magick_Failed:
		return "ImageMagick resize/orientation failed"
	case .Mozjpeg_Failed:
		return "MozJPEG compression failed"
	case .Pngquant_Failed:
		return "pngquant compression failed"
	case .Oxipng_Failed:
		return "Oxipng optimization failed"
	case .Empty_Output:
		return "Optimized output was empty"
	case .Size_Read_Failed:
		return "Failed to compare output size"
	case .Optimized_Not_Smaller:
		return "Optimized output was not smaller"
	case .Final_Path_Failed:
		return "Failed to plan final output path"
	case .Replace_Failed:
		return "Failed to safely replace original"
	case .Copy_Failed:
		return "Failed to write optimized output"
	}
	return "Image processing failed"
}
