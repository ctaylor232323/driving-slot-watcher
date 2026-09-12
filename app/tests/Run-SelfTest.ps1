<#
.SYNOPSIS
    End-to-end test of the monitor against a local fake scheduling page.

.DESCRIPTION
    Proves the whole chain works -- Playwright launch, waiting for JavaScript to
    render, detection, state comparison, cooldown, and the alert decision --
    without touching the real website and without making any noise.

    Your real config.json and state are backed up and restored.

.EXAMPLE
    .\tests\Run-SelfTest.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$TestDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root    = Split-Path -Parent $TestDir
$Fixture = Join-Path $TestDir 'fixtures\fake-page.html'

$ConfigPath  = Join-Path $Root 'config.json'
$StateDir    = Join-Path $Root 'state'
$StatePath   = Join-Path $StateDir 'last-state.json'
$StoragePath = Join-Path $StateDir 'storage.json'

. (Join-Path $Root 'lib\Common.ps1')

# Everything this test writes goes in a sandbox directory: its own config,
# state, logs and snapshots. Nothing here reads or writes the real ones.
#
# It used to back up and restore the real config.json and storage.json instead.
# That looked safe until a scheduled check fired mid-test, picked up the test
# config, and saved an empty session over the real sign-in -- which silently
# logged the monitor out.
$Sandbox = Join-Path $env:TEMP ('dsm-selftest-' + [guid]::NewGuid().ToString('N'))
$SandboxState = Join-Path $Sandbox 'state'
$SandboxLogs = Join-Path $Sandbox 'logs'
$SandboxSnaps = Join-Path $Sandbox 'snapshots'
foreach ($d in @($Sandbox, $SandboxState, $SandboxLogs, $SandboxSnaps)) {
    New-Item -ItemType Directory -Path $d -Force | Out-Null
}

$ConfigPath = Join-Path $Sandbox 'config.json'
$StatePath = Join-Path $SandboxState 'last-state.json'
$StoragePath = Join-Path $SandboxState 'storage.json'

$results = @()
function Assert-Equal {
    param([string] $Name, $Expected, $Actual)
    $pass = ("$Expected" -eq "$Actual")
    $script:results += [pscustomobject]@{ Test = $Name; Expected = $Expected; Actual = $Actual; Pass = $pass }
    if ($pass) { Write-Host ("  PASS  {0}" -f $Name) -ForegroundColor Green }
    else { Write-Host ("  FAIL  {0}  (expected '{1}', got '{2}')" -f $Name, $Expected, $Actual) -ForegroundColor Red }
}

if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

try {
    # A blank but valid session, since the fake page needs no login.
    Write-Utf8NoBom -Path $StoragePath -Content '{ "cookies": [], "origins": [] }'

    $fixtureUri = 'file:///' + ($Fixture -replace '\\', '/')

    # Start from the real config so the test exercises the real detection
    # settings, then redirect every output path into the sandbox.
    # Use the real config if setup has run, otherwise the shipped template,
    # so the test works on a fresh copy that nobody has configured yet.
    $baseConfig = Join-Path $Root 'config.json'
    if (-not (Test-Path $baseConfig)) { $baseConfig = Join-Path $Root 'config.template.json' }
    $cfg = Get-Content $baseConfig -Raw | ConvertFrom-Json
    $cfg.runtime | Add-Member -NotePropertyName stateDir -NotePropertyValue $SandboxState -Force
    $cfg.runtime | Add-Member -NotePropertyName logDir -NotePropertyValue $SandboxLogs -Force
    $cfg.runtime | Add-Member -NotePropertyName snapshotDir -NotePropertyValue $SandboxSnaps -Force
    # Silence every outbound channel for the duration of the test.
    $cfg.alerts.toast = $false
    $cfg.alerts.sound = $false
    $cfg.alerts.popup = $false
    $cfg.alerts.openBrowserOnAlert = $false
    $cfg.alerts.ntfy.enabled = $false
    $cfg.alerts.email.enabled = $false
    $cfg.runtime.jitterSeconds = 0
    $cfg.detection.settleMs = 2500

    # Do not let the daily summary fire during the test.
    $cfg.alerts.dailySummary.enabled = $false

    function Set-TestUrl {
        param([string] $Mode)
        $cfg.schedulingUrl = ($fixtureUri + '?mode=' + $Mode)
        Write-Utf8NoBom -Path $ConfigPath -Content ($cfg | ConvertTo-Json -Depth 10)
    }

    function Get-State {
        return (Get-Content $StatePath -Raw | ConvertFrom-Json)
    }

    $checker = Join-Path $Root 'Check-Slots.ps1'

    Write-Host ''
    Write-Host 'Test 1: page says "No Available Open Slots" -- expect no_slots, no alert' -ForegroundColor Cyan
    Set-TestUrl 'none'
    & $checker -NoJitter -ConfigPath $ConfigPath | Out-Null
    $s = Get-State
    Assert-Equal 'status is no_slots' 'no_slots' $s.status
    Assert-Equal 'no alert was raised' '' ([string]$s.lastAlertAt)

    Write-Host ''
    Write-Host 'Test 2: real openings appear -- expect slots_available and an alert' -ForegroundColor Cyan
    Set-TestUrl 'open'
    & $checker -NoJitter -ConfigPath $ConfigPath | Out-Null
    $s = Get-State
    Assert-Equal 'status is slots_available' 'slots_available' $s.status
    Assert-Equal 'two openings parsed' 2 $s.slotCount
    Assert-Equal 'an alert was raised' $true ([bool]$s.lastAlertAt)
    $firstAlertAt = $s.lastAlertAt

    Write-Host ''
    Write-Host 'Test 3: same openings again -- expect no repeat alert (cooldown holds)' -ForegroundColor Cyan
    & $checker -NoJitter -ConfigPath $ConfigPath | Out-Null
    $s = Get-State
    Assert-Equal 'status still slots_available' 'slots_available' $s.status
    Assert-Equal 'alert time unchanged' $firstAlertAt $s.lastAlertAt

    Write-Host ''
    Write-Host 'Test 4: -Force overrides the cooldown' -ForegroundColor Cyan
    & $checker -NoJitter -Force -ConfigPath $ConfigPath | Out-Null
    $s = Get-State
    Assert-Equal 'alert time moved forward' $true ($s.lastAlertAt -ne $firstAlertAt)

    Write-Host ''
    Write-Host 'Test 5: back to no slots -- expect a quiet no_slots result' -ForegroundColor Cyan
    Set-TestUrl 'none'
    & $checker -NoJitter -ConfigPath $ConfigPath | Out-Null
    $s = Get-State
    Assert-Equal 'status is no_slots' 'no_slots' $s.status

    Write-Host ''
    Write-Host 'Test 6: banner gone but nothing recognisable -- expect page_changed' -ForegroundColor Cyan
    Set-TestUrl 'weird'
    & $checker -NoJitter -ConfigPath $ConfigPath | Out-Null
    $s = Get-State
    Assert-Equal 'status is page_changed' 'page_changed' $s.status

    Write-Host ''
    Write-Host 'Test 6b: the site error page reads as a session problem, not a page change' -ForegroundColor Cyan
    Set-TestUrl 'oops'
    & $checker -NoJitter -ConfigPath $ConfigPath | Out-Null
    $s = Get-State
    Assert-Equal 'status is login_required' 'login_required' $s.status
    Assert-Equal 'reason points at the error page' $true ($s.reason -like '*error page*')

    Write-Host ''
    Write-Host 'Test 7: missing session file -- expect a clean error, not a crash' -ForegroundColor Cyan
    Remove-Item $StoragePath -Force
    Set-TestUrl 'none'
    & $checker -NoJitter -ConfigPath $ConfigPath | Out-Null
    $s = Get-State
    Assert-Equal 'status is error' 'error' $s.status
    Assert-Equal 'error mentions Setup-Login' $true ($s.reason -like '*Setup-Login*')
    Write-Host ''
    Write-Host 'Test 8: email vs text recipient splitting and body trimming' -ForegroundColor Cyan
    . (Join-Path $Root 'lib\Notify.ps1')

    $split = Split-AlertRecipients -To 'dad@example.com, 6145550100@vzwpix.com; mom@example.org,6145550101@tmomail.net'
    Assert-Equal 'two mailboxes recognized' 2 $split.Email.Count
    Assert-Equal 'two phone gateways recognized' 2 $split.Sms.Count
    Assert-Equal 'a plain address is not treated as a phone' $false (Test-IsSmsAddress 'dad@example.com')
    Assert-Equal 'a gateway address is treated as a phone' $true (Test-IsSmsAddress '6145550100@txt.att.net')

    $fullBody = @(
        'An opening showed up on the scheduling page. Book it now -- first come, first served.',
        '',
        'What the page is showing:',
        '  - Thu 09/11/2026 4:00 PM - 6:00 PM Instructor: R. Hall',
        '  - Sat 09/13/2026 9:00 AM - 11:00 AM Instructor: T. Nguyen'
    ) -join "`r`n"

    $short = Get-ShortAlertBody -Body $fullBody -Url 'https://www.tds.ms/x'
    Assert-Equal 'short body keeps the first lesson time' $true ($short -like '*Thu 09/11/2026 4:00 PM*')
    Assert-Equal 'short body keeps the second lesson time' $true ($short -like '*Sat 09/13/2026 9:00 AM*')
    Assert-Equal 'short body drops the prose' $false ($short -like '*first come*')
    Assert-Equal 'short body carries the link' $true ($short -like '*https://www.tds.ms/x*')
    Assert-Equal 'short body fits a text message' $true ($short.Length -le 300)

    $longBody = "  - " + ('X' * 500)
    $trimmed = Get-ShortAlertBody -Body $longBody -Url 'https://www.tds.ms/x'
    Assert-Equal 'an over-long body is truncated' $true ($trimmed.Length -le 300)
    Assert-Equal 'truncated body still carries the link' $true ($trimmed -like '*https://www.tds.ms/x*')

    $noSlots = Get-ShortAlertBody -Body "The saved session expired.`r`n`r`nRun Setup-Login.ps1." -Url ''
    Assert-Equal 'bodies with no bullets still produce text' $true ($noSlots.Length -gt 0)

    Write-Host ''
    Write-Host 'Test 8b: the daily summary fires once a day and catches up after sleep' -ForegroundColor Cyan

    $today8am = (Get-Date -Hour 8 -Minute 0 -Second 0 -Millisecond 0)

    Assert-Equal 'not due before the scheduled hour' $false `
        (Test-ShouldSendSummary -Now $today8am.AddHours(-1) -LastSentIso '' -AtHour 8)
    Assert-Equal 'due at the scheduled hour when never sent' $true `
        (Test-ShouldSendSummary -Now $today8am -LastSentIso '' -AtHour 8)
    Assert-Equal 'not due again once sent today' $false `
        (Test-ShouldSendSummary -Now $today8am.AddHours(3) `
            -LastSentIso $today8am.AddMinutes(1).ToUniversalTime().ToString('o') -AtHour 8)
    Assert-Equal 'still due after a sleeping laptop missed the hour' $true `
        (Test-ShouldSendSummary -Now $today8am.AddHours(6) `
            -LastSentIso $today8am.AddDays(-1).ToUniversalTime().ToString('o') -AtHour 8)
    Assert-Equal 'a garbled timestamp does not suppress the summary' $true `
        (Test-ShouldSendSummary -Now $today8am.AddHours(1) -LastSentIso 'not-a-date' -AtHour 8)

    # Log parsing, against a throwaway log directory.
    $fakeLogs = Join-Path $env:TEMP ('dsm-selftest-logs-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fakeLogs -Force | Out-Null
    $stampNow = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $stampOld = (Get-Date).AddDays(-2).ToString('yyyy-MM-dd HH:mm:ss')
    $logName = 'monitor-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd')
    @(
        "$stampNow  INFO   Result: no_slots -- Matched something.",
        "$stampNow  INFO   Result: no_slots -- Matched something.",
        "$stampNow  INFO   Result: error -- boom",
        "$stampNow  ALERT  ALERT: something happened",
        "$stampNow  INFO   Checking the scheduling page...",
        "$stampOld  INFO   Result: no_slots -- too old to count"
    ) | Set-Content -Path (Join-Path $fakeLogs $logName) -Encoding UTF8

    $act = Get-MonitorActivity -LogDir $fakeLogs -Since (Get-Date).AddHours(-24)
    Assert-Equal 'counts only Result lines' 3 $act.Checks
    Assert-Equal 'counts no_slots results' 2 $act.NoSlots
    Assert-Equal 'counts failures' 1 $act.Errors
    Assert-Equal 'counts alerts' 1 $act.Alerts
    Assert-Equal 'ignores entries outside the window' $true ($act.Checks -eq 3)
    Remove-Item $fakeLogs -Recurse -Force

    $healthyMsg = Format-SummaryMessage -Status 'no_slots' -Activity $act -ExpectedChecks 3
    Assert-Equal 'healthy message says it can see the page' $true ($healthyMsg -like '*can see the scheduling page*')
    Assert-Equal 'healthy message reports the check count' $true ($healthyMsg -like '*3 checks*')

    $brokenMsg = Format-SummaryMessage -Status 'login_required' -Activity $act -ExpectedChecks 3
    Assert-Equal 'expired-session message leads with NOT WATCHING' $true ($brokenMsg -like 'NOT WATCHING*')
    Assert-Equal 'expired-session message names the fix' $true ($brokenMsg -like '*Setup-Login.ps1*')

    $sleepyMsg = Format-SummaryMessage -Status 'no_slots' -Activity $act -ExpectedChecks 96
    Assert-Equal 'a thin day is called out' $true ($sleepyMsg -like '*asleep*')

    Write-Host ''
    Write-Host 'Test 8c: no Start Menu shortcut name contains a character Windows forbids' -ForegroundColor Cyan

    # A shortcut called "Is it working?" shipped in 1.0.1 and killed the install
    # outright: Windows cannot create a file with ? in the name, so Inno failed
    # with IPersistFile::Save 0x8007007B partway through. The earlier install
    # test passed /NOICONS, which skips shortcut creation, so it never saw it.
    $issPath = Join-Path (Split-Path $Root) 'installer\DrivingSlotWatcher.iss'
    if (Test-Path $issPath) {
        $iss = Get-Content $issPath -Raw
        $names = [regex]::Matches($iss, '(?m)^Name:\s*"\{(?:group|autodesktop|commonprograms|userprograms)\}\\([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value }

        Assert-Equal 'found shortcut names to check' $true ($names.Count -gt 0)

        # Windows forbids  \ / : * ? " < > |  in a file name.
        $illegal = @($names | Where-Object { $_ -match '[?*:<>|"]' })
        if ($illegal.Count -gt 0) {
            foreach ($n in $illegal) { Write-Host ("        offending name: {0}" -f $n) -ForegroundColor Red }
        }
        Assert-Equal 'every shortcut name is a legal filename' 0 $illegal.Count
    }
    else {
        Write-Host '  (installer script not found, skipping)' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host 'Test 9: alerts leaving the machine link to the login page, not a deep link' -ForegroundColor Cyan

    $sched = 'https://www.tds.ms/CentralizeSP/BtwScheduling/Lessons?SchedulingTypeId=1'
    $login = 'https://www.tds.ms/CentralizeSP/Student/Login/yourschoolname'

    Assert-Equal 'login page wins over the deep link' $login `
        (Get-RemoteAlertUrl -ClickUrl '' -LoginUrl $login -SchedulingUrl $sched)
    Assert-Equal 'an explicit clickUrl overrides everything' 'https://example.com/x' `
        (Get-RemoteAlertUrl -ClickUrl 'https://example.com/x' -LoginUrl $login -SchedulingUrl $sched)
    Assert-Equal 'with no login URL it falls back to the scheduling page' $sched `
        (Get-RemoteAlertUrl -ClickUrl '' -LoginUrl '' -SchedulingUrl $sched)
}
finally {
    if ($Sandbox -and (Test-Path $Sandbox)) {
        Remove-Item $Sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ''
    Write-Host 'Sandbox removed. Your real config, state and logs were never touched.' -ForegroundColor DarkGray
}

$failed = @($results | Where-Object { -not $_.Pass })
Write-Host ''
Write-Host ('=== {0} of {1} checks passed ===' -f ($results.Count - $failed.Count), $results.Count) -ForegroundColor Cyan
if ($failed.Count -gt 0) { exit 1 }
exit 0
