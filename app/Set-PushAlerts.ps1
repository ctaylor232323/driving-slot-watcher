<#
.SYNOPSIS
    Sets up phone push alerts via ntfy. No password, no account, no email.

.DESCRIPTION
    Generates a private topic name, saves it to config.json, and offers to send
    a test push so you can confirm it lands on your phone.

    This is the lowest-friction way to get alerts off this desk and onto your
    phone, and it needs no credentials of any kind.

.EXAMPLE
    .\Set-PushAlerts.ps1
#>

[CmdletBinding()]
param(
    [string] $Topic
)

$ErrorActionPreference = 'Stop'

$Root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Root 'config.json'

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Notify.ps1')

$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

function New-RandomTopic {
    # A topic name is the only thing protecting these alerts, so make it long
    # and random rather than guessable.
    $chars = 'abcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object 'byte[]' 14
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()

    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) { [void]$sb.Append($chars[$b % $chars.Length]) }
    return ('drive-' + $sb.ToString())
}

Write-Host ''
Write-Host '=== Phone push setup (ntfy) ===' -ForegroundColor Cyan
Write-Host ''

$existing = ''
if ($cfg.alerts.ntfy -and $cfg.alerts.ntfy.topic) { $existing = $cfg.alerts.ntfy.topic }

if ($Topic) {
    $chosen = $Topic.Trim()
}
elseif ($existing) {
    Write-Host "A topic is already configured: $existing"
    $keep = Read-Host 'Keep it? (Y/n)'
    if ($keep -match '^(n|no)$') { $chosen = New-RandomTopic } else { $chosen = $existing }
}
else {
    $chosen = New-RandomTopic
}

$cfg.alerts.ntfy.enabled = $true
$cfg.alerts.ntfy.topic   = $chosen
if (-not $cfg.alerts.ntfy.server) { $cfg.alerts.ntfy.server = 'https://ntfy.sh' }

Write-Utf8NoBom -Path $ConfigPath -Content ($cfg | ConvertTo-Json -Depth 10)

Write-Host ''
Write-Host 'Your private topic:' -ForegroundColor Green
Write-Host ''
Write-Host ("    {0}" -f $chosen) -ForegroundColor White
Write-Host ''
Write-Host 'On your phone:' -ForegroundColor Cyan
Write-Host '  1. Install "ntfy" from the App Store or Play Store (free, no account).'
Write-Host '  2. Tap + to subscribe to a topic.'
Write-Host '  3. Type the topic name above, exactly. Leave the server as ntfy.sh.'
Write-Host '  4. Allow notifications when it asks.'
Write-Host ''
Write-Host 'Treat that topic name like a password: anyone who knows it can read your' -ForegroundColor Yellow
Write-Host 'alerts, and they travel through the public ntfy.sh server. The only thing' -ForegroundColor Yellow
Write-Host 'in them is the lesson dates and times already shown on the school website.' -ForegroundColor Yellow
Write-Host ''

$send = Read-Host 'Send a test push now? (Y/n)'
if ($send -match '^(n|no)$') {
    Write-Host ''
    Write-Host 'Skipped. When you are ready:  .\Check-Slots.ps1 -TestAlert'
    exit 0
}

Write-Host ''
Write-Host 'Sending...'
$ok = Send-NtfyPush -Server $cfg.alerts.ntfy.server -Topic $chosen `
    -Title 'Driving school monitor' `
    -Message 'Test push. If you can read this on your phone, slot alerts will reach you.' `
    -ClickUrl (Get-Prop $cfg 'schedulingUrl')

if ($ok) {
    Write-Host 'Sent.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'It should arrive within a second or two. If nothing shows up, check that'
    Write-Host 'the topic on your phone matches exactly, then run this script again.'
}
else {
    Write-Host 'The push could not be sent. Check your internet connection, then retry.' -ForegroundColor Red
    Write-Host 'Details:  .\Set-PushAlerts.ps1 -Verbose'
}

Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  .\Check-Slots.ps1 -TestAlert     # full alert through every channel'
Write-Host '  .\Install-Task.ps1               # start checking every 15 minutes'
