# imgoptz Implementation Plan

## Purpose

`imgoptz` is a Windows-only folder image optimizer. It optimizes one input directory at a time, supporting only JPEG and PNG files. Users launch `imgoptz.exe` by double-clicking it, which opens a console window, prompts for a directory path, processes supported images, prints results, then prompts again. Typing `exit` closes the program and the console window.

The current `src/main.odin` demo already proves the intended UI shape: Windows-only guard, change cwd to the executable directory, line-based stdin prompt loop, and child process execution with inherited console output. Build the real tool by expanding that structure, not replacing it with a different UI model.

## Distribution Layout

The distributed app root is the directory containing `imgoptz.exe`. The folder can have any name. All runtime paths are relative to that app root.

The distributed app root should use this layout:

```text
<app-root>/
  imgoptz.exe
  imgoptz.json          optional
  output/               required only when output_mode = "dir" and default out_dir is used
  profiles/
    sRGB2014.icc
    sRGB2014.LICENSE.txt
  tools/
    mozjpeg/
      mozjpeg.exe
      LICENSE.md
      README.ijg
      README-mozilla.txt
    oxipng/
      oxipng.exe
      LICENSE
    pngquant/
      pngquant.exe
      COPYRIGHT
    imagemagick/
      magick.exe
      LICENSE.txt
      NOTICE.txt
      policy.xml
```

The app changes cwd to the executable directory at startup, so all relative paths resolve against `<app-root>/`.

Required executable paths:

```text
tools\mozjpeg\mozjpeg.exe
tools\oxipng\oxipng.exe
tools\pngquant\pngquant.exe
tools\imagemagick\magick.exe
profiles\sRGB2014.icc
```

## License Files

Keep required third-party notices beside each tool.

MozJPEG/libjpeg-turbo:

```text
tools\mozjpeg\LICENSE.md
tools\mozjpeg\README.ijg
tools\mozjpeg\README-mozilla.txt
```

Local license guidance states binary distribution documentation must include: `This software is based in part on the work of the Independent JPEG Group.` Keeping `LICENSE.md` and `README.ijg` with the executable satisfies this requirement more clearly than shipping the binary alone.

Oxipng:

```text
tools\oxipng\LICENSE
```

Oxipng is MIT licensed, so include its copyright and permission notice with the binary.

pngquant/libimagequant:

```text
tools\pngquant\COPYRIGHT
```

Keep pngquant's copyright and license notice beside the binary.

ImageMagick:

```text
tools\imagemagick\LICENSE.txt
tools\imagemagick\NOTICE.txt
tools\imagemagick\policy.xml
```

`policy.xml` is not strictly required for the basic resize-to-PPM command, but keep it so runtime resource/security policy is explicit and distributable.

ICC sRGB profile:

```text
profiles\sRGB2014.icc
profiles\sRGB2014.LICENSE.txt
```

Use ICC's official `sRGB2014.icc`, not a copied Windows system `sRGB Color Space Profile.icm`, for distribution. The ICC profile may be copied, distributed, embedded, made, used, and sold without restriction when unaltered. Keep the profile copyright tag intact and include the ICC license text in `sRGB2014.LICENSE.txt`.

## User Flow

1. User double-clicks `imgoptz.exe`.
2. Windows opens a new console window because the app is built with console subsystem.
3. App verifies it is running on Windows.
4. App changes cwd to its executable directory, which is the app root.
5. App loads config from `imgoptz.json` if present.
6. App validates required tools.
7. If `gpu = true`, app probes ImageMagick OpenCL GPU support.
8. App prints banner and active config summary.
9. App prompts for one input image directory.
10. User enters a directory path or `exit`.
11. If `exit`, app exits cleanly.
12. App validates the input directory.
13. App discovers supported files in that one directory, recursively only when configured.
14. App processes files with a balanced worker count.
15. App prints per-file results and final summary.
16. App returns to the prompt.

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
    "alpha": true
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
```

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

## Resize Rules

All JPEG and PNG files go through a resize/orientation step before encoding/optimization.

Use ImageMagick to apply:

```text
-auto-orient -filter Lanczos -resize <max_dimension>x<max_dimension>
```

Append `>` to the resize geometry:

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

JPEG files use the pipeline: ImageMagick resize/orient, ICC profile decision, then MozJPEG compression with the selected ICC profile embedded.

Final MozJPEG flags:

```text
-quality 78 -progressive -optimize -sample 2x2 -quant-table 2 -tune-ms-ssim
```

PPM cannot carry ICC profiles, so the pixel stream and ICC profile must be handled separately.

Profile decision rules:

1. If the source JPEG has an sRGB-family or P3-family ICC profile, extract that exact source profile to a temporary `*.source.icc` sidecar and embed it in the MozJPEG output.
2. If the source JPEG has any other ICC profile, convert pixels to sRGB with `profiles\sRGB2014.icc` during the ImageMagick step, then embed `profiles\sRGB2014.icc` in the MozJPEG output.
3. If the source JPEG has no ICC profile, treat it as unsupported/unknown, convert pixels to sRGB with `profiles\sRGB2014.icc`, then embed `profiles\sRGB2014.icc` in the MozJPEG output.

Retained profile families include at minimum profiles identified as `sRGB`, `IEC 61966-2-1`, `IEC61966-2.1`, `IEC61966-2-1`, `Display P3`, `DCI-P3 D65 Gamut with sRGB Transfer`, or other descriptions containing `P3`.

Retained-profile command shape:

```text
tools\imagemagick\magick.exe identify -quiet -format %[profile:icc] input.jpg
tools\imagemagick\magick.exe input.jpg icc:temp.source.icc
tools\imagemagick\magick.exe input.jpg -auto-orient -filter Lanczos -resize 1920x1920> ppm:-
tools\mozjpeg\mozjpeg.exe -quality 78 -progressive -optimize -sample 2x2 -quant-table 2 -tune-ms-ssim -icc temp.source.icc -outfile temp.jpg
```

Unsupported/no-profile command shape:

```text
tools\imagemagick\magick.exe input.jpg -auto-orient -filter Lanczos -resize 1920x1920> -profile profiles\sRGB2014.icc ppm:-
tools\mozjpeg\mozjpeg.exe -quality 78 -progressive -optimize -sample 2x2 -quant-table 2 -tune-ms-ssim -icc profiles\sRGB2014.icc -outfile temp.jpg
```

Implementation should pipe ImageMagick stdout into MozJPEG stdin when practical. If the process API makes piping impractical, write a temporary resized PPM and delete it on all success, failure, and skip-larger paths.

JPEG config maps to MozJPEG flags:

```text
jpeg.quality      -> -quality N
jpeg.progressive  -> -progressive when true
jpeg.optimize     -> -optimize when true
jpeg.sample       -> -sample HxV
jpeg.quant_table  -> -quant-table N
jpeg.tune         -> -tune-ms-ssim when set to "ms-ssim"
```

Write MozJPEG output to a temp `.jpg` first, then apply output mode rules. Delete any temporary `*.source.icc` sidecar after a successful output is accepted. Also delete `*.source.icc` when processing fails, and when the generated JPEG is equal/larger than the original and is skipped.

## PNG Pipeline

PNG files use the pipeline: ImageMagick resize/orient to a temporary PNG, pngquant lossy quantization without dithering, then Oxipng optimization.

Command shape:

```text
tools\imagemagick\magick.exe input.png -auto-orient -filter Lanczos -resize 1920x1920> temp.resized.png
tools\pngquant\pngquant.exe --force --output temp.quant.png --quality 40-95 --speed 1 --nofs --strip -- temp.resized.png
tools\oxipng\oxipng.exe --force -o 4 --strip safe --alpha --interlace off --out temp.optimized.png temp.quant.png
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
```

Write Oxipng output to a temp `.png` first, then apply output mode rules. Delete `temp.resized.png` and `temp.quant.png` on all success, failure, and skip-larger paths.

## Slugify Output Names

Every successfully optimized image has a third processing step: slugify the final output file name.

Slugify behavior will be implemented with a pre-existing Odin slugify script that will be copied into this codebase later.

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

## GPU and OpenCL

ImageMagick can use OpenCL for resize, and local `magick.exe` reports OpenCL support.

Behavior:

1. If `gpu = false`, never probe and never enable GPU.
2. If `gpu = true`, run a lightweight startup probe.
3. If probe succeeds, set `MAGICK_OCL_DEVICE=GPU` for ImageMagick child processes.
4. If probe fails, warn and fall back to CPU.
5. Never blindly enable GPU without a successful probe.

GPU only applies to ImageMagick resize work. MozJPEG, pngquant, and Oxipng remain CPU tools.

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
MAGICK_THREAD_LIMIT=1 or 2
oxipng --threads 1 when app-level workers > 1
```

If workers is explicitly configured as an integer, respect it after clamping to a safe minimum of 1.

## Temp Files and Safety

Never overwrite original files directly during processing.

Use temp files beside the original for `in-place` mode, because same-volume replacement is safer and usually atomic enough for this use case.

For `dir` mode, temp files can be created in the destination output folder or in a temporary work location, but final output should only appear after successful optimization and size comparison.

Temp file naming should avoid collisions:

```text
<original>.imgoptz.<pid>.<counter>.tmp
```

Failure handling:

1. If ImageMagick fails, delete temp files and mark file failed.
2. If MozJPEG/pngquant/Oxipng fails, delete temp files and mark file failed.
3. If temp output does not exist or is empty, delete temp files and mark file failed.
4. If final output is not smaller, delete temp files and mark file skipped.
5. If replacement/copy fails, preserve original and mark file failed.

JPEG ICC sidecars are temp files. Delete `*.source.icc` on every path: successful accepted output, tool failure, empty output, skip-larger, and replacement/copy failure.

## Console Output

Normal console output should read like a structured console UI, not a raw log stream. Do not print `[INFO]`, `[WARN]`, or `[ERROR]` level prefixes in the default console UI. Reserve log-level prefixes for optional debug log files only.

Keep the stdin prompt loop and console-subsystem double-click flow. Do not replace it with a GUI, fullscreen TUI, command-line batch mode, watcher, or multi-directory interface.

Use this startup banner:

```text
  ██╗███╗   ███╗ ██████╗  ██████╗ ██████╗ ████████╗███████╗   ┌──────────────────────────────┐
  ██║████╗ ████║██╔════╝ ██╔═══██╗██╔══██╗╚══██╔══╝╚══███╔╝   │ >_ Imgoptz                   │
  ██║██╔████╔██║██║  ███╗██║   ██║██████╔╝   ██║     ███╔╝    │                              │
  ██║██║╚██╔╝██║██║   ██║██║   ██║██╔═══╝    ██║    ███╔╝     │ Folder image optimizer       │
  ██║██║ ╚═╝ ██║╚██████╔╝╚██████╔╝██║        ██║   ███████╗   │ JPEG + PNG optimizer         │
  ╚═╝╚═╝     ╚═╝ ╚═════╝  ╚═════╝ ╚═╝        ╚═╝   ╚══════╝   └──────────────────────────────┘
```

Use section headers for major UI areas:

```text
>_ APP SETTINGS
>_ INPUT
>_ DISCOVERY
>_ PROGRESS
>_ SUMMARY
```

Use simple boxed blocks for summary-style information:

```text
>_ APP SETTINGS
┌
│ App root   "C:\Users\huydc\CongHuy\Programming\tools\imgoptz\dist"
│ Config     ✅ imgoptz.json loaded
│ GPU        ✅ ImageMagick OpenCL
│ Workers    4
│ Output     in-place
└
```

Input block example:

```text
>_ INPUT

Paste one image directory path, or type 'exit':
C:\Users\tools\imgoptz\dist\demo\in-place\png

✅ Accepted: C:\Users\tools\imgoptz\dist\demo\in-place\png
```

Do not print an artificial prompt marker before the pasted input unless the app is responsible for rendering that text. Windows console input echo is enough.

Discovery block example:

```text
>_ DISCOVERY
┌
│ Found      5 images
│ JPEG       0
│ PNG        5
│ Recursive  false
└
```

Progress block example:

```text
>_ PROGRESS

[1/5] ✅ OK     Demo 1.png
[2/5] ✅ OK     Demo 2.png
[3/5] ❌ ERROR  Demo 3.png
      ❌ ERROR  pngquant compression failed
      ℹ️ INFO   Kept original unchanged; no optimized output was written.
[4/5] ✅ OK     Demo 4.png
[5/5] ❌ ERROR  Demo 5.png
      ❌ ERROR  pngquant compression failed
      ℹ️ INFO   Kept original unchanged; no optimized output was written.
```

Use these status labels in progress rows and indented detail rows:

```text
✅ OK
⚠️ SKIP
❌ ERROR
ℹ️ INFO
```

Use concise user-facing error copy rather than raw internal enum names where practical:

```text
ImageMagick resize/orientation failed
MozJPEG compression failed
pngquant compression failed
Oxipng optimization failed
Optimized output was not smaller
Kept original unchanged; no optimized output was written.
```

Every error detail should be indented under the file row it belongs to. Per-file success output should include the output path, original size, optimized size, and percentage size reduction once safe output handling is implemented.

Summary block example:

```text
>_ SUMMARY
┌
│ Succeeded  3
│ Skipped    0
│ Failed     2
│ Result     Completed with failures
└
```

Do not emit a separate warning block when the summary already communicates the final warning or failure state.

## Debug Logging

Default is console-only.

If `debug_log = true`, append detailed logs to `debug_log_file`.

Relative `debug_log_file` resolves against `<app-root>/`.

Do not require logging for normal operation.

## Build

Current production build script emits the release binary to `dist/imgoptz.exe`:

```bash
odin build src -out:dist/imgoptz.exe -target:windows_amd64 -subsystem:console -o:speed -strict-style -vet -vet-packages:main -vet-unused-procedures -vet-tabs -disallow-do -warnings-as-errors
```

`scripts/run.ps1` should call `scripts/build_dev.ps1` first, then launch the built development binary:

```powershell
./scripts/build_dev.ps1
./dist/imgoptz_dev.exe
```

## Implementation Phases

1. Keep and clean up the current `src/main.odin` UI loop.
2. Add `exit` handling.
3. Add path trimming, quote stripping, and one-input-directory validation.
4. Add config model with built-in defaults.
5. Add `imgoptz.json` parser and validation warnings.
6. Add tool validation for the final distribution paths.
7. Add output mode validation and output root resolution.
8. Add ImageMagick GPU probe when `gpu = true`.
9. Add supported file discovery with optional recursion.
10. Add relative path preservation for recursive `dir` output mode.
11. Add JPEG pipeline with ICC retention/conversion and `*.source.icc` cleanup.
12. Add PNG pipeline with Magick temp resize, pngquant, and Oxipng output.
13. Add temp file cleanup and size comparison.
14. Add safe original replacement for `in-place` mode.
15. Add slugify final output names and collision handling.
16. Add output copy/move for `dir` mode.
17. Add worker pool and auto worker heuristic.
18. Add progress output and final summary, including percentage size reduction.
19. Add optional debug logging.
20. Test with spaces, special characters, Unicode paths, and quoted paths.
21. Test relative and absolute input directories.
22. Test relative and absolute `out_dir`.
23. Test missing configured `out_dir` fallback to default output.
24. Test missing default output folder error.
25. Test recursive input with preserved output paths.
26. Test slugify collisions.
27. Test uppercase extensions.
28. Test corrupt images.
29. Test missing tools.
30. Test repeated prompt loop and `exit`.
