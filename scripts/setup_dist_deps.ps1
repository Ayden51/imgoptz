[CmdletBinding()]
param(
	[switch]$Force
)

$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ManifestPath = Join-Path $PSScriptRoot "dependencies.json"
$Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$DistDir = Join-Path $RootDir "dist"
$CacheDir = Join-Path $RootDir ($Manifest.cache_dir -replace "/", [IO.Path]::DirectorySeparatorChar)
$DownloadDir = Join-Path $CacheDir "downloads"
$ExtractDir = Join-Path $CacheDir "extract"
$BuildDir = Join-Path $CacheDir "build"

function Convert-ToNativePath {
	param([string]$Path)
	return $Path -replace "/", [IO.Path]::DirectorySeparatorChar
}

function Join-RootPath {
	param([string]$RelativePath)
	return Join-Path $RootDir (Convert-ToNativePath $RelativePath)
}

function Join-DistPath {
	param([string]$RelativePath)
	return Join-Path $DistDir (Convert-ToNativePath $RelativePath)
}

function Ensure-Directory {
	param([string]$Path)
	if (-not (Test-Path -LiteralPath $Path)) {
		New-Item -ItemType Directory -Path $Path | Out-Null
	}
}

function Reset-Directory {
	param([string]$Path)
	if (Test-Path -LiteralPath $Path) {
		Remove-Item -LiteralPath $Path -Recurse -Force
	}
	New-Item -ItemType Directory -Path $Path | Out-Null
}

function Reset-RuntimeDirectory {
	param([string]$Path)
	Ensure-Directory $Path
	Get-ChildItem -LiteralPath $Path -Force | Where-Object { $_.Name -ne ".gitkeep" } | Remove-Item -Recurse -Force
}

function Assert-CommandAvailable {
	param(
		[string]$Name,
		[string]$Purpose
	)

	if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
		throw "$Name is required for $Purpose. Install it or add it to PATH, then rerun scripts/setup_dist_deps.ps1."
	}
}

function Quote-CmdArgument {
	param([string]$Value)
	return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-VisualStudioDevCmd {
	$vswherePath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (-not (Test-Path -LiteralPath $vswherePath)) {
		throw "vswhere.exe was not found. Install Visual Studio with C++ build tools or add vswhere to its standard Visual Studio Installer path, then rerun scripts/setup_dist_deps.ps1."
	}

	$installationPath = & $vswherePath -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
	if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installationPath)) {
		throw "Visual Studio with the C++ x64 toolchain was not found. Install the C++ build tools and Windows SDK, then rerun scripts/setup_dist_deps.ps1."
	}

	$devCmdPath = Join-Path $installationPath.Trim() "Common7\Tools\VsDevCmd.bat"
	if (-not (Test-Path -LiteralPath $devCmdPath)) {
		throw "Visual Studio developer command script was not found at $devCmdPath. Repair Visual Studio C++ tools, then rerun scripts/setup_dist_deps.ps1."
	}

	return $devCmdPath
}

function Assert-LastExitCode {
	param([string]$Action)
	if ($LASTEXITCODE -ne 0) {
		throw "$Action failed with exit code $LASTEXITCODE."
	}
}

function Assert-FileHash {
	param(
		[string]$Path,
		[string]$ExpectedSha256
	)

	$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
	if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
		throw "Checksum mismatch for $Path. Expected $ExpectedSha256, got $actual."
	}
}

function Download-PinnedFile {
	param($Dependency)

	Ensure-Directory $DownloadDir
	$downloadPath = Join-Path $DownloadDir $Dependency.download_file
	if ($Force -and (Test-Path -LiteralPath $downloadPath)) {
		Remove-Item -LiteralPath $downloadPath -Force
	}

	if (-not (Test-Path -LiteralPath $downloadPath)) {
		Write-Host "Downloading $($Dependency.name) $($Dependency.version)"
		Invoke-WebRequest -Uri $Dependency.download_url -OutFile $downloadPath -MaximumRedirection 5
	}

	Assert-FileHash $downloadPath $Dependency.sha256
	return $downloadPath
}

function Expand-PinnedArchive {
	param(
		[string]$ArchivePath,
		[string]$ArchiveType,
		[string]$DestinationPath
	)

	Reset-Directory $DestinationPath
	switch ($ArchiveType) {
		"zip" {
			Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationPath -Force
		}
		"7z" {
			$sevenZip = Get-Command "7z" -ErrorAction SilentlyContinue
			if ($sevenZip) {
				& $sevenZip.Source x $ArchivePath "-o$DestinationPath" -y | Out-Host
				Assert-LastExitCode "Extracting $ArchivePath with 7z"
				break
			}

			$tar = Get-Command "tar" -ErrorAction SilentlyContinue
			if (-not $tar) {
				throw "7z or tar is required to extract $ArchivePath. Install one of them or add it to PATH, then rerun scripts/setup_dist_deps.ps1."
			}

			& $tar.Source -xf $ArchivePath -C $DestinationPath
			Assert-LastExitCode "Extracting $ArchivePath with tar"
		}
		"crate" {
			Assert-CommandAvailable "tar" "extracting pngquant's crates.io source package"
			$tar = Get-Command "tar"
			& $tar.Source -xf $ArchivePath -C $DestinationPath
			Assert-LastExitCode "Extracting $ArchivePath"
		}
		default {
			throw "Unsupported archive type '$ArchiveType'."
		}
	}
}

function Find-RequiredFile {
	param(
		[string]$Root,
		[string]$FileName
	)

	$file = Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction Stop | Where-Object { $_.Name -ieq $FileName } | Select-Object -First 1
	if (-not $file) {
		throw "Could not find $FileName under $Root."
	}
	return $file.FullName
}

function Copy-RequiredFile {
	param(
		[string]$SourcePath,
		[string]$DestinationPath
	)

	Ensure-Directory (Split-Path -Parent $DestinationPath)
	Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Copy-FromExtract {
	param(
		[string]$ExtractRoot,
		[string]$FileName,
		[string]$DestinationPath
	)

	Copy-RequiredFile (Find-RequiredFile $ExtractRoot $FileName) $DestinationPath
}

function Get-Dependency {
	param([string]$Name)
	$dependency = $Manifest.dependencies | Where-Object { $_.name -eq $Name } | Select-Object -First 1
	if (-not $dependency) {
		throw "Dependency '$Name' is missing from $ManifestPath."
	}
	return $dependency
}

function Get-TopExtractDirectory {
	param([string]$ExtractRoot)

	$directories = @(Get-ChildItem -LiteralPath $ExtractRoot -Directory)
	if ($directories.Count -eq 1) {
		return $directories[0].FullName
	}
	return $ExtractRoot
}

function Install-ImageMagick {
	param($Dependency)

	$archivePath = Download-PinnedFile $Dependency
	$extractPath = Join-Path $ExtractDir $Dependency.name
	Expand-PinnedArchive $archivePath $Dependency.archive_type $extractPath
	$destination = Join-DistPath "tools/imagemagick"
	Reset-RuntimeDirectory $destination

	Copy-FromExtract $extractPath "magick.exe" (Join-Path $destination "magick.exe")
	Copy-FromExtract $extractPath "LICENSE.txt" (Join-Path $destination "LICENSE.txt")
	Copy-FromExtract $extractPath "NOTICE.txt" (Join-Path $destination "NOTICE.txt")
	Copy-FromExtract $extractPath "policy.xml" (Join-Path $destination "policy.xml")
}

function Install-MozJpeg {
	param($Dependency)

	Assert-CommandAvailable "cmake" "building MozJPEG from source"
	Assert-CommandAvailable "nasm" "building MozJPEG SIMD code"
	Assert-CommandAvailable "ninja" "building MozJPEG with Visual Studio C++ tools"
	$devCmdPath = Get-VisualStudioDevCmd

	$archivePath = Download-PinnedFile $Dependency
	$extractPath = Join-Path $ExtractDir $Dependency.name
	Expand-PinnedArchive $archivePath $Dependency.archive_type $extractPath
	$sourcePath = Get-TopExtractDirectory $extractPath
	$mozBuildDir = Join-Path $BuildDir "mozjpeg"
	Reset-Directory $mozBuildDir

	$configureCommand = "call $(Quote-CmdArgument $devCmdPath) -arch=x64 -host_arch=x64 && cmake -S $(Quote-CmdArgument $sourcePath) -B $(Quote-CmdArgument $mozBuildDir) -G Ninja -DCMAKE_BUILD_TYPE=Release -DENABLE_SHARED=FALSE -DWITH_JPEG8=1 -DPNG_SUPPORTED=FALSE"
	& cmd.exe /d /s /c $configureCommand
	Assert-LastExitCode "Configuring MozJPEG"
	$buildCommand = "call $(Quote-CmdArgument $devCmdPath) -arch=x64 -host_arch=x64 && cmake --build $(Quote-CmdArgument $mozBuildDir) --target cjpeg-static"
	& cmd.exe /d /s /c $buildCommand
	Assert-LastExitCode "Building MozJPEG cjpeg-static"

	$cjpeg = Get-ChildItem -LiteralPath $mozBuildDir -Recurse -File -Filter "cjpeg-static.exe" | Select-Object -First 1
	if (-not $cjpeg) {
		throw "MozJPEG build completed but cjpeg-static.exe was not found under $mozBuildDir."
	}

	$destination = Join-DistPath "tools/mozjpeg"
	Reset-RuntimeDirectory $destination
	Copy-RequiredFile $cjpeg.FullName (Join-Path $destination "mozjpeg.exe")
	Copy-RequiredFile (Join-Path $sourcePath "LICENSE.md") (Join-Path $destination "LICENSE.md")
	Copy-RequiredFile (Join-Path $sourcePath "README.ijg") (Join-Path $destination "README.ijg")
	Copy-RequiredFile (Join-Path $sourcePath "README-mozilla.txt") (Join-Path $destination "README-mozilla.txt")
}

function Install-Oxipng {
	param($Dependency)

	$archivePath = Download-PinnedFile $Dependency
	$extractPath = Join-Path $ExtractDir $Dependency.name
	Expand-PinnedArchive $archivePath $Dependency.archive_type $extractPath
	$destination = Join-DistPath "tools/oxipng"
	Reset-RuntimeDirectory $destination

	Copy-FromExtract $extractPath "oxipng.exe" (Join-Path $destination "oxipng.exe")
	Copy-FromExtract $extractPath "LICENSE.txt" (Join-Path $destination "LICENSE")
}

function Install-Pngquant {
	param($Dependency)

	Assert-CommandAvailable "cargo" "building pngquant from crates.io source"
	Assert-CommandAvailable "rustc" "building pngquant from crates.io source"

	$archivePath = Download-PinnedFile $Dependency
	$extractPath = Join-Path $ExtractDir $Dependency.name
	Expand-PinnedArchive $archivePath $Dependency.archive_type $extractPath
	$sourcePath = Get-TopExtractDirectory $extractPath

	& cargo build --release --manifest-path (Join-Path $sourcePath "Cargo.toml")
	Assert-LastExitCode "Building pngquant"

	$binaryPath = Join-Path $sourcePath "target/release/pngquant.exe"
	if (-not (Test-Path -LiteralPath $binaryPath)) {
		throw "pngquant build completed but pngquant.exe was not found at $binaryPath."
	}

	$destination = Join-DistPath "tools/pngquant"
	Reset-RuntimeDirectory $destination
	Copy-RequiredFile $binaryPath (Join-Path $destination "pngquant.exe")
	Copy-RequiredFile (Join-Path $sourcePath "COPYRIGHT") (Join-Path $destination "COPYRIGHT")

	$sourceNotice = @(
		"pngquant $($Dependency.version) corresponding source",
		"",
		"Source URL: $($Dependency.source_url)",
		"Source SHA-256: $($Dependency.source_sha256)",
		"Downloaded by: scripts/setup_dist_deps.ps1 using scripts/dependencies.json",
		"Build command: cargo build --release --manifest-path <extracted-source>/Cargo.toml",
		"Bundled binary: tools/pngquant/pngquant.exe",
		"License notice: tools/pngquant/COPYRIGHT copied from the same verified source package.",
		"Release source archive: scripts/bundle_dist.ps1 prepares pngquant-$($Dependency.version)-source.zip beside the imgoptz app bundle."
	)
	Set-Content -LiteralPath (Join-Path $destination "SOURCE.txt") -Value $sourceNotice -Encoding UTF8
}

function Install-SrgbProfile {
	param($Dependency)

	$downloadPath = Download-PinnedFile $Dependency
	$destination = Join-DistPath "profiles"
	Reset-RuntimeDirectory $destination
	Copy-RequiredFile $downloadPath (Join-Path $destination "sRGB2014.icc")

	$licenseNotice = @(
		"Copyright (c) 2015 International Color Consortium",
		"",
		"This profile is made available by the International Color Consortium, and may be copied, distributed, embedded, made,",
		"used, and sold without restriction. Altered versions of this profile shall have the original identification and",
		"copyright information removed and shall not be misrepresented as the original profile.",
		"",
		"Source: $($Dependency.source_url)",
		"SHA-256: $($Dependency.source_sha256)",
		"License reference: https://registry.color.org/profile-library/"
	)
	Set-Content -LiteralPath (Join-Path $destination "sRGB2014.LICENSE.txt") -Value $licenseNotice -Encoding UTF8
}

function Invoke-VersionCheck {
	param($Dependency)

	if ([string]::IsNullOrWhiteSpace($Dependency.expected_version_regex)) {
		return
	}

	$exePath = Join-DistPath $Dependency.dist_exe_path
	if (-not (Test-Path -LiteralPath $exePath)) {
		throw "Missing installed executable: $exePath"
	}

	[string[]]$versionArgs = switch ($Dependency.name) {
		"imagemagick" { @("-version") }
		"mozjpeg" { @("-version") }
		"oxipng" { @("--version") }
		"pngquant" { @("--version") }
		default { @() }
	}

	$output = & $exePath $versionArgs 2>&1
	if ($LASTEXITCODE -ne 0) {
		throw "$($Dependency.name) version check failed with exit code $LASTEXITCODE.`n$output"
	}

	$text = ($output | Out-String).Trim()
	if ($text -notmatch $Dependency.expected_version_regex) {
		throw "$($Dependency.name) version output did not match '$($Dependency.expected_version_regex)':`n$text"
	}

	Write-Host "Verified $($Dependency.name) $($Dependency.version)"
}

function Assert-InstalledFiles {
	param($Dependency)

	$paths = @($Dependency.dist_exe_path) + @($Dependency.dist_license_paths)
	foreach ($relativePath in $paths) {
		$path = Join-DistPath $relativePath
		if (-not (Test-Path -LiteralPath $path)) {
			throw "Missing required runtime file: $path"
		}
	}
}

Ensure-Directory $DistDir
Ensure-Directory $DownloadDir
Ensure-Directory $ExtractDir
Ensure-Directory $BuildDir

Install-ImageMagick (Get-Dependency "imagemagick")
Install-MozJpeg (Get-Dependency "mozjpeg")
Install-Oxipng (Get-Dependency "oxipng")
Install-Pngquant (Get-Dependency "pngquant")
Install-SrgbProfile (Get-Dependency "srgb2014")

foreach ($dependency in $Manifest.dependencies) {
	Assert-InstalledFiles $dependency
	Invoke-VersionCheck $dependency
}

Write-Host "Dependency setup complete. Runtime tools are installed under dist/."
