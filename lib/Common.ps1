# Shared helpers. Dot-sourced by the PowerShell scripts in this folder.
# Windows PowerShell 5.1 compatible.

# Safe property read off a ConvertFrom-Json object: missing or null returns
# the default instead of throwing.
function Get-Prop {
    param($Object, [string] $Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }
    return $prop.Value
}

# Set-Content -Encoding UTF8 on PowerShell 5.1 writes a byte-order mark, and
# Node's JSON.parse refuses to read it. Anything Node has to read must go
# through here.
function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Content
    )
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}


# --------------------------------------------------- daily "still alive" note ---

# Is a daily summary due? True once local time has passed $AtHour and nothing
# has been sent since that moment today.
#
# Written this way so a sleeping laptop catches up rather than skipping a day:
# wake at 2pm with an 8am slot still unsent and it goes out at 2pm.
function Test-ShouldSendSummary {
    param(
        [Parameter(Mandatory = $true)][datetime] $Now,
        [AllowEmptyString()][string] $LastSentIso,
        [int] $AtHour = 8
    )

    $triggerToday = (Get-Date -Year $Now.Year -Month $Now.Month -Day $Now.Day `
            -Hour $AtHour -Minute 0 -Second 0 -Millisecond 0)

    if ($Now -lt $triggerToday) { return $false }
    if (-not $LastSentIso) { return $true }

    try {
        $last = [datetime]::Parse($LastSentIso, $null,
            [System.Globalization.DateTimeStyles]::RoundtripKind).ToLocalTime()
    }
    catch {
        return $true
    }

    return ($last -lt $triggerToday)
}

# Counts what the monitor actually did over a window, straight from the logs.
# The logs are the honest record: they cannot claim a check happened when the
# machine was asleep.
function Get-MonitorActivity {
    param(
        [Parameter(Mandatory = $true)][string] $LogDir,
        [Parameter(Mandatory = $true)][datetime] $Since
    )

    $counts = [ordered]@{
        Checks          = 0
        NoSlots         = 0
        SlotsAvailable  = 0
        PageChanged     = 0
        LoginRequired   = 0
        Errors          = 0
        Alerts          = 0
        LastCheck       = $null
        LastGoodCheck   = $null
    }

    if (-not (Test-Path $LogDir)) { return [pscustomobject]$counts }

    # Two days of files is enough to cover any 24h window.
    $files = @(Get-ChildItem $LogDir -Filter 'monitor-*.log' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 3)

    foreach ($file in $files) {
        foreach ($rawLine in (Get-Content $file.FullName -ErrorAction SilentlyContinue)) {
            # A log file written with -Encoding UTF8 can carry a BOM on its
            # first line; strip it rather than trying to match it.
            $line = $rawLine.TrimStart([char]0xFEFF)
            if ($line -notmatch '^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(\w+)\s+(.*)$') { continue }

            # $when must be typed before TryParse: with an untyped $null,
            # PowerShell cannot resolve the [ref] overload and throws.
            $when = [datetime]::MinValue
            if (-not [datetime]::TryParse($Matches[1], [ref]$when)) { continue }
            if ($when -lt $Since) { continue }

            $rest = $Matches[3]

            if ($rest -match '^ALERT:') { $counts.Alerts++ }
            if ($rest -notmatch '^Result:\s+(\w+)') { continue }

            $status = $Matches[1]
            $counts.Checks++

            # Take the latest, not the last one read: files are walked newest
            # first, so plain assignment would leave the OLDEST timestamp here.
            if (-not $counts.LastCheck -or $when -gt $counts.LastCheck) {
                $counts.LastCheck = $when
            }

            $good = ($status -eq 'no_slots' -or $status -eq 'slots_available')
            if ($good -and (-not $counts.LastGoodCheck -or $when -gt $counts.LastGoodCheck)) {
                $counts.LastGoodCheck = $when
            }

            switch ($status) {
                'no_slots'        { $counts.NoSlots++ }
                'slots_available' { $counts.SlotsAvailable++ }
                'page_changed'    { $counts.PageChanged++ }
                'login_required'  { $counts.LoginRequired++ }
                'error'           { $counts.Errors++ }
            }
        }
    }

    return [pscustomobject]$counts
}

# Builds the daily message. Leads with whether the monitor can actually see the
# page, because "it is running" and "it is working" are different claims.
function Format-SummaryMessage {
    param(
        [Parameter(Mandatory = $true)][string] $Status,
        [Parameter(Mandatory = $true)] $Activity,
        [int] $ExpectedChecks = 96
    )

    $healthy = ($Status -eq 'no_slots' -or $Status -eq 'slots_available')

    $lines = @()
    if ($healthy) {
        $lines += 'Monitor is alive and can see the scheduling page.'
    }
    elseif ($Status -eq 'login_required') {
        $lines += 'NOT WATCHING: the session expired. Run Setup-Login.ps1 to fix it.'
    }
    elseif ($Status -eq 'error') {
        $lines += 'NOT WATCHING: checks are failing. See the logs.'
    }
    else {
        $lines += 'Monitor is alive, but the page did not look as expected. Worth a glance.'
    }

    if ($Status -eq 'slots_available') {
        $lines += 'Right now: SLOTS ARE OPEN.'
    }
    elseif ($Status -eq 'no_slots') {
        $lines += 'Right now: no openings.'
    }

    $lines += ('Last 24h: {0} checks, {1} failed.' -f $Activity.Checks, $Activity.Errors)

    if ($Activity.LastCheck) {
        $lines += ('Last check: {0}.' -f ([datetime]$Activity.LastCheck).ToString('h:mm tt'))
    }

    # A quiet stretch usually means the laptop slept, which is worth saying out
    # loud -- those are hours nobody was watching.
    if ($Activity.Checks -lt ($ExpectedChecks * 0.7)) {
        $lines += 'Fewer checks than a full day would give -- the laptop was probably asleep for part of it.'
    }

    return ($lines -join ' ')
}
