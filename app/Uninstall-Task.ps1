<#
.SYNOPSIS
    Removes the scheduled task. Leaves the folder, config, and logs alone.

.DESCRIPTION
    Uses schtasks.exe, which works as a normal user on this machine.
    Unregister-ScheduledTask needs elevation here.
#>

[CmdletBinding()]
param(
    [string] $TaskName = 'DrivingSchoolSlotMonitor'
)

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "No scheduled task named '$TaskName' is registered." -ForegroundColor Yellow
    exit 0
}

$schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
$output = & $schtasks '/Delete' '/TN' $TaskName '/F' 2>&1

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Host 'The task could NOT be removed.' -ForegroundColor Red
    Write-Host ("Reason: {0}" -f ($output -join ' ')) -ForegroundColor Red
    Write-Host 'Try again from an Administrator PowerShell window.' -ForegroundColor Yellow
    exit 1
}

Write-Host "Removed the scheduled task '$TaskName'." -ForegroundColor Green
Write-Host 'Your config, logs, and saved session are untouched.'
