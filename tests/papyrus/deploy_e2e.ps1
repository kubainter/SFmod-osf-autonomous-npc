# Compile + deploy the dev-only in-game E2E test harness.
# Deploys to the GAME Data dir only - never into release/ (never ships).
param(
    [string]$GameRoot = "G:\Starfield"
)

$ErrorActionPreference = "Stop"

$SrcFile     = "$PSScriptRoot\OSF_E2ETests.psc"
$Compiler    = "$GameRoot\Tools\Papyrus Compiler\PapyrusCompiler.exe"
$SourceDir   = "$GameRoot\Data\Scripts\Source"
$GameScripts = "$GameRoot\Data\Scripts"

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("osf_e2e_" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path "$work\out" -Force | Out-Null
try {
    Copy-Item $SrcFile "$work\OSF_E2ETests.psc" -Force

    $FlagsFile = "$SourceDir\Base\Starfield_Papyrus_Flags.flg"
    $Include   = "$SourceDir;$SourceDir\Base"

    & $Compiler "$work\OSF_E2ETests.psc" -f="$FlagsFile" -o="$work\out" -i="$Include"
    if ($LASTEXITCODE -ne 0) { throw "PapyrusCompiler exit code $LASTEXITCODE" }

    $built = "$work\out\OSF_E2ETests.pex"
    if (-not (Test-Path $built)) { throw "compiler produced no .pex" }

    Copy-Item $built    "$GameScripts\OSF_E2ETests.pex" -Force
    Copy-Item $SrcFile  "$SourceDir\OSF_E2ETests.psc"   -Force
    Copy-Item "$PSScriptRoot\osfe2e.txt" "$GameRoot\osfe2e.txt" -Force

    Write-Host "OK: OSF_E2ETests.pex deployed -> $GameScripts" -ForegroundColor Green
    Write-Host "Run in console:  cgf `"OSF_E2ETests.RunAll`"   (or: bat osfe2e)" -ForegroundColor Cyan
    Write-Host "Results:         Documents\My Games\Starfield\Logs\Script\User\OSF_Autonomous.N.log" -ForegroundColor Cyan
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
