param(
    [string]$InstallRoot = $PSScriptRoot,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Wait-To-Close {
    [void](Read-Host "Press Enter to close this window")
}

function Resolve-InstallRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $PSScriptRoot
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Install root does not exist: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Assert-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing expected file: $Path"
    }
}

function Test-AppRoot {
    param([string]$Root)

    $requiredFiles = @(
        "imgoptz.exe",
        "imgoptz.json",
        "profiles\sRGB2014.icc"
    )

    $missing = @()
    foreach ($file in $requiredFiles) {
        $path = Join-Path $Root $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $missing += $file
        }
    }
    return $missing
}

function Join-RootPath {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    return (Join-Path $Root $RelativePath)
}

function Test-DependencyInToolsFolder {
    param(
        [object]$Dependency,
        [string]$Root
    )

    $missing = @()
    foreach ($file in $Dependency.LocalFiles) {
        $path = Join-RootPath -Root $Root -RelativePath $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $missing += $file
        }
    }

    return [pscustomobject]@{
        FoundAll = ($missing.Count -eq 0)
        Missing = $missing
    }
}

function Test-DependencyOnPath {
    param([object]$Dependency)

    $found = @()
    $missing = @()
    foreach ($commandName in $Dependency.PathCommands) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            $missing += $commandName
        } else {
            $found += "$commandName => $($command.Source)"
        }
    }

    return [pscustomobject]@{
        FoundAll = ($missing.Count -eq 0)
        Found = $found
        Missing = $missing
    }
}

function Show-ToolStatus {
    param(
        [object[]]$Dependencies,
        [string]$Root
    )

    Write-Host ""
    Write-Host "Tool status"
    Write-Host "-----------"

    $statuses = @()
    foreach ($dependency in $Dependencies) {
        $local = Test-DependencyInToolsFolder -Dependency $dependency -Root $Root
        $path = Test-DependencyOnPath -Dependency $dependency

        Write-Host ""
        Write-Host $dependency.DisplayName
        if ($local.FoundAll) {
            Write-Host "[OK] Found in app tools folder."
        } else {
            Write-Host "[INFO] Not complete in app tools folder."
            foreach ($file in $local.Missing) {
                Write-Host "          Missing: $file"
            }
        }

        if ($path.FoundAll) {
            Write-Host "[OK] Found on PATH."
            foreach ($entry in $path.Found) {
                Write-Host "     $entry"
            }
        } else {
            Write-Host "[INFO] Not complete on PATH."
            foreach ($commandName in $path.Missing) {
                Write-Host "       Missing command: $commandName"
            }
        }

        if ($local.FoundAll -or $path.FoundAll) {
            Write-Host "[OK] Available to imgoptz."
        } else {
            Write-Host "[MISSING] Not found in either location. Setup will download it into the app tools folder after acknowledgement."
        }

        $statuses += [pscustomobject]@{
            Dependency = $dependency
            LocalFound = $local.FoundAll
            PathFound = $path.FoundAll
            Available = ($local.FoundAll -or $path.FoundAll)
        }
    }

    return $statuses
}

function Show-LicenseNotice {
    param([object[]]$Dependencies)

    Write-Host ""
    Write-Host "Important dependency and license notice"
    Write-Host "---------------------------------------"
    Write-Host "imgoptz is an orchestrator. It calls these external tools to optimize images: libvips, MozJPEG, pngquant, and Oxipng."
    Write-Host "imgoptz does not grant or cover the licenses for those tools for your purpose or use case."
    Write-Host "This setup helper downloads the specific official tool archives listed below and extracts them into the app tools folder."
    Write-Host "You are responsible for reviewing each tool's license and complying with it for your use case."
    Write-Host ""
    Write-Host "Tool     Version  Official source"
    Write-Host "----     -------  ---------------"
    foreach ($dependency in $Dependencies) {
        Write-Host ("{0,-8} {1,-8} {2}" -f $dependency.Name, $dependency.Version, $dependency.Url)
    }
}

function Read-LicenseAcknowledgement {
    while ($true) {
        $answer = Read-Host "Type yes or no to acknowledge that you are responsible for these tool licenses"
        $normalized = $answer.Trim().ToLowerInvariant()
        if ($normalized -eq "yes") {
            return $true
        }
        if ($normalized -eq "no") {
            return $false
        }
        Write-Host "Please type exactly yes or no."
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
        [object]$Dependency,
        [string]$Root
    )

    $archivePath = Join-Path $script:DownloadDir $Dependency.ArchiveName
    Get-Download -Name $Dependency.DisplayName -Url $Dependency.Url -Sha256 $Dependency.Sha256 -OutputPath $archivePath

    foreach ($relativePath in $Dependency.CleanPaths) {
        $path = Join-RootPath -Root $Root -RelativePath $relativePath
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

    $destination = Join-RootPath -Root $Root -RelativePath $Dependency.Destination
    Ensure-Directory $destination
    Write-Host "Extracting $($Dependency.DisplayName)"
    Expand-Archive -LiteralPath $archivePath -DestinationPath $destination -Force
}

function Resolve-VerificationPath {
    param(
        [string]$Root,
        [object]$Dependency,
        [int]$Index
    )

    $pathCommand = Get-Command $Dependency.PathCommands[$Index] -ErrorAction SilentlyContinue
    if ($null -ne $pathCommand) {
        return $pathCommand.Source
    }

    $localPath = Join-RootPath -Root $Root -RelativePath $Dependency.LocalFiles[$Index]
    if (Test-Path -LiteralPath $localPath -PathType Leaf) {
        return $localPath
    }

    throw "Missing expected tool: $($Dependency.DisplayName)"
}

function Verify-AvailableTools {
    param(
        [string]$Root,
        [object[]]$Dependencies
    )

    $vips = Resolve-VerificationPath -Root $Root -Dependency $Dependencies[0] -Index 0
    $vipsheader = Resolve-VerificationPath -Root $Root -Dependency $Dependencies[0] -Index 1
    $mozjpeg = Resolve-VerificationPath -Root $Root -Dependency $Dependencies[1] -Index 0
    $pngquant = Resolve-VerificationPath -Root $Root -Dependency $Dependencies[2] -Index 0
    $oxipng = Resolve-VerificationPath -Root $Root -Dependency $Dependencies[3] -Index 0

    Assert-File $vips
    Assert-File $vipsheader
    Assert-File $mozjpeg
    Assert-File $pngquant
    Assert-File $oxipng

    Write-Host ""
    Write-Host "Verifying available tools"
    & $vips --version | Out-Host
    & $mozjpeg -version 2>&1 | Out-Host
    & $pngquant --version | Out-Host
    & $oxipng --version | Out-Host
}

$Dependencies = @(
    [pscustomobject]@{
        Name = "libvips"
        DisplayName = "libvips 8.18.5"
        Version = "8.18.5"
        Url = "https://github.com/libvips/build-win64-mxe/releases/download/v8.18.5/vips-dev-x64-web-8.18.5-static.zip"
        Sha256 = "109C23D6A71328D821AB5B08CB0212242EF7B7E038739F4E1F706B00BF990E10"
        ArchiveName = "vips-dev-x64-web-8.18.5-static.zip"
        Destination = "tools"
        CleanPaths = @("tools\vips-dev-8.18")
        LocalFiles = @("tools\vips-dev-8.18\bin\vips.exe", "tools\vips-dev-8.18\bin\vipsheader.exe")
        PathCommands = @("vips.exe", "vipsheader.exe")
    }
    [pscustomobject]@{
        Name = "MozJPEG"
        DisplayName = "MozJPEG 4.0.3"
        Version = "4.0.3"
        Url = "https://github.com/mozilla/mozjpeg/releases/download/v4.0.3/mozjpeg-v4.0.3-win-x64.zip"
        Sha256 = "C8DB69B2BBF9CFF05447E60454B55317F719D9793B9100597BFCD4682836F7EE"
        ArchiveName = "mozjpeg-v4.0.3-win-x64.zip"
        Destination = "tools\mozjpeg"
        CleanPaths = @("tools\mozjpeg")
        LocalFiles = @("tools\mozjpeg\static\Release\cjpeg-static.exe")
        PathCommands = @("cjpeg-static.exe")
    }
    [pscustomobject]@{
        Name = "pngquant"
        DisplayName = "pngquant 2.17.0 Windows binary"
        Version = "2.17.0"
        Url = "https://pngquant.org/pngquant-windows.zip"
        Sha256 = "BD0257AEECCFE446A4CD764927E26F8AF6051796F28ABED104307284107B120D"
        ArchiveName = "pngquant-windows.zip"
        Destination = "tools"
        CleanPaths = @("tools\pngquant")
        LocalFiles = @("tools\pngquant\pngquant.exe")
        PathCommands = @("pngquant.exe")
    }
    [pscustomobject]@{
        Name = "Oxipng"
        DisplayName = "Oxipng 10.1.1"
        Version = "10.1.1"
        Url = "https://github.com/oxipng/oxipng/releases/download/v10.1.1/oxipng-10.1.1-x86_64-pc-windows-msvc.zip"
        Sha256 = "0F57B33ABB46C76258AC8E20BE604A48208141D514BC2936B5200ED626976DD8"
        ArchiveName = "oxipng-10.1.1-x86_64-pc-windows-msvc.zip"
        Destination = "tools"
        CleanPaths = @("tools\oxipng-10.1.1-x86_64-pc-windows-msvc")
        LocalFiles = @("tools\oxipng-10.1.1-x86_64-pc-windows-msvc\oxipng.exe")
        PathCommands = @("oxipng.exe")
    }
)

try {
    $Root = Resolve-InstallRoot $InstallRoot
    $missingAppFiles = @(Test-AppRoot -Root $Root)
    if ($missingAppFiles.Count -gt 0) {
        Write-Host "imgoptz setup cannot continue."
        Write-Host "This script must be run from the imgoptz app root: the folder that contains imgoptz.exe."
        Write-Host ""
        Write-Host "Checked folder: $Root"
        Write-Host "Missing app files:"
        foreach ($file in $missingAppFiles) {
            Write-Host "  $file"
        }
        Write-Host ""
        Wait-To-Close
        exit 1
    }

    $ToolsDir = Join-RootPath -Root $Root -RelativePath "tools"
    $script:DownloadDir = Join-RootPath -Root $Root -RelativePath ".imgoptz-deps"

    Write-Host "imgoptz dependency setup"
    Write-Host "App root: $Root"

    $statuses = Show-ToolStatus -Dependencies $Dependencies -Root $Root
    Show-LicenseNotice -Dependencies $Dependencies

    $acknowledged = Read-LicenseAcknowledgement
    if (-not $acknowledged) {
        Write-Host ""
        Write-Host "No tools were downloaded. Run this setup again if you decide to install the dependencies."
        Wait-To-Close
        exit 1
    }

    $dependenciesToInstall = @()
    foreach ($status in $statuses) {
        if ($Force -or (-not $status.Available)) {
            $dependenciesToInstall += $status.Dependency
        }
    }

    if ($dependenciesToInstall.Count -eq 0) {
        Write-Host ""
        Write-Host "All tools are already available from PATH or the app tools folder. Nothing to download."
    } else {
        Ensure-Directory $ToolsDir
        Ensure-Directory $script:DownloadDir

        Write-Host ""
        Write-Host "Installing missing app-local tools"
        foreach ($dependency in $dependenciesToInstall) {
            Expand-Dependency -Dependency $dependency -Root $Root
        }
    }

    Verify-AvailableTools -Root $Root -Dependencies $Dependencies

    Write-Host ""
    Write-Host "Dependency setup complete. You can now run imgoptz.exe."
    Wait-To-Close
} catch {
    Write-Host ""
    Write-Host "Setup failed: $($_.Exception.Message)"
    Wait-To-Close
    exit 1
}
