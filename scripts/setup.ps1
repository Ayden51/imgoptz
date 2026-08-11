param(
    [string]$InstallRoot = $PSScriptRoot,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-InstallRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $PSScriptRoot
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Get-Download {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Sha256,
        [string]$OutputPath
    )

    if ($Force -and (Test-Path -LiteralPath $OutputPath)) {
        Remove-Item -LiteralPath $OutputPath -Force
    }
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        Write-Host "Downloading $Name"
        Invoke-WebRequest -Uri $Url -OutFile $OutputPath
    }

    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $OutputPath).Hash
    if ($actual -ne $Sha256) {
        throw "Checksum mismatch for $Name. Expected $Sha256, got $actual."
    }
}

function Expand-Dependency {
    param(
        [string]$Name,
        [string]$Url,
        [string]$Sha256,
        [string]$ArchiveName,
        [string]$Destination,
        [string[]]$CleanPaths
    )

    $archivePath = Join-Path $script:DownloadDir $ArchiveName
    Get-Download -Name $Name -Url $Url -Sha256 $Sha256 -OutputPath $archivePath

    foreach ($path in $CleanPaths) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
    Ensure-Directory $Destination
    Write-Host "Extracting $Name"
    Expand-Archive -LiteralPath $archivePath -DestinationPath $Destination -Force
}

function Assert-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing expected file: $Path"
    }
}

$Root = Resolve-InstallRoot $InstallRoot
$ToolsDir = Join-Path $Root "tools"
$ProfilesDir = Join-Path $Root "profiles"
$srgbPath = Join-Path $ProfilesDir "sRGB2014.icc"
$script:DownloadDir = Join-Path $Root ".imgoptz-deps"

Assert-File $srgbPath
Ensure-Directory $ToolsDir
Ensure-Directory $script:DownloadDir

Write-Host "Installing imgoptz runtime tools into $Root"
Write-Host "You are responsible for reviewing and accepting each tool license."

Expand-Dependency `
    -Name "libvips 8.18.5" `
    -Url "https://github.com/libvips/build-win64-mxe/releases/download/v8.18.5/vips-dev-x64-web-8.18.5-static.zip" `
    -Sha256 "109C23D6A71328D821AB5B08CB0212242EF7B7E038739F4E1F706B00BF990E10" `
    -ArchiveName "vips-dev-x64-web-8.18.5-static.zip" `
    -Destination $ToolsDir `
    -CleanPaths @((Join-Path $ToolsDir "vips-dev-8.18"))

Expand-Dependency `
    -Name "MozJPEG 4.0.3" `
    -Url "https://github.com/mozilla/mozjpeg/releases/download/v4.0.3/mozjpeg-v4.0.3-win-x64.zip" `
    -Sha256 "C8DB69B2BBF9CFF05447E60454B55317F719D9793B9100597BFCD4682836F7EE" `
    -ArchiveName "mozjpeg-v4.0.3-win-x64.zip" `
    -Destination (Join-Path $ToolsDir "mozjpeg") `
    -CleanPaths @((Join-Path $ToolsDir "mozjpeg"))

Expand-Dependency `
    -Name "pngquant 2.17.0 Windows binary" `
    -Url "https://pngquant.org/pngquant-windows.zip" `
    -Sha256 "BD0257AEECCFE446A4CD764927E26F8AF6051796F28ABED104307284107B120D" `
    -ArchiveName "pngquant-windows.zip" `
    -Destination $ToolsDir `
    -CleanPaths @((Join-Path $ToolsDir "pngquant"))

Expand-Dependency `
    -Name "Oxipng 10.1.1" `
    -Url "https://github.com/oxipng/oxipng/releases/download/v10.1.1/oxipng-10.1.1-x86_64-pc-windows-msvc.zip" `
    -Sha256 "0F57B33ABB46C76258AC8E20BE604A48208141D514BC2936B5200ED626976DD8" `
    -ArchiveName "oxipng-10.1.1-x86_64-pc-windows-msvc.zip" `
    -Destination $ToolsDir `
    -CleanPaths @((Join-Path $ToolsDir "oxipng-10.1.1-x86_64-pc-windows-msvc"))

$vips = Join-Path $ToolsDir "vips-dev-8.18\bin\vips.exe"
$vipsheader = Join-Path $ToolsDir "vips-dev-8.18\bin\vipsheader.exe"
$mozjpeg = Join-Path $ToolsDir "mozjpeg\static\Release\cjpeg-static.exe"
$pngquant = Join-Path $ToolsDir "pngquant\pngquant.exe"
$oxipng = Join-Path $ToolsDir "oxipng-10.1.1-x86_64-pc-windows-msvc\oxipng.exe"

Assert-File $vips
Assert-File $vipsheader
Assert-File $mozjpeg
Assert-File $pngquant
Assert-File $oxipng
Assert-File $srgbPath

Write-Host "Verifying installed tools"
& $vips --version | Out-Host
& $mozjpeg -version 2>&1 | Out-Host
& $pngquant --version | Out-Host
& $oxipng --version | Out-Host

Write-Host "Dependency setup complete. You can now run imgoptz.exe."
