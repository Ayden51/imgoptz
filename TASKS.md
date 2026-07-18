# imgoptz Task Tracker

Source of truth: `PLAN.md`. Keep this tracker aligned with the spec before changing behavior.

## Phase 0: Diagnostics Foundation

Goal: establish leak tracking and unified console logging before feature work grows.

- [x] Add Odin debug memory tracking directly in `src/main.odin`.
- [x] Report outstanding tracked allocations on app exit during debug builds.
- [x] Keep memory tracker code in `main.odin`; do not move it to a module because it does not compose reliably with logging setup.
- [x] Initialize Odin `core:log` console logging at startup.
- [x] Standardize user-facing console output through the logging API.
- [x] Destroy the logger before reporting tracked allocations so logger internals do not appear as leaks.
- [x] Run unit tests with Odin's test runner.
- [x] Run a debug executable smoke test and check memory tracker output for leaks.

## Phase 1: Console Input Foundation

Goal: turn the launcher demo into the real prompt shell without image processing yet.

- [x] Replace demo banner with `== imgoptz ==` and print working directory.
- [x] Preserve Windows-only startup guard.
- [x] Preserve startup cwd change to the executable directory.
- [x] Preserve repeated stdin prompt loop.
- [x] Add case-insensitive `exit` handling after trimming input.
- [x] Trim pasted input whitespace.
- [x] Strip one pair of surrounding double quotes from pasted paths.
- [x] Validate that exactly one non-empty directory path was provided.
- [x] Accept absolute and relative input paths, resolved from the app root cwd.
- [x] Remove demo `cmd.exe /c dir` child process execution.
- [x] Print clear errors and return to the prompt without exiting.
- [x] Verify spaces, Unicode, `&`, and parentheses in directory names.
- [x] Verify relative paths, absolute paths, quoted paths, empty input, file input, missing directory, EOF, and `exit`.

## Phase 2: Config Defaults And Parsing

Goal: add typed runtime settings while preserving default behavior.

- [x] Add config data model with built-in defaults from `PLAN.md`.
- [x] Update defaults for the selected JPEG pipeline: quality 78, quant table 2, `tune = "ms-ssim"`, and ICC profile preservation.
- [x] Update defaults for the selected PNG pipeline: pngquant quality/speed/dither plus Oxipng level/interlace/strip/alpha.
- [x] Load only `imgoptz.json` from app root when present.
- [x] Warn and use full defaults for invalid JSON.
- [x] Warn for unknown options and ignore them.
- [x] Validate individual option values and fall back per option.
- [x] Enforce `gpu` as JSON boolean only.
- [x] Enforce `output_mode` as `in-place` or `dir` only.
- [x] Enforce `workers` as `auto` or positive integer.
- [x] Validate JPEG `quality`, `sample`, `quant_table`, `tune`, and `preserve_profiles`.
- [x] Validate PNG `pngquant_quality`, `pngquant_speed`, `pngquant_dither`, `oxipng_level`, `interlace`, `strip`, and `alpha`.
- [x] Print active config summary at startup.
- [x] Verify missing, invalid, partial, unknown, and invalid-value configs.

## Phase 3: Runtime Environment Validation

Goal: fail early when the app distribution is incomplete.

- [ ] Validate `tools\mozjpeg\mozjpeg.exe`.
- [ ] Validate `tools\oxipng\oxipng.exe`.
- [ ] Validate `tools\pngquant\pngquant.exe`.
- [ ] Validate `tools\imagemagick\magick.exe`.
- [ ] Validate `profiles\sRGB2014.icc`.
- [ ] Validate required third-party notice files beside each tool.
- [ ] Resolve `out_dir` according to app root rules.
- [ ] Implement `dir` output root fallback warnings.
- [ ] Error if the accepted `dir` output root does not exist.
- [ ] Probe ImageMagick OpenCL only when `gpu = true`.
- [ ] Set `MAGICK_OCL_DEVICE=GPU` only after a successful probe.
- [ ] Verify missing tools, missing notices, GPU false, GPU probe success, and GPU probe failure.

## Phase 4: Discovery And Output Planning

Goal: enumerate work safely before optimization starts.

- [ ] Discover only `.jpg`, `.jpeg`, and `.png`, case-insensitively.
- [ ] Keep discovery non-recursive by default.
- [ ] Add recursive discovery controlled by config.
- [ ] Count JPEG and PNG files separately for console output.
- [ ] Plan destination paths for `in-place` mode.
- [ ] Plan destination paths for `dir` mode.
- [ ] Preserve relative paths for recursive `dir` output mode.
- [ ] Verify uppercase extensions, ignored files, empty folders, recursive folders, and preserved relative paths.

## Phase 5: Single-File Processing Pipelines

Goal: process one image at a time correctly and safely.

- [ ] Generate collision-resistant temp file names.
- [ ] Implement JPEG ImageMagick-to-MozJPEG pipeline.
- [ ] Implement JPEG ICC profile retention/conversion and `*.source.icc` cleanup.
- [ ] Implement PNG ImageMagick-to-temp plus pngquant plus Oxipng pipeline.
- [ ] Pass child process arguments as arrays, not shell-concatenated commands.
- [ ] Apply ImageMagick resize/orientation rules.
- [ ] Map JPEG config to MozJPEG flags.
- [ ] Map PNG config to pngquant and Oxipng flags.
- [ ] Limit child tool threads where needed for later worker scaling.
- [ ] Verify valid JPEG, valid PNG, corrupt inputs, command failures, and temp cleanup.

## Phase 6: Safe Outputs

Goal: write optimized results only when smaller.

- [ ] Compare temp optimized size against original size.
- [ ] Skip and delete temp files when output is not smaller.
- [ ] Safely replace originals for `in-place` mode.
- [ ] Copy/move optimized files into accepted output root for `dir` mode.
- [ ] Add slugify final output names after optimization.
- [ ] Preserve lowercase image extensions for final names.
- [ ] Resolve slugify name collisions per destination directory.
- [ ] Verify smaller output, larger output, replace failure, copy failure, slugify Unicode, and collisions.

## Phase 7: Parallel Processing And Reporting

Goal: process folders efficiently without oversubscribing tools.

- [ ] Add worker pool.
- [ ] Implement `workers = auto` heuristic.
- [ ] Clamp explicit worker counts to a safe minimum of 1.
- [ ] Limit ImageMagick thread count for child processes.
- [ ] Pass `oxipng --threads 1` when app-level workers exceed 1.
- [ ] Print per-file progress with status, output path, sizes, and percent reduction.
- [ ] Print final succeeded/skipped/failed summary.
- [ ] Preserve deterministic, readable console output under parallel work.
- [ ] Verify worker counts on low/high CPU machines where practical and repeated prompt loop after processing.

## Phase 8: Debug Logging And Release Hardening

Goal: finish operator diagnostics and broad edge-case coverage.

- [ ] Add optional debug logging controlled by config.
- [ ] Resolve relative `debug_log_file` against app root.
- [ ] Append detailed child process and decision logs when enabled.
- [ ] Keep normal operation console-only.
- [ ] Run full manual matrix from `PLAN.md` implementation phases 20-30.
- [ ] Re-run `./build.sh` with warnings as errors.
- [ ] Document any remaining operational constraints.

## Current Feature Selection

- Current feature branch: `feat/config-defaults-parsing`.
- Scope: Phase 2 only.
- Reason: later runtime validation, discovery, and processing depend on typed config values and predictable fallback behavior.
