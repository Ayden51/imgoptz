$ErrorActionPreference = "Stop"

& "$PSScriptRoot\build_dev.ps1"
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}

& "$PSScriptRoot\..\dist\imgoptz_dev.exe"
exit $LASTEXITCODE
