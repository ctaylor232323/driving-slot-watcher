<#
.SYNOPSIS
    One-time (occasionally repeated) sign-in so the monitor can see the
    scheduling page.

.DESCRIPTION
    Opens a browser window using a profile that belongs to this tool only. You
    sign in by hand -- this script never asks for, sees, or stores your password.
    When you press Enter it saves the session cookies the site handed the
    browser, and offers to record the scheduling page URL in config.json.

    Re-run this whenever the monitor reports that the session expired.
#>

[CmdletBinding()]
param(
    [string] $StartUrl
)

$ErrorActionPreference = 'Stop'

$Root       = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Root 'config.json'
$StateDir   = Join-Path $Root 'state'
$CapturePath = Join-Path $StateDir 'captured-url.txt'

if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

. (Join-Path $Root 'lib\Common.ps1')

$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if (-not $StartUrl) {
    # Login page first, not the scheduling page. You are normally here because
    # the session died, and this site answers a signed-out request for the
    # scheduling page with "Oops! Something went wrong." -- a confusing place to
    # be dropped when you came to sign in. Pass -StartUrl to override.
    if ((Get-Prop $cfg 'loginUrl')) {
        $StartUrl = $cfg.loginUrl
        Write-Host "Starting at the saved login URL: $StartUrl"
    }
    elseif ($cfg.schedulingUrl) {
        $StartUrl = $cfg.schedulingUrl
        Write-Host "Starting at the saved scheduling URL: $StartUrl"
    }
    else {
        Write-Host ''
        Write-Host 'Paste the driving school login page URL (the page where you normally sign in).'
        $StartUrl = (Read-Host 'URL').Trim()
    }
}

if (-not $StartUrl) {
    Write-Host 'No URL given. Nothing to do.' -ForegroundColor Yellow
    exit 1
}

if (Test-Path $CapturePath) { Remove-Item $CapturePath -Force }

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host 'node.exe is not on PATH. Install Node.js LTS and reopen PowerShell.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Opening a browser window. Your password stays between you and the site.' -ForegroundColor Cyan

# Run in the foreground so the browser can prompt you and the Enter keypress
# lands in this console.
# 'Continue' while node runs: anything it writes to stderr is information,
# not a reason to abort the sign-in.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $node.Source (Join-Path $Root 'login.js') $StartUrl
$ErrorActionPreference = $prevEap

if (-not (Test-Path (Join-Path $StateDir 'storage.json'))) {
    Write-Host ''
    Write-Host 'No session was saved. Try again and make sure you press Enter in this window' -ForegroundColor Yellow
    Write-Host 'before closing the browser.' -ForegroundColor Yellow
    exit 1
}

$captured = ''
if (Test-Path $CapturePath) { $captured = (Get-Content $CapturePath -Raw).Trim() }

Write-Host ''
Write-Host 'Session saved.' -ForegroundColor Green

if ($captured) {
    Write-Host "The page you left the browser on was:"
    Write-Host "  $captured" -ForegroundColor Cyan

    $useIt = $true
    if ($cfg.schedulingUrl -and ($cfg.schedulingUrl -ne $captured)) {
        Write-Host "config.json currently has: $($cfg.schedulingUrl)"
        $answer = Read-Host 'Replace it with the URL above? (y/N)'
        $useIt = ($answer -match '^(y|yes)$')
    }
    elseif ($cfg.schedulingUrl -eq $captured) {
        $useIt = $false
        Write-Host 'That already matches config.json -- nothing to change.'
    }

    if ($useIt) {
        $cfg.schedulingUrl = $captured
        Write-Utf8NoBom -Path $ConfigPath -Content ($cfg | ConvertTo-Json -Depth 10)
        Write-Host 'config.json updated with the scheduling URL.' -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Next step: run a manual check.' -ForegroundColor Cyan
Write-Host '  .\Check-Slots.ps1 -NoJitter -Verbose'
