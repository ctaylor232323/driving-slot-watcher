<#
.SYNOPSIS
    Shows what the monitor last saw, the recent log, and the task's health.
#>

[CmdletBinding()]
param(
    [int] $LogLines = 20,
    [string] $TaskName = 'DrivingSchoolSlotMonitor'
)

$Root      = Split-Path -Parent $MyInvocation.MyCommand.Path
$StatePath = Join-Path $Root 'state\last-state.json'
$LogDir    = Join-Path $Root 'logs'
$SnapDir   = Join-Path $Root 'snapshots'

Write-Host ''
Write-Host '=== Last check ===' -ForegroundColor Cyan
if (Test-Path $StatePath) {
    $s = Get-Content $StatePath -Raw | ConvertFrom-Json
    Write-Host ("Status            : {0}" -f $s.status)
    Write-Host ("Reason            : {0}" -f $s.reason)
    Write-Host ("Checked at        : {0}" -f ([datetime]$s.checkedAt).ToLocalTime())
    Write-Host ("Openings found    : {0}" -f $s.slotCount)
    Write-Host ("Errors in a row   : {0}" -f $s.consecutiveErrors)
    if ($s.lastAlertAt) {
        Write-Host ("Last alert        : {0}" -f ([datetime]$s.lastAlertAt).ToLocalTime())
    }
    else {
        Write-Host 'Last alert        : never'
    }
    if ($s.slots -and $s.slots.Count -gt 0) {
        Write-Host ''
        Write-Host 'Lines that looked like openings:'
        foreach ($line in ($s.slots | Select-Object -First 15)) { Write-Host "  - $line" }
    }
}
else {
    Write-Host 'No check has run yet.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '=== Scheduled task ===' -ForegroundColor Cyan
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host ("State          : {0}" -f $task.State)
    Write-Host ("Last run       : {0}" -f $info.LastRunTime)
    Write-Host ("Last result    : {0}" -f $info.LastTaskResult)
    Write-Host ("Next run       : {0}" -f $info.NextRunTime)
}
else {
    Write-Host "Not running. Double-click INSTALL.cmd to set it up." -ForegroundColor Yellow
}

Write-Host ''
Write-Host '=== Newest snapshot ===' -ForegroundColor Cyan
if (Test-Path $SnapDir) {
    $shot = Get-ChildItem $SnapDir -Filter *.png -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($shot) {
        Write-Host $shot.FullName
        Write-Host '(open it to see exactly what the monitor saw)'
    }
    else { Write-Host 'None yet.' }
}
else { Write-Host 'None yet.' }

Write-Host ''
Write-Host ("=== Log, last {0} lines ===" -f $LogLines) -ForegroundColor Cyan
$log = Get-ChildItem $LogDir -Filter 'monitor-*.log' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if ($log) {
    Get-Content $log.FullName -Tail $LogLines
}
else {
    Write-Host 'No log files yet.' -ForegroundColor Yellow
}
Write-Host ''
