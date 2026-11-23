# Installs a "Boot to Bliss" button on Windows (Desktop + Start menu).
#
# Clicking it asks for confirmation, sets the UEFI one-time boot entry
# ({fwbootmgr} bootsequence) to the "BlissOS" firmware entry and restarts.
# Only that one boot goes to Bliss; the normal boot order is unchanged.
#
# Run once, from an ADMIN PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\Install-BootToBliss.ps1
# Remove again:
#   powershell -ExecutionPolicy Bypass -File .\Install-BootToBliss.ps1 -Uninstall
#
# The button runs through a scheduled task with highest privileges, so there is
# no UAC prompt on each click (bcdedit needs admin rights).

#Requires -RunAsAdministrator
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$TaskName  = 'Boot to Bliss'
$Dir       = Join-Path $env:ProgramData 'BootSwitch'
$Script    = Join-Path $Dir 'BootToBliss.ps1'
$Shortcuts = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Boot to Bliss.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'Boot to Bliss.lnk')
)

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $Shortcuts | ForEach-Object { Remove-Item $_ -ErrorAction SilentlyContinue }
    Remove-Item $Dir -Recurse -ErrorAction SilentlyContinue
    Write-Host 'Boot to Bliss removed.'
    return
}

# Check that the firmware entry exists before installing anything.
$fw = (bcdedit /enum firmware) -join "`n"
if (-not (($fw -split "`n\s*`n") | Where-Object { $_ -match 'BlissOS' })) {
    throw 'No "BlissOS" entry in the UEFI boot list (bcdedit /enum firmware). Nothing installed.'
}

$payload = @'
# Restart into Bliss OS once. Installed by Install-BootToBliss.ps1.
Add-Type -AssemblyName PresentationFramework
$title = 'Boot to Bliss'
$answer = [System.Windows.MessageBox]::Show(
    "Restart into Bliss OS now?`n`nUnsaved work will be lost.", $title, 'OKCancel', 'Question')
if ($answer -ne 'OK') { exit 0 }

# Firmware entries are blank-line separated blocks; take the GUID of the BlissOS one.
# Matching on the GUID pattern keeps this working on non-English Windows.
$fw = (bcdedit /enum firmware) -join "`n"
$block = ($fw -split "`n\s*`n") | Where-Object { $_ -match 'BlissOS' } | Select-Object -First 1
if (-not $block -or $block -notmatch '(\{[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}\})') {
    [System.Windows.MessageBox]::Show('No BlissOS entry found in the UEFI boot list.', $title, 'OK', 'Error') | Out-Null
    exit 1
}
$id = $Matches[1]

bcdedit /set '{fwbootmgr}' bootsequence $id | Out-Null
if ($LASTEXITCODE -ne 0) {
    [System.Windows.MessageBox]::Show("bcdedit failed to set the one-time boot entry ($id).", $title, 'OK', 'Error') | Out-Null
    exit 1
}
shutdown.exe /r /t 0
'@

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
Set-Content -Path $Script -Value $payload -Encoding UTF8

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Script`""
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal `
    -Settings $settings -Force | Out-Null

$shell = New-Object -ComObject WScript.Shell
foreach ($path in $Shortcuts) {
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath   = Join-Path $env:SystemRoot 'System32\schtasks.exe'
    $lnk.Arguments    = "/run /tn `"$TaskName`""
    $lnk.WindowStyle  = 7   # minimized, so no console flashes up
    $lnk.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',238'
    $lnk.Description  = 'Restart into Bliss OS once'
    $lnk.Save()
}

Write-Host 'Installed. "Boot to Bliss" is on the Desktop and in the Start menu (right-click it to pin to Start or the taskbar).'
