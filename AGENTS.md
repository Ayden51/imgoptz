# AGENTS.md

## Sources Of Truth

- Read `PLAN.md` before changing behavior; it is the product spec and implementation sequence.
- Root app code is Odin in `src/`; `mozjpeg/` and `oxipng/` are git submodules/vendor sources, not the app implementation.
- `dist/` is ignored but is the current development distribution root with `imgoptz.exe` and locally acquired runtime tools.

## Commands

- Agent scripts live in `scripts/`; bootstrap the Odin launcher with `odin build scripts -out:scripts.exe -target:windows_amd64 -strict-style -vet -vet-tabs -warnings-as-errors` when `scripts.exe` is missing.
- Production build exactly with `./scripts.exe build`, which runs `odin build src -out:dist/imgoptz.exe -target:windows_amd64 -subsystem:console -o:speed -strict-style -vet -vet-packages:main -vet-unused-procedures -vet-tabs -disallow-do -warnings-as-errors`.
- Development run with `./scripts.exe dev`; it builds `dist/imgoptz_dev.exe` with `-debug` through the registered `dev` script, then launches it.
- Preview with `./scripts.exe preview`; it launches `./dist/imgoptz.exe` and requires `./scripts.exe build` to have run first.
- Run Odin tests with `odin test src`; focused runs use `-define:ODIN_TEST_NAMES=package.test_name`.
- Use `dist\demo\in-place` only for in-place mode testing and demoing.
- Use `dist\demo\out-dir` only as original-image fixtures and for `output_mode = "dir"` testing and demoing; never run in-place mode there.
- For out-dir local testing, the default output directory is `<app-root>\output`, which is `dist\output` in this workspace.
- Test discovery modes with their dedicated demo folders: `jpg`, `png`, `mixed`, and `recursive` exist under both `dist\demo\in-place` and `dist\demo\out-dir`.
- Before handing back code changes, run `odin test src`, `./scripts.exe build`, and `./scripts.exe dev` through at least an `exit` prompt path.
- For memory leak checks, run the development executable through at least an `exit` prompt path. If it prints `=== N allocations not freed: ===`, treat that as a failure and fix the leak before handoff. No leak report means the app-level debug tracker found no outstanding allocations.
- Odin's test runner has its own memory tracking enabled by default; investigate any memory diagnostics it prints before considering tests passing.

## Branch Flow

- `main`: stable baseline.
- `develop`: integration branch for accepted task tracker and approved feature work.
- Agents must work in branch isolation for every user request that may change files.
- Before editing, check the current branch. If it is `develop` or `main`, do not edit there unless the user directly instructs you to do so.
- For normal work, create or use a request-specific `feat/<short-name>`, `fix/<short-name>`, or `release/<short-name>` branch based on `develop`.
- Use `hotfix/<short-name>` only for urgent critical bug fixes, and branch it from `main`.
- If already on a non-protected request branch, continue there only when it matches the current request; otherwise create a new isolated branch from the correct base.
- Git ref names cannot contain `:`, so use slash-prefixed names like `feat/<short-name>` instead.
- Merge back to `develop` only after review and explicit approval.

## Runtime Contract

- This is Windows-only; keep the `when ODIN_OS != .Windows` guard and console-subsystem, double-click flow.
- Preserve the prompt loop UI: users paste one directory path, processing finishes, then the app prompts again; `exit` closes it.
- At startup, change cwd to the executable directory. All relative paths, config, logs, tools, and default output resolve against that app root.
- Required runtime tool paths under the app root are `tools\mozjpeg\static\Release\cjpeg-static.exe`, `tools\oxipng-10.1.1-x86_64-pc-windows-msvc\oxipng.exe`, `tools\pngquant\pngquant.exe`, `tools\vips-dev-8.18\bin\vips.exe`, and `tools\vips-dev-8.18\bin\vipsheader.exe`.
- Redistribute `profiles\sRGB2014.icc` and its license inside the app release package. Do not distribute third-party tools, tool notices, tool source packages, or dependency setup helpers inside the app release package; users acquire dependency tool rights themselves. `scripts/setup.ps1` is a source-hosted end-user helper, not a developer setup script or release asset.
- Accept only JPEG/PNG extensions case-insensitively: `.jpg`, `.jpeg`, `.png`; default discovery is non-recursive.

## Implementation Pitfalls

- Do not replace the stdin console workflow with a GUI, command-line batch mode, watcher, or multi-directory interface.
- Strip surrounding quotes from pasted paths and handle whitespace, Unicode, `&`, parentheses, and other Windows shell-special characters.
- Start child tools with argument arrays where possible; avoid shell-concatenated commands. If `cmd.exe` is unavoidable, quote Windows paths deliberately.
- JPEG pipeline: libvips should resize/orient to raw RGB stdout; the app writes the PPM header and streams that into MozJPEG stdin; MozJPEG writes a temp `.jpg` first.
- PNG pipeline: libvips writes a temp resized/profiled PNG, pngquant quantizes it, then Oxipng writes a temp optimized PNG.
- Never overwrite originals directly. Compare temp output size first; replace/copy only when smaller, then slugify successful final names.
- `output_mode` accepts only `in-place` and `dir`; do not normalize `inplace` or other spellings.
- `gpu` accepts only JSON booleans. It is currently a no-op compatibility setting in the libvips pipeline.
- Avoid oversubscription when worker pool is added: set `VIPS_CONCURRENCY` and pass `oxipng --threads 1` when app-level workers are greater than 1.

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
