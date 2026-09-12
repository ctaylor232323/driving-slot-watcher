<#
.SYNOPSIS
    Checks the driving school scheduling page once and alerts if a slot opened.

.DESCRIPTION
    Runs the headless Playwright checker, compares the result against the last
    known state, and raises an alert when openings appear. It never books
    anything -- it just tells you and opens the page.

.PARAMETER Force
    Alert even if the cooldown window has not elapsed.

.PARAMETER NoJitter
    Skip the random start delay. Use this for manual test runs.

.PARAMETER TestAlert
    Fire a sample alert through every configured channel and exit. Does not
    touch the website.

.EXAMPLE
    .\Check-Slots.ps1 -NoJitter
#>

[CmdletBinding()]
param(
    [switch] $Force,
    [switch] $NoJitter,
    [switch] $TestAlert,
    [switch] $Digest,

    # Point at a different config to run fully isolated -- its runtime.stateDir,
    # runtime.logDir and runtime.snapshotDir keep the real ones untouched. The
    # self-test uses this.
    [string] $ConfigPath
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $ConfigPath) { $ConfigPath = Join-Path $Root 'config.json' }

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Notify.ps1')

if (-not (Test-Path $ConfigPath)) {
    Write-Host "config not found at $ConfigPath" -ForegroundColor Red
    exit 1
}
$cfg     = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$alerts  = Get-Prop $cfg 'alerts' (New-Object psobject)
$runtime = Get-Prop $cfg 'runtime' (New-Object psobject)

# These three let a test run point every written file somewhere else, so it can
# neither read nor clobber the real session, state or logs.
function Resolve-Dir {
    param([string] $Configured, [string] $Fallback)
    if (-not $Configured) { return $Fallback }
    if ([System.IO.Path]::IsPathRooted($Configured)) { return $Configured }
    return (Join-Path $Root $Configured)
}

$StateDir = Resolve-Dir (Get-Prop $runtime 'stateDir' '') (Join-Path $Root 'state')
$LogDir   = Resolve-Dir (Get-Prop $runtime 'logDir' '')   (Join-Path $Root 'logs')

$StatePath  = Join-Path $StateDir 'last-state.json'
$ResultPath = Join-Path $StateDir 'last-result.json'
$CredPath   = Join-Path $StateDir 'email.cred'
$LockPath   = Join-Path $StateDir 'check.lock'

function Log {
    param([string] $Message, [string] $Level = 'INFO')
    Write-MonitorLog -Message $Message -Level $Level -LogDir $LogDir
}

foreach ($dir in @($StateDir, $LogDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}


# ---------------------------------------------------------------- alerting ---

function Invoke-Alert {
    param(
        [Parameter(Mandatory = $true)][string] $Title,
        [Parameter(Mandatory = $true)][string] $Body,
        [string] $Url,
        [switch] $SkipOpenBrowser
    )

    Log "ALERT: $Title -- $Body" 'ALERT'

    # The desktop browser can go straight to the scheduling page, because this
    # machine may already hold a session. Anything leaving the machine gets the
    # login page instead -- see Get-RemoteAlertUrl for why.
    $remoteUrl = Get-RemoteAlertUrl -ClickUrl (Get-Prop $alerts 'clickUrl' '') `
        -LoginUrl (Get-Prop $cfg 'loginUrl' '') -SchedulingUrl $Url

    $remoteBody = $Body
    if ($remoteUrl -ne $Url) {
        $remoteBody = $Body + "`r`n`r`nOn your phone: sign in, then Scheduling > Schedule My Drive."
    }

    if ([bool](Get-Prop $alerts 'toast' $true)) {
        [void](Show-DesktopToast -Title $Title -Message $Body)
    }

    if ([bool](Get-Prop $alerts 'popup' $false)) {
        Show-AlertPopup -Title $Title -Message $Body
    }

    $ntfy = Get-Prop $alerts 'ntfy'
    if ($ntfy -and [bool](Get-Prop $ntfy 'enabled' $false) -and (Get-Prop $ntfy 'topic')) {
        $ok = Send-NtfyPush -Server (Get-Prop $ntfy 'server' 'https://ntfy.sh') `
            -Topic (Get-Prop $ntfy 'topic') -Title $Title -Message $remoteBody -ClickUrl $remoteUrl
        if ($ok) { Log 'Phone push sent via ntfy.' } else { Log 'ntfy push failed.' 'WARN' }
    }

    $email = Get-Prop $alerts 'email'
    if ($email -and [bool](Get-Prop $email 'enabled' $false)) {
        $rcpt = Split-AlertRecipients -To (Get-Prop $email 'to' '')

        if ($rcpt.Email.Count -gt 0) {
            $bodyWithLink = $remoteBody
            if ($remoteUrl) { $bodyWithLink = "$remoteBody`r`n`r`n$remoteUrl" }
            $ok = Send-AlertEmail -EmailConfig $email -To $rcpt.Email `
                -Subject $Title -Body $bodyWithLink -CredentialPath $CredPath
            if ($ok) { Log ('Alert email sent to {0} address(es).' -f $rcpt.Email.Count) }
            else { Log 'Alert email failed.' 'WARN' }
        }

        # Phone gateways get a trimmed body: a text message has no room for prose,
        # and an over-long one is what carriers drop first.
        if ($rcpt.Sms.Count -gt 0) {
            $shortBody = Get-ShortAlertBody -Body $Body -Url $remoteUrl
            $ok = Send-AlertEmail -EmailConfig $email -To $rcpt.Sms `
                -Subject 'Driving slots open' -Body $shortBody -CredentialPath $CredPath
            if ($ok) { Log ('Text alert sent to {0} number(s).' -f $rcpt.Sms.Count) }
            else { Log 'Text alert failed.' 'WARN' }
        }
    }

    if (-not $SkipOpenBrowser -and [bool](Get-Prop $alerts 'openBrowserOnAlert' $true) -and $Url) {
        Open-SchedulingPage -Url $Url -Mode (Get-Prop $alerts 'openIn' 'default') -Root $Root
        Log 'Opened the scheduling page in a browser.'
    }

    # Sound last: it blocks for a few seconds and everything else should already
    # be on screen and on your phone by then.
    if ([bool](Get-Prop $alerts 'sound' $true)) {
        Play-AlertSound -Repeat ([int](Get-Prop $alerts 'soundRepeat' 6))
    }
}

# The daily note deliberately does NOT go through Invoke-Alert: it must never
# make noise, pop a toast, or open a browser. It is a quiet "still working"
# message, and it is sent by the checker itself so that silence means the
# checker stopped -- which is the whole point of having it.
function Send-DailySummary {
    param(
        [Parameter(Mandatory = $true)][string] $Status,
        [Parameter(Mandatory = $true)] $Activity
    )

    $summaryCfg = Get-Prop $alerts 'dailySummary'
    $priority = Get-Prop $summaryCfg 'priority' 'low'
    $expected = [int](Get-Prop $summaryCfg 'expectedChecksPerDay' 96)

    $message = Format-SummaryMessage -Status $Status -Activity $Activity -ExpectedChecks $expected
    $needsAction = ($Status -ne 'no_slots' -and $Status -ne 'slots_available')
    $title = $(if ($needsAction) { 'Driving monitor: needs attention' } else { 'Driving monitor: all good' })

    $sentAnywhere = $false

    $ntfy = Get-Prop $alerts 'ntfy'
    if ($ntfy -and [bool](Get-Prop $ntfy 'enabled' $false) -and (Get-Prop $ntfy 'topic')) {
        # Nudge the priority up if it is telling you to go do something.
        $p = $(if ($needsAction) { 'default' } else { $priority })
        $remoteUrl = Get-RemoteAlertUrl -ClickUrl (Get-Prop $alerts 'clickUrl' '') `
            -LoginUrl (Get-Prop $cfg 'loginUrl' '') -SchedulingUrl (Get-Prop $cfg 'schedulingUrl' '')
        if (Send-NtfyPush -Server (Get-Prop $ntfy 'server' 'https://ntfy.sh') `
                -Topic (Get-Prop $ntfy 'topic') -Title $title -Message $message `
                -ClickUrl $remoteUrl -Priority $p) {
            $sentAnywhere = $true
            Log 'Daily summary pushed to your phone.'
        }
        else {
            Log 'Daily summary push failed; will retry on the next check.' 'WARN'
        }
    }

    $email = Get-Prop $alerts 'email'
    if ($email -and [bool](Get-Prop $email 'enabled' $false) -and
        [bool](Get-Prop $summaryCfg 'includeEmail' $false)) {
        $rcpt = Split-AlertRecipients -To (Get-Prop $email 'to' '')
        $all = @($rcpt.Email) + @($rcpt.Sms)
        if ($all.Count -gt 0) {
            if (Send-AlertEmail -EmailConfig $email -To $all -Subject $title `
                    -Body $message -CredentialPath $CredPath) {
                $sentAnywhere = $true
                Log 'Daily summary emailed.'
            }
            else { Log 'Daily summary email failed.' 'WARN' }
        }
    }

    if (-not $sentAnywhere) {
        Log 'Daily summary had no working channel. Enable ntfy with Set-PushAlerts.ps1.' 'WARN'
    }
    return $sentAnywhere
}

if ($TestAlert) {
    Log 'Running a test alert through every configured channel.'
    Invoke-Alert -Title 'TEST -- Driving school slot monitor' `
        -Body ("This is a test alert fired at {0}. If you can see, hear, and (if enabled) receive this on your phone, the notification side is working." -f (Get-Date -Format 'h:mm tt')) `
        -Url (Get-Prop $cfg 'schedulingUrl') -SkipOpenBrowser:(-not (Get-Prop $cfg 'schedulingUrl'))
    Log 'Test alert finished.'
    exit 0
}


# ----------------------------------------------------------------- the run ---

$jitter = [int](Get-Prop $runtime 'jitterSeconds' 60)
if (-not $NoJitter -and $jitter -gt 0) {
    $wait = Get-Random -Minimum 0 -Maximum ($jitter + 1)
    Log "Waiting $wait s before checking (spreads out the scheduled runs)."
    Start-Sleep -Seconds $wait
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Log 'node.exe is not on PATH. Install Node.js or set the full path in Install-Task.ps1.' 'ERROR'
    exit 1
}

# One check at a time per state directory. The scheduled task already uses
# IgnoreNew, but a manual run alongside it would have two processes writing the
# same state and session files.
if (Test-Path $LockPath) {
    $lockAge = ((Get-Date) - (Get-Item $LockPath).LastWriteTime).TotalMinutes
    if ($lockAge -lt 12) {
        Log ('Another check has been running for {0:N1} min; skipping this one.' -f $lockAge) 'WARN'
        exit 0
    }
    Log 'Found a stale lock from a run that died; taking it over.' 'WARN'
}
Write-Utf8NoBom -Path $LockPath -Content ((Get-Date).ToUniversalTime().ToString('o'))

if (Test-Path $ResultPath) { Remove-Item $ResultPath -Force }

Log 'Checking the scheduling page...'
$checker = Join-Path $Root 'check-slots.js'
$outFile = Join-Path $LogDir 'checker-stdout.log'
$errFile = Join-Path $LogDir 'checker-stderr.log'

# Start-Process rather than a plain call: the checker writes progress to stderr,
# and with $ErrorActionPreference = 'Stop' a piped native stderr stream would be
# treated as a terminating error.
$proc = Start-Process -FilePath $node.Source `
    -ArgumentList ('"{0}" --config "{1}"' -f $checker, $ConfigPath) `
    -WorkingDirectory $Root -NoNewWindow -Wait -PassThru `
    -RedirectStandardOutput $outFile -RedirectStandardError $errFile

if (Test-Path $errFile) {
    foreach ($line in (Get-Content $errFile -ErrorAction SilentlyContinue)) { Write-Verbose $line }
}
if ($proc.ExitCode -ne 0) {
    Log ('The checker exited with code {0}; see logs\checker-stderr.log' -f $proc.ExitCode) 'WARN'
}

if (-not (Test-Path $ResultPath)) {
    Log 'The checker produced no result file. Run it directly to see why: node check-slots.js' 'ERROR'
    Remove-Item $LockPath -Force -ErrorAction SilentlyContinue
    exit 1
}
$result = Get-Content $ResultPath -Raw | ConvertFrom-Json

$status      = Get-Prop $result 'status' 'error'
$reason      = Get-Prop $result 'reason' ''
$fingerprint = Get-Prop $result 'fingerprint' ''
$slots       = @(Get-Prop $result 'slots' @())
$url         = Get-Prop $result 'url' (Get-Prop $cfg 'schedulingUrl')

foreach ($w in @(Get-Prop $result 'warnings' @())) { Log "checker warning: $w" 'WARN' }

$prev = $null
if (Test-Path $StatePath) {
    try { $prev = Get-Content $StatePath -Raw | ConvertFrom-Json } catch { $prev = $null }
}
$prevStatus     = Get-Prop $prev 'status' 'unknown'
$lastAlertAt    = Get-Prop $prev 'lastAlertAt' ''
$lastAlertFp    = Get-Prop $prev 'lastAlertFingerprint' ''
$errorStreak    = [int](Get-Prop $prev 'consecutiveErrors' 0)

$cooldownMin = [int](Get-Prop $alerts 'cooldownMinutes' 45)
$minutesSinceAlert = [double]::MaxValue
if ($lastAlertAt) {
    try {
        $then = [datetime]::Parse($lastAlertAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $minutesSinceAlert = ((Get-Date).ToUniversalTime() - $then.ToUniversalTime()).TotalMinutes
    }
    catch { $minutesSinceAlert = [double]::MaxValue }
}

Log ("Result: {0} -- {1}" -f $status, $reason)
if ($slots.Count -gt 0) {
    Log ("Lines that look like openings ({0}):" -f $slots.Count)
    foreach ($s in ($slots | Select-Object -First 12)) { Log "    $s" }
}

$shouldAlert = $false
$title = ''
$body = ''

switch ($status) {

    'slots_available' {
        $newSituation = ($prevStatus -ne 'slots_available') -or ($fingerprint -ne $lastAlertFp)
        if ($Force -or $newSituation -or ($minutesSinceAlert -ge $cooldownMin)) {
            $shouldAlert = $true
            $title = 'Driving lesson slots are OPEN'
            $lines = @('An opening showed up on the scheduling page. Book it now -- first come, first served.', '')
            if ($slots.Count -gt 0) {
                $lines += 'What the page is showing:'
                foreach ($s in ($slots | Select-Object -First 8)) { $lines += "  - $s" }
            }
            else {
                $lines += $reason
            }
            $body = ($lines -join "`r`n")
        }
        else {
            Log ("Slots still open but already alerted {0:N0} min ago; staying quiet until {1} min." -f $minutesSinceAlert, $cooldownMin)
        }
    }

    'page_changed' {
        $newSituation = ($fingerprint -ne $lastAlertFp)
        if ($Force -or ($newSituation -and ($minutesSinceAlert -ge $cooldownMin))) {
            $shouldAlert = $true
            $title = 'Scheduling page changed -- worth a look'
            $body = "The `"No Available Open Slots`" message is gone, but no lesson date or time was recognised.`r`n`r`n$reason"
        }
        else {
            Log 'Page-changed state already reported; staying quiet.'
        }
    }

    'login_required' {
        if ($Force -or ($minutesSinceAlert -ge 360)) {
            $shouldAlert = $true
            $title = 'Driving school monitor needs a fresh login'
            $body = "The monitor cannot see the scheduling page, so it is NOT watching for openings right now.`r`n`r`n$reason`r`n`r`nFix: run Setup-Login.ps1 in C:\DrivingSchoolMonitor and sign in again."
        }
        else {
            Log 'Session expired; already reported recently.' 'WARN'
        }
    }

    'error' {
        $errorStreak = $errorStreak + 1
        $threshold = [int](Get-Prop $runtime 'errorAlertAfter' 3)
        Log ("Check failed ({0} in a row): {1}" -f $errorStreak, $reason) 'ERROR'
        if ($Force -or ($errorStreak -eq $threshold)) {
            $shouldAlert = $true
            $title = 'Driving school monitor is failing'
            $body = "$errorStreak checks in a row failed.`r`n`r`n$reason`r`n`r`nCheck C:\DrivingSchoolMonitor\logs for detail."
        }
    }

    default {
        Log 'No openings.'
    }
}

if ($status -ne 'error') { $errorStreak = 0 }

if ($shouldAlert) {
    Invoke-Alert -Title $title -Body $body -Url $url
}

# --------------------------------------------- the daily "still alive" note ---

$summaryCfg  = Get-Prop $alerts 'dailySummary'
$lastSummary = Get-Prop $prev 'lastSummaryAt' ''
$summarySent = $false

$summaryDue = $Digest
if (-not $summaryDue -and $summaryCfg -and [bool](Get-Prop $summaryCfg 'enabled' $false)) {
    $summaryDue = Test-ShouldSendSummary -Now (Get-Date) -LastSentIso $lastSummary `
        -AtHour ([int](Get-Prop $summaryCfg 'atHour' 8))
}

if ($summaryDue) {
    $activity = Get-MonitorActivity -LogDir $LogDir -Since (Get-Date).AddHours(-24)
    Log ('Daily summary: {0} checks in the last 24h, {1} failed.' -f $activity.Checks, $activity.Errors)
    $summarySent = Send-DailySummary -Status $status -Activity $activity
}

# Only record it as sent if a channel actually accepted it. A failed send (no
# internet, say) stays due and goes out on a later check.
$newSummaryAt = $lastSummary
if ($summarySent) { $newSummaryAt = (Get-Date).ToUniversalTime().ToString('o') }

$newState = [ordered]@{
    status               = $status
    reason               = $reason
    fingerprint          = $fingerprint
    slotCount            = $slots.Count
    slots                = $slots
    checkedAt            = (Get-Date).ToUniversalTime().ToString('o')
    consecutiveErrors    = $errorStreak
    previousStatus       = $prevStatus
    lastAlertAt          = $(if ($shouldAlert) { (Get-Date).ToUniversalTime().ToString('o') } else { $lastAlertAt })
    lastAlertFingerprint = $(if ($shouldAlert) { $fingerprint } else { $lastAlertFp })
    lastSummaryAt        = $newSummaryAt
}
Write-Utf8NoBom -Path $StatePath -Content ($newState | ConvertTo-Json -Depth 5)

Remove-Item $LockPath -Force -ErrorAction SilentlyContinue

if ($status -eq 'error') { exit 1 }
exit 0
