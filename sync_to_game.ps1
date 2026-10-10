param(
    [Parameter(Mandatory=$true)]
    [string]$GameData
)

$ErrorActionPreference = 'Stop'
$projectDir = $PSScriptRoot
$releaseData = Join-Path $projectDir 'release\Data'

if (-not (Test-Path $releaseData)) {
    Write-Host "ERROR: release\Data/ not found at $releaseData" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $GameData)) {
    Write-Host "ERROR: game Data/ not found at $GameData" -ForegroundColor Red
    exit 1
}

Write-Host "Syncing release\Data/ -> $GameData" -ForegroundColor Cyan
Write-Host ""

# Files to sync (only our mod's files)
$files = @(
    'OSFAutonomous.esm',
    'Scripts\OSF_AutonomousManagerScript.pex',
    'Scripts\Source\OSF_AutonomousManagerScript.psc',
    'OSF\osfautonomous-solo.osf.json',
    'OSF\osfautonomous-solo.sounds.json',
    'OSF\Autonomous\Animations\solo_standing_touch.glb',
    'SFSE\Plugins\OSFUI\settings\osf.autonomous.json',
    'Sound\OSF\Autonomous\Female\ohh.wem',
    'Sound\OSF\Autonomous\Female\oh_yeah.wem',
    'Sound\OSF\Autonomous\Female\do_it.wem',
    'Sound\OSF\Autonomous\Female\love_it.wem'
)

$copied = 0
$skipped = 0
foreach ($file in $files) {
    $src = Join-Path $releaseData $file
    $dst = Join-Path $GameData $file

    if (-not (Test-Path $src)) {
        Write-Host "  SKIP (not in release): $file" -ForegroundColor Yellow
        $skipped++
        continue
    }

    # Create destination directory if needed
    $dstDir = Split-Path $dst -Parent
    if (-not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }

    # Check if file differs
    $copyIt = $true
    if (Test-Path $dst) {
        $srcHash = (Get-FileHash $src -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash $dst -Algorithm SHA256).Hash
        if ($srcHash -eq $dstHash) {
            $copyIt = $false
        }
    }

    if ($copyIt) {
        Copy-Item $src $dst -Force
        Write-Host "  COPIED: $file" -ForegroundColor Green
        $copied++
    } else {
        Write-Host "  OK:     $file (already in sync)"
    }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  Sync complete: $copied copied, $skipped skipped" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
