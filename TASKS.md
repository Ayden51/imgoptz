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

- [x] Validate `tools\mozjpeg\mozjpeg.exe`.
- [x] Validate `tools\oxipng\oxipng.exe`.
- [x] Validate `tools\pngquant\pngquant.exe`.
- [x] Validate `tools\imagemagick\magick.exe`.
- [x] Validate `profiles\sRGB2014.icc`.
- [x] Validate required third-party notice files beside each tool.
- [x] Resolve `out_dir` according to app root rules.
- [x] Implement `dir` output root fallback warnings.
- [x] Error if the accepted `dir` output root does not exist.
- [x] Probe ImageMagick OpenCL only when `gpu = true`.
- [x] Set `MAGICK_OCL_DEVICE=GPU` only after a successful probe.
- [x] Verify missing tools, missing notices, GPU false, GPU probe success, and GPU probe failure.

## Phase 4: Discovery And Output Planning

Goal: enumerate work safely before optimization starts.

- [x] Discover only `.jpg`, `.jpeg`, and `.png`, case-insensitively.
- [x] Keep discovery non-recursive by default.
- [x] Add recursive discovery controlled by config.
- [x] Count JPEG and PNG files separately for console output.
- [x] Plan destination paths for `in-place` mode.
- [x] Plan destination paths for `dir` mode.
- [x] Preserve relative paths for recursive `dir` output mode.
- [x] Verify uppercase extensions, ignored files, empty folders, recursive folders, and preserved relative paths.

## Phase 5: Single-File Processing Pipelines

Goal: process one image at a time correctly and safely.

- [x] Generate collision-resistant temp file names.
- [x] Implement JPEG ImageMagick-to-MozJPEG pipeline.
- [x] Implement JPEG ICC profile retention/conversion and `*.source.icc` cleanup.
- [x] Implement PNG ImageMagick-to-temp plus pngquant plus Oxipng pipeline.
- [x] Pass child process arguments as arrays, not shell-concatenated commands.
- [x] Apply ImageMagick resize/orientation rules.
- [x] Map JPEG config to MozJPEG flags.
- [x] Map PNG config to pngquant and Oxipng flags.
- [x] Limit child tool threads where needed for later worker scaling.
- [x] Verify valid JPEG, valid PNG, corrupt inputs, command failures, and temp cleanup.

## Phase 5A: PNG Quality Default Update

Goal: apply the selected lossy PNG quality default before safe output behavior changes make comparisons user-visible.

- [x] Change the built-in `png.pngquant_quality` default from `80-95` to `40-95`.
- [x] Update `dist/imgoptz.json` so the development distribution matches the spec default.
- [x] Update config fallback tests and PNG command tests that currently expect `80-95`.
- [x] Verify PNG config parsing, validation fallback, and command construction use `40-95` by default.

## Phase 5B: Structured Console UI

Goal: replace dense flat log-style output with readable console UI blocks before adding final output reporting.

- [x] Render the `Imgoptz` startup banner from `PLAN.md`.
- [x] Replace startup summary lines with the `>_ APP SETTINGS` block.
- [x] Replace prompt and accepted-directory output with the `>_ INPUT` block.
- [x] Replace discovery output with the `>_ DISCOVERY` block.
- [x] Replace per-file processing output with the `>_ PROGRESS` block and indented detail rows.
- [x] Replace completion warnings with the `>_ SUMMARY` block; do not emit a redundant warning block when failures are already summarized.
- [x] Keep normal console output free of `[INFO]`, `[WARN]`, and `[ERROR]` prefixes; reserve level prefixes for optional debug log files.
- [x] Verify the prompt loop remains line-based and works with `exit`, empty input, invalid paths, accepted paths, and repeated runs.

## Phase 6: Safe Outputs

Goal: write optimized results only when smaller.

- [x] Compare temp optimized size against original size.
- [x] Skip and delete temp files when output is not smaller.
- [x] Safely replace originals for `in-place` mode.
- [x] Copy/move optimized files into accepted output root for `dir` mode.
- [x] Copy the existing Odin slugify script into this codebase before wiring final-name behavior.
- [x] Add slugify final output names after optimization.
- [x] Notice for slugify task: discovery currently plans `destination_path` before slugify/collision handling; verify Phase 6 treats it as a pre-slug destination and does not bypass final-name rules.
- [x] Preserve lowercase image extensions for final names.
- [x] Resolve slugify name collisions per destination directory.
- [x] Verify smaller output, larger output, replace failure, copy failure, slugify Unicode, and collisions.

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
- [ ] Notice for deterministic output task: discovery order follows OS directory enumeration; verify whether sorting discovered work items by relative path is needed before/while adding parallel reporting.
- [ ] Verify worker counts on low/high CPU machines where practical and repeated prompt loop after processing.

## Phase 8: Debug Logging And Release Hardening

Goal: finish operator diagnostics and broad edge-case coverage.

- [ ] Add optional debug logging controlled by config.
- [ ] Resolve relative `debug_log_file` against app root.
- [ ] Append detailed child process and decision logs when enabled.
- [ ] Keep normal operation console-only.
- [ ] Run full manual matrix from `PLAN.md` implementation phases 23-33.
- [ ] Re-run `./scripts/build.ps1` with warnings as errors.
- [ ] Document any remaining operational constraints.

## Current Feature Selection

- Current feature branch: `feat/safe-outputs`.
- Scope: Phase 6 only.
- Reason: parallel processing and debug logging remain separated for later phases.
