param(
    [string]$Version = "1.1.2",
    [switch]$SkipTests
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
# Test gate — the suite must be green before packaging a release.
# Bypass only for emergencies: build_zip.ps1 -Version X.Y.Z -SkipTests
# ---------------------------------------------------------------------------
if (-not $SkipTests) {
    Write-Host "Running test gate (pytest)..." -ForegroundColor Cyan
    Push-Location $projectDir
    try {
        py -m pytest tests -x -q
        $testCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($testCode -ne 0) {
        Write-Host "`nERROR: test suite failed - refusing to build release." -ForegroundColor Red
        Write-Host "Fix the failures first, or bypass explicitly with -SkipTests." -ForegroundColor Red
        exit 1
    }
    Write-Host "Test gate: green.`n" -ForegroundColor Green
}

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
    'CHANGELOG.md'
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

# Remove empty directories left behind in staging (e.g. Scripts/Source after .psc strip)
$emptyDirs = Get-ChildItem $stagingDir -Recurse -Directory |
    Where-Object { -not (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue) } |
    Sort-Object { $_.FullName.Length } -Descending
foreach ($dir in $emptyDirs) {
    Write-Host "  Removing empty dir: $($dir.FullName.Replace($stagingDir, ''))" -ForegroundColor Yellow
    Remove-Item $dir.FullName -Recurse -Force
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

# Path to 7-Zip executable
$7zExe = "C:\Program Files\7-Zip\7z.exe"

if (Test-Path $7zExe) {
    Write-Host "Using 7-Zip for compression to preserve correct folder structure for MO2/Vortex..." -ForegroundColor Cyan
    # a: add, -tzip: zip archive format, -mx=5: normal compression, -r: recurse
    $7zArgs = @(
        "a", 
        "-tzip", 
        "-mx=5", 
        "`"$zipPath`"", 
        "`"$stagingDir\*`""
    )
    $process = Start-Process -FilePath $7zExe -ArgumentList $7zArgs -Wait -NoNewWindow -PassThru
    
    if ($process.ExitCode -ne 0) {
        Write-Host "ERROR: 7-Zip failed with exit code $($process.ExitCode). Aborting." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "WARNING: 7-Zip not found at $7zExe. Falling back to native Windows tar.exe..." -ForegroundColor Yellow
    # Windows 10/11 native tar.exe produces spec-compliant zip files with forward slashes (/)
    # We must Push-Location into the staging dir and use * instead of -C staging . 
    # to prevent tar from prepending './' to all paths, which breaks MO2/FOMOD.
    Push-Location -Path $stagingDir
    $tarArgs = @("-a", "-c", "-f", "`"$zipPath`"", "*")
    $process = Start-Process -FilePath "tar.exe" -ArgumentList $tarArgs -Wait -NoNewWindow -PassThru
    Pop-Location
    if ($process.ExitCode -ne 0) {
        Write-Host "ERROR: tar.exe failed with exit code $($process.ExitCode). Aborting." -ForegroundColor Red
        exit 1
    }
}

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
