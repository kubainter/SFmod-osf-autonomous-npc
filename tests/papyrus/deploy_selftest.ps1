# Compile + deploy the dev-only in-game self-test harness.
# Deploys to the GAME Data dir only - never into release/ (never ships).
param(
    [string]$GameRoot = $env:STARFIELD_ROOT
)

$ErrorActionPreference = "Stop"
if (-not $GameRoot) {
    Write-Host "ERROR: pass -GameRoot or set the STARFIELD_ROOT environment variable." -ForegroundColor Red
    exit 1
}

$SrcFile     = "$PSScriptRoot\OSF_SelfTests.psc"
$Compiler    = "$GameRoot\Tools\Papyrus Compiler\PapyrusCompiler.exe"
$SourceDir   = "$GameRoot\Data\Scripts\Source"
$GameScripts = "$GameRoot\Data\Scripts"

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("osf_selftest_" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path "$work\out" -Force | Out-Null
try {
    Copy-Item $SrcFile "$work\OSF_SelfTests.psc" -Force

    $FlagsFile = "$SourceDir\Base\Starfield_Papyrus_Flags.flg"
    $Include   = "$SourceDir;$SourceDir\Base"

    & $Compiler "$work\OSF_SelfTests.psc" -f="$FlagsFile" -o="$work\out" -i="$Include"
    if ($LASTEXITCODE -ne 0) { throw "PapyrusCompiler exit code $LASTEXITCODE" }

    $built = "$work\out\OSF_SelfTests.pex"
    if (-not (Test-Path $built)) { throw "compiler produced no .pex" }

    Copy-Item $built    "$GameScripts\OSF_SelfTests.pex" -Force
    Copy-Item $SrcFile  "$SourceDir\OSF_SelfTests.psc"   -Force
    Copy-Item "$PSScriptRoot\osfselftest.txt" "$GameRoot\osfselftest.txt" -Force

    Write-Host "OK: OSF_SelfTests.pex deployed -> $GameScripts" -ForegroundColor Green
    Write-Host "Run in console:  cgf `"OSF_SelfTests.RunAll`"   (or: bat osfselftest)" -ForegroundColor Cyan
    Write-Host "Results:         Documents\My Games\Starfield\Logs\Script\User\OSF_Autonomous.log" -ForegroundColor Cyan
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
