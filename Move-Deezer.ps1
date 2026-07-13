#Requires -Version 5.1
<#
  Move-Deezer.ps1
  Relocates the Deezer desktop app and its data (settings + downloaded music)
  to another drive using directory symbolic links, or restores it back to C:.

  Modes:
    1 - Move Deezer to a new location
    2 - Restore Deezer back to drive C: and remove symlinks

  The script self-elevates to Administrator (required for mklink).
#>

# ============================ Self-elevation ============================
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Administrator rights are required. Requesting elevation...'
    Write-Host 'Требуются права администратора. Запрашиваю повышение прав...'
    # Relaunch with the same PowerShell host we are currently running in
    # (pwsh.exe for PowerShell 7+, powershell.exe for Windows PowerShell 5.1)
    $hostExe = (Get-Process -Id $PID).Path
    if (-not $hostExe) { $hostExe = 'powershell.exe' }
    try {
        Start-Process -FilePath $hostExe -Verb RunAs `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    }
    catch {
        Write-Host 'Elevation was cancelled. Exiting. / Повышение прав отменено. Выход.'
        Start-Sleep -Seconds 3
    }
    exit
}

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ============================ Constants ============================
$AppSource         = Join-Path $env:LOCALAPPDATA 'Programs\deezer-desktop'   # application binaries
# Data folder (settings + downloaded music): the name differs between Deezer versions,
# so we check the candidates in order and use the first one that exists.
$DataCandidates    = @(
    (Join-Path $env:APPDATA 'Deezer'),          # newer Deezer versions
    (Join-Path $env:APPDATA 'deezer-desktop')   # older Deezer versions
)
$SafetyMarginBytes = 200MB

# Picks the actual data folder path: a symlink candidate has priority (already-moved
# installation), then any existing folder; returns $null if nothing exists.
function Resolve-DataSource {
    $link = $DataCandidates | Where-Object { Test-IsSymlink $_ } | Select-Object -First 1
    if ($link) { return $link }
    return ($DataCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

# ============================ Localization ============================
$Strings = @{
    en = @{
        Banner            = '=== Deezer Relocation Tool ==='
        ModeTitle         = 'What do you want to do?'
        Mode1             = '  [1] Move Deezer to a new location'
        Mode2             = '  [2] Restore Deezer back to drive C: and remove symlinks'
        ModePrompt        = 'Your choice (1/2)'
        YesNoHint         = ' (y/n)'
        Cancelled         = 'Operation cancelled by user. Nothing was changed.'
        PressEnter        = 'Press Enter to exit'
        ErrAlreadyMoved   = "Deezer appears to be already moved: the AppData paths are symbolic links pointing to:`n  App:  {0}`n  Data: {1}`nTo move it to another location, first run this script in restore mode (option 2), then repeat the move."
        ErrAppMissing     = "Deezer application folder was not found:`n  {0}`nWhat to do: make sure Deezer is installed (https://www.deezer.com), launch it at least once, close it, then run this script again."
        ErrDataMissing    = "Deezer data folder was not found in any of the expected locations:`n  {0}`nWhat to do: launch Deezer at least once so it creates its data folder, close it, then run this script again."
        ErrMixedState     = 'Inconsistent state: one of the Deezer folders is a symbolic link and the other is not. Please inspect and fix the folders manually before using this script.'
        PromptTarget      = "Enter the target base folder (e.g. D:\Music).`nA 'Deezer' folder will be created inside it"
        ErrBadPath        = 'Invalid path. Enter a full path including a drive letter, e.g. D:\Music'
        ErrDriveMissing   = 'Drive {0} does not exist.'
        NoteDeezerLeaf    = "The path you entered already ends with 'Deezer', so it will be used as the Deezer folder itself:`n  {0}"
        WarnCDrive        = 'Warning: the target folder is on drive C:. Moving Deezer there will NOT free up space on C:. Continue anyway?'
        WarnTargetExists  = "The folder already exists and is not empty:`n  {0}`nALL of its contents will be PERMANENTLY DELETED before the move. Continue?"
        SpaceInfo         = 'Data to move: {0}.  Free space on {1} {2}.'
        ErrNoSpace        = 'Not enough free space on the target drive. Free up at least {0} and run the script again. Nothing was changed.'
        PlanTitle         = 'The script will now perform the following actions:'
        PlanKill          = '  1. Close all running Deezer processes.'
        PlanClear         = '  2. Prepare the target folder (create it; clear it if it already exists).'
        PlanMoveApp       = "  3. Move the application folder:`n       {0}`n       -> {1}"
        PlanMoveData      = "  4. Move the data folder (settings + downloaded music):`n       {0}`n       -> {1}"
        PlanLinks         = '  5. Create symbolic links at the original locations so Deezer keeps working as usual.'
        ConfirmProceed    = 'Proceed?'
        StepKill          = '[1/5] Closing Deezer processes...'
        StepClear         = '[2/5] Preparing the target folder...'
        StepMoveApp       = '[3/5] Moving the application folder (this may take a while)...'
        StepMoveData      = '[4/5] Moving the data folder (this may take a while)...'
        StepLinks         = '[5/5] Creating symbolic links...'
        ErrRobocopy       = "ERROR: failed to move files (robocopy reported a failure).`nDeezer may be in a partially moved state. Check these folders manually:`n  {0}`n  {1}`n  {2}`n  {3}"
        ErrSymlink        = "ERROR: failed to create the symbolic link:`n  {0}`nThe files were already moved to the new location. You can create the link manually from an elevated command prompt:`n  mklink /D `"{0}`" `"{1}`""
        DoneMoveTitle     = '=== Done! Summary of what was done: ==='
        DoneMoveApp       = '  * Application moved to: {0}'
        DoneMoveData      = '  * Settings and downloaded music moved to: {0}'
        DoneMoveLinks     = '  * Symbolic links created at the original AppData locations. Deezer will work as before, but all files (including future music downloads) are now stored on the new drive.'
        UninstallTitle    = 'How to uninstall Deezer later:'
        UninstallSteps    = "  1. Run this script again and choose restore mode (option 2). This returns all files to drive C: and removes the symbolic links.`n  2. Uninstall Deezer the usual way: Windows Settings -> Apps -> Installed apps -> Deezer -> Uninstall.`n  3. If any leftover folders remain in the location you chose today, delete them manually.`nNote: uninstalling without restoring first may leave broken links and orphaned files on the new drive."
        # Restore mode
        ErrNotMoved       = "The Deezer folders in AppData are not symbolic links:`n  {0}`n  {1}`nIt looks like Deezer was not moved by this script (or has already been restored). Nothing to restore."
        ErrLinkTargetGone = "The symbolic link points to a folder that no longer exists:`n  {0}`nCannot restore automatically. Check the target drive and fix the situation manually."
        RestoreInfo       = "Found a moved Deezer installation:`n  App:  {0}`n  Data: {1}"
        PlanRestoreTitle  = 'The script will now perform the following actions:'
        PlanRestoreKill   = '  1. Close all running Deezer processes.'
        PlanRestoreUnlink = '  2. Remove the symbolic links from AppData.'
        PlanRestoreCopy   = "  3. Copy all files back to their original locations on drive C:`n       {0} -> {1}`n       {2} -> {3}"
        PlanRestoreAsk    = '  4. Ask whether to delete the folders on the new drive or keep them as a backup.'
        StepUnlink        = '[2/4] Removing symbolic links...'
        StepCopyBack      = '[3/4] Copying files back to drive C: (this may take a while)...'
        StepBackupAsk     = '[4/4] Cleanup of the old location.'
        ErrRestoreCopy    = "ERROR: failed to copy files back (robocopy reported a failure).`nThe symbolic links have already been removed. Check these folders manually:`n  {0}`n  {1}`n  {2}`n  {3}"
        PromptDeleteBak   = "Delete the moved folders from the new drive?`n  {0}`n(y = delete, n = keep as a backup)"
        DeletedBackup     = 'The folders on the new drive were deleted.'
        KeptBackup        = 'The folders were kept as a backup at: {0}'
        DoneRestoreTitle  = '=== Done! Summary of what was done: ==='
        DoneRestore1      = '  * All Deezer files were copied back to their original locations on drive C:.'
        DoneRestore2      = '  * The symbolic links were removed. Deezer now works entirely from drive C: again.'
        DoneRestore3      = '  * You can now safely uninstall Deezer via Windows Settings -> Apps, or move it again with this script.'
    }
    ru = @{
        Banner            = '=== Инструмент переноса Deezer ==='
        ModeTitle         = 'Что вы хотите сделать?'
        Mode1             = '  [1] Перенести Deezer в новый каталог'
        Mode2             = '  [2] Вернуть Deezer обратно на диск C: и удалить симлинки'
        ModePrompt        = 'Ваш выбор (1/2)'
        YesNoHint         = ' (y/n, д/н)'
        Cancelled         = 'Операция отменена пользователем. Ничего не изменено.'
        PressEnter        = 'Нажмите Enter для выхода'
        ErrAlreadyMoved   = "Похоже, Deezer уже перенесён: пути в AppData являются символическими ссылками, указывающими на:`n  Приложение: {0}`n  Данные:     {1}`nЧтобы перенести его в другое место, сначала запустите скрипт в режиме восстановления (пункт 2), а затем повторите перенос."
        ErrAppMissing     = "Каталог приложения Deezer не найден:`n  {0}`nЧто делать: убедитесь, что Deezer установлен (https://www.deezer.com), запустите его хотя бы один раз, закройте и запустите этот скрипт снова."
        ErrDataMissing    = "Каталог данных Deezer не найден ни в одном из ожидаемых расположений:`n  {0}`nЧто делать: запустите Deezer хотя бы один раз, чтобы он создал каталог данных, закройте его и запустите этот скрипт снова."
        ErrMixedState     = 'Несогласованное состояние: один из каталогов Deezer является символической ссылкой, а другой — нет. Проверьте и исправьте каталоги вручную перед использованием скрипта.'
        PromptTarget      = "Укажите целевой каталог (например, D:\Music).`nВнутри него будет создан каталог 'Deezer'"
        ErrBadPath        = 'Некорректный путь. Укажите полный путь с буквой диска, например D:\Music'
        ErrDriveMissing   = 'Диск {0} не существует.'
        NoteDeezerLeaf    = "Указанный путь уже заканчивается на 'Deezer', поэтому он будет использован как каталог Deezer:`n  {0}"
        WarnCDrive        = 'Внимание: целевой каталог находится на диске C:. Перенос туда НЕ освободит место на диске C:. Всё равно продолжить?'
        WarnTargetExists  = "Каталог уже существует и не пуст:`n  {0}`nВСЁ его содержимое будет БЕЗВОЗВРАТНО УДАЛЕНО перед переносом. Продолжить?"
        SpaceInfo         = 'Объём переносимых данных: {0}.  Свободно на диске {1} {2}.'
        ErrNoSpace        = 'Недостаточно свободного места на целевом диске. Освободите не менее {0} и запустите скрипт снова. Ничего не изменено.'
        PlanTitle         = 'Скрипт выполнит следующие действия:'
        PlanKill          = '  1. Завершит все запущенные процессы Deezer.'
        PlanClear         = '  2. Подготовит целевой каталог (создаст его; очистит, если он уже существует).'
        PlanMoveApp       = "  3. Перенесёт каталог приложения:`n       {0}`n       -> {1}"
        PlanMoveData      = "  4. Перенесёт каталог данных (настройки + загруженная музыка):`n       {0}`n       -> {1}"
        PlanLinks         = '  5. Создаст символические ссылки в исходных расположениях, чтобы Deezer продолжал работать как обычно.'
        ConfirmProceed    = 'Продолжить?'
        StepKill          = '[1/5] Завершение процессов Deezer...'
        StepClear         = '[2/5] Подготовка целевого каталога...'
        StepMoveApp       = '[3/5] Перенос каталога приложения (это может занять время)...'
        StepMoveData      = '[4/5] Перенос каталога данных (это может занять время)...'
        StepLinks         = '[5/5] Создание символических ссылок...'
        ErrRobocopy       = "ОШИБКА: не удалось переместить файлы (robocopy сообщил о сбое).`nDeezer может находиться в частично перенесённом состоянии. Проверьте эти каталоги вручную:`n  {0}`n  {1}`n  {2}`n  {3}"
        ErrSymlink        = "ОШИБКА: не удалось создать символическую ссылку:`n  {0}`nФайлы уже перемещены в новое расположение. Вы можете создать ссылку вручную из командной строки с правами администратора:`n  mklink /D `"{0}`" `"{1}`""
        DoneMoveTitle     = '=== Готово! Что было сделано: ==='
        DoneMoveApp       = '  * Приложение перенесено в: {0}'
        DoneMoveData      = '  * Настройки и загруженная музыка перенесены в: {0}'
        DoneMoveLinks     = '  * В исходных расположениях AppData созданы символические ссылки. Deezer будет работать как прежде, но все файлы (включая будущие загрузки музыки) теперь хранятся на новом диске.'
        UninstallTitle    = 'Как удалить Deezer в будущем:'
        UninstallSteps    = "  1. Запустите этот скрипт ещё раз и выберите режим восстановления (пункт 2). Это вернёт все файлы на диск C: и удалит символические ссылки.`n  2. Удалите Deezer обычным способом: Параметры Windows -> Приложения -> Установленные приложения -> Deezer -> Удалить.`n  3. Если в выбранном сегодня каталоге останутся какие-либо папки, удалите их вручную.`nПримечание: удаление без предварительного восстановления может оставить нерабочие ссылки и «осиротевшие» файлы на новом диске."
        # Режим восстановления
        ErrNotMoved       = "Каталоги Deezer в AppData не являются символическими ссылками:`n  {0}`n  {1}`nПохоже, Deezer не был перенесён этим скриптом (или уже восстановлен). Восстанавливать нечего."
        ErrLinkTargetGone = "Символическая ссылка указывает на каталог, которого больше не существует:`n  {0}`nАвтоматическое восстановление невозможно. Проверьте целевой диск и исправьте ситуацию вручную."
        RestoreInfo       = "Обнаружена перенесённая установка Deezer:`n  Приложение: {0}`n  Данные:     {1}"
        PlanRestoreTitle  = 'Скрипт выполнит следующие действия:'
        PlanRestoreKill   = '  1. Завершит все запущенные процессы Deezer.'
        PlanRestoreUnlink = '  2. Удалит символические ссылки из AppData.'
        PlanRestoreCopy   = "  3. Скопирует все файлы обратно в исходные расположения на диске C:`n       {0} -> {1}`n       {2} -> {3}"
        PlanRestoreAsk    = '  4. Спросит, удалить ли каталоги на новом диске или оставить их как резервную копию.'
        StepUnlink        = '[2/4] Удаление символических ссылок...'
        StepCopyBack      = '[3/4] Копирование файлов обратно на диск C: (это может занять время)...'
        StepBackupAsk     = '[4/4] Очистка старого расположения.'
        ErrRestoreCopy    = "ОШИБКА: не удалось скопировать файлы обратно (robocopy сообщил о сбое).`nСимволические ссылки уже удалены. Проверьте эти каталоги вручную:`n  {0}`n  {1}`n  {2}`n  {3}"
        PromptDeleteBak   = "Удалить перенесённые каталоги с нового диска?`n  {0}`n(y/д = удалить, n/н = оставить как резервную копию)"
        DeletedBackup     = 'Каталоги на новом диске удалены.'
        KeptBackup        = 'Каталоги оставлены как резервная копия по пути: {0}'
        DoneRestoreTitle  = '=== Готово! Что было сделано: ==='
        DoneRestore1      = '  * Все файлы Deezer скопированы обратно в исходные расположения на диске C:.'
        DoneRestore2      = '  * Символические ссылки удалены. Deezer снова полностью работает с диска C:.'
        DoneRestore3      = '  * Теперь можно безопасно удалить Deezer через Параметры Windows -> Приложения либо снова перенести его этим скриптом.'
    }
}

# ============================ Helpers ============================
$script:Lang = 'en'

function T([string]$Key) { return $Strings[$script:Lang][$Key] }

function Exit-Script([int]$Code = 0) {
    Read-Host (T 'PressEnter') | Out-Null
    exit $Code
}

function Fail([string]$Message) {
    Write-Host ''
    Write-Host $Message -ForegroundColor Red
    Exit-Script 1
}

function Ask-YesNo([string]$Prompt) {
    while ($true) {
        $answer = (Read-Host ($Prompt + (T 'YesNoHint'))).Trim().ToLower()
        if ($answer -in @('y', 'yes', 'д', 'да'))  { return $true }
        if ($answer -in @('n', 'no', 'н', 'нет')) { return $false }
    }
}

function Test-IsSymlink([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-SymlinkTarget([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    $target = @($item.Target)[0]
    if (-not $target) { return $null }
    return ([string]$target) -replace '^\\\\\?\\', ''
}

function Get-DirSizeBytes([string]$Path) {
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [long]0 }
    return [long]$sum
}

function Format-Bytes([double]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Get-FreeSpaceBytes([string]$AnyPathOnDrive) {
    $root = [IO.Path]::GetPathRoot($AnyPathOnDrive)
    return (New-Object IO.DriveInfo($root)).AvailableFreeSpace
}

function Stop-Deezer {
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -like '*deezer*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Invoke-RoboCopy([string]$From, [string]$To, [switch]$Move) {
    $rcArgs = @($From, $To, '/E', '/COPY:DAT', '/DCOPY:DAT', '/R:2', '/W:2', '/NFL', '/NDL', '/NP', '/NJH')
    if ($Move) { $rcArgs += '/MOVE' }
    & robocopy @rcArgs | Out-Null
    return ($LASTEXITCODE -lt 8)   # robocopy: codes 0-7 = success
}

function Remove-Symlink([string]$Path) {
    # rmdir removes only the link itself, never the link target's contents
    cmd /c rmdir "$Path" 2>$null | Out-Null
    return (-not (Test-Path -LiteralPath $Path))
}

# ============================ Language selection ============================
Write-Host ''
Write-Host '=== Deezer Relocation Tool / Инструмент переноса Deezer ==='
Write-Host ''
Write-Host 'Select language / Выберите язык:'
Write-Host '  [1] English (default)'
Write-Host '  [2] Русский'
$langChoice = (Read-Host 'Choice / Выбор [1]').Trim()
$script:Lang = if ($langChoice -eq '2') { 'ru' } else { 'en' }
Write-Host ''

# ============================ Mode selection ============================
Write-Host (T 'ModeTitle')
Write-Host (T 'Mode1')
Write-Host (T 'Mode2')
$mode = ''
while ($mode -notin @('1', '2')) {
    $mode = (Read-Host (T 'ModePrompt')).Trim()
}
Write-Host ''

# ======================================================================
#                              MODE 1: MOVE
# ======================================================================
if ($mode -eq '1') {

    # --- Detect the actual data folder ---
    $DataSource = Resolve-DataSource
    if (-not $DataSource) {
        Fail ((T 'ErrDataMissing') -f ($DataCandidates -join "`n  "))
    }

    # --- Validate current state ---
    $appIsLink  = Test-IsSymlink $AppSource
    $dataIsLink = Test-IsSymlink $DataSource

    if ($appIsLink -and $dataIsLink) {
        Fail ((T 'ErrAlreadyMoved') -f (Get-SymlinkTarget $AppSource), (Get-SymlinkTarget $DataSource))
    }
    if ($appIsLink -or $dataIsLink) {
        Fail (T 'ErrMixedState')
    }
    if (-not (Test-Path -LiteralPath $AppSource)) { Fail ((T 'ErrAppMissing') -f $AppSource) }

    # --- Ask for the target base folder ---
    $basePath = ''
    while ($true) {
        $basePath = (Read-Host (T 'PromptTarget')).Trim().Trim('"').Trim("'")
        if ([string]::IsNullOrWhiteSpace($basePath)) { continue }
        if (-not ($basePath -match '^[A-Za-z]:\\')) {
            Write-Host (T 'ErrBadPath') -ForegroundColor Yellow
            continue
        }
        $driveRoot = $basePath.Substring(0, 3)
        if (-not (Test-Path -LiteralPath $driveRoot)) {
            Write-Host ((T 'ErrDriveMissing') -f $basePath.Substring(0, 2)) -ForegroundColor Yellow
            continue
        }
        break
    }

    # If the entered path already ends with "Deezer", use it as the Deezer root itself
    if ((Split-Path $basePath -Leaf) -ieq 'Deezer') {
        $deezerRoot = $basePath
        Write-Host ((T 'NoteDeezerLeaf') -f $deezerRoot)
    }
    else {
        $deezerRoot = Join-Path $basePath 'Deezer'
    }
    $appTarget  = Join-Path $deezerRoot 'App'
    $dataTarget = Join-Path $deezerRoot 'Data'
    Write-Host ''

    # --- Warn if the target is on drive C: ---
    if (([IO.Path]::GetPathRoot($deezerRoot)) -ieq ([IO.Path]::GetPathRoot($AppSource))) {
        if (-not (Ask-YesNo (T 'WarnCDrive'))) {
            Write-Host (T 'Cancelled')
            Exit-Script 0
        }
        Write-Host ''
    }

    # --- Existing target folder: confirm clearing ---
    $targetExistsNonEmpty = (Test-Path -LiteralPath $deezerRoot) -and
        ((Get-ChildItem -LiteralPath $deezerRoot -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
    if ($targetExistsNonEmpty) {
        if (-not (Ask-YesNo ((T 'WarnTargetExists') -f $deezerRoot))) {
            Write-Host (T 'Cancelled')
            Exit-Script 0
        }
        Write-Host ''
    }

    # --- Free space check ---
    $totalBytes = (Get-DirSizeBytes $AppSource) + (Get-DirSizeBytes $DataSource)
    $freeBytes  = Get-FreeSpaceBytes $deezerRoot
    Write-Host ((T 'SpaceInfo') -f (Format-Bytes $totalBytes), ([IO.Path]::GetPathRoot($deezerRoot)), (Format-Bytes $freeBytes))
    if ($freeBytes -lt ($totalBytes + $SafetyMarginBytes)) {
        Fail ((T 'ErrNoSpace') -f (Format-Bytes ($totalBytes + $SafetyMarginBytes)))
    }
    Write-Host ''

    # --- Action plan + confirmation ---
    Write-Host (T 'PlanTitle')
    Write-Host (T 'PlanKill')
    Write-Host (T 'PlanClear')
    Write-Host ((T 'PlanMoveApp')  -f $AppSource,  $appTarget)
    Write-Host ((T 'PlanMoveData') -f $DataSource, $dataTarget)
    Write-Host (T 'PlanLinks')
    Write-Host ''
    if (-not (Ask-YesNo (T 'ConfirmProceed'))) {
        Write-Host (T 'Cancelled')
        Exit-Script 0
    }
    Write-Host ''

    # --- 1. Stop Deezer ---
    Write-Host (T 'StepKill')
    Stop-Deezer

    # --- 2. Prepare target folders ---
    Write-Host (T 'StepClear')
    if ($targetExistsNonEmpty) {
        Get-ChildItem -LiteralPath $deezerRoot -Force | Remove-Item -Recurse -Force
    }
    New-Item -ItemType Directory -Path $appTarget  -Force | Out-Null
    New-Item -ItemType Directory -Path $dataTarget -Force | Out-Null

    # --- 3-4. Move folders ---
    Write-Host (T 'StepMoveApp')
    $okApp = Invoke-RoboCopy -From $AppSource -To $appTarget -Move
    Write-Host (T 'StepMoveData')
    $okData = Invoke-RoboCopy -From $DataSource -To $dataTarget -Move
    if (-not ($okApp -and $okData)) {
        Fail ((T 'ErrRobocopy') -f $AppSource, $DataSource, $appTarget, $dataTarget)
    }
    # robocopy /MOVE normally removes the (now empty) source dirs; make sure of it
    foreach ($p in @($AppSource, $DataSource)) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    }

    # --- 5. Create symlinks ---
    Write-Host (T 'StepLinks')
    try {
        New-Item -ItemType SymbolicLink -Path $AppSource -Target $appTarget -ErrorAction Stop | Out-Null
    }
    catch {
        Fail ((T 'ErrSymlink') -f $AppSource, $appTarget)
    }
    try {
        New-Item -ItemType SymbolicLink -Path $DataSource -Target $dataTarget -ErrorAction Stop | Out-Null
    }
    catch {
        Fail ((T 'ErrSymlink') -f $DataSource, $dataTarget)
    }

    # --- Summary + uninstall instructions ---
    Write-Host ''
    Write-Host (T 'DoneMoveTitle') -ForegroundColor Green
    Write-Host ((T 'DoneMoveApp')  -f $appTarget)
    Write-Host ((T 'DoneMoveData') -f $dataTarget)
    Write-Host (T 'DoneMoveLinks')
    Write-Host ''
    Write-Host (T 'UninstallTitle') -ForegroundColor Cyan
    Write-Host (T 'UninstallSteps')
    Write-Host ''
    Exit-Script 0
}

# ======================================================================
#                             MODE 2: RESTORE
# ======================================================================
if ($mode -eq '2') {

    # --- Detect the actual data folder ---
    $DataSource = Resolve-DataSource
    if (-not $DataSource) { $DataSource = $DataCandidates[0] }   # for error messages only

    # --- Validate current state ---
    $appIsLink  = Test-IsSymlink $AppSource
    $dataIsLink = Test-IsSymlink $DataSource

    if (-not ($appIsLink -and $dataIsLink)) {
        if ($appIsLink -or $dataIsLink) { Fail (T 'ErrMixedState') }
        Fail ((T 'ErrNotMoved') -f $AppSource, $DataSource)
    }

    $appTarget  = Get-SymlinkTarget $AppSource
    $dataTarget = Get-SymlinkTarget $DataSource
    if (-not $appTarget  -or -not (Test-Path -LiteralPath $appTarget))  { Fail ((T 'ErrLinkTargetGone') -f $appTarget) }
    if (-not $dataTarget -or -not (Test-Path -LiteralPath $dataTarget)) { Fail ((T 'ErrLinkTargetGone') -f $dataTarget) }

    Write-Host ((T 'RestoreInfo') -f $appTarget, $dataTarget)
    Write-Host ''

    # --- Free space check on C: ---
    $totalBytes = (Get-DirSizeBytes $appTarget) + (Get-DirSizeBytes $dataTarget)
    $freeBytes  = Get-FreeSpaceBytes $AppSource
    Write-Host ((T 'SpaceInfo') -f (Format-Bytes $totalBytes), ([IO.Path]::GetPathRoot($AppSource)), (Format-Bytes $freeBytes))
    if ($freeBytes -lt ($totalBytes + $SafetyMarginBytes)) {
        Fail ((T 'ErrNoSpace') -f (Format-Bytes ($totalBytes + $SafetyMarginBytes)))
    }
    Write-Host ''

    # --- Action plan + confirmation ---
    Write-Host (T 'PlanRestoreTitle')
    Write-Host (T 'PlanRestoreKill')
    Write-Host (T 'PlanRestoreUnlink')
    Write-Host ((T 'PlanRestoreCopy') -f $appTarget, $AppSource, $dataTarget, $DataSource)
    Write-Host (T 'PlanRestoreAsk')
    Write-Host ''
    if (-not (Ask-YesNo (T 'ConfirmProceed'))) {
        Write-Host (T 'Cancelled')
        Exit-Script 0
    }
    Write-Host ''

    # --- 1. Stop Deezer ---
    Write-Host (T 'StepKill')
    Stop-Deezer

    # --- 2. Remove symlinks ---
    Write-Host (T 'StepUnlink')
    if (-not (Remove-Symlink $AppSource))  { Fail ((T 'ErrSymlink') -f $AppSource,  $appTarget) }
    if (-not (Remove-Symlink $DataSource)) { Fail ((T 'ErrSymlink') -f $DataSource, $dataTarget) }

    # --- 3. Copy files back to C: ---
    Write-Host (T 'StepCopyBack')
    $okApp  = Invoke-RoboCopy -From $appTarget  -To $AppSource
    $okData = Invoke-RoboCopy -From $dataTarget -To $DataSource
    if (-not ($okApp -and $okData)) {
        Fail ((T 'ErrRestoreCopy') -f $appTarget, $dataTarget, $AppSource, $DataSource)
    }

    # --- 4. Delete or keep the folders on the new drive ---
    Write-Host (T 'StepBackupAsk')
    $deezerRoot = Split-Path $appTarget -Parent
    if (Ask-YesNo ((T 'PromptDeleteBak') -f $deezerRoot)) {
        Remove-Item -LiteralPath $appTarget  -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $dataTarget -Recurse -Force -ErrorAction SilentlyContinue
        # remove the Deezer root folder as well if it is now empty
        if ((Test-Path -LiteralPath $deezerRoot) -and
            ((Get-ChildItem -LiteralPath $deezerRoot -Force | Measure-Object).Count -eq 0)) {
            Remove-Item -LiteralPath $deezerRoot -Force
        }
        Write-Host (T 'DeletedBackup')
    }
    else {
        Write-Host ((T 'KeptBackup') -f $deezerRoot)
    }

    # --- Summary ---
    Write-Host ''
    Write-Host (T 'DoneRestoreTitle') -ForegroundColor Green
    Write-Host (T 'DoneRestore1')
    Write-Host (T 'DoneRestore2')
    Write-Host (T 'DoneRestore3')
    Write-Host ''
    Exit-Script 0
}
