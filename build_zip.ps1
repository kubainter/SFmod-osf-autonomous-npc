param(
    [string]$Version = "1.0.4"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths — repo_upload is the single source of truth
# ---------------------------------------------------------------------------
$projectDir   = $PSScriptRoot                    # repo_upload/
$releaseSrc   = Join-Path $projectDir 'release'   # repo_upload/release/ (distributable files)
$zipsDir      = Join-Path $projectDir 'zips'      # repo_upload/zips/ (output)
$zipName      = "OSFAutonomous_v$Version.zip"
$zipPath      = Join-Path $zipsDir $zipName
$stagingDir   = Join-Path $projectDir 'staging'

# ---------------------------------------------------------------------------
# Distributable files — everything in repo_upload/release/
# This must NOT contain:
#   - .psc source files (those live in src/)
#   - dev_source/ or Python venvs
#   - nexus_description.md (that's for the Nexus page, not the mod archive)
# ---------------------------------------------------------------------------
$distributable = @(
    'Data',
    'fomod',
    'README.txt',
    'CHANGELOG.txt'
)

# ---------------------------------------------------------------------------
# Clean previous staging
# ---------------------------------------------------------------------------
if (Test-Path $stagingDir) {
    Remove-Item $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

if (-not (Test-Path $zipsDir)) {
    New-Item -ItemType Directory -Path $zipsDir -Force | Out-Null
}

# ---------------------------------------------------------------------------
# Copy distributable files to staging
# ---------------------------------------------------------------------------
Write-Host "Staging distributable files from repo_upload/release/..." -ForegroundColor Cyan
foreach ($item in $distributable) {
    $src = Join-Path $releaseSrc $item
    if (-not (Test-Path $src)) {
        Write-Host "  SKIP (not found): $item" -ForegroundColor Yellow
        continue
    }
    $dst = Join-Path $stagingDir $item
    if ((Get-Item $src).PSIsContainer) {
        Copy-Item $src $dst -Recurse -Force
    } else {
        Copy-Item $src $dst -Force
    }
    Write-Host "  OK: $item"
}

# ---------------------------------------------------------------------------
# Verify critical files exist in staging
# ---------------------------------------------------------------------------
Write-Host "`nVerifying staged files..." -ForegroundColor Cyan
$critical = @(
    'Data\OSFAutonomous.esm',
    'Data\Scripts\OSF_AutonomousManagerScript.pex',
    'Data\OSF\osfautonomous-solo.osf.json',
    'Data\OSF\osfautonomous-solo.sounds.json',
    'Data\OSF\Autonomous\Animations\solo_standing_touch.glb',
    'fomod\info.xml',
    'fomod\ModuleConfig.xml'
)
$allOk = $true
foreach ($file in $critical) {
    $path = Join-Path $stagingDir $file
    if (Test-Path $path) {
        $size = (Get-Item $path).Length
        Write-Host "  OK: $file ($size bytes)"
    } else {
        Write-Host "  MISSING: $file" -ForegroundColor Red
        $allOk = $false
    }
}

# ---------------------------------------------------------------------------
# Verify NO .psc source files leaked into staging
# ---------------------------------------------------------------------------
$pscFiles = Get-ChildItem $stagingDir -Recurse -Filter '*.psc' -ErrorAction SilentlyContinue
if ($pscFiles) {
    Write-Host "`n  WARNING: .psc files found in staging (should not be in release):" -ForegroundColor Yellow
    foreach ($f in $pscFiles) {
        Write-Host "    $($f.FullName.Replace($stagingDir, ''))" -ForegroundColor Yellow
    }
    Write-Host "  Removing .psc files from staging..." -ForegroundColor Yellow
    $pscFiles | Remove-Item -Force
}

if (-not $allOk) {
    Write-Host "`nERROR: Critical files missing from staging. Aborting." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Count staged files
# ---------------------------------------------------------------------------
$stagedCount = (Get-ChildItem $stagingDir -Recurse -File).Count
$stagedSize = (Get-ChildItem $stagingDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Host "`nStaged: $stagedCount files, $([math]::Round($stagedSize / 1KB, 1)) KB" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Remove old zip if exists
# ---------------------------------------------------------------------------
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

# ---------------------------------------------------------------------------
# Create zip
# ---------------------------------------------------------------------------
Write-Host "`nPackaging -> $zipPath..." -ForegroundColor Cyan
Compress-Archive -Path (Join-Path $stagingDir '*') -DestinationPath $zipPath -Force

# ---------------------------------------------------------------------------
# Cleanup staging
# ---------------------------------------------------------------------------
Remove-Item $stagingDir -Recurse -Force

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
$zipSize = (Get-Item $zipPath).Length
$hash = Get-FileHash $zipPath -Algorithm SHA256

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "  Release built successfully!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  File:   $zipPath"
Write-Host "  Size:   $([math]::Round($zipSize / 1KB, 1)) KB ($zipSize bytes)"
Write-Host "  SHA256: $($hash.Hash)"
Write-Host "  Files:  $stagedCount"
Write-Host "=========================================" -ForegroundColor Green
