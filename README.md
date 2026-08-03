# imgoptz

`imgoptz` is a Windows-only folder image optimizer for JPEG and PNG files. It is designed for double-click use: launch `imgoptz.exe`, paste one folder path, review the results, approve saving optimized files, then process another folder or type `exit`.

The app is intentionally conservative. By default it previews first, writes optimized files to an output folder beside the selected image folder, and only keeps optimized files when they are smaller than the original.

## Features

- Optimizes `.jpg`, `.jpeg`, and `.png` files case-insensitively.
- Resizes large images to fit within the configured maximum dimension without enlarging smaller images.
- Preserves or converts color profiles using the bundled `sRGB2014.icc` profile.
- Uses MozJPEG for JPEG compression, pngquant plus Oxipng for PNG optimization, and ImageMagick for resize/orientation.
- Supports current-folder-only or recursive folder discovery.
- Supports output-folder mode and in-place replacement mode.
- Uses dry-run approval by default so users can review before writing files.
- Slugifies successful output filenames and handles name collisions.

## Quick Start For Users

1. Download the release `.zip` from GitHub Releases.
2. Extract the whole folder somewhere writable, such as `Downloads` or `Desktop`.
3. Double-click `imgoptz.exe`.
4. Paste one image folder path into the console window.
5. Review the results.
6. Type `y` or `yes` to save optimized files, or press `N`/type `no` to discard them.
7. Paste another folder path, or type `exit` to close the app.

The bundled user guide is `dist/README.txt` in this repository and should be included in release zip files.

## Default Output Behavior

The default config in `dist/imgoptz.json` uses:

```json
{
  "dry_run": true,
  "output_mode": "dir",
  "out_dir": "~/imgoptz-output"
}
```

This means optimized files are previewed first, then written to an `imgoptz-output` folder inside the selected image folder only after approval. Original images are not replaced in the default mode.

The app writes only optimized files that are smaller than the original. Files that do not get smaller are skipped.

## Configuration

The app reads exactly one optional config file from the app root:

```text
imgoptz.json
```

The distributed config references the bundled schema for editor validation:

```json
"$schema": "./schema/imgoptz.schema.json"
```

Important settings:

| Setting | Default | Description |
| --- | --- | --- |
| `recursive` | `false` | Search subfolders when true. |
| `max_dimension` | `1920` | Maximum width or height after resize. |
| `workers` | `"auto"` | Balanced worker count, or a positive integer. |
| `gpu` | `true` | Probe ImageMagick OpenCL GPU support before enabling it. |
| `dry_run` | `true` | Preview and ask before saving optimized files. |
| `output_mode` | `"dir"` | Use `"dir"` for an output folder or `"in-place"` to replace originals after approval. |
| `out_dir` | `"~/imgoptz-output"` | Output folder for `output_mode = "dir"`. `~/` means relative to the selected image folder. |
| `jpeg.quality` | `78` | MozJPEG quality. |
| `png.pngquant_quality` | `"40-95"` | pngquant quality range. |
| `debug_log` | `false` | Write a detailed per-run debug log when true. |

Invalid config values warn at startup and fall back per option. Unknown settings warn and are ignored, except the editor-only `$schema` metadata field.

## Development

Root app code is in `src/`. The `mozjpeg/` and `oxipng/` folders are vendor/submodule sources, not the app implementation.

This project targets Windows. Use the PowerShell scripts in this workspace because Odin is available from PowerShell here.

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

Tests:

```powershell
odin test src
```

Before handing off code changes, run:

```powershell
odin test src
./scripts/build.ps1
./scripts/build_dev.ps1
```

For debug memory leak checks, run the development executable through at least the `exit` prompt path and treat any `=== N allocations not freed: ===` report as a failure.

## Release Zip Checklist

For `v0.1.0`, the user-facing app asset should be one `.zip` containing the app root. The app root is the folder that contains `imgoptz.exe`; all runtime paths resolve relative to that folder.

Include these app files:

```text
imgoptz.exe
README.txt
LICENSE.txt
imgoptz.json
schema/imgoptz.schema.json
profiles/sRGB2014.icc
profiles/sRGB2014.LICENSE.txt
tools/mozjpeg/mozjpeg.exe
tools/mozjpeg/LICENSE.md
tools/mozjpeg/README.ijg
tools/mozjpeg/README-mozilla.txt
tools/oxipng/oxipng.exe
tools/oxipng/LICENSE
tools/pngquant/pngquant.exe
tools/pngquant/COPYRIGHT
tools/pngquant/SOURCE.txt
tools/imagemagick/magick.exe
tools/imagemagick/LICENSE.txt
tools/imagemagick/NOTICE.txt
tools/imagemagick/policy.xml
```

Do not include development-only files in the public release zip unless they are intentionally needed:

```text
imgoptz_dev.exe
imgoptz_dev.pdb
demo/
output/
```

Documentation and notice findings for the release bundle:

- `dist/LICENSE.txt` is needed because the app's MIT license should travel with the distributed binary.
- MozJPEG/libjpeg-turbo documentation must acknowledge: `This software is based in part on the work of the Independent JPEG Group.` The bundled `README.txt` includes this sentence, and the release zip should also keep `tools/mozjpeg/README.ijg` and `tools/mozjpeg/LICENSE.md`.
- Oxipng's MIT license notice should remain at `tools/oxipng/LICENSE`.
- ImageMagick's license and notice should remain at `tools/imagemagick/LICENSE.txt` and `tools/imagemagick/NOTICE.txt`. Keep `policy.xml` beside `magick.exe` so runtime policy is explicit.
- The ICC profile license should remain at `profiles/sRGB2014.LICENSE.txt`.
- pngquant 2.17.0 is GPLv3-or-later or commercially licensed. If releasing under GPLv3, keep `tools/pngquant/COPYRIGHT` and `tools/pngquant/SOURCE.txt`, and attach a complete `pngquant-2.17.0-source.zip` source asset to the same GitHub Release page as the app zip. If the release must have exactly one downloadable asset, include that complete pngquant source folder inside the app zip instead. If using a commercial pngquant license instead, keep the license proof outside the public repo and update `tools/pngquant/SOURCE.txt` before release.

Create the pngquant GPL source asset from a recursive checkout so the `libimagequant` submodule is included:

```powershell
git clone --branch 2.17.0 --recursive https://github.com/kornelski/pngquant.git pngquant-2.17.0-source
Compress-Archive -Path "pngquant-2.17.0-source" -DestinationPath "pngquant-2.17.0-source.zip"
```

The bundled `pngquant.exe` reports `2.17.0 (September 2021)`. The checked source tag is `kornelski/pngquant` commit `7bc73591f4de8517f01a54d8f475fea2df193b7c`, with `ImageOptim/libimagequant` submodule commit `a6cc4ade66710ec799ca41297f6d2c2b4070d0ff`.

## License

`imgoptz` is licensed under the MIT License. See `LICENSE` for the app license.

The release bundle also includes third-party executables and notices under `dist/tools/` and `dist/profiles/`. Those files retain their own licenses and notices.
