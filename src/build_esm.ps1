# build_esm.ps1 ??? Generates OSFAutonomous.esm (Starfield plugin)
# Creates a minimal QUST record with VMAD script binding to OSF_AutonomousManagerScript.
# Adapted from HighlightQuestGivers/build_esm.ps1.

$ErrorActionPreference = "Stop"

$EsmPath = "G:\Starfield\Data\OSFAutonomous.esm"
$RecordVersion = [uint16]0x0246   # Starfield record version (verified with Stroud patch)

# ---------------------------------------------------------------------------
# Binary helpers
# ---------------------------------------------------------------------------

function Concat-Bytes([byte[]]$a, [byte[]]$b) {
    $c = New-Object byte[] ($a.Length + $b.Length)
    if ($a.Length -gt 0) { [System.Buffer]::BlockCopy($a, 0, $c, 0, $a.Length) }
    if ($b.Length -gt 0) { [System.Buffer]::BlockCopy($b, 0, $c, $a.Length, $b.Length) }
    return $c
}

function New-SubrecordBytes([string]$type, [byte[]]$data) {
    $typeBytes = [System.Text.Encoding]::ASCII.GetBytes($type)
    $sizeBytes = [System.BitConverter]::GetBytes([uint16]$data.Length)
    $t = Concat-Bytes $typeBytes $sizeBytes
    return Concat-Bytes $t $data
}

function New-Record([string]$type, [uint32]$flags, [uint32]$formId, [byte[]]$subrecords) {
    $typeBytes = [System.Text.Encoding]::ASCII.GetBytes($type)
    $sizeBytes = [System.BitConverter]::GetBytes([uint32]$subrecords.Length)
    $flagBytes = [System.BitConverter]::GetBytes([uint32]$flags)
    $formIdBytes = [System.BitConverter]::GetBytes([uint32]$formId)
    $vcBytes = [System.BitConverter]::GetBytes([uint32]0x00000000)   # VC=0 for new records
    $verBytes = [System.BitConverter]::GetBytes([uint16]$RecordVersion)
    $vc2Bytes = [System.BitConverter]::GetBytes([uint16]0)
    $header = Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes $typeBytes $sizeBytes) $flagBytes) $formIdBytes) $vcBytes) $verBytes) $vc2Bytes
    return Concat-Bytes $header $subrecords
}

function New-Group([string]$label, [byte[]]$records) {
    $typeBytes = [System.Text.Encoding]::ASCII.GetBytes("GRUP")
    $sizeBytes = [System.BitConverter]::GetBytes([uint32]($records.Length + 24))
    $labelBytes = [System.Text.Encoding]::ASCII.GetBytes($label)
    $groupTypeBytes = [System.BitConverter]::GetBytes([uint32]0)
    $vcBytes = [System.BitConverter]::GetBytes([uint32]0)
    $verBytes = [System.BitConverter]::GetBytes([uint16]0)   # GRUP version=0 (matches OSFSeduce)
    $vc2Bytes = [System.BitConverter]::GetBytes([uint16]0)
    $header = Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes $typeBytes $sizeBytes) $labelBytes) $groupTypeBytes) $vcBytes) $verBytes) $vc2Bytes
    return Concat-Bytes $header $records
}

function Write-LPString([string]$s) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($s)
    $lenBytes = [System.BitConverter]::GetBytes([uint16]$bytes.Length)
    return Concat-Bytes $lenBytes $bytes
}

# ---------------------------------------------------------------------------
# TES4 Header
# ---------------------------------------------------------------------------

# HEDR: version 0.96 (Starfield standard), record count 1, flags 0x00000801
# All working Starfield plugins use HEDR version 0.96, NOT 1.0 (which is Skyrim/FO4)
$hedrData = [System.BitConverter]::GetBytes([float]0.96) `
          + [System.BitConverter]::GetBytes([uint32]1) `
          + [System.BitConverter]::GetBytes([uint32]0x00000801)
$hedrData = [byte[]]$hedrData
$subHedr = New-SubrecordBytes "HEDR" $hedrData

# CNAM: plugin name (null-terminated)
$cnamBytes = [System.Text.Encoding]::ASCII.GetBytes("OSFAutonomous`0")
$subCnam = New-SubrecordBytes "CNAM" $cnamBytes

# MAST: Starfield.esm (only master needed)
# NOTE: Do NOT add DATA subrecord after MAST — that is a legacy Skyrim/FO4 format.
# Starfield does not use it, and Wrye Bash rejects it with "Unexpected subrecord: TES4.DATA".
$subMaster = New-SubrecordBytes "MAST" ([System.Text.Encoding]::ASCII.GetBytes("Starfield.esm`0"))

# BNAM: author
$subBnam = New-SubrecordBytes "BNAM" ([System.Text.Encoding]::ASCII.GetBytes("Botan`0"))

# INCC: int 0
$subIncc = New-SubrecordBytes "INCC" ([System.BitConverter]::GetBytes([uint32]0))

# Assemble TES4 subrecords
$tes4Subrecords = Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes $subHedr $subCnam) $subMaster) $subBnam) $subIncc

# TES4 record: flags 0x00000001 (ESM only), FormID 0
# Do NOT use 0x00000101 — bit 0x100 is not valid for Starfield ESM files
$tes4Record = New-Record "TES4" 0x00000001 0 $tes4Subrecords

# ---------------------------------------------------------------------------
# QUST Record
# ---------------------------------------------------------------------------

# EDID: editor ID
$subEdid = New-SubrecordBytes "EDID" ([System.Text.Encoding]::ASCII.GetBytes("OSF_AutonomousManager_Quest`0"))

# VMAD: script binding — MUST come before FULL (matches working plugins)
# Version 6, object format 2, 1 script, 0 properties
$vmadParts = @()
$vmadParts += [byte[]](0x06, 0x00)         # version = 6
$vmadParts += [byte[]](0x02, 0x00)         # object format = 2
$vmadParts += [byte[]](0x01, 0x00)         # script count = 1
$vmadParts += Write-LPString "OSF_AutonomousManagerScript"  # script name
$vmadParts += [byte[]](0x00)               # script status = 0 (local)
$vmadParts += [System.BitConverter]::GetBytes([uint16]0)    # property count = 0

# Flatten VMAD
$vmadData = [byte[]]@()
foreach ($part in $vmadParts) {
    $vmadData = Concat-Bytes $vmadData $part
}
$subVmad = New-SubrecordBytes "VMAD" $vmadData

# FULL: display name — comes after VMAD
$subFull = New-SubrecordBytes "FULL" ([System.Text.Encoding]::ASCII.GetBytes("OSF Autonomous NPC Interactions`0"))

# DNAM: quest flags (12 bytes)
# First uint16: 0x0001 = Start Game Enabled (bit 0 only)
# This matches HighlightQuestGivers which is proven to work.
$questFlags = [byte[]](0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
$subDnam = New-SubrecordBytes "DNAM" $questFlags

# NEXT: empty (size=0) — matches HighlightQuestGivers and OSFSeduce
$subNext = New-SubrecordBytes "NEXT" ([byte[]]@())

# ANAM: quest data (4 bytes)
$subAnam = New-SubrecordBytes "ANAM" ([byte[]](0, 0, 0, 0))

# Assemble QUST subrecords — order: EDID, VMAD, FULL, DNAM, NEXT, ANAM
$questSubrecords = Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes (Concat-Bytes $subEdid $subVmad) $subFull) $subDnam) $subNext) $subAnam

# QUST record: FormID 0x01000801 (mod index 0x01 = first master, object 0x801)
$questFormId = 0x01000801
$questRecord = New-Record "QUST" 0 $questFormId $questSubrecords

# Wrap in top-level QUST group
$questGroup = New-Group "QUST" $questRecord

# ---------------------------------------------------------------------------
# Write ESM
# ---------------------------------------------------------------------------

$fullEsmBytes = Concat-Bytes $tes4Record $questGroup

[System.IO.File]::WriteAllBytes($EsmPath, $fullEsmBytes)
Write-Host "OSFAutonomous.esm created at $EsmPath (Size: $($fullEsmBytes.Length) bytes)" -ForegroundColor Green

# Hex preview (first 128 bytes)
$b = [System.IO.File]::ReadAllBytes($EsmPath)
$hex = ($b[0..127] | ForEach-Object { $_.ToString('X2') }) -join ' '
Write-Host "First 128 bytes: $hex" -ForegroundColor DarkGray

# Verify structure
Write-Host "`n=== Verification ===" -ForegroundColor Cyan
$tes4Size = [System.BitConverter]::ToUInt32($b, 4)
Write-Host "TES4 size: $tes4Size bytes"
$cnamOffset = 0
for ($i = 0; $i -lt $b.Length - 8; $i++) {
    if ($b[$i] -eq 0x43 -and $b[$i+1] -eq 0x4E -and $b[$i+2] -eq 0x41 -and $b[$i+3] -eq 0x4D) {
        $cnamLen = [System.BitConverter]::ToUInt16($b, $i + 4)
        $cnamVal = [System.Text.Encoding]::ASCII.GetString($b, $i + 6, $cnamLen - 1)
        Write-Host "CNAM: length=$cnamLen value=$cnamVal"
        break
    }
}
$grupOffset = 24 + $tes4Size
if ($grupOffset -lt $b.Length) {
    $grupType = [System.Text.Encoding]::ASCII.GetString($b, $grupOffset, 4)
    $grupSize = [System.BitConverter]::ToUInt32($b, $grupOffset + 4)
    $grupLabel = [System.Text.Encoding]::ASCII.GetString($b, $grupOffset + 8, 4)
    Write-Host "GRUP: type=$grupType size=$grupSize label=$grupLabel"
}
$questOffset = $grupOffset + 24
if ($questOffset -lt $b.Length) {
    $questType = [System.Text.Encoding]::ASCII.GetString($b, $questOffset, 4)
    $questSize = [System.BitConverter]::ToUInt32($b, $questOffset + 4)
    $questForm = [System.BitConverter]::ToUInt32($b, $questOffset + 12)
    $questVer = [System.BitConverter]::ToUInt16($b, $questOffset + 20)
    Write-Host "QUST: type=$questType size=$questSize formID=0x$($questForm.ToString('X8')) version=0x$($questVer.ToString('X4'))"
}

