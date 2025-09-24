<#
.SYNOPSIS
    Rewrites a FAT32/exFAT TF card’s directory entries in alphabetical order
    by backing up, wiping, and restoring — with progress bars and safety checks.

.DESCRIPTION
    Many portable players (e.g., FiiO) list items in physical write order.
    This script:
      1) Targets the card by drive letter
      2) Detects filesystem + drive type and adds strong safeguards
      3) Backs up all content with progress
      4) Wipes the card (after confirmations)
      5) Restores in alphabetical order with optional depth:
           - "All": full-depth rewrite (slower, most thorough)
           - "TopLevel": only reorder root entries; copy each root folder as a block (faster)
      6) Cleans up temporary backup folder automatically when done

    WARNING: This DELETES all files from the target drive before re-copying.

.NOTES
    - Run PowerShell as Administrator
    - Ensure backup location has enough free space
    - Tested on Windows 10/11 PowerShell 5.1+
#>

# =========================
# ====== CONFIG START =====
# =========================

# Drive letter of your TF card (include trailing backslash, e.g., "E:\")
$CardDrive = "K:\"

# Backup location (must be on a drive with enough free space)
$BackupRoot = "E:\TFCardTempBackup"

# Sorting scope:
#   "All"      = rewrite ALL folders/files at ALL levels in alphabetical order
#   "TopLevel" = ONLY reorder root-level entries; copy each root folder as a block
$SortScope = "TopLevel"   # "All" or "TopLevel"

# Require an extra confirmation before wiping contents
$RequireConfirmation = $true

# =======================
# ====== CONFIG END =====
# =======================

# Fail fast on errors (safer for destructive ops)
$ErrorActionPreference = "Stop"

# -------- Helper: Progress-safe percentage calc --------
function Get-Percent([int]$i,[int]$total) {
    if ($total -le 0) { return 100 }
    return [int](($i / $total) * 100)
}

# -------- Preconditions: drive existence --------
if (-not (Test-Path $CardDrive)) {
    throw "Drive $CardDrive not found. Update `$CardDrive and try again."
}

# -------- Safety: detect filesystem + drive type & guardrails --------
$driveLetter = $CardDrive.Substring(0,1)
$vol = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop
$driveType = $vol.DriveType.ToString()    # e.g., Removable, Fixed
$fsType    = $vol.FileSystem              # e.g., exFAT, FAT32, NTFS

Write-Host "Detected drive: $CardDrive"
Write-Host "  Filesystem: $fsType"
Write-Host "  DriveType:  $driveType (Removable=external media; Fixed=internal/system)"
Write-Host ""

# Strong block for non-removable types we shouldn't touch
if ($driveType -in @('CD-ROM','Network','No Root Directory','Unknown','RAM Disk')) {
    throw "Refusing to operate on drive type '$driveType'. Choose a valid removable/fixed storage device."
}

# Extra-strong protection for system drive (e.g., C:\)
$systemDriveLetter = $env:SystemDrive.Substring(0,1)
$looksLikeSystem = ($driveType -eq 'Fixed' -and $driveLetter -eq $systemDriveLetter) -or (Test-Path (Join-Path $CardDrive 'Windows'))

if ($looksLikeSystem) {
    Write-Warning "The selected drive ($CardDrive) appears to be the SYSTEM drive."
    Write-Warning "CONTINUING WILL ERASE YOUR OPERATING SYSTEM FILES."
    $confirmSys = Read-Host "To proceed anyway, type EXACTLY: ERASESYS"
    if ($confirmSys -ne "ERASESYS") { throw "User aborted — refusing to wipe a system drive." }
}
elseif ($driveType -eq 'Fixed') {
    # Non-system fixed drive (internal HDD/SSD) — still very risky
    Write-Warning "The selected drive ($CardDrive) is a FIXED internal drive."
    Write-Warning "Proceeding will ERASE all contents on this drive."
    $confirmFixed = Read-Host "To proceed, type EXACTLY: ERASE"
    if ($confirmFixed -ne "ERASE") { throw "User aborted — refusing to wipe a fixed drive." }
}

# If removable but not FAT32/exFAT, allow but warn
if ($driveType -eq 'Removable' -and $fsType -notin @('FAT32','exFAT')) {
    Write-Warning "Drive is removable but formatted as '$fsType'. Script is intended for FAT32/exFAT."
    $confirmFs = Read-Host "Continue anyway? Type 'YES' to continue"
    if ($confirmFs -ne "YES") { throw "User aborted due to unexpected filesystem." }
}

# -------- Prepare backup folder --------
if (Test-Path $BackupRoot) {
    Write-Host "Cleaning existing backup folder: $BackupRoot"
    Remove-Item -Recurse -Force $BackupRoot
}
New-Item -ItemType Directory -Path $BackupRoot | Out-Null

# -------- Estimate size & verify free space --------
$cardFilesForSize = Get-ChildItem -LiteralPath $CardDrive -Recurse -Force -File -ErrorAction SilentlyContinue
$cardSizeBytes = ($cardFilesForSize | Measure-Object Length -Sum).Sum
$backupDrive = Get-PSDrive -Name ($BackupRoot.Substring(0,1))
if ($backupDrive.Free -lt $cardSizeBytes) {
    throw "Not enough free space on backup drive. Required: $([math]::Round($cardSizeBytes/1GB,2)) GB, Available: $([math]::Round($backupDrive.Free/1GB,2)) GB."
}

Write-Host ""
Write-Host "=== PLAN ==="
Write-Host "Card drive:        $CardDrive"
Write-Host "Filesystem:        $fsType ($driveType)"
Write-Host "Backup location:   $BackupRoot"
Write-Host "Estimated size:    $([math]::Round($cardSizeBytes/1GB,2)) GB"
Write-Host "Sort scope:        $SortScope"
Write-Host ""

if ($RequireConfirmation) {
    $resp = Read-Host "Proceed to BACK UP, WIPE, and RESTORE in '$SortScope' alphabetical order? Type 'Y' to continue"
    if ($resp -ne 'Y') { throw "User aborted." }
}

# ======================
# ======= BACKUP =======
# ======================
Write-Host "`nBacking up contents with progress..."
# 1) Preserve full directory tree first (keeps empty dirs)
$allDirs = Get-ChildItem -LiteralPath $CardDrive -Recurse -Force -Directory | Sort-Object FullName
foreach ($d in $allDirs) {
    $rel = $d.FullName.Substring($CardDrive.Length).TrimStart('\')
    $destDir = Join-Path $BackupRoot $rel
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
}

# 2) Copy all files with progress
$allFiles = Get-ChildItem -LiteralPath $CardDrive -Recurse -Force -File | Sort-Object FullName
$total = $allFiles.Count
$i = 0
$activity = "Backing up files"
foreach ($f in $allFiles) {
    $i++
    $rel = $f.FullName.Substring($CardDrive.Length).TrimStart('\')
    $destPath = Join-Path $BackupRoot $rel

    Write-Progress -Activity $activity -Status "$i of $total" -PercentComplete (Get-Percent $i $total) -CurrentOperation $rel

    $parent = Split-Path $destPath -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Copy-Item -LiteralPath $f.FullName -Destination $destPath -Force
}
Write-Progress -Activity $activity -Completed
Write-Host "Backup complete -> $BackupRoot"

# ======================
# ======== WIPE ========
# ======================
Write-Host "`nWiping target drive..."
Get-ChildItem -LiteralPath $CardDrive -Force | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Recurse -Force
}
Write-Host "Wipe complete."

# ====================================
# ======== RESTORE (Filtered) ========
# ====================================
Write-Host "`nRestoring in alphabetical order (scope: $SortScope)..."

switch ($SortScope) {

    "TopLevel" {
        # --- TOP-LEVEL MODE ---
        # 1) Create root-level directories in alphabetical order
        $rootDirs = Get-ChildItem -LiteralPath $BackupRoot -Force -Directory | Sort-Object Name
        $totalDirs = $rootDirs.Count
        $d = 0
        $actDirs = "Restoring root-level directories"
        foreach ($dir in $rootDirs) {
            $d++
            Write-Progress -Activity $actDirs -Status "$d of $totalDirs" -PercentComplete (Get-Percent $d $totalDirs) -CurrentOperation $dir.Name
            $target = Join-Path $CardDrive $dir.Name
            New-Item -ItemType Directory -Force -Path $target | Out-Null
        }
        Write-Progress -Activity $actDirs -Completed

        # 2) Copy root-level files in alphabetical order
        $rootFiles = Get-ChildItem -LiteralPath $BackupRoot -Force -File | Sort-Object Name
        $totalRootFiles = $rootFiles.Count
        $rf = 0
        $actFiles = "Restoring root-level files"
        foreach ($file in $rootFiles) {
            $rf++
            Write-Progress -Activity $actFiles -Status "$rf of $totalRootFiles" -PercentComplete (Get-Percent $rf $totalRootFiles) -CurrentOperation $file.Name
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $CardDrive $file.Name) -Force
        }
        Write-Progress -Activity $actFiles -Completed

        # 3) Copy each root-level directory subtree as a block (fast)
        $actTree = "Restoring folder contents"
        $t = 0
        foreach ($dir in $rootDirs) {
            $t++
            Write-Progress -Activity $actTree -Status "$t of $totalDirs" -PercentComplete (Get-Percent $t $totalDirs) -CurrentOperation $dir.Name
            Copy-Item -LiteralPath $dir.FullName -Destination $CardDrive -Recurse -Force
        }
        Write-Progress -Activity $actTree -Completed
    }

    "All" {
        # --- FULL-DEPTH MODE ---
        # 1) Recreate ALL directories in alphabetical order
        $restoreDirs = Get-ChildItem -LiteralPath $BackupRoot -Recurse -Directory | Sort-Object FullName
        $totalDirs = $restoreDirs.Count
        $di = 0
        $activityDirs = "Restoring directories"
        foreach ($dir in $restoreDirs) {
            $di++
            $rel = $dir.FullName.Substring($BackupRoot.Length).TrimStart('\')
            $target = Join-Path $CardDrive $rel
            Write-Progress -Activity $activityDirs -Status "$di of $totalDirs" -PercentComplete (Get-Percent $di $totalDirs) -CurrentOperation $rel
            New-Item -ItemType Directory -Force -Path $target | Out-Null
        }
        Write-Progress -Activity $activityDirs -Completed

        # 2) Copy ALL files in alphabetical order
        $restoreFiles = Get-ChildItem -LiteralPath $BackupRoot -Recurse -File | Sort-Object FullName
        $totalRestore = $restoreFiles.Count
        $ri = 0
        $activityFiles = "Restoring files (alphabetical)"
        foreach ($f in $restoreFiles) {
            $ri++
            $rel = $f.FullName.Substring($BackupRoot.Length).TrimStart('\')
            $target = Join-Path $CardDrive $rel
            Write-Progress -Activity $activityFiles -Status "$ri of $totalRestore" -PercentComplete (Get-Percent $ri $totalRestore) -CurrentOperation $rel
            $parent = Split-Path $target -Parent
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            Copy-Item -LiteralPath $f.FullName -Destination $target -Force
        }
        Write-Progress -Activity $activityFiles -Completed
    }

    default {
        throw "Invalid SortScope '$SortScope'. Use 'All' or 'TopLevel'."
    }
}

# ======================
# ======= CLEANUP ======
# ======================
Write-Host "`nCleaning up temporary backup folder..."
try {
    Remove-Item -Recurse -Force $BackupRoot
    Write-Host "Temporary folder $BackupRoot has been deleted."
}
catch {
    Write-Warning "Could not delete $BackupRoot. Please remove it manually."
}

Write-Host "`nAll done! Contents on $CardDrive have been rewritten in '$SortScope' order."
