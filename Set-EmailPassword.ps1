<#
.SYNOPSIS
    Stores the app password used for the optional email alert.

.DESCRIPTION
    You type the password here; it is encrypted with Windows DPAPI under your
    own account and written to state\email.cred. Nobody else on the machine can
    read it, and it will not work if copied to another machine or account.

    For Gmail/Outlook use an APP PASSWORD, not your real account password.
    Enable the email channel in config.json under alerts.email.
#>

$Root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir = Join-Path $Root 'state'
$CredPath = Join-Path $StateDir 'email.cred'

if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

Write-Host ''
Write-Host 'Enter the app password for the sending mailbox (it will not be shown).' -ForegroundColor Cyan
$secure = Read-Host 'App password' -AsSecureString

if (-not $secure -or $secure.Length -eq 0) {
    Write-Host 'Nothing entered; no change made.' -ForegroundColor Yellow
    exit 1
}

. (Join-Path $Root 'lib\Common.ps1')
Write-Utf8NoBom -Path $CredPath -Content (ConvertFrom-SecureString -SecureString $secure)

Write-Host ''
Write-Host "Saved (encrypted) to $CredPath" -ForegroundColor Green

# If Set-TextAlerts.ps1 already recorded a sender and recipients, switch the
# channel on now that it has a password to use.
$ConfigPath = Join-Path $Root 'config.json'
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if ($cfg.alerts.email.from -and $cfg.alerts.email.to) {
    if (-not $cfg.alerts.email.enabled) {
        $cfg.alerts.email.enabled = $true
        Write-Utf8NoBom -Path $ConfigPath -Content ($cfg | ConvertTo-Json -Depth 10)
        Write-Host 'Email/text alerts are now switched ON.' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host ("  Sending as : {0}" -f $cfg.alerts.email.from)
    Write-Host ("  Alerting   : {0}" -f $cfg.alerts.email.to)
    Write-Host ''
    Write-Host 'Test it:  .\Check-Slots.ps1 -TestAlert' -ForegroundColor Cyan
}
else {
    Write-Host ''
    Write-Host 'No sender or recipients are configured yet. Run this to set them up:' -ForegroundColor Yellow
    Write-Host '  .\Set-TextAlerts.ps1' -ForegroundColor Cyan
}
