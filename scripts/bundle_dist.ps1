[CmdletBinding()]
param(
	[string]$PackagePath = "dist/imgoptz-windows-64-bit.zip",
	[string]$PngquantSourcePackagePath = "dist/pngquant-3.0.3-source.zip"
)

$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ManifestPath = Join-Path $PSScriptRoot "dependencies.json"
$Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$DistDir = Join-Path $RootDir "dist"
$CacheDir = Join-Path $RootDir ($Manifest.cache_dir -replace "/", [IO.Path]::DirectorySeparatorChar)
$DownloadDir = Join-Path $CacheDir "downloads"
$PackageOutputPath = Join-Path $RootDir ($PackagePath -replace "/", [IO.Path]::DirectorySeparatorChar)
$PngquantSourceOutputPath = Join-Path $RootDir ($PngquantSourcePackagePath -replace "/", [IO.Path]::DirectorySeparatorChar)
$BundleWorkDir = Join-Path $DistDir ".bundle"
$PackageRoot = Join-Path $BundleWorkDir "imgoptz"
$PngquantSourceRoot = Join-Path $BundleWorkDir "pngquant-source"

function Convert-ToNativePath {
	param([string]$Path)
	return $Path -replace "/", [IO.Path]::DirectorySeparatorChar
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

function Assert-RequiredFile {
	param([string]$RelativePath)
	$path = Join-DistPath $RelativePath
	if (-not (Test-Path -LiteralPath $path)) {
		throw "Missing required bundle file: $path"
	}
}

function Test-DependencyFilesPresent {
	foreach ($dependency in $Manifest.dependencies) {
		$paths = @($dependency.dist_exe_path) + @($dependency.dist_license_paths)
		foreach ($relativePath in $paths) {
			if (-not (Test-Path -LiteralPath (Join-DistPath $relativePath))) {
				return $false
			}
		}
	}
	return $true
}

function Invoke-VersionCheck {
	param($Dependency)

	if ([string]::IsNullOrWhiteSpace($Dependency.expected_version_regex)) {
		return
	}

	$exePath = Join-DistPath $Dependency.dist_exe_path
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
}

function Get-Dependency {
	param([string]$Name)
	$dependency = $Manifest.dependencies | Where-Object { $_.name -eq $Name } | Select-Object -First 1
	if (-not $dependency) {
		throw "Dependency '$Name' is missing from $ManifestPath."
	}
	return $dependency
}

function Get-TopDirectory {
	param([string]$Root)

	$directories = @(Get-ChildItem -LiteralPath $Root -Directory)
	if ($directories.Count -eq 1) {
		return $directories[0].FullName
	}
	return $Root
}

function Download-PinnedFile {
	param($Dependency)

	Ensure-Directory $DownloadDir
	$downloadPath = Join-Path $DownloadDir $Dependency.download_file
	if (-not (Test-Path -LiteralPath $downloadPath)) {
		Write-Host "Downloading $($Dependency.name) source package for release"
		Invoke-WebRequest -Uri $Dependency.download_url -OutFile $downloadPath -MaximumRedirection 5
	}

	Assert-FileHash $downloadPath $Dependency.sha256
	return $downloadPath
}

function Write-PngquantSourcePackage {
	$dependency = Get-Dependency "pngquant"
	$archivePath = Download-PinnedFile $dependency
	$sourceParent = Split-Path -Parent $PngquantSourceOutputPath
	Ensure-Directory $sourceParent

	if (Test-Path -LiteralPath $PngquantSourceOutputPath) {
		Remove-Item -LiteralPath $PngquantSourceOutputPath -Force
	}

	if (Test-Path -LiteralPath $PngquantSourceRoot) {
		Remove-Item -LiteralPath $PngquantSourceRoot -Recurse -Force
	}
	New-Item -ItemType Directory -Path $PngquantSourceRoot | Out-Null

	$tar = Get-Command "tar" -ErrorAction SilentlyContinue
	if (-not $tar) {
		throw "tar is required to prepare the pngquant source package. Install tar or add it to PATH, then rerun scripts/bundle_dist.ps1."
	}

	& $tar.Source -xf $archivePath -C $PngquantSourceRoot
	if ($LASTEXITCODE -ne 0) {
		throw "Extracting pngquant source failed with exit code $LASTEXITCODE."
	}

	$sourceRoot = Get-TopDirectory $PngquantSourceRoot
	$sourceNotice = @(
		"pngquant $($dependency.version) corresponding source for imgoptz distribution",
		"",
		"Source URL: $($dependency.source_url)",
		"Source SHA-256: $($dependency.source_sha256)",
		"This archive was prepared by scripts/bundle_dist.ps1 from the verified crates.io source package."
	)
	Set-Content -LiteralPath (Join-Path $sourceRoot "IMGOPTZ-SOURCE.txt") -Value $sourceNotice -Encoding UTF8
	$minimumZipTime = [datetime]"1980-01-01T00:00:00"
	Get-Item -LiteralPath $sourceRoot | Where-Object { $_.LastWriteTime -lt $minimumZipTime } | ForEach-Object { $_.LastWriteTime = $minimumZipTime }
	Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force | Where-Object { $_.LastWriteTime -lt $minimumZipTime } | ForEach-Object { $_.LastWriteTime = $minimumZipTime }

	Compress-Archive -LiteralPath $sourceRoot -DestinationPath $PngquantSourceOutputPath -CompressionLevel Optimal
	Write-Host "pngquant source package written to $PngquantSourceOutputPath"
}

if (-not (Test-DependencyFilesPresent)) {
	Write-Host "Runtime dependencies are incomplete; running setup_dist_deps.ps1."
	& "$PSScriptRoot\setup_dist_deps.ps1"
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}

& "$PSScriptRoot\build.ps1"
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}

$requiredFiles = @(
	"imgoptz.exe",
	"imgoptz.json",
	"LICENSE.txt",
	"README.txt",
	"schema/imgoptz.schema.json"
)

foreach ($relativePath in $requiredFiles) {
	Assert-RequiredFile $relativePath
}

foreach ($dependency in $Manifest.dependencies) {
	$paths = @($dependency.dist_exe_path) + @($dependency.dist_license_paths)
	foreach ($relativePath in $paths) {
		Assert-RequiredFile $relativePath
	}
	Invoke-VersionCheck $dependency
}

if (Test-Path -LiteralPath $BundleWorkDir) {
	Remove-Item -LiteralPath $BundleWorkDir -Recurse -Force
}
New-Item -ItemType Directory -Path $PackageRoot | Out-Null

$bundleItems = @(
	"imgoptz.exe",
	"imgoptz.json",
	"LICENSE.txt",
	"README.txt",
	"schema",
	"profiles",
	"tools"
)

foreach ($item in $bundleItems) {
	Copy-Item -LiteralPath (Join-DistPath $item) -Destination $PackageRoot -Recurse -Force
}

Get-ChildItem -LiteralPath $PackageRoot -Recurse -Force -File -Filter ".gitkeep" | Remove-Item -Force

if (Test-Path -LiteralPath $PackageOutputPath) {
	Remove-Item -LiteralPath $PackageOutputPath -Force
}

$packageParent = Split-Path -Parent $PackageOutputPath
if (-not (Test-Path -LiteralPath $packageParent)) {
	New-Item -ItemType Directory -Path $packageParent | Out-Null
}

Compress-Archive -LiteralPath $PackageRoot -DestinationPath $PackageOutputPath -CompressionLevel Optimal
Write-PngquantSourcePackage
Remove-Item -LiteralPath $BundleWorkDir -Recurse -Force

Write-Host "Bundle written to $PackageOutputPath"
