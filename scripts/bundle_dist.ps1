[CmdletBinding()]
param(
	[string]$PackagePath = "dist/imgoptz-windows-amd64.zip"
)

$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ManifestPath = Join-Path $PSScriptRoot "dependencies.json"
$Manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$DistDir = Join-Path $RootDir "dist"
$PackageOutputPath = Join-Path $RootDir ($PackagePath -replace "/", [IO.Path]::DirectorySeparatorChar)
$BundleWorkDir = Join-Path $DistDir ".bundle"
$PackageRoot = Join-Path $BundleWorkDir "imgoptz"

function Convert-ToNativePath {
	param([string]$Path)
	return $Path -replace "/", [IO.Path]::DirectorySeparatorChar
}

function Join-DistPath {
	param([string]$RelativePath)
	return Join-Path $DistDir (Convert-ToNativePath $RelativePath)
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

if (Test-Path -LiteralPath $PackageOutputPath) {
	Remove-Item -LiteralPath $PackageOutputPath -Force
}

$packageParent = Split-Path -Parent $PackageOutputPath
if (-not (Test-Path -LiteralPath $packageParent)) {
	New-Item -ItemType Directory -Path $packageParent | Out-Null
}

Compress-Archive -LiteralPath $PackageRoot -DestinationPath $PackageOutputPath -CompressionLevel Optimal
Remove-Item -LiteralPath $BundleWorkDir -Recurse -Force

Write-Host "Bundle written to $PackageOutputPath"
