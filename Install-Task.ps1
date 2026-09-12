<#
.SYNOPSIS
    Registers the Windows Task Scheduler job that runs the checker on a loop.

.DESCRIPTION
    Creates a task under your own account that runs Check-Slots.ps1 every
    -IntervalMinutes (15 by default), plus once at logon so it picks itself up
    again after a reboot.

    The task runs as you and only while you are logged on -- that is what lets
    it pop a toast, make noise, and open the browser on your desktop.

    Registration goes through schtasks.exe with a task XML rather than
    Register-ScheduledTask. On this machine the PowerShell cmdlet is refused
    with "Access is denied" unless elevated, while schtasks.exe succeeds as a
    normal user. The XML keeps every setting the cmdlet would have given us.

.PARAMETER IntervalMinutes
    Minutes between checks. 15 is the default; 60 is gentler on the site.

.PARAMETER TaskName
    Name of the scheduled task. Default: DrivingSchoolSlotMonitor.

.EXAMPLE
    .\Install-Task.ps1
    .\Install-Task.ps1 -IntervalMinutes 30
#>

[CmdletBinding()]
param(
    [ValidateRange(5, 1440)][int] $IntervalMinutes = 15,
    [string] $TaskName = 'DrivingSchoolSlotMonitor'
)

$ErrorActionPreference = 'Stop'

$Root   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script = Join-Path $Root 'Check-Slots.ps1'

if (-not (Test-Path $Script)) {
    Write-Host 'Check-Slots.ps1 not found next to this script.' -ForegroundColor Red
    exit 1
}

function Esc { param([string] $Text) return [System.Security.SecurityElement]::Escape($Text) }

# Windows PowerShell 5.1 specifically: these scripts are written for it, and it
# is present on every Windows box regardless of what shell you launched from.
$psExe    = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$schtasks = Join-Path $env:WINDIR 'System32\schtasks.exe'
$user     = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$start    = (Get-Date).Date.ToString('yyyy-MM-ddTHH:mm:ss')
$taskArgs = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $Script

# No <Duration> under <Repetition> is how Task Scheduler spells "forever".
# Supplying [TimeSpan]::MaxValue instead yields P99999999DT23H59M59S, which it
# rejects as out of range.
$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Watches the driving school behind-the-wheel scheduling page and alerts when an opening appears. Does not book anything.</Description>
    <URI>\$(Esc $TaskName)</URI>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$start</StartBoundary>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>PT$($IntervalMinutes)M</Interval>
      </Repetition>
    </TimeTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$(Esc $user)</UserId>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$(Esc $user)</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>7</Priority>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <RestartOnFailure>
      <Interval>PT5M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$(Esc $psExe)</Command>
      <Arguments>$(Esc $taskArgs)</Arguments>
      <WorkingDirectory>$(Esc $Root)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

# schtasks.exe requires the XML file to be UTF-16.
$xmlPath = Join-Path $env:TEMP ('dsm-task-{0}.xml' -f [guid]::NewGuid().ToString('N'))
[System.IO.File]::WriteAllText($xmlPath, $xml, [System.Text.Encoding]::Unicode)

try {
    $output = & $schtasks '/Create' '/TN' $TaskName '/XML' $xmlPath '/F' 2>&1
    $code = $LASTEXITCODE
}
finally {
    [System.IO.File]::Delete($xmlPath)
}

# Verify rather than assume: report success only once the task is really there.
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if (-not $task) {
    Write-Host ''
    Write-Host 'The task was NOT registered.' -ForegroundColor Red
    Write-Host ("schtasks exit code {0}: {1}" -f $code, ($output -join ' ')) -ForegroundColor Red
    Write-Host ''
    Write-Host 'If that mentions access being denied, right-click PowerShell,' -ForegroundColor Yellow
    Write-Host 'choose "Run as Administrator", and run this script again.' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host ("Scheduled task '{0}' registered." -f $TaskName) -ForegroundColor Green

$exported = Export-ScheduledTask -TaskName $TaskName
$rep = ([regex]::Match($exported, '(?s)<Repetition>.*?</Repetition>')).Value

if ($rep -match '<Duration>') {
    Write-Host ''
    Write-Host 'Warning: the repetition has an end time, so it will stop repeating:' -ForegroundColor Yellow
    Write-Host ('  ' + ($rep -replace '\s+', ' ')) -ForegroundColor Yellow
}
elseif ($rep -match '<Interval>PT(\d+)M</Interval>') {
    Write-Host ("  Runs every {0} minutes, indefinitely, plus once at logon." -f $Matches[1])
}
Write-Host ("  Runs as {0}, only while you are logged on." -f $user)
Write-Host ("  Next run: {0}" -f (Get-ScheduledTaskInfo -TaskName $TaskName).NextRunTime)

Write-Host ''
Write-Host 'Handy commands (schtasks works without Administrator on this machine):'
Write-Host ("  schtasks /Run    /TN {0}              # run one check now" -f $TaskName)
Write-Host ("  schtasks /Change /TN {0} /DISABLE     # pause it" -f $TaskName)
Write-Host ("  schtasks /Change /TN {0} /ENABLE      # resume it" -f $TaskName)
Write-Host '  .\Show-Status.ps1                                       # health check'
Write-Host '  .\Uninstall-Task.ps1                                    # remove it'

Write-Host ''
Write-Host 'Kicking off one run now so you can confirm it works...' -ForegroundColor Cyan
$runOut = & $schtasks '/Run' '/TN' $TaskName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host ("Could not start it: {0}" -f ($runOut -join ' ')) -ForegroundColor Yellow
    Write-Host 'It will still fire on its own schedule.' -ForegroundColor Yellow
    exit 0
}

Write-Host 'Started. Waiting for it to finish...'
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    if ((Get-ScheduledTask -TaskName $TaskName).State -ne 'Running') { break }
}

$info = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Host ''
Write-Host ("  Last run    : {0}" -f $info.LastRunTime)
Write-Host ("  Result code : {0}  {1}" -f $info.LastTaskResult, $(if ($info.LastTaskResult -eq 0) { '(success)' } else { '(see logs)' }))
Write-Host ''
Write-Host 'What it saw:' -ForegroundColor Cyan
& (Join-Path $Root 'Show-Status.ps1') -LogLines 6
