# Deezer Relocation Tool

**[Русская версия / Russian version](README.ru.md)**

A PowerShell script that moves the Deezer desktop app — together with its settings and downloaded music — from drive `C:` to any location you choose, and can move everything back at any time.

## The problem

The Deezer desktop app for Windows does not ask where to install itself. It always installs to drive `C:` and downloads all saved music there as well:

```
C:\Users\<username>\AppData\Local\Programs\deezer-desktop   (application)
C:\Users\<username>\AppData\Roaming\Deezer                  (settings + downloaded music)
```

If your `C:` drive is short on space, this quickly becomes a problem.

## The solution

The script moves both folders to a drive of your choice and creates **directory symbolic links** (symlinks) at the original locations. Deezer keeps working exactly as before — it "thinks" it still lives in `AppData` — while all files, including future music downloads, are actually stored on the new drive.

## Features

- **Two interface languages** — English (default) and Russian, selected at startup.
- **Two modes:**
  - **Move** — relocate Deezer to a new folder;
  - **Restore** — copy everything back to drive `C:` and remove the symlinks.
- **Single target path** — you enter one base folder (e.g. `D:\Music`); the script creates a `Deezer` folder inside it with two subfolders: `App` (the application) and `Data` (settings and downloaded music).
- **Safety checks before any change:**
  - verifies that Deezer is installed and not already moved;
  - detects the data folder name automatically (`Deezer` for newer versions, `deezer-desktop` for older ones);
  - checks free space on the target drive (and on `C:` when restoring);
  - warns and asks for confirmation if the target folder already exists and is not empty;
  - shows a full action plan and asks for confirmation before doing anything.
- **Self-elevation** — the script requests Administrator rights itself via UAC (required for creating symlinks).
- **Backup option on restore** — after copying files back to `C:`, the script asks whether to delete the folders on the new drive or keep them as a backup.

## Requirements

- Windows Vista or later (tested with Windows 10/11 in mind);
- Windows PowerShell 5.1 (built into Windows) or PowerShell 7+;
- Administrator rights (the script requests them automatically);
- The target folder must be on an **NTFS** volume (required for symbolic links).

## Files

| File | Purpose |
|------|---------|
| `Move-Deezer.ps1` | The main script |
| `Run-Move-Deezer.bat` | Double-click launcher (prefers PowerShell 7 if installed, falls back to Windows PowerShell 5.1) |

## Usage

1. Put `Move-Deezer.ps1` and `Run-Move-Deezer.bat` in the same folder.
2. Double-click `Run-Move-Deezer.bat` (or run the `.ps1` from a terminal: `powershell -ExecutionPolicy Bypass -File .\Move-Deezer.ps1`).
3. Confirm the UAC prompt to grant Administrator rights.
4. Select the language: `1` — English (or just press Enter), `2` — Russian.
5. Select the mode:
   - `1` — **Move Deezer to a new location.** Enter the target base folder (e.g. `D:\Music`). Review the action plan and confirm. The script closes Deezer, moves the folders and creates the symlinks.
   - `2` — **Restore Deezer back to drive C:.** The script finds the moved installation automatically by reading the symlink targets, copies everything back, removes the symlinks and asks whether to delete or keep the folders on the new drive.

### Notes

- If the path you enter already ends with `Deezer` (e.g. `D:\Music\Deezer`), the script uses it directly instead of creating a nested `Deezer\Deezer`.
- If the target `Deezer` folder already exists and is not empty, the script warns you that **all of its contents will be deleted** and proceeds only after your explicit confirmation.
- The script never restarts Deezer automatically — launch it yourself after the move.

## How to uninstall Deezer after moving it

1. Run the script and choose restore mode (`2`) — this returns all files to drive `C:` and removes the symlinks.
2. Uninstall Deezer the usual way: Windows Settings → Apps → Installed apps → Deezer → Uninstall.
3. Delete any leftover folders on the new drive manually.

Uninstalling without restoring first may leave broken links and orphaned files on the new drive.

## Disclaimer

The script moves application data on your disk. It performs multiple safety checks and asks for confirmation before every destructive action, but you use it at your own risk. Backing up important data before the first run is always a good idea.
