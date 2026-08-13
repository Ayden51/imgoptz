# imgoptz Implementation Plan

## Purpose

`imgoptz` is a Windows-only folder image optimizer. It optimizes one input directory at a time, supporting only JPEG and PNG files. Users launch `imgoptz.exe` by double-clicking it, which opens a console window, prompts for a directory path, processes supported images, prints results, then prompts again. Typing `exit` closes the program and the console window.

The current `src/main.odin` demo already proves the intended UI shape: Windows-only guard, change cwd to the executable directory, line-based stdin prompt loop, and child process execution with inherited console output. Build the real tool by expanding that structure, not replacing it with a different UI model.

## Distribution Layout

The distributed app root is the directory containing `imgoptz.exe`. The folder can have any name. All runtime paths are relative to that app root.

The release app package must contain only the imgoptz app files:

```text
<app-root>/
  imgoptz.exe
  README.txt
  LICENSE.txt
  imgoptz.json
  profiles/
    sRGB2014.icc
    sRGB2014.LICENSE.txt
  schema/
    imgoptz.schema.json
```

Do not include dependency tools, dependency notices, source packages, or dependency setup helpers in the app package. The only redistributed third-party runtime asset is `profiles/sRGB2014.icc`, with its license in `profiles/sRGB2014.LICENSE.txt`. That means no `tools/`, no pngquant source-compliance archive, and no third-party tool license aggregation inside the imgoptz release zip.

The app changes cwd to the executable directory at startup, so all relative paths resolve against `<app-root>/`.

After users acquire/install dependency tools, the runtime app root should have this layout. App-local tool folder names must match the tool name and may include a version suffix, such as `oxipng-10.1.1-x86_64-pc-windows-msvc` or `vips-dev-8.18`. The ICC profile is part of the release package:

```text
tools\mozjpeg\static\Release\cjpeg-static.exe
tools\oxipng[-version...]\oxipng.exe
tools\pngquant\pngquant.exe
tools\vips-dev[-version...]\bin\vips.exe
tools\vips-dev[-version...]\bin\vipsheader.exe
profiles\sRGB2014.icc
```

## License Files

The imgoptz release package includes the imgoptz app license in `LICENSE.txt` and the redistributed ICC profile license in `profiles/sRGB2014.LICENSE.txt`. The imgoptz license does not cover libvips, MozJPEG, pngquant, Oxipng, the sRGB ICC profile, or their transitive dependencies.

Users and developers are responsible for acquiring dependency tools themselves and confirming they have the right to use them. The optional dependency setup helper downloads official upstream tool files and extracts them without removing upstream notices, but those tool files are not distributed as part of imgoptz.

## Dependency Setup And Bundling

Runtime tools are not app source and are not release package contents. The tracked release assets `imgoptz.json`, `schema/imgoptz.schema.json`, `profiles/sRGB2014.icc`, and `profiles/sRGB2014.LICENSE.txt` must already be present in git. The release process builds only the exe, then validates and packages the required release files.

Use the Odin script launcher only for app build and packaging:

1. `scripts.exe package` builds `dist/imgoptz.exe`, validates the release package files, and creates the app zip.
2. Packaging must fail if any required release file is missing: `imgoptz.exe`, `README.txt`, `LICENSE.txt`, `imgoptz.json`, `profiles/sRGB2014.icc`, `profiles/sRGB2014.LICENSE.txt`, or `schema/imgoptz.schema.json`.
3. Packaging must not call a dependency setup script and must not create pngquant source-compliance archives, because imgoptz no longer distributes pngquant binaries.

The end-user helper is `scripts/setup.ps1` in the source repository. It is not part of the app zip and is not distributed as a GitHub Release asset. Users who choose the helper should download the source file from GitHub, place it in the extracted app folder, then run it there. It downloads official upstream tool files, verifies SHA-256 checksums, and extracts archives as-is. It does not download the ICC profile because that profile is already included in the app zip. It performs no build step and does not curate or relicense dependency tool contents.

The helper should verify these version commands after install:

```text
tools\vips-dev[-version...]\bin\vips.exe --version
tools\mozjpeg\static\Release\cjpeg-static.exe -version
tools\oxipng[-version...]\oxipng.exe --version
tools\pngquant\pngquant.exe --version
```

Initial pinned dependency targets:

```text
libvips      8.18.5 official x64 vips-web static prebuilt, SHA-256 109C23D6A71328D821AB5B08CB0212242EF7B7E038739F4E1F706B00BF990E10
MozJPEG      v4.0.3 official Windows x64 prebuilt, SHA-256 C8DB69B2BBF9CFF05447E60454B55317F719D9793B9100597BFCD4682836F7EE
Oxipng       10.1.1 x86_64-pc-windows-msvc
pngquant     2.17.0 official Windows binary from pngquant.org, SHA-256 BD0257AEECCFE446A4CD764927E26F8AF6051796F28ABED104307284107B120D
sRGB ICC     Redistributed ICC sRGB2014.icc, SHA-256 384B832DE3412066743B52A75EE906B6FB9FB8D9E09E936FC2C43223815C6E0A
```

Recommended pinned sources from the dependency research:

```text
libvips      https://github.com/libvips/build-win64-mxe/releases/download/v8.18.5/vips-dev-x64-web-8.18.5-static.zip
MozJPEG      https://github.com/mozilla/mozjpeg/releases/download/v4.0.3/mozjpeg-v4.0.3-win-x64.zip
Oxipng       https://github.com/oxipng/oxipng/releases/download/v10.1.1/oxipng-10.1.1-x86_64-pc-windows-msvc.zip
pngquant     https://pngquant.org/pngquant-windows.zip
sRGB ICC     https://registry.color.org/rgb-registry/profiles/sRGB2014.icc
```

Do not vendor `mozjpeg/` or `oxipng/` submodules for app releases. The helper uses the older official MozJPEG `v4.0.3` Windows x64 prebuilt because later MozJPEG releases do not provide official Windows binaries. The app must call `cjpeg-static.exe` from the extracted archive instead of renaming it.

Do not build libvips, MozJPEG, pngquant, or Oxipng in the helper. Developers who need different versions must install or build those tools themselves into the runtime paths expected by the app. Dependency version updates are release work and require checksum refresh, compatibility testing of JPEG/PNG command lines, dependency-rights review, `PLAN.md`/`TASKS.md` updates, and an app version update.

## User Flow

1. User double-clicks `imgoptz.exe`.
2. Windows opens a new console window because the app is built with console subsystem.
3. App verifies it is running on Windows.
4. App changes cwd to its executable directory, which is the app root.
5. App loads config from `imgoptz.json` if present.
6. App validates required tools.
7. The legacy `gpu` setting is ignored by the libvips pipeline unless a future GPU-capable resize backend is explicitly added.
8. App prints banner and active config summary.
9. App prompts for one input image directory.
10. User enters a directory path or `exit`.
11. If `exit`, app exits cleanly.
12. App validates the input directory.
13. App discovers supported files in that one directory, recursively only when configured.
14. App processes files with a balanced worker count.
15. App prints per-file results and final summary.
16. App waits briefly so the summary remains readable.
17. App returns to the prompt.

Only accept one input directory at a time. If users want to process multiple directories, they should organize those directories under one parent folder and enable `recursive`.

## Path Rules

Input directory paths may be absolute or relative.

Relative input paths resolve against `<app-root>/`, because the app changes cwd to the executable directory.

Examples:

```text
C:\Images\Trip      absolute input path
..\photos           relative to <app-root>/
photos              <app-root>/photos
```

`out_dir` paths may also be absolute or relative.

Relative `out_dir` paths resolve against `<app-root>/`.

Handle folder names and file names containing whitespace or special characters correctly. For example, this input must work:

```text
C:\Images\Summer Trip\
```

Implementation should pass subprocess arguments as argument arrays where possible, not by string-concatenating shell commands. If a shell is unavoidable, quote and escape paths correctly for Windows paths containing spaces, parentheses, ampersands, Unicode characters, and other shell-special characters.

Strip surrounding quotes from pasted paths, so these are equivalent:

```text
C:\Images\Trip
"C:\Images\Trip"
```

## Supported Files

Supported extensions are case-insensitive:

```text
.jpg
.jpeg
.png
```

Ignore all other files.

Default discovery is non-recursive. Recursive discovery is controlled by config.

## Config File

Use exactly one config file name:

```text
imgoptz.json
```

Default config:

```json
{
  "recursive": false,
  "max_dimension": 1920,
  "workers": "auto",
  "gpu": true,
  "debug_log": false,
  "debug_log_file": "imgoptz.log",
  "dry_run": true,
  "output_mode": "in-place",
  "out_dir": "output",
  "jpeg": {
    "enabled": true,
    "quality": 78,
    "progressive": true,
    "optimize": true,
    "sample": "2x2",
    "quant_table": 2,
    "tune": "ms-ssim",
    "preserve_profiles": true
  },
  "png": {
    "enabled": true,
    "pngquant_quality": "40-95",
    "pngquant_speed": 1,
    "pngquant_dither": false,
    "oxipng_level": 4,
    "interlace": false,
    "strip": "safe",
    "alpha": true,
    "preserve_profiles": true
  }
}
```

Config validation rules:

1. Missing `imgoptz.json`: use built-in defaults.
2. Invalid JSON: warn and use the entire default config.
3. Valid JSON with invalid option values: warn for each invalid option and use the default value for that option.
4. Unknown options should warn and be ignored.
5. Config warnings print to console.

`gpu` accepts only JSON booleans:

```json
"gpu": true
"gpu": false
```

Do not accept string values like `"auto"` for `gpu`.

`output_mode` accepts only:

```text
in-place
dir
```

Do not accept `inplace` and do not normalize alternate spellings.

`workers` accepts:

```text
"auto"
positive integer
```

JPEG option validation:

```text
jpeg.quality           integer 0..100
jpeg.sample            HxV sampling string accepted by MozJPEG, default 2x2
jpeg.quant_table       integer table id accepted by MozJPEG, default 2
jpeg.tune              "ms-ssim" only for the final default pipeline
jpeg.preserve_profiles JSON boolean
```

PNG option validation:

```text
png.pngquant_quality   MIN-MAX integer range accepted by pngquant, default 40-95
png.pngquant_speed     integer accepted by pngquant, default 1
png.pngquant_dither    JSON boolean; false means pass --nofs
png.oxipng_level       integer accepted by Oxipng, default 4
png.interlace          JSON boolean
png.strip              safe/all/<list>/none
png.alpha              JSON boolean
png.preserve_profiles  JSON boolean
```

When `png.preserve_profiles = true`, do not allow PNG stripping settings that remove color-management chunks. If `png.strip = "all"`, or if a chunk list explicitly strips `iCCP`, `sRGB`, or `cICP`, warn and use the default `png.strip = "safe"` for that option.

## Output Modes

### in-place

`output_mode = "in-place"` behavior:

1. Process each image through temp files.
2. Compare final optimized temp file size against original file size.
3. Replace the original only if the optimized file is smaller.
4. Slugify the final file name after replacement.
5. Delete temp files when output is equal/larger or processing fails.
6. Print skipped files that did not get smaller.

Never provide an option to blindly replace larger or equal output.

### dir

`output_mode = "dir"` behavior:

1. Process each image through temp files.
2. Compare final optimized temp file size against original file size.
3. Slugify the final output file name.
4. Write/copy the optimized file into `out_dir` only if it is smaller.
5. Do not emit output for files that do not get smaller.
6. Print skipped files that did not get smaller.

`out_dir` defaults to:

```text
<app-root>\output
```

If a configured `out_dir` does not exist, print a warning and fall back to the default output folder `<app-root>\output`.

Do not create the configured `out_dir` automatically. This prevents mistyped output paths from creating arbitrary directories users cannot find.

If fallback `<app-root>\output` also does not exist, print an error and abort processing for that input directory.

When `output_mode = "dir"` and `recursive = true`, preserve relative paths under the accepted output root.

Example:

```text
Input root:
C:\Images\Trip

Input files:
C:\Images\Trip\a.jpg
C:\Images\Trip\day1\b.png

out_dir:
C:\Optimized

Output files:
C:\Optimized\a.jpg
C:\Optimized\day1\b.png
```

Creating subfolders under an accepted output root is allowed:

```text
C:\Optimized\day1\
```

Creating the output root itself is not allowed:

```text
C:\Optimized
```

## Future Dry-Run Approval And Output Defaults

After the current safe-output behavior is complete, change the default UX to be non-destructive by default:

```json
{
  "output_mode": "dir",
  "out_dir": "~/imgoptz-output",
  "dry_run": true
}
```

`dry_run` accepts only JSON booleans. Default `dry_run = true` means the app optimizes to temporary files and previews the accepted outputs before writing final files.

### Dry-run approval flow

1. User enters one target directory path.
2. App discovers supported images.
3. App runs resize and optimization into temp files.
4. App compares optimized temp size against the original size. Outputs that are equal or larger are rejected during this optimization pass and are not eligible for final writing.
5. App reports successful, skipped, and failed files, including size reduction for successful temp outputs. Planned slugified final names may be shown in the dedicated approval preview, but not as indented progress detail rows.
6. App clearly states that the user must check the results and approve saving optimized files.
7. App prompts for approval.
8. Accepted approval inputs are `y` exactly and `yes` case-insensitively.
9. Accepted decline inputs are `N` exactly and `no` case-insensitively.
10. Empty input is invalid and re-prompts, matching the main input step behavior.
11. Invalid non-empty input re-prompts.
12. On approval, app finalizes only successful temp outputs by replacing originals in `in-place` mode or writing to the output directory in `dir` mode.
13. On decline, app deletes all temp artifacts and writes nothing.
14. If `dry_run = false`, app skips the approval prompt and finalizes successful temp outputs immediately.

The dry-run preview must not require re-running external optimizers after approval; approval finalizes the already-created successful temp outputs.

### Target-relative output directory rules

1. Absolute `out_dir` paths resolve as absolute paths.
2. App-root-relative `out_dir` paths that do not start with `~/`, such as `output`, `.\output`, `./output`, or `/output`, resolve against `<app-root>/`.
3. Target-relative `out_dir` paths starting with `~/` resolve against the accepted user input directory.
4. Missing absolute or app-root-relative configured output roots are checked at startup. If missing, warn and fall back to `~/imgoptz-output` for each accepted input directory.
5. Target-relative `~/...` output roots are not checked at startup and are not created during discovery.
6. The default/fallback target-relative output folder is created automatically only immediately before writing final output files.

## Resize Rules

All JPEG and PNG files go through a resize/orientation step before encoding/optimization.

Use libvips to apply equivalent shrink-only resize and EXIF orientation behavior:

```text
vips thumbnail input output 1920 --height 1920 --size down
```

The libvips `--size down` setting replaces ImageMagick's `>` resize geometry:

```text
1920x1920>
```

This means:

1. Keep original aspect ratio.
2. Shrink only if width or height exceeds `max_dimension`.
3. Never enlarge smaller images.

Examples with `max_dimension = 1920`:

```text
1536x2048 -> 1440x1920
2048x1536 -> 1920x1440
1080x1920 -> unchanged
```

## JPEG Pipeline

JPEG files use the pipeline: libvips ICC profile decision and resize/orient to PPM stdout, then MozJPEG compression with the selected ICC profile embedded.

Final MozJPEG flags:

```text
-quality 78 -progressive -optimize -sample 2x2 -quant-table 2 -tune-ms-ssim
```

PPM cannot carry ICC profiles, so the pixel stream and ICC profile must be handled separately.

Profile decision rules:

1. If the source JPEG has any ICC profile, extract that exact source profile to a temporary `*.source.icc` sidecar and embed it in the MozJPEG output.
2. If the source JPEG has no ICC profile, convert pixels to sRGB with `profiles\sRGB2014.icc` during the libvips step, then embed `profiles\sRGB2014.icc` in the MozJPEG output.

Retained-profile command shape:

```text
tools\vips-dev[-version...]\bin\vipsheader.exe -f icc-profile-data input.jpg
decode base64 ICC stdout to temp.source.icc
tools\vips-dev[-version...]\bin\vips.exe thumbnail input.jpg .raw 1920 --height 1920 --size down
prepend PPM header: P6\n<resized-width> <resized-height>\n255\n
tools\mozjpeg\static\Release\cjpeg-static.exe -quality 78 -progressive -optimize -sample 2x2 -quant-table 2 -tune-ms-ssim -icc temp.source.icc -outfile temp.jpg
```

No-profile command shape:

```text
tools\vips-dev[-version...]\bin\vips.exe thumbnail input.jpg .raw 1920 --height 1920 --size down --output-profile profiles\sRGB2014.icc
prepend PPM header: P6\n<resized-width> <resized-height>\n255\n
tools\mozjpeg\static\Release\cjpeg-static.exe -quality 78 -progressive -optimize -sample 2x2 -quant-table 2 -tune-ms-ssim -icc profiles\sRGB2014.icc -outfile temp.jpg
```

Phase 8A JPEG Unicode-path hardening requirements:

Implementation should pipe libvips raw RGB stdout into MozJPEG stdin after the app writes the PPM `P6` header. Avoid writing JPEG pixel intermediates to source-derived file paths, because MozJPEG's command-line tool may not open non-ASCII Windows paths reliably.

JPEG processing should create one per-run temp workspace for JPEG-only artifacts. Use generated ASCII filenames inside that workspace for MozJPEG-visible files such as `source.icc`, `sRGB2014.icc`, and `optimized.jpg`. Copy the installed `profiles\sRGB2014.icc` into that workspace before passing it to MozJPEG, and extract retained source ICC profiles into that workspace instead of beside the source image.

The JPEG resize/compress handoff must use libvips raw RGB stdout output, such as the CLI `.raw` stdout target. The app must determine the resized dimensions, write the PPM `P6` header to MozJPEG stdin, then stream the raw bytes from libvips into MozJPEG stdin. MozJPEG should not receive a PPM input filename. MozJPEG may write its JPEG output to an ASCII temp workspace file or to stdout captured by the app; in either case, the final output rules still operate on a temp `.jpg` first. Do not fall back to lossy libvips JPEG output for MozJPEG input.

If the JPEG temp workspace path itself contains non-ASCII characters and MozJPEG cannot open the ICC profile path, do not fail the whole JPEG pipeline solely because ICC embedding is unavailable. Log the ICC preservation/embedding failure in debug logs, omit the `-icc` argument for that image, and continue compression so the image can still produce an optimized final file. libvips pixel conversion should still run when a conversion profile is available through libvips; the degraded behavior is only that the final JPEG may miss its intended embedded ICC profile.

JPEG config maps to MozJPEG flags:

```text
jpeg.quality      -> -quality N
jpeg.progressive  -> -progressive when true
jpeg.optimize     -> -optimize when true
jpeg.sample       -> -sample HxV
jpeg.quant_table  -> -quant-table N
jpeg.tune         -> -tune-ms-ssim when set to "ms-ssim"
```

Write MozJPEG output to a temp `.jpg` first, then apply output mode rules. Delete any temporary JPEG workspace artifacts after a successful output is accepted. Also delete JPEG workspace artifacts when processing fails, and when the generated JPEG is equal/larger than the original and is skipped.

## PNG Pipeline

PNG files use the pipeline: libvips resize/orient with ICC profile decision, pngquant lossy quantization without dithering, libvips ICC profile embedding, then Oxipng optimization.

PNG profile decision rules mirror the JPEG pipeline when `png.preserve_profiles = true`:

1. If the source PNG has any ICC profile, preserve that exact source profile through the optimized PNG.
2. If the source PNG has no ICC profile, convert pixels to sRGB with `profiles\sRGB2014.icc` during the libvips step, then keep the sRGB ICC profile in the optimized PNG.

The PNG ICC implementation should not duplicate the JPEG-only ICC decision logic. Extract shared profile-presence decision helpers that both JPEG and PNG pipelines call, while keeping format-specific extraction, embedding, and output verification in the relevant pipeline code.

Do not pass `pngquant --strip` in the default pipeline. Do not rely on pngquant to preserve ICC data; attach the selected ICC profile to `temp.quant.png` with libvips before Oxipng. Let Oxipng own final stripping behavior after profile embedding.

Use Oxipng `--strip safe` by default. Oxipng safe stripping keeps PNG display/color-management chunks such as `iCCP`, `sRGB`, and `cICP`; `--strip all` is incompatible with `png.preserve_profiles = true`.

Command shape:

```text
tools\vips-dev[-version...]\bin\vipsheader.exe -f icc-profile-data input.png
decode base64 ICC stdout to temp.source.icc when retaining a source profile
tools\vips-dev[-version...]\bin\vips.exe thumbnail input.png temp.resized.png 1920 --height 1920 --size down
tools\pngquant\pngquant.exe --force --output temp.quant.png --quality 40-95 --speed 1 --nofs -- temp.resized.png
tools\vips-dev[-version...]\bin\vips.exe pngsave temp.quant.png temp.profiled.png --profile temp.source.icc
tools\oxipng[-version...]\oxipng.exe --force -o 4 --strip safe --alpha --interlace off --out temp.optimized.png temp.profiled.png
```

No-profile command shape:

```text
tools\vips-dev[-version...]\bin\vips.exe thumbnail input.png temp.resized.png 1920 --height 1920 --size down --output-profile profiles\sRGB2014.icc
tools\pngquant\pngquant.exe --force --output temp.quant.png --quality 40-95 --speed 1 --nofs -- temp.resized.png
tools\vips-dev[-version...]\bin\vips.exe pngsave temp.quant.png temp.profiled.png --profile profiles\sRGB2014.icc
tools\oxipng[-version...]\oxipng.exe --force -o 4 --strip safe --alpha --interlace off --out temp.optimized.png temp.profiled.png
```

PNG config maps to tool flags:

```text
png.pngquant_quality -> pngquant --quality MIN-MAX
png.pngquant_speed   -> pngquant --speed N
png.pngquant_dither  -> omit --nofs when true, pass --nofs when false
png.oxipng_level     -> oxipng -o N
png.interlace        -> oxipng --interlace on/off
png.strip            -> oxipng --strip safe/all/<list>, omitted if set to none
png.alpha            -> oxipng --alpha when true
png.preserve_profiles -> PNG ICC profile retention/conversion before pngquant and Oxipng
```

Write Oxipng output to a temp `.png` first, then apply output mode rules. Delete `temp.resized.png`, `temp.quant.png`, `temp.profiled.png`, and ICC sidecars on all success, failure, and skip-larger paths.

When `png.preserve_profiles = true`, verify the optimized temp PNG still has the expected color profile before final output handling. If the expected profile is missing, delete temp files and mark the file failed rather than writing an unprofiled optimized PNG.

## Slugify Output Names

Every successfully optimized image has a third processing step: slugify the final output file name.

Slugify behavior will be implemented with a pre-existing Odin slugify script. Copy that script into this codebase before wiring slugify into output handling, keep it in `package main`, and adapt only what is needed for allocator ownership, style, and tests.

Expected behavior:

```text
Ảnh 1.jpg -> anh-1.jpg
```

Preserve the image extension after slugifying the file stem. Prefer lowercase extensions for final names.

In `output_mode = "in-place"`, slugify after the original has been replaced by the smaller optimized file.

In `output_mode = "dir"`, slugify before writing the final optimized file into the output directory.

If slugified file names collide, append a numeric suffix before the extension:

```text
img.jpg
img-1.jpg
img-2.jpg
```

Collision handling is scoped to the destination directory. For recursive `dir` output, each preserved relative subdirectory has its own collision scope.

Skipped files that do not get smaller do not produce renamed output.

## GPU

The libvips migration removes ImageMagick OpenCL resize work. Keep `gpu` config parsing for now so existing config files remain valid, but do not probe or enable GPU acceleration in the libvips pipeline. If `gpu = true`, print no warning solely because GPU acceleration is unavailable; it is a no-op compatibility setting until a future GPU-capable backend is specified.

## Worker Strategy

Use Odin as the orchestration layer and external tools for the heavy image work.

Default `workers = "auto"` should choose a balanced worker count instead of pushing the machine to the limit.

Initial heuristic:

```text
logical cores <= 4   -> 1 worker
logical cores 6-8    -> 2 workers
logical cores 10-16  -> 4 workers
logical cores 24+    -> 6-8 workers
available RAM < 8GB  -> max 2 workers
available RAM < 16GB -> max 4 workers
```

Also consider current system load if accessible from Odin/Windows APIs.

Avoid thread oversubscription:

```text
VIPS_CONCURRENCY=1 or 2
oxipng --threads 1 when app-level workers > 1
```

If workers is explicitly configured as an integer, respect it after clamping to a safe minimum of 1.

## Temp Files and Safety

Never overwrite original files directly during processing.

Use temp files beside the original for `in-place` mode when the external tool can safely handle the source path. JPEG processing is an exception: MozJPEG-visible intermediates should use the JPEG per-run temp workspace described in the JPEG pipeline section, then finalization should stage/copy the accepted optimized JPEG back beside the original before replacing the original.

For `dir` mode, temp files can be created in the destination output folder or in a temporary work location, but final output should only appear after successful optimization and size comparison.

Temp file naming should avoid collisions:

```text
<original>.imgoptz.<pid>.<counter>.tmp
```

Failure handling:

1. If libvips fails, delete temp files and mark file failed.
2. If MozJPEG/pngquant/Oxipng fails, delete temp files and mark file failed.
3. If temp output does not exist or is empty, delete temp files and mark file failed.
4. If final output is not smaller, delete temp files and mark file skipped.
5. If replacement/copy fails, preserve original and mark file failed.

JPEG ICC sidecars are temp files. Delete JPEG workspace ICC files on every path: successful accepted output, tool failure, empty output, skip-larger, and replacement/copy failure.

## Console Output

Normal console output should read like a structured console UI, not a raw log stream. Do not print `[INFO]`, `[WARN]`, or `[ERROR]` level prefixes in the default console UI. Reserve log-level prefixes for optional debug log files only.

Approved UX copy updates:

1. Dry-run output should frame processing as a preview before saving. In in-place mode, print `? Mode: preview first, then replace originals only after approval.` after discovery.
2. Dry-run summaries should use `Preview:  N Ready - N Skipped - N Failed` and `Potential savings:`. Non-dry-run summaries keep `Files:  N Succeeded - N Skipped - N Failed` and `Saved:`.
3. Keep negative percentage reductions such as `-78%`; for successful reductions below 1%, show `(<1%)`.
4. The dry-run approval prompt should say `? Finish processing. Optimized files are waiting to be saved to disk. Check the results above before saving optimized files.` and use `(y/N)`, with empty input meaning No.
5. In-place approval success should say `√ Replaced N original files with optimized versions.` Dir mode approval success should say `√ Wrote N optimized files to folder "<absolute path>".`
6. Declining dry-run approval should say `- Discarded optimized files. Originals unchanged.`
7. Accepted input should say `√ Directory accepted`. Discovery should say `? Found N images (N JPG, N PNG) - Scope: current folder only.` or `Scope: including subfolders.`
8. User-facing error copy should prefer direct, friendly language. Add `Please` when instructing users to check a path, permissions, or configuration and try again.
9. Progress rows should separate filenames from details with `|`. Filename stems longer than 25 characters should be shortened for display only by keeping the first 15 Unicode characters, then `...`, then the last word and extension. Last-word separators are spaces, `_`, and `-`, but not `.`.

Keep the stdin prompt loop and console-subsystem double-click flow. Do not replace it with a GUI, fullscreen TUI, command-line batch mode, watcher, or multi-directory interface.

The normal console UI is independent from debug logging and must stay the same whether `debug_log` is enabled or disabled in a later phase.

Use this startup banner, preceded by one blank lines:

```text
  ██╗███╗   ███╗ ██████╗  ██████╗ ██████╗ ████████╗███████╗
  ██║████╗ ████║██╔════╝ ██╔═══██╗██╔══██╗╚══██╔══╝╚══███╔╝
  ██║██╔████╔██║██║  ███╗██║   ██║██████╔╝   ██║     ███╔╝
  ██║██║╚██╔╝██║██║   ██║██║   ██║██╔═══╝    ██║    ███╔╝
  ██║██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║        ██║   ███████╗
  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝        ╚═╝   ╚══════╝
```

Use section headers for major UI areas:

```text
>_ INPUT
>_ SUMMARY
```

Input block example:

```text
>_ INPUT
Paste one image directory path, or type 'exit':
C:\Users\tools\imgoptz\dist\demo\in-place\png

√ Valid path
? Found 5 images (0 JPG, 5 PNG) - non-recursive
```

Do not print an artificial prompt marker before the pasted input unless the app is responsible for rendering that text. Windows console input echo is enough.

Progress block example:

```text
√ Demo 1.png  1 MB -> 220 KB (-78%)
√ Demo 2.png  840 KB -> 410 KB (-51%)
X Demo 3.png  pngquant compression failed
√ Demo 4.png  2.4 MB -> 1.1 MB (-54%)
X Demo 5.png  pngquant compression failed
```

Use these status markers in user-facing rows:

```text
√ success
X error
? info
- skip
! warning
```

Use concise user-facing error copy rather than raw internal enum names where practical:

```text
libvips resize/orientation failed
MozJPEG compression failed
pngquant compression failed
Oxipng optimization failed
Optimized output was not smaller
Kept original unchanged; no optimized output was written.
```

Per-file success output should include the original size, optimized size, and percentage size reduction in the success row. Do not print the final or slugified output path as an indented progress detail row. Normal progress output should not print separate start, active, and done rows.

Pace progress rows so bursts of worker completions remain readable in the console. When multiple files finish at nearly the same time, print completed rows one at a time with a short delay between rows, without adding an artificial delay before naturally spaced rows. Keep this pacing in the normal console UI path, not in debug logging.

Summary block example:

```text
>_ SUMMARY
Files:  3 Succeeded - 0 Skipped - 2 Failed
Saved:  4.24 MB -> 1.73 MB (-59.2%) - Completed in 2.4s
```

Do not emit a separate warning block when the summary already communicates the final warning or failure state.

After printing the summary block, wait briefly before returning to the next input prompt so users can read the result before the console advances to `>_ INPUT` again. This read pause is a UI delay and should not be included in the reported processing duration.

## Debug Logging

Default is console-only.

If `debug_log = true`, write detailed logs to a new file for each app run. Do not append multiple runs into one log file.

Prefix the configured `debug_log_file` basename with a filesystem-safe datetime for the actual run log path, preserving the configured directory. Example: `debug_log_file = "logs/imgoptz.log"` writes to `logs/YYYYMMDD-HHMMSS-nnnnnnnnn-imgoptz.log`.

Relative `debug_log_file` resolves against `<app-root>/`.

Implement debug file logging with a separate logging flow from console UI output. Normal console output must keep the same structured UI style whether debug logging is enabled or disabled, and must not gain log-level or timestamp prefixes.

Debug mode must use Odin `core:log` file logging and must not route normal TUI console rows through the debug logger. The TUI console logging and debug file logging are separate outputs.

Debug log file entries must include log level and date/time. The file should be easy to read: organize detailed logs with block structure matching the existing app settings, input, discovery, progress, and summary sections where practical. Log app state transitions verbosely, including config loading, runtime validation, input parsing, discovery traversal, worker processing, temp cleanup, size comparison, final write decisions, and summary totals. For each external child process, log the process label, argument array, relevant environment overrides, exit state, exit code, stdout, stderr, and execution errors when present.

Do not require logging for normal operation.

## Build And Script Launcher

Contributor automation is driven by a small Odin CLI launcher compiled from the `scripts/` package. Contributors already need Odin to work on the repo, so the bootstrap command is intentionally one Odin build:

```bash
odin build scripts -out:scripts.exe -target:windows_amd64 -strict-style -vet -vet-tabs -warnings-as-errors
```

The generated `scripts.exe` is local build output and must not be committed. After bootstrap, contributors and AI agents should call the same launcher from any Windows developer shell:

```bash
./scripts.exe build
./scripts.exe dev
./scripts.exe test
./scripts.exe preview
./scripts.exe package
```

Each script must live in exactly one `.odin` file under `scripts/`. `scripts/main.odin` is the launcher entrypoint; Odin automatically compiles the other `.odin` files in the same directory into the same package. Each script file registers one script descriptor with the launcher at startup, including whether the script is enabled. The launcher lists registered enabled and disabled scripts, but it only runs registered scripts that are enabled.

Production build emits the release binary to `dist/imgoptz.exe`:

```bash
odin build src -out:dist/imgoptz.exe -target:windows_amd64 -subsystem:console -o:speed -strict-style -vet -vet-packages:main -vet-unused-procedures -vet-tabs -disallow-do -warnings-as-errors
```

`scripts.exe dev` should build the app in debug mode first, then launch the built development binary. `scripts.exe preview` should launch the production binary only, and it must print a clear error if `dist/imgoptz.exe` is missing:

```bash
./scripts.exe dev
./dist/imgoptz_dev.exe

./scripts.exe preview
./dist/imgoptz.exe
```

Phase 10B replaces duplicate shell-specific development automation with registered Odin scripts. There is no developer dependency setup script. `scripts/setup.ps1` is a source-hosted end-user helper, not a contributor bootstrap path, not part of the app zip, and not a GitHub Release asset.

## Implementation Phases

1. Keep and clean up the current `src/main.odin` UI loop.
2. Add `exit` handling.
3. Add path trimming, quote stripping, and one-input-directory validation.
4. Add config model with built-in defaults.
5. Add `imgoptz.json` parser and validation warnings.
6. Add tool validation for the final distribution paths.
7. Add output mode validation and output root resolution.
8. Validate runtime libvips availability and treat `gpu` as a no-op compatibility setting.
9. Add supported file discovery with optional recursion.
10. Add relative path preservation for recursive `dir` output mode.
11. Phase 11: Migrate resize/profile handling from ImageMagick to the official `vips-web` static prebuilt, using libvips raw RGB output plus an app-written PPM header for external MozJPEG stdin.
12. Add PNG pipeline with libvips temp resize/profile embedding, shared ICC retention/conversion logic, pngquant without `--strip`, and Oxipng output.
13. Apply the updated PNG quality default: `png.pngquant_quality = "40-95"` across built-in defaults, config fallback behavior, distribution config, tests, and PNG command verification.
14. Replace flat console log-style output with the structured console UI: banner, app settings block, input block, discovery block, progress block, and summary block.
15. Add temp file cleanup and size comparison.
16. Add safe original replacement for `in-place` mode.
17. Copy the existing Odin slugify script into this codebase and adapt it to repo style, package layout, allocator ownership, and tests.
18. Add slugify final output names and collision handling.
19. Add output copy/move for `dir` mode.
20. Add worker pool and auto worker heuristic.
21. Add progress output and final summary, including original size, optimized size, and percentage size reduction in success rows, without final/slugified output path detail rows.
22. Add optional debug logging.
23. Phase 8A: Harden JPEG Unicode-path handling with a per-run temp workspace, PPM stdout producer-to-MozJPEG piping, and graceful ICC omission when MozJPEG cannot open temp ICC paths.
24. Phase 9: Add dry-run approval mode, defaulting to preview-first and requiring explicit approval before final writes.
25. Phase 10: Change default output behavior to `output_mode = "dir"` with target-relative `out_dir = "~/imgoptz-output"`.
26. Phase 10A: Remove dependency tool bundling from the release package and package only app-owned files plus the redistributed ICC profile and license.
27. Phase 10B: Add the Odin `scripts.exe` launcher, move development automation into registered `.odin` files under `scripts/`, and remove developer dependency setup automation.
28. Add `scripts/setup.ps1` as a source-hosted end-user helper that downloads verified official prebuilt dependency tools without build steps and leaves the bundled ICC profile untouched.
29. Test with spaces, special characters, Unicode paths, and quoted paths.
30. Test relative and absolute input directories.
31. Test relative, absolute, and target-relative `out_dir`.
32. Test missing configured `out_dir` fallback to target-relative default output.
33. Test delayed creation of target-relative output folders.
34. Test recursive input with preserved output paths.
35. Test slugify collisions.
36. Test uppercase extensions.
37. Test corrupt images.
38. Test missing tools/profile.
39. Test PNG ICC retention through libvips, pngquant, and Oxipng.
40. Test progress success rows include before/after sizes and percentage reduction, and do not print final/slugified output path detail rows.
41. Test repeated prompt loop and `exit`.
