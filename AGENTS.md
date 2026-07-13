# AGENTS.md

## Sources Of Truth
- Read `PLAN.md` before changing behavior; it is the product spec and implementation sequence.
- Root app code is Odin in `src/`; `mozjpeg/` and `oxipng/` are git submodules/vendor sources, not the app implementation.
- `dist/` is ignored but is the current development distribution root with `imgoptz.exe` and runtime tools.

## Commands
- Production build exactly with `./build.sh`, which runs `odin build src -out:dist/imgoptz.exe -target:windows_amd64 -subsystem:console -o:speed -strict-style -vet -vet-packages:main -vet-unused-procedures -vet-tabs -disallow-do -warnings-as-errors`.
- Development build with `./build_dev.sh`, which emits `dist/imgoptz_dev.exe` with `-debug` so the debug memory tracker is active.
- Run with `./run.sh`; it builds via `./build_dev.sh`, then launches `./dist/imgoptz_dev.exe`.
- Run Odin tests with `odin test src`; focused runs use `-define:ODIN_TEST_NAMES=package.test_name`.
- Before handing back code changes, run `odin test src`, a production build, and a development build.
- For memory leak checks, run the development executable through at least an `exit` prompt path. If it prints `=== N allocations not freed: ===`, treat that as a failure and fix the leak before handoff. No leak report means the app-level debug tracker found no outstanding allocations.
- Odin's test runner has its own memory tracking enabled by default; investigate any memory diagnostics it prints before considering tests passing.

## Branch Flow
- `main`: stable baseline.
- `develop`: integration branch for accepted task tracker and approved feature work.
- Feature branches: branch from `develop`, use `feat/<short-name>` because Git ref names cannot contain `:`.
- Merge back to `develop` only after review and explicit approval.

## Runtime Contract
- This is Windows-only; keep the `when ODIN_OS != .Windows` guard and console-subsystem, double-click flow.
- Preserve the prompt loop UI: users paste one directory path, processing finishes, then the app prompts again; `exit` closes it.
- At startup, change cwd to the executable directory. All relative paths, config, logs, tools, and default output resolve against that app root.
- Required runtime tool paths are `tools\mozjpeg\mozjpeg.exe`, `tools\oxipng\oxipng.exe`, and `tools\imagemagick\magick.exe` under the app root.
- Keep third-party notices beside tools: MozJPEG `LICENSE.md`, `README.ijg`, `README-mozilla.txt`; Oxipng `LICENSE`; ImageMagick `LICENSE.txt`, `NOTICE.txt`, `policy.xml`.
- Accept only JPEG/PNG extensions case-insensitively: `.jpg`, `.jpeg`, `.png`; default discovery is non-recursive.

## Implementation Pitfalls
- Do not replace the stdin console workflow with a GUI, command-line batch mode, watcher, or multi-directory interface.
- Strip surrounding quotes from pasted paths and handle whitespace, Unicode, `&`, parentheses, and other Windows shell-special characters.
- Start child tools with argument arrays where possible; avoid shell-concatenated commands. If `cmd.exe` is unavoidable, quote Windows paths deliberately.
- JPEG pipeline: ImageMagick should resize/orient to `ppm:-` and pipe stdout into MozJPEG stdin; MozJPEG writes a temp `.jpg` first.
- PNG pipeline: ImageMagick writes a temp resized PNG, then Oxipng writes a temp optimized PNG.
- Never overwrite originals directly. Compare temp output size first; replace/copy only when smaller, then slugify successful final names.
- `output_mode` accepts only `in-place` and `dir`; do not normalize `inplace` or other spellings.
- `gpu` accepts only JSON booleans. If true, probe ImageMagick OpenCL first, then set `MAGICK_OCL_DEVICE=GPU` only for child processes after a successful probe.
- Avoid oversubscription when worker pool is added: limit ImageMagick threads and pass `oxipng --threads 1` when app-level workers are greater than 1.

## Odin Conventions For This Repo
- `src/` is one directory-based package; every `.odin` file there must use `package main`.
- Prefer a single package while features are still coupled. New subpackages must be independent because Odin forbids cyclic imports.
- Split source by feature/responsibility within `src/` instead of growing `main.odin` into a catch-all file.
- Keep `main.odin` limited to startup orchestration. Move input parsing, validation, processing, config, tool probing, discovery, and output behavior into focused files as those responsibilities appear.
- Each procedure should either orchestrate a small flow or do exactly one job. Do not mix user interaction, validation, filesystem work, and processing decisions in one procedure.
- Extract reusable business logic into pure or low-side-effect procedures where practical, so it can be tested without console I/O or child processes.
- Follow the enforced Odin style: tabs for indentation, opening braces at end of line, `Ada_Case` types, `snake_case` procedures/values, `SCREAMING_SNAKE_CASE` constants.
- Prefer `value := Type { ... }` initializers and type inference unless the explicit type clarifies conversion or allocation lifetime.
- Procedures that allocate returned memory should take `allocator := context.allocator`; use `context.temp_allocator` for short-lived intermediate strings/data and clone only durable results.
- Use `defer` for real cleanup paths with multiple exits, but avoid scattering it where linear cleanup is clearer.
