$ErrorActionPreference = "Stop"
$ProjectDir = "G:\Starfield\src\OSFAutonomous"
$ScriptSource = "$ProjectDir\OSF_AutonomousManagerScript.psc"
$PapyrusCompiler = "G:\Starfield\Tools\Papyrus Compiler\PapyrusCompiler.exe"
$PapyrusSourceDir = "G:\Starfield\Data\Scripts\Source"
$PapyrusOutputDir = "G:\Starfield\Data\Scripts"

Copy-Item -Path $ScriptSource -Destination "$PapyrusSourceDir\OSF_AutonomousManagerScript.psc" -Force

$FlagsFile = "$PapyrusSourceDir\Base\Starfield_Papyrus_Flags.flg"
$IncludePaths = "$PapyrusSourceDir;$PapyrusSourceDir\Base"

& $PapyrusCompiler "$PapyrusSourceDir\OSF_AutonomousManagerScript.psc" -f="$FlagsFile" -o="$PapyrusOutputDir" -i="$IncludePaths"

$pex = "$PapyrusOutputDir\OSF_AutonomousManagerScript.pex"
if (Test-Path $pex) {
    $size = (Get-Item $pex).Length
    Write-Host "OK: $size bytes" -ForegroundColor Green
} else {
    Write-Host "FAIL" -ForegroundColor Red
    exit 1
}
