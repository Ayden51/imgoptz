$ErrorActionPreference = "Stop"

odin build src -out:dist/imgoptz.exe -target:windows_amd64 -subsystem:console -o:speed -strict-style -vet -vet-packages:main -vet-unused-procedures -vet-tabs -disallow-do -warnings-as-errors
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}
