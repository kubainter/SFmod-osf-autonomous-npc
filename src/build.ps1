# build.ps1 — Full build pipeline for OSF Autonomous NPC Interactions mod
# 1. Copies Papyrus source to the game's Source directory
# 2. Compiles .psc → .pex using PapyrusCompiler
# 3. Generates .esm using build_esm.ps1
# 4. Copies OSF UI JSON settings to the game's OSFUI settings directory

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$ProjectDir     = "G:\Starfield\src\OSFAutonomous"
$ScriptSource   = "$ProjectDir\OSF_AutonomousManagerScript.psc"
$JsonSettings   = "$ProjectDir\osf.autonomous.json"

$PapyrusCompiler = "G:\Starfield\Tools\Papyrus Compiler\PapyrusCompiler.exe"
$PapyrusSourceDir = "G:\Starfield\Data\Scripts\Source"
$PapyrusOutputDir = "G:\Starfield\Data\Scripts"

$EsmBuildScript  = "$ProjectDir\build_esm.ps1"
$EsmOutputPath   = "G:\Starfield\Data\OSFAutonomous.esm"

$OsfUiSettingsDir = "G:\Starfield\Data\SFSE\Plugins\OSFUI\settings"

# ---------------------------------------------------------------------------
# Step 1: Copy Papyrus source to game's Source directory
# ---------------------------------------------------------------------------
Write-Host "`n[1/4] Copying Papyrus source..." -ForegroundColor Cyan

$targetPsc = "$PapyrusSourceDir\OSF_AutonomousManagerScript.psc"
Copy-Item -Path $ScriptSource -Destination $targetPsc -Force
Write-Host "  Copied: $ScriptSource → $targetPsc" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 2: Compile Papyrus script
# ---------------------------------------------------------------------------
Write-Host "`n[2/4] Compiling Papyrus script..." -ForegroundColor Cyan

if (-not (Test-Path $PapyrusCompiler)) {
    Write-Host "ERROR: Papyrus compiler not found at $PapyrusCompiler" -ForegroundColor Red
    exit 1
}

# PapyrusCompiler expects: PapyrusCompiler.exe <sourceFile> -f=<flagsFile> -o=<outputDir> -i=<includeDir>
# Starfield flags file is in the Base subdirectory
$FlagsFile = "$PapyrusSourceDir\Base\Starfield_Papyrus_Flags.flg"
# Include paths: Source (for OSF scripts) + Source\Base (for vanilla scripts) + Source\User (for third-party extender scripts like Cassiopeia)
$IncludePaths = "$PapyrusSourceDir;$PapyrusSourceDir\Base;$PapyrusSourceDir\User"

Write-Host "  Running: $PapyrusCompiler "$ScriptSource" -f="$FlagsFile" -o="$PapyrusOutputDir" -i="$IncludePaths"" -ForegroundColor DarkGray
$compilerDir = Split-Path $PapyrusCompiler
Push-Location $compilerDir
& $PapyrusCompiler $ScriptSource -f="$FlagsFile" -o="$PapyrusOutputDir" -i="$IncludePaths"
$compileExit = $LASTEXITCODE
Pop-Location

if ($compileExit -ne 0) {
    Write-Host "ERROR: Papyrus compilation failed with exit code $compileExit" -ForegroundColor Red
    exit 1
}

$compiledPex = "$PapyrusOutputDir\OSF_AutonomousManagerScript.pex"
if (Test-Path $compiledPex) {
    $pexSize = (Get-Item $compiledPex).Length
    Write-Host "  Compiled: $compiledPex ($pexSize bytes)" -ForegroundColor Green
} else {
    Write-Host "ERROR: Compiled .pex not found at $compiledPex" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Step 3: Generate ESM
# ---------------------------------------------------------------------------
Write-Host "`n[3/4] Generating ESM..." -ForegroundColor Cyan

& powershell -ExecutionPolicy Bypass -File $EsmBuildScript
$esmExit = $LASTEXITCODE

if ($esmExit -ne 0) {
    Write-Host "ERROR: ESM build failed with exit code $esmExit" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $EsmOutputPath)) {
    Write-Host "ERROR: ESM not found at $EsmOutputPath" -ForegroundColor Red
    exit 1
}

$esmSize = (Get-Item $EsmOutputPath).Length
Write-Host "  Generated: $EsmOutputPath ($esmSize bytes)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 4: Copy OSF UI JSON settings
# ---------------------------------------------------------------------------
Write-Host "`n[4/4] Installing OSF UI settings..." -ForegroundColor Cyan

if (-not (Test-Path $OsfUiSettingsDir)) {
    New-Item -ItemType Directory -Path $OsfUiSettingsDir -Force | Out-Null
}

$targetJson = "$OsfUiSettingsDir\osf.autonomous.json"
Copy-Item -Path $JsonSettings -Destination $targetJson -Force
Write-Host "  Copied: $JsonSettings → $targetJson" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " BUILD COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " ESM:     $EsmOutputPath ($esmSize bytes)"
Write-Host " Script:  $compiledPex ($pexSize bytes)"
Write-Host " Settings: $targetJson"
Write-Host ""
Write-Host " Next steps:" -ForegroundColor Yellow
Write-Host "  1. Activate OSFAutonomous.esm in Vortex/plugins.txt"
Write-Host "  2. Launch game and verify in SFSE logs"
Write-Host "  3. Open OSF UI (F10) to configure settings"
Write-Host ""
