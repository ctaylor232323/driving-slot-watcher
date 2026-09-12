<#
.SYNOPSIS
    Stops the watcher and removes what it stored.

.DESCRIPTION
    Removes the scheduled task and deletes the saved sign-in, logs and page
    snapshots. Normally launched by double-clicking UNINSTALL.cmd.

    The saved sign-in is the part that matters: it is a live session for your
    driving school account, so it should not be left lying around once you are
    done.

.PARAMETER KeepSettings
    Remove the schedule but keep config.json, so you can start it again later
    without redoing setup. The saved sign-in is still deleted.

.PARAMETER Quiet
    No prompts. For unattended use.
#>

[CmdletBinding()]
param(
    [switch] $KeepSettings,
    [switch] $Quiet
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskName = 'DrivingSchoolSlotMonitor'

Write-Host ''
Write-Host '  ==============================================================' -ForegroundColor White
Write-Host '     DRIVING LESSON SLOT WATCHER -- UNINSTALL' -ForegroundColor White
Write-Host '  ==============================================================' -ForegroundColor White
Write-Host ''
Write-Host '  This will:'
Write-Host '    * stop the every-15-minutes checking'
Write-Host '    * delete the saved sign-in to your driving school account'
Write-Host '    * delete the logs and the saved pictures of your pages'
if (-not $KeepSettings) {
    Write-Host '    * delete your settings'
}
Write-Host ''
Write-Host '  It does not touch your driving school account itself, and it'
Write-Host '  cannot cancel any lesson you have booked.'
Write-Host ''

if (-not $Quiet) {
    $go = Read-Host '  Go ahead? (y/N)'
    if ($go -notmatch '^(y|yes)$') {
        Write-Host ''
        Write-Host '  Nothing was changed.' -ForegroundColor Yellow
        Read-Host '  Press Enter to close'
        exit 0
    }
}

Write-Host ''

# --- the schedule
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    # schtasks rather than Unregister-ScheduledTask: the cmdlet needs elevation
    # on some machines, schtasks does not.
    $schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
    & $schtasks '/Delete' '/TN' $TaskName '/F' 2>&1 | Out-Null

    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Write-Host '  Could not remove the schedule.' -ForegroundColor Red
        Write-Host '  Right-click UNINSTALL.cmd and choose "Run as administrator".' -ForegroundColor Yellow
        Read-Host '  Press Enter to close'
        exit 1
    }
    Write-Host '  Stopped the every-15-minutes checking.' -ForegroundColor Green
}
else {
    Write-Host '  It was not scheduled, so there was nothing to stop.'
}

# --- the private bits
$removed = @()
foreach ($target in @('state', 'profile', 'snapshots', 'logs')) {
    $path = Join-Path $Root $target
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $path)) { $removed += $target }
    }
}

if ($removed -contains 'state' -or $removed -contains 'profile') {
    Write-Host '  Deleted the saved sign-in.' -ForegroundColor Green
}
if ($removed -contains 'snapshots') {
    Write-Host '  Deleted the saved pictures of your scheduling pages.' -ForegroundColor Green
}
if ($removed -contains 'logs') {
    Write-Host '  Deleted the logs.' -ForegroundColor Green
}

if (-not $KeepSettings) {
    $cfg = Join-Path $Root 'config.json'
    if (Test-Path $cfg) {
        Remove-Item $cfg -Force -ErrorAction SilentlyContinue
        Write-Host '  Deleted your settings.' -ForegroundColor Green
    }
}
else {
    Write-Host '  Kept your settings, so INSTALL.cmd can pick up where it left off.'
}

Write-Host ''
Write-Host '  ==============================================================' -ForegroundColor Green
Write-Host '     REMOVED' -ForegroundColor Green
Write-Host '  ==============================================================' -ForegroundColor Green
Write-Host ''
Write-Host '  Nothing is running any more and the saved sign-in is gone.'
Write-Host ''
Write-Host '  To finish, delete this folder:'
Write-Host ("    {0}" -f $Root) -ForegroundColor Cyan
Write-Host ''
Write-Host '  (It cannot delete itself while it is running.)'
Write-Host ''

if (-not $Quiet) { Read-Host '  Press Enter to close' }
