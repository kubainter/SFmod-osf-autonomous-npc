$ErrorActionPreference = "Stop"
# Source of truth: repo release dir. Compiling in-place inside the game dirs is
# flaky (PapyrusCompiler reports bogus "filename does not match script name" /
# crashes on game-directory paths), so we compile a copy under %TEMP% and deploy.
$GameRoot = $env:STARFIELD_ROOT
if (-not $GameRoot) {
    Write-Host "ERROR: set the STARFIELD_ROOT environment variable to your Starfield install directory." -ForegroundColor Red
    exit 1
}
$ScriptSource = "$PSScriptRoot\..\release\Data\Scripts\Source\OSF_AutonomousManagerScript.psc"
$PapyrusCompiler = "$GameRoot\Tools\Papyrus Compiler\PapyrusCompiler.exe"
$PapyrusSourceDir = "$GameRoot\Data\Scripts\Source"
$ReleasePex = "$PSScriptRoot\..\release\Data\Scripts\OSF_AutonomousManagerScript.pex"
$GamePex = "$GameRoot\Data\Scripts\OSF_AutonomousManagerScript.pex"

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("osf_pbuild_" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path "$work\out" -Force | Out-Null
try {
    Copy-Item -Path $ScriptSource -Destination "$work\OSF_AutonomousManagerScript.psc" -Force
    Copy-Item -Path $ScriptSource -Destination "$PapyrusSourceDir\OSF_AutonomousManagerScript.psc" -Force

    $FlagsFile = "$PapyrusSourceDir\Base\Starfield_Papyrus_Flags.flg"
    $IncludePaths = "$PapyrusSourceDir;$PapyrusSourceDir\Base"

    & $PapyrusCompiler "$work\OSF_AutonomousManagerScript.psc" -f="$FlagsFile" -o="$work\out" -i="$IncludePaths"
    if ($LASTEXITCODE -ne 0) { throw "PapyrusCompiler exit code $LASTEXITCODE" }

    $built = "$work\out\OSF_AutonomousManagerScript.pex"
    if (-not (Test-Path $built)) { throw "compiler produced no .pex" }

    Copy-Item $built $ReleasePex -Force
    Copy-Item $built $GamePex -Force
    Write-Host "OK: $((Get-Item $ReleasePex).Length) bytes -> release + game" -ForegroundColor Green
} finally {
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
