<#
.SYNOPSIS
    Sets up email and/or text-message alerts.

.DESCRIPTION
    Walks through the sending mailbox, the app password, and who gets alerted.
    Text messages go through your carrier's email-to-SMS gateway, so they need
    no extra service or account -- just the phone number and carrier.

    Run it again any time to add a number or change the recipients.

.EXAMPLE
    .\Set-TextAlerts.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$Root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Root 'config.json'
$StateDir   = Join-Path $Root 'state'
$CredPath   = Join-Path $StateDir 'email.cred'

. (Join-Path $Root 'lib\Common.ps1')
. (Join-Path $Root 'lib\Notify.ps1')

if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$gateways = Get-SmsGatewayTable

Write-Host ''
Write-Host '=== Alert setup: email and text ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Both ride on one outgoing mailbox. A text is just an email sent to your'
Write-Host 'carrier''s gateway address, so there is no service to sign up for.'
Write-Host ''

# ---------------------------------------------------------- sending mailbox ---

$currentFrom = $cfg.alerts.email.from
if ($currentFrom) { Write-Host "Current sending mailbox: $currentFrom" }

Write-Host ''
Write-Host 'Which mailbox should SEND the alerts?' -ForegroundColor Cyan
Write-Host 'A personal Gmail or Outlook.com account is the path of least resistance.'
Write-Host 'A work Microsoft 365 account often cannot be used here, because most'
Write-Host 'tenants disable the SMTP sign-in this needs.'
Write-Host ''

$from = (Read-Host "Sending address$(if ($currentFrom) { " [$currentFrom]" })").Trim()
if (-not $from -and $currentFrom) { $from = $currentFrom }
if (-not $from) {
    Write-Host 'No sending address given; nothing changed.' -ForegroundColor Yellow
    exit 1
}

$smtp = 'smtp.gmail.com'
$port = 587
if ($from -match '(?i)@(outlook|hotmail|live|msn)\.') {
    $smtp = 'smtp-mail.outlook.com'
    Write-Host ''
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host '  Heads up: a Hotmail / Outlook.com account almost certainly will' -ForegroundColor Yellow
    Write-Host '  NOT work as the sender.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Microsoft retired password sign-in for third-party apps on' -ForegroundColor Yellow
    Write-Host '  consumer accounts and no longer issues app passwords for them,' -ForegroundColor Yellow
    Write-Host '  so there is no password you can enter here that will be' -ForegroundColor Yellow
    Write-Host '  accepted. Their server offers only LOGIN and XOAUTH2, and the' -ForegroundColor Yellow
    Write-Host '  password half of that is closed to accounts like yours.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  A Hotmail address works fine as a RECIPIENT. It is only' -ForegroundColor Yellow
    Write-Host '  sending that is blocked.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Your options:' -ForegroundColor Yellow
    Write-Host '    - Send from a Gmail account instead (app password works).' -ForegroundColor Yellow
    Write-Host '    - Or skip email entirely and use .\Set-PushAlerts.ps1,' -ForegroundColor Yellow
    Write-Host '      which needs no password at all and is more reliable.' -ForegroundColor Yellow
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''
    $goOn = Read-Host '  Try it anyway? (y/N)'
    if ($goOn -notmatch '^(y|yes)$') {
        Write-Host ''
        Write-Host 'Stopped, nothing changed. Recommended instead:' -ForegroundColor Cyan
        Write-Host '  .\Set-PushAlerts.ps1'
        exit 0
    }
}
elseif ($from -match '(?i)@yahoo\.') { $smtp = 'smtp.mail.yahoo.com' }
elseif ($from -notmatch '(?i)@gmail\.com$') {
    Write-Host ''
    Write-Host "Not a provider I know the SMTP server for." -ForegroundColor Yellow
    $entered = (Read-Host "SMTP server for $from [smtp.gmail.com]").Trim()
    if ($entered) { $smtp = $entered }
    $enteredPort = (Read-Host "SMTP port [587]").Trim()
    if ($enteredPort) { $port = [int]$enteredPort }
}
Write-Host "Using SMTP server: $smtp port $port"

# ---------------------------------------------------------------- recipients ---

$recipients = @()

Write-Host ''
Write-Host 'Where should alerts go?' -ForegroundColor Cyan
$emailTo = (Read-Host 'Email address to alert (blank to skip)').Trim()
if ($emailTo) { $recipients += ($emailTo -split '\s*[;,]\s*' | Where-Object { $_ }) }

Write-Host ''
Write-Host 'Add a phone number for text alerts? Leave blank to skip.' -ForegroundColor Cyan

while ($true) {
    $number = (Read-Host 'Phone number (10 digits, blank to finish)').Trim()
    if (-not $number) { break }

    $digits = ($number -replace '[^0-9]', '')
    if ($digits.Length -eq 11 -and $digits.StartsWith('1')) { $digits = $digits.Substring(1) }
    if ($digits.Length -ne 10) {
        Write-Host '  That does not look like a 10-digit US number. Try again.' -ForegroundColor Yellow
        continue
    }

    Write-Host ''
    Write-Host '  Carriers:' -ForegroundColor Cyan
    $names = @($gateways.Keys)
    for ($i = 0; $i -lt $names.Count; $i++) {
        Write-Host ('    {0,2}. {1,-20} {2}' -f ($i + 1), $names[$i], $gateways[$names[$i]])
    }
    Write-Host '  (the "-sms" variants are the older plain-SMS gateways; try one if the default is dropped)'
    Write-Host ''

    $choice = (Read-Host '  Carrier number').Trim()
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx) -or $idx -lt 1 -or $idx -gt $names.Count) {
        Write-Host '  Not a valid choice; skipping this number.' -ForegroundColor Yellow
        continue
    }

    $address = ('{0}@{1}' -f $digits, $gateways[$names[$idx - 1]])
    $recipients += $address
    Write-Host ("  Added: {0}" -f $address) -ForegroundColor Green
    Write-Host ''
}

if ($recipients.Count -eq 0) {
    Write-Host ''
    Write-Host 'No recipients given; nothing changed.' -ForegroundColor Yellow
    exit 1
}

# ------------------------------------------------------------------ password ---

$needPassword = $true
if (Test-Path $CredPath) {
    Write-Host ''
    $reuse = Read-Host 'A saved app password already exists. Keep it? (Y/n)'
    $needPassword = ($reuse -match '^(n|no)$')
}

if ($needPassword) {
    Write-Host ''
    Write-Host 'Enter the APP PASSWORD for the sending mailbox (not your normal password).' -ForegroundColor Cyan
    Write-Host 'Gmail: myaccount.google.com > Security > App passwords (needs 2-Step Verification on).'
    Write-Host 'It is encrypted for your Windows account only, and never leaves this machine'
    Write-Host 'except as an SMTP login to your own mail provider.'
    Write-Host ''
    Write-Host 'Or just press Enter to stop here -- your recipients will be saved and you'
    Write-Host 'can add the password later with .\Set-EmailPassword.ps1'
    Write-Host ''
    $secure = Read-Host 'App password' -AsSecureString

    if (-not $secure -or $secure.Length -eq 0) {
        # Keep the recipient list rather than making them retype it, but leave
        # the channel off so no run tries to send without a password.
        $cfg.alerts.email.enabled    = $false
        $cfg.alerts.email.from       = $from
        $cfg.alerts.email.to         = ($recipients -join ', ')
        $cfg.alerts.email.smtpServer = $smtp
        $cfg.alerts.email.port       = $port
        Write-Utf8NoBom -Path $ConfigPath -Content ($cfg | ConvertTo-Json -Depth 10)

        Write-Host ''
        Write-Host 'No password entered. Your recipients were saved, but email and text' -ForegroundColor Yellow
        Write-Host 'alerts are switched OFF until a password is added.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'To finish later:  .\Set-EmailPassword.ps1' -ForegroundColor Cyan
        Write-Host 'Or skip email entirely:  .\Set-PushAlerts.ps1' -ForegroundColor Cyan
        exit 0
    }

    Write-Utf8NoBom -Path $CredPath -Content (ConvertFrom-SecureString -SecureString $secure)
    Write-Host 'App password saved (encrypted).' -ForegroundColor Green
}

# -------------------------------------------------------------------- config ---

$cfg.alerts.email.enabled    = $true
$cfg.alerts.email.from       = $from
$cfg.alerts.email.to         = ($recipients -join ', ')
$cfg.alerts.email.smtpServer = $smtp
$cfg.alerts.email.port       = $port
$cfg.alerts.email.useSsl     = $true

Write-Utf8NoBom -Path $ConfigPath -Content ($cfg | ConvertTo-Json -Depth 10)

$split = Split-AlertRecipients -To $cfg.alerts.email.to

Write-Host ''
Write-Host 'Saved.' -ForegroundColor Green
Write-Host ("  Sending as : {0}" -f $from)
if ($split.Email.Count -gt 0) { Write-Host ("  Email to   : {0}" -f ($split.Email -join ', ')) }
if ($split.Sms.Count -gt 0) { Write-Host ("  Text to    : {0}" -f ($split.Sms -join ', ')) }
Write-Host ''
Write-Host 'Now send yourself a real one:' -ForegroundColor Cyan
Write-Host '  .\Check-Slots.ps1 -TestAlert'
Write-Host ''
Write-Host 'If the text never arrives, the carrier dropped it -- run this again and pick' -ForegroundColor Yellow
Write-Host 'the "-sms" variant for your carrier, or use the ntfy phone push instead.' -ForegroundColor Yellow
