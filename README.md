# imgoptz

`imgoptz` is a Windows-only CLI image optimizer for folders of JPEG and PNG files. The v0.1.0 MVP ships a console TUI first, so non-technical users can double-click the app, paste one folder path, preview optimized results, approve saving, then process another folder or type `exit`.

The app keeps the workflow conservative by default. It writes smaller optimized files to an output folder, leaves originals unchanged, and skips any file that does not get smaller. Future releases are planned to support both direct terminal CLI usage for developers and the current TUI-style flow for non-technical users.

## Documentation

- [Features](#features)
- [Roadmap](#roadmap)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [User Guide](#user-guide)
- [Configuration](#configuration)
- [Development](#development)
- [Release Bundle](#release-bundle)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

- Safe by default: preview first, then save only after approval.
- Dual workflow goal: direct terminal CLI usage for developers, plus a double-click console TUI for non-technical users.
- JPEG and PNG support: accepts `.jpg`, `.jpeg`, and `.png` case-insensitively.
- Smaller web-ready images: resizes large images to a configurable maximum dimension without enlarging smaller images.
- High-quality compression stack: ImageMagick handles resize/orientation, MozJPEG compresses JPEG, and pngquant plus Oxipng optimize PNG.
- Color-aware output: preserves supported sRGB and P3 profiles, or converts unknown/missing profiles to the bundled `sRGB2014.icc` profile.
- Flexible discovery: scan the selected folder only, or include subfolders with `recursive` mode.
- Safe output modes: save to an output folder or replace originals in-place after approval.
- Clean names: successful output filenames are slugified and collision-safe.
- Debuggable when needed: optional per-run debug logs for troubleshooting.

## Roadmap

The v0.1.0 goal is a real-life MVP centered on the current console TUI flow. Planned future work includes:

- Direct terminal CLI mode for developers and automation-friendly workflows.
- Continued TUI mode for non-technical users who prefer double-click usage.
- A setup script that downloads and installs local runtime dependencies into `dist/`.
- Optional support for using ImageMagick, MozJPEG, pngquant, and Oxipng from the local machine `PATH`, so contributors can skip manual dependency preparation.

## Installation

### Release Build

1. Download the release `.zip` from GitHub Releases.
2. Extract the whole zip file to a writable folder such as `Downloads`, `Desktop`, or another local folder.
3. Keep the extracted files together. `imgoptz.exe` expects its config, profiles, schema, tools, and license files beside it.
4. Double-click `imgoptz.exe`.

Do not run `imgoptz.exe` from inside the zip preview window, and do not move the executable by itself.

### From Source

This project targets Windows and is built with Odin. The app code is in `src/`; the source repository does not track the runtime tool binaries needed by the app.

Before running a locally built executable, download the runtime dependencies yourself and place them under `dist/` using the same layout as the release bundle:

```text
dist/
├─ profiles/
│  ├─ sRGB2014.icc
│  └─ sRGB2014.LICENSE.txt
└─ tools/
   ├─ imagemagick/
   │  ├─ magick.exe
   │  ├─ LICENSE.txt
   │  ├─ NOTICE.txt
   │  └─ policy.xml
   ├─ mozjpeg/
   │  ├─ mozjpeg.exe
   │  ├─ LICENSE.md
   │  ├─ README.ijg
   │  └─ README-mozilla.txt
   ├─ oxipng/
   │  ├─ oxipng.exe
   │  └─ LICENSE
   └─ pngquant/
      ├─ pngquant.exe
      ├─ COPYRIGHT
      └─ SOURCE.txt
```

The build scripts compile only the `imgoptz` executable. They do not download ImageMagick, MozJPEG, pngquant, Oxipng, or the ICC profile. If these files are missing, the app will fail runtime validation.

Production build:

```powershell
./scripts/build.ps1
```

Development build:

```powershell
./scripts/build_dev.ps1
```

Build and run the development executable:

```powershell
./scripts/run.ps1
```

The build output is written under `dist/`.

## Quick Start

1. Double-click `imgoptz.exe`.
2. Paste one image folder path when the console asks for it.
3. Press Enter.
4. Review the preview summary.
5. Type `y` or `yes` to save optimized files, or press Enter/type `N`/`no` to discard them.
6. Paste another folder path, or type `exit` to close the app.

Example input path:

```text
C:\Users\YourName\Pictures\Trip
```

Quoted paths and paths with spaces are accepted:

```text
"C:\Users\YourName\Pictures\Summer Trip"
```

## User Guide

### Supported Files

`imgoptz` processes only these extensions:

```text
.jpg
.jpeg
.png
```

All other files are ignored.

### Default Output

The release config defaults to:

```json
{
  "dry_run": true,
  "output_mode": "dir",
  "out_dir": "~/imgoptz-output"
}
```

With these settings, `imgoptz` previews optimized files first. If you approve, it writes smaller optimized files into an `imgoptz-output` folder inside the selected image folder.

Example:

```text
Input folder:
C:\Users\YourName\Pictures\Trip

Output folder:
C:\Users\YourName\Pictures\Trip\imgoptz-output
```

Original files are not replaced in the default mode. Files that do not get smaller are skipped.

### In-Place Mode

Set `output_mode` to `"in-place"` only if you want approved optimized files to replace originals:

```json
"output_mode": "in-place"
```

Even in in-place mode, `imgoptz` writes temporary files first and replaces an original only when the optimized file is smaller and you approve the dry-run prompt.

### Result Labels

The console uses these result words:

| Label | Meaning |
| --- | --- |
| `Ready` | The preview output is smaller and can be saved if you approve. |
| `Succeeded` | The optimized file was saved. |
| `Skipped` | The optimized output was not smaller, so no file was written. |
| `Failed` | The image could not be processed; the original remains unchanged. |
| `Potential savings` | Space that can be saved if you approve the preview. |
| `Saved` | Space saved after final files were written. |

## Configuration

`imgoptz` reads one optional config file from the app root:

```text
imgoptz.json
```

The distributed config includes a schema reference for editor validation:

```json
"$schema": "./schema/imgoptz.schema.json"
```

Important settings:

| Setting | Default | Description |
| --- | --- | --- |
| `recursive` | `false` | Search subfolders when true. |
| `max_dimension` | `1920` | Maximum width or height after resizing. Smaller images are not enlarged. |
| `workers` | `"auto"` | Balanced worker count, or a positive integer. |
| `gpu` | `true` | Probe ImageMagick OpenCL GPU support before enabling GPU resize work. |
| `dry_run` | `true` | Preview results and ask before saving files. |
| `output_mode` | `"dir"` | Use `"dir"` for output-folder mode or `"in-place"` to replace originals after approval. |
| `out_dir` | `"~/imgoptz-output"` | Output folder for `output_mode = "dir"`. `~/` means relative to the selected image folder. |
| `debug_log` | `false` | Write a detailed per-run log file when true. |
| `debug_log_file` | `"imgoptz.log"` | Base log filename or path. Runtime logs receive a timestamp prefix. |
| `jpeg.enabled` | `true` | Enable JPEG processing. |
| `jpeg.quality` | `78` | MozJPEG quality value. |
| `jpeg.progressive` | `true` | Write progressive JPEG output. |
| `jpeg.optimize` | `true` | Enable MozJPEG Huffman table optimization. |
| `jpeg.sample` | `"2x2"` | MozJPEG chroma subsampling value. |
| `jpeg.quant_table` | `2` | MozJPEG quantization table. |
| `jpeg.tune` | `"ms-ssim"` | MozJPEG tuning mode. |
| `jpeg.preserve_profiles` | `true` | Preserve supported source color profiles or convert to bundled sRGB. |
| `png.enabled` | `true` | Enable PNG processing. |
| `png.pngquant_quality` | `"40-95"` | pngquant quality range. |
| `png.pngquant_speed` | `1` | pngquant speed/compression tradeoff. |
| `png.pngquant_dither` | `false` | Enable or disable pngquant dithering. |
| `png.oxipng_level` | `4` | Oxipng optimization level. |
| `png.interlace` | `false` | Enable PNG interlacing. |
| `png.strip` | `"safe"` | Oxipng metadata stripping mode. `safe` keeps color-management chunks. |
| `png.alpha` | `true` | Enable Oxipng alpha optimization. |
| `png.preserve_profiles` | `true` | Preserve supported source color profiles or convert to bundled sRGB. |

Config validation is forgiving. Invalid JSON makes the app warn and use the full default config. Invalid option values warn and fall back per option. Unknown options warn and are ignored, except the editor-only `$schema` field.

### Common Config Changes

Search subfolders:

```json
"recursive": true
```

Use a larger maximum image dimension:

```json
"max_dimension": 2560
```

Replace originals after approval:

```json
"output_mode": "in-place"
```

Write a debug log for troubleshooting:

```json
"debug_log": true
```

JSON booleans must be lowercase and unquoted:

```json
"recursive": true
```

Do not write booleans as strings:

```json
"recursive": "true"
```

## Development

The main app is a single Odin package under `src/`. Keep the Windows console workflow, safe output behavior, and bundled runtime layout intact unless the public product direction changes.

### Repository Layout

```text
imgoptz/
├─ src/                  Odin app source, package main
├─ scripts/              Build and run helper scripts
├─ dist/                 Local development distribution root, prepared locally
│  ├─ imgoptz.exe        Production build output
│  ├─ imgoptz_dev.exe    Development build output
│  ├─ README.txt         Bundled release user guide
│  ├─ LICENSE.txt        App license for release bundles
│  ├─ imgoptz.json       Release config template
│  ├─ schema/            JSON schema for config editors
│  ├─ profiles/          Runtime ICC profile and license
│  └─ tools/             Runtime image tools
│     ├─ imagemagick/
│     ├─ mozjpeg/
│     ├─ oxipng/
│     └─ pngquant/
├─ mozjpeg/              Vendor/submodule source
├─ oxipng/               Vendor/submodule source
├─ LICENSE
└─ README.md
```

### Test And Verify

Run tests:

```powershell
odin test src
```

Run the required handoff checks before returning code changes:

```powershell
odin test src
./scripts/build.ps1
./scripts/build_dev.ps1
```

For memory leak checks, run the development executable through at least the `exit` prompt path. Treat any `=== N allocations not freed: ===` report as a failure.

For image-processing tests, prepare your own JPEG and PNG files or use throwaway copies of your own images. The repository intentionally does not rely on bundled sample images because image licensing is outside the project scope.

## Release Bundle

The release zip should contain one app root folder. The app root is the folder that contains `imgoptz.exe`; all runtime paths resolve relative to that folder.

Required release layout:

```text
imgoptz/
├─ imgoptz.exe
├─ README.txt
├─ LICENSE.txt
├─ imgoptz.json
├─ schema/
│  └─ imgoptz.schema.json
├─ profiles/
│  ├─ sRGB2014.icc
│  └─ sRGB2014.LICENSE.txt
└─ tools/
   ├─ imagemagick/
   │  ├─ magick.exe
   │  ├─ LICENSE.txt
   │  ├─ NOTICE.txt
   │  └─ policy.xml
   ├─ mozjpeg/
   │  ├─ mozjpeg.exe
   │  ├─ LICENSE.md
   │  ├─ README.ijg
   │  └─ README-mozilla.txt
   ├─ oxipng/
   │  ├─ oxipng.exe
   │  └─ LICENSE
   └─ pngquant/
      ├─ pngquant.exe
      ├─ COPYRIGHT
      └─ SOURCE.txt
```

## Troubleshooting

- If a tool is missing, extract the full zip again and keep `imgoptz.exe` with its `tools/` folder.
- If no files are found, check that the folder contains `.jpg`, `.jpeg`, or `.png` files. If they are in subfolders, set `recursive` to `true`.
- If no optimized files are saved, the optimized versions may not have been smaller, or the approval prompt may have been declined.
- If config validation fails, check for missing commas, quoted booleans such as `"true"`, misspelled output modes such as `"inplace"`, and empty path values.
- If images fail to process, the source image may be corrupt or unsupported. Set `debug_log` to `true` for a detailed log.

## Contributing

Issues and pull requests should stay aligned with the product goals in this README. Keep the Windows console flow, the one-folder-at-a-time prompt loop, safe output behavior, and bundled runtime layout intact unless the public product direction changes first.

Before proposing code changes, run the required verification commands in [Test And Verify](#test-and-verify). Documentation-only changes should still be checked for consistency with `dist/imgoptz.json` and the bundled release files.

## License

`imgoptz` is licensed under the MIT License. See `LICENSE` for the app license.

The release bundle includes third-party executables, profiles, and notices under `dist/tools/` and `dist/profiles/`. Those files retain their own licenses and notices.
