# tf_card_sorter

## Purpose
Many portable audio players (such as FiiO devices) do **not** sort folders or files alphabetically.  
Instead, they display them in the order that the filesystem (exFAT/FAT32) stored them.  

This PowerShell script fixes that by:
1. Backing up all files and folders from a TF/microSD card to a temporary folder.
2. Wiping the card completely.
3. Restoring all files and folders in **strict alphabetical order**.
4. Cleaning up the temporary backup folder when finished.

This forces devices that depend on write order to show content alphabetically.

---

## Features
- **Alphabetical restore**  
  Ensures that files and folders are written back in sorted order.

- **Two modes of operation**  
  - `TopLevel`: Only reorders root-level folders and files. Subfolders are copied as-is (faster).  
  - `All`: Reorders every folder and file at every depth (slower, but guarantees strict ordering).

- **Safety checks**  
  - Detects filesystem type (FAT32, exFAT, NTFS, etc.).  
  - Detects drive type (Removable vs Fixed vs System).  
  - Demands explicit confirmation (`ERASE` or `ERASESYS`) before touching fixed/system drives.  
  - Refuses unsafe drive types (network, CD-ROM, etc.).

- **Progress bars** for backup and restore operations.

- **Automatic cleanup** of the temporary backup folder.

---

## Requirements
- Windows 10/11  
- PowerShell 5.1 or later  
- Run as **Administrator**  
- Sufficient free disk space on the backup drive  

---

## Configuration
At the top of the script you’ll find the configuration block:

```powershell
# Drive letter of your TF card (include trailing backslash, e.g., "E:\")
$CardDrive = "E:\"

# Backup location (must be on a drive with enough free space)
$BackupRoot = "C:\TFCardTempBackup"

# Sorting scope:
#   "All"      = rewrite ALL folders/files at ALL levels in alphabetical order
#   "TopLevel" = ONLY reorder root-level entries; copy each root folder as a block
$SortScope = "TopLevel"

# Require an extra confirmation before wiping contents
$RequireConfirmation = $true

    $CardDrive: The TF card’s drive letter (e.g. "F:\").

    $BackupRoot: Temporary folder for backup (deleted when done).

    $SortScope:

        "TopLevel" → only fix root folder/file order.

        "All" → fix order everywhere.

    $RequireConfirmation: If true, script asks before wiping the card.
```


Usage

    Insert your TF card and note its drive letter (e.g. E:\).

    Edit the script configuration as described above.

    Open PowerShell as Administrator.

    Navigate to the folder containing the script:

```cd C:\Path\To\Script```

Allow script execution (temporary for this session):

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Run the script:

```    .\Sort-TFCard.ps1```

What Happens During Execution

    The script prints drive info (filesystem, drive type).

    If the drive is Fixed or System, it requires special confirmation:

        Type ERASE for fixed drives.

        Type ERASESYS for system drives.

    A plan summary is shown (drive, backup folder, estimated size, mode).

    You must type Y to confirm before wiping begins.

    Backup is created with a progress bar.

    The card is wiped completely.

    Files/folders are restored in the chosen alphabetical mode, with progress bars.

    The temporary backup folder is deleted automatically.

    Final confirmation message is printed.

Example

If your TF card is mounted as F:\ and you want all folders/files sorted everywhere:

```
$CardDrive  = "F:\"
$BackupRoot = "D:\CardBackup"
$SortScope  = "All"
```

Then run:

```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Sort-TFCard.ps1
```

Safety Notes

    Double-check $CardDrive before running. If you point it at the wrong drive, data will be lost.

    The script has strong safeguards, but use it with caution.

    Always back up important files before running.

    If you’d prefer to keep the backup, comment out or remove the cleanup section at the end of the script.

License

This script is provided as-is, without warranty. Use at your own risk.
