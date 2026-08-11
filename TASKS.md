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

## Phase 6A: PNG ICC Profile Preservation

Goal: preserve PNG color profiles through optimization without duplicating JPEG ICC decision logic.

- [x] Add `png.preserve_profiles` config defaulting to `true`.
- [x] Validate `png.preserve_profiles` as a JSON boolean.
- [x] Update default config, `dist/imgoptz.json`, and config tests for `png.preserve_profiles`.
- [x] Reject or fall back from PNG strip settings that remove color-management chunks while `png.preserve_profiles = true`.
- [x] Extract shared ICC profile-family detection from the current JPEG-specific helper.
- [x] Extract shared preserve-vs-convert ICC decision logic that both JPEG and PNG pipelines can call.
- [x] Keep format-specific profile extraction, embedding, and verification in JPEG/PNG pipeline code.
- [x] Remove `pngquant --strip` from the default PNG command path.
- [x] Preserve or convert PNG ICC profiles through ImageMagick, pngquant, and Oxipng according to `PLAN.md`.
- [x] Verify optimized temp PNGs still contain the expected profile before final output handling.
- [x] Update PNG command tests so pngquant does not include `--strip` and Oxipng still receives the configured strip mode.
- [x] Add tests for PNG ICC retention/conversion through the optimized temp output.

## Phase 6B: Enhanced Progress Size Output

Goal: make successful progress rows show the size win without adding noisy output-path details.

- [x] Carry original size, optimized size, and percentage reduction through successful finalization results.
- [x] Print success progress rows as `<original size> -> <optimized size> (<negative percent>%)`.
- [x] Do not print final or slugified output paths as indented progress detail rows.
- [x] Add progress output tests for size formatting and omitted output-path detail rows.

## Phase 7: Parallel Processing And Reporting

Goal: process folders efficiently without oversubscribing tools.

- [x] Add worker pool.
- [x] Implement `workers = auto` heuristic.
- [x] Clamp explicit worker counts to a safe minimum of 1.
- [x] Revisit ImageMagick thread limit for app-level parallelism instead of adding per-file oversubscription.
- [x] Pass `oxipng --threads 1` when app-level workers exceed 1.
- [x] Preserve the established per-file progress format under parallel execution.
- [x] Preserve deterministic, readable console output under parallel work.
- [x] Print live progress activity while workers are running so the console does not stay blank until all images finish.
- [x] Print live worker completion rows as each temp optimization finishes, while keeping final result rows after all workers complete.
- [x] Notice for deterministic output task: discovery order follows OS directory enumeration; verify whether sorting discovered work items by relative path is needed before/while adding parallel reporting.
- [x] Verify worker counts on low/high CPU machines where practical.

## Phase 7A: TUI Refresh And Logging Split Contract

Goal: simplify the normal console UI and establish that future debug logging must not change console output.

- [x] Remove the right-side box from the ASCII startup banner.
- [x] Add blank-line padding above the banner.
- [x] Keep normal console output independent from debug logging.
- [x] Remove the normal-flow `>_ APP SETTINGS` section.
- [x] Remove the standalone `>_ DISCOVERY` section.
- [x] Merge valid path feedback with discovery counts.
- [x] Replace emoji status glyphs with legacy-console-friendly markers: `√`, `X`, `?`, `-`, and `!`.
- [x] Rework normal progress output to one success, skip, or failure row per image.
- [x] Print per-image result rows in the order files finish.
- [x] Rework summary output to compact `Files:` and `Saved:` rows with elapsed time.
- [x] Add tests for compact progress rows and summary reduction.

## Phase 8: Debug Logging

Goal: finish operator diagnostics without changing the normal console UI.

- [x] Add optional debug logging controlled by config.
- [x] Resolve relative `debug_log_file` against app root.
- [x] Use Odin `core:log` file logging so existing user-facing logging calls can remain largely untouched.
- [x] Keep console output in the existing structured UI format without log-level prefixes.
- [x] Write log level and date/time on every debug log file entry.
- [x] Write each app run to a new datetime-prefixed debug log file instead of appending multiple runs into one file.
- [x] Write detailed child process and decision logs when enabled.
- [x] Organize debug file output with readable block structure matching the existing app/input/discovery/progress/summary sections where practical.
- [x] Log app state transitions, parsed inputs, child process argument arrays, relevant environment overrides, exit state, stdout, and stderr when debug logging is enabled.
- [x] Keep normal operation console-only.

## Phase 8A: JPEG Unicode Temp Workspace

Goal: keep JPEG optimization working for Unicode input paths even when MozJPEG cannot open non-ASCII Windows paths.

- [x] Create one per-run temp workspace for JPEG-only processing artifacts.
- [x] Use generated ASCII filenames in the workspace for MozJPEG-visible artifacts, including `source.icc`, copied `sRGB2014.icc`, and optimized JPEG temp outputs.
- [x] Copy the bundled `profiles\sRGB2014.icc` into the JPEG temp workspace before passing it to MozJPEG.
- [x] Extract retained source JPEG ICC profiles into the JPEG temp workspace instead of beside the source image.
- [x] Change the JPEG resize/compress handoff to `ppm:-`, piping ImageMagick stdout directly into MozJPEG stdin instead of writing a resized PPM temp file.
- [x] Avoid failing the whole JPEG pipeline solely because MozJPEG cannot open a temp ICC path; log the ICC failure, omit `-icc`, and continue compression without the embedded final ICC profile.
- [x] Stage/copy accepted optimized JPEGs back beside the original before final replacement so `in-place` replacement keeps the existing preserve-original safety behavior.
- [x] Keep PNG processing temp behavior unchanged in this phase.
- [x] Verify JPEG Unicode source paths, retained ICC paths, sRGB conversion paths, ICC omission fallback, temp cleanup, and final in-place replacement.

## Phase 9: Dry-Run Approval Mode

Goal: make optimization preview-first and require explicit approval before final writes by default.

- [x] Add `dry_run` config as a JSON boolean defaulting to `true`.
- [x] In dry-run mode, run resize and optimization to temp files, then reject outputs that are not smaller before asking for approval.
- [x] Keep successful temp optimized files available for finalization after approval.
- [x] Prompt users to approve saving optimized files after dry-run results.
- [x] Accept `y` exactly and `yes` case-insensitively as approval.
- [x] Accept `N` exactly and `no` case-insensitively as decline.
- [x] Treat empty approval input as invalid and re-prompt.
- [x] Treat other approval input as invalid and re-prompt.
- [x] On approval, finalize only successful dry-run temp outputs.
- [x] On decline, delete all temp artifacts and write nothing.
- [x] When `dry_run = false`, skip approval and finalize successful temp outputs immediately.
- [x] Update `dist/imgoptz.json` so the development distribution includes the new `dry_run` default.
- [x] Add tests for `dry_run` default config, approval parsing, approval finalization, decline cleanup, and no-prompt non-dry-run finalization.

## Phase 10: Target-Relative Output Directory Defaults

Goal: make default `dir` output non-destructive and relative to the user's accepted input directory.

- [x] Change the built-in default `output_mode` to `dir` in this phase.
- [x] Change the built-in default `out_dir` to `~/imgoptz-output` in this phase.
- [x] Update `dist/imgoptz.json` so the development distribution matches the new output defaults.
- [x] Resolve `~/...` output paths relative to the accepted user input directory.
- [x] Keep absolute `out_dir` paths resolved and existence-checked at startup.
- [x] Keep app-root-relative `out_dir` paths resolved and existence-checked at startup.
- [x] Warn and fall back to `~/imgoptz-output` when an absolute or app-root-relative configured output root is missing.
- [x] Skip startup existence checks for target-relative `~/...` output roots.
- [x] Do not create output roots during discovery.
- [x] Auto-create target-relative output folders only immediately before writing final output files.
- [x] Add tests for target-relative output resolution, fallback behavior, delayed directory creation, and updated output defaults.

## Phase 10A: Dependency Setup And Bundling

Goal: make the distributable runtime reproducible from pinned official dependency inputs instead of relying on checked-out vendor source folders.

- [x] Add a pinned dependency manifest for ImageMagick, MozJPEG, Oxipng, pngquant, and `sRGB2014.icc`.
- [x] Add `scripts/setup_dist_deps.ps1` to download dependencies, verify SHA-256 checksums, extract or build as required, and copy only required runtime files into `dist/`.
- [x] Verify installed dependency versions with `magick.exe -version`, `mozjpeg.exe -version`, `oxipng.exe --version`, and `pngquant.exe --version`.
- [x] Bundle ImageMagick `7.1.2-29` portable Q16-HDRI x64 with `LICENSE.txt`, `NOTICE.txt`, `colors.xml`, and `policy.xml`.
- [x] Bundle Oxipng `10.1.1` from the official Windows release with `LICENSE`.
- [x] Bundle pngquant `3.0.3` from crates.io source with `COPYRIGHT` and `SOURCE.txt` documenting exact corresponding source for GPL compliance.
- [x] Bundle ICC `sRGB2014.icc` from the ICC registry with `sRGB2014.LICENSE.txt` and verify SHA-256 `384B832DE3412066743B52A75EE906B6FB9FB8D9E09E936FC2C43223815C6E0A`.
- [x] Bundle MozJPEG from the official `v4.1.5` source tag by building `cjpeg-static.exe`, copying it as `tools\mozjpeg\mozjpeg.exe`, and bundling `LICENSE.md`, `README.ijg`, and `README-mozilla.txt` from the same source.
- [x] Add `scripts/bundle_dist.ps1` to build `dist/imgoptz.exe`, call setup when required files are missing, validate the complete runtime layout, and package from local `dist/` only.
- [x] Remove `mozjpeg/` and `oxipng/` submodules only after setup can reproduce the required runtime binaries from pinned inputs.
- [x] Document the dependency update policy: maintainer-only version bumps, checksum refresh, compatibility testing, license/source review, docs update, and app version update.
- [x] Verify setup and bundling from a clean `dist/` dependency state.
- [x] Fail early with clear setup errors when required MozJPEG/pngquant build tooling is missing before downloading or building dependencies.

## Phase 10B: Script Entrypoint Unification

Goal: replace shell-specific script implementations with a registered Odin CLI launcher that works from common Windows developer shells.

- [x] Research uv-style shell dispatch and reject it for this repo in favor of an Odin launcher because contributors already require Odin.
- [x] Add `scripts/main.odin` as the launcher entrypoint, built locally as `scripts.exe`.
- [x] Add startup self-registration so each script lives in one `.odin` file under `scripts/` and registers its enabled/disabled descriptor with the launcher.
- [x] Register local development scripts for `dev`, `build`, `preview`, and `test`.
- [x] Use standard script names `setup` for pinned dependency installation and `package` for distributable archives.
- [x] Port legacy dependency setup behavior into exactly one Odin `setup` file.
- [x] Port legacy packaging behavior into exactly one Odin `package` file.
- [x] Remove legacy `.ps1` and `.sh` scripts only after their registered Odin replacements are fully verified.
- [x] Verify launcher behavior from PowerShell, `cmd.exe`, Git Bash, and bash-like environments where available.
- [x] Verify launcher behavior with repo paths containing spaces and special characters.
- [x] Update command documentation to point contributors at `scripts.exe` and the Odin bootstrap command.

## Phase 11: libvips Migration

Goal: replace ImageMagick with the official `vips-web` static prebuilt while preserving the current JPEG and PNG optimization behavior.

- [x] Update the pinned dependency manifest to download `vips-dev-x64-web-8.18.5-static.zip` from the official `build-win64-mxe` `v8.18.5` release and verify SHA-256 `109C23D6A71328D821AB5B08CB0212242EF7B7E038739F4E1F706B00BF990E10`.
- [x] Copy only required libvips runtime files into `dist/tools/libvips`: `vips.exe`, `vipsheader.exe`, required DLLs such as `libvips-42.dll`, `LICENSE`, `README.md`, and `versions.json`.
- [x] Keep using `tools\mozjpeg\mozjpeg.exe` as the external final JPEG encoder even though the upstream `vips-web` prebuilt includes MozJPEG internally.
- [x] Reject `vips-all` and any libvips package that includes ImageMagick/MagickCore, Ghostscript/gslib, Poppler/PDFium, PDF/PS/EPS/XPS, FFTW GPL, OpenEXR, JPEG XL, OpenJPEG, or RAW camera support.
- [x] Accept that the official `vips-web` prebuilt includes web-oriented features such as SVG, HEIF/AVIF, WebP, TIFF, UHDR, text/font rendering, and MozJPEG, because the app still discovers only JPEG/PNG and uses libvips only as a child process for resize/profile handling.
- [x] Replace runtime validation for `tools\imagemagick\magick.exe` with validation for `tools\libvips\vips.exe`, `tools\libvips\vipsheader.exe`, libvips runtime DLLs, libvips notices, and `versions.json`.
- [x] Verify `vips --vips-config`, `vips -l foreign`, and `vips rawsave --help-operation` prove the expected runtime surface before packaging; do not require PPM save support because the selected prebuilt reports PPM disabled.
- [x] Replace ImageMagick ICC identification/extraction with `vipsheader -f icc-profile-data`, decode the base64 ICC bytes, and write temp workspace `.icc` sidecars like the current pipeline.
- [x] Replace JPEG resize/orient with libvips raw RGB stdout output, prepend the PPM header in the app, and pipe the resulting PPM stream directly into external MozJPEG stdin while preserving current MozJPEG flags and ICC embedding behavior.
- [x] Replace PNG resize/orient with libvips temp PNG output, keep pngquant unchanged, then embed the selected ICC into the quantized PNG with libvips before Oxipng.
- [x] Treat the legacy `gpu` config as a no-op compatibility setting in the libvips pipeline; remove ImageMagick OpenCL probing and `MAGICK_*` environment handling.
- [x] Update command construction tests and processing tests for libvips JPEG/PNG resize, ICC extraction/embedding, raw-to-PPM piping, temp cleanup, Unicode paths, and PNG ICC verification.
- [x] Run the mixed demo comparison against the current baseline and verify dimensions, ICC retention, and output-size behavior remain acceptable.
- [x] Remove ImageMagick from setup, packaging, distribution layout, docs, and required notice validation after libvips replacement tests pass.

## Phase 12: Dependency-Free App Distribution

Goal: ship only imgoptz-owned files in the app package and require users/developers to acquire dependency tools and usage rights separately.

- [x] Remove developer dependency setup automation and the pinned dependency manifest from `scripts/`.
- [x] Change `scripts.exe package` to build a dependency-free app zip containing only `imgoptz.exe`, `README.txt`, `LICENSE.txt`, `imgoptz.json`, and `schema/imgoptz.schema.json`.
- [x] Stop creating pngquant source-compliance release archives because imgoptz no longer distributes pngquant binaries.
- [x] Add `scripts/setup-imgoptz-deps.ps1` as a source-hosted end-user helper that downloads official prebuilt/static dependency packages, verifies SHA-256 checksums, and extracts them without build steps.
- [x] Switch runtime paths to official extracted dependency layouts, including MozJPEG `v4.0.3` `cjpeg-static.exe`, pngquant `2.17.0` from the official Windows zip, Oxipng's official Windows zip, and libvips `vips-dev-8.18`.
- [x] Update docs and plan so imgoptz's license covers only imgoptz app files and dependency rights remain the user's responsibility.

## Current Feature Selection

- Current feature branch: `fix/distribution-legal-compliance`.
- Scope: Phase 12 dependency-free distribution implementation.
- Reason: imgoptz should not distribute dependency tools, dependency notices, source packages, or the sRGB ICC profile. Users and developers must acquire dependency tools and rights separately.
