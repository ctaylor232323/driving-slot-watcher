<#
.SYNOPSIS
    Sets up the Driving Lesson Slot Watcher from scratch. Start here.

.DESCRIPTION
    Walks through everything: Node.js, the browser library, your school's page,
    signing in, phone alerts, and the every-15-minutes schedule.

    Normally launched by double-clicking INSTALL.cmd.

.PARAMETER IntervalMinutes
    How often to check. 15 by default.

.PARAMETER SkipTask
    Do everything except register the scheduled task.
#>

[CmdletBinding()]
param(
    [ValidateRange(5, 1440)][int] $IntervalMinutes = 15,
    [switch] $SkipTask
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $Root 'lib\Common.ps1')

function Write-Step {
    param([int] $Number, [int] $Of, [string] $Text)
    Write-Host ''
    Write-Host ('  Step {0} of {1}: {2}' -f $Number, $Of, $Text) -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 62)) -ForegroundColor DarkGray
}

function Write-Problem {
    param([string] $Text)
    Write-Host ''
    Write-Host "  $Text" -ForegroundColor Red
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

$TOTAL = 6

Clear-Host
Write-Host ''
Write-Host '  ==============================================================' -ForegroundColor White
Write-Host '     DRIVING LESSON SLOT WATCHER' -ForegroundColor White
Write-Host '  ==============================================================' -ForegroundColor White
Write-Host ''
Write-Host '  Watches your driving school''s behind-the-wheel scheduling page'
Write-Host '  and alerts you the moment an opening appears.'
Write-Host ''
Write-Host '  It never books anything. Openings are first come, first served,'
Write-Host '  and booking blind could grab a time your child cannot make, so'
Write-Host '  the last click stays yours.'
Write-Host ''
Write-Host '  It never sees your password. You sign in yourself, in a real'
Write-Host '  browser window, exactly as you normally would.'
Write-Host ''
Write-Host '  Setup takes about five minutes.'
Write-Host ''
Read-Host '  Press Enter to begin'


# ------------------------------------------------------------ 1. Node.js ---

Write-Step 1 $TOTAL 'Checking for Node.js'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Refresh-Path
    $node = Get-Command node -ErrorAction SilentlyContinue
}

if ($node) {
    Write-Host ("  Found Node.js {0}" -f (& $node.Source --version)) -ForegroundColor Green
}
else {
    Write-Host '  Node.js is not installed. It is a free tool from the OpenJS'
    Write-Host '  Foundation that this uses to drive the browser.'
    Write-Host ''

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $go = Read-Host '  Install it now automatically? (Y/n)'
        if ($go -match '^(n|no)$') {
            Write-Host ''
            Write-Host '  Install it yourself from https://nodejs.org (choose LTS),' -ForegroundColor Yellow
            Write-Host '  then run INSTALL.cmd again.' -ForegroundColor Yellow
            exit 1
        }

        Write-Host ''
        Write-Host '  Installing Node.js. This takes a minute or two...'
        & $winget.Source install -e --id OpenJS.NodeJS.LTS `
            --accept-source-agreements --accept-package-agreements --silent 2>&1 |
            ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

        Refresh-Path
        $node = Get-Command node -ErrorAction SilentlyContinue

        if (-not $node) {
            Write-Problem 'Node.js was installed but this window cannot see it yet.'
            Write-Host '  Close this window, open INSTALL.cmd again, and it will continue.' -ForegroundColor Yellow
            Read-Host '  Press Enter to close'
            exit 1
        }
        Write-Host ("  Installed Node.js {0}" -f (& $node.Source --version)) -ForegroundColor Green
    }
    else {
        Write-Problem 'Node.js is missing and this PC has no automatic installer.'
        Write-Host '  Install it from https://nodejs.org (choose the LTS button),' -ForegroundColor Yellow
        Write-Host '  then run INSTALL.cmd again.' -ForegroundColor Yellow
        Read-Host '  Press Enter to close'
        exit 1
    }
}


# ------------------------------------------------- 2. Playwright + browser ---

Write-Step 2 $TOTAL 'Installing the browser automation library'

Push-Location $Root
try {
    Write-Host '  Downloading (about 10 MB)...'
    & npm install --no-fund --no-audit 2>&1 |
        Select-Object -Last 3 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

    if (-not (Test-Path (Join-Path $Root 'node_modules\playwright'))) {
        Write-Problem 'The library did not install. Are you online?'
        Read-Host '  Press Enter to close'
        exit 1
    }
    Write-Host '  Library installed.' -ForegroundColor Green

    # Prefer the Edge already on the machine: no extra download, and it looks
    # like an ordinary browser to the website.
    $edgePaths = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
    )
    $haveEdge = $false
    foreach ($p in $edgePaths) { if ($p -and (Test-Path $p)) { $haveEdge = $true } }

    if ($haveEdge) {
        $channel = 'msedge'
        Write-Host '  Using Microsoft Edge, which is already on this PC.' -ForegroundColor Green
    }
    else {
        $channel = ''
        Write-Host '  No Edge found, so downloading a browser instead (about 150 MB).'
        Write-Host '  This is the slow part; give it a few minutes...'
        & npx playwright install chromium 2>&1 |
            Select-Object -Last 2 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        Write-Host '  Browser installed.' -ForegroundColor Green
    }
}
finally {
    Pop-Location
}


# ------------------------------------------------------- 3. The school URL ---

Write-Step 3 $TOTAL 'Your driving school''s login page'

$ConfigPath = Join-Path $Root 'config.json'
$TemplatePath = Join-Path $Root 'config.template.json'

if (-not (Test-Path $ConfigPath)) {
    Copy-Item $TemplatePath $ConfigPath
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

Write-Host '  Open the page where you normally sign in to the driving school,'
Write-Host '  then copy the whole web address out of the address bar.'
Write-Host ''
Write-Host '  It usually looks something like:'
Write-Host '    https://www.tds.ms/CentralizeSP/Student/Login/yourschoolname' -ForegroundColor DarkGray
Write-Host ''

if ($cfg.loginUrl) {
    Write-Host ("  Currently saved: {0}" -f $cfg.loginUrl)
    $keep = Read-Host '  Keep it? (Y/n)'
    if ($keep -notmatch '^(n|no)$') { $loginUrl = $cfg.loginUrl }
}

while (-not $loginUrl) {
    $entered = (Read-Host '  Paste the login page address').Trim().Trim('"')
    if ($entered -match '^https?://\S+$') { $loginUrl = $entered }
    else { Write-Host '  That does not look like a web address. It should start with https://' -ForegroundColor Yellow }
}

$cfg.loginUrl = $loginUrl
$cfg.runtime.channel = $channel
Write-Utf8NoBom -Path $ConfigPath -Content ($cfg | ConvertTo-Json -Depth 10)
Write-Host '  Saved.' -ForegroundColor Green


# ------------------------------------------------------------- 4. Sign in ---

Write-Step 4 $TOTAL 'Signing in'

Write-Host '  A browser window is about to open at your school''s login page.'
Write-Host ''
Write-Host '  In that window:'
Write-Host '    1. Sign in as usual.'
Write-Host '    2. TICK "Remember me" if you see it. This keeps the watcher'
Write-Host '       signed in far longer, and saves you repeating this.' -ForegroundColor Yellow
Write-Host '    3. Go to the page that lists BOOKABLE openings.'
Write-Host '       On most of these sites that is Scheduling > Schedule My Drive.'
Write-Host '       It is NOT "My Schedule", which only lists lessons already booked.' -ForegroundColor Yellow
Write-Host '    4. Leave the browser sitting on that page and come back here.'
Write-Host ''
Read-Host '  Press Enter to open the browser'

& (Join-Path $Root 'Setup-Login.ps1') -StartUrl $loginUrl

if (-not (Test-Path (Join-Path $Root 'state\storage.json'))) {
    Write-Problem 'No sign-in was saved.'
    Write-Host '  Run INSTALL.cmd again, and remember to press Enter in THIS window' -ForegroundColor Yellow
    Write-Host '  before closing the browser.' -ForegroundColor Yellow
    Read-Host '  Press Enter to close'
    exit 1
}


# -------------------------------------------------------------- 5. Verify ---

Write-Step 5 $TOTAL 'Checking that it can read the page'

& (Join-Path $Root 'Check-Slots.ps1') -NoJitter | Out-Null

$state = Get-Content (Join-Path $Root 'state\last-state.json') -Raw | ConvertFrom-Json
Write-Host ''

switch ($state.status) {
    'no_slots' {
        Write-Host '  Working. It can see the page, and there are no openings right now.' -ForegroundColor Green
        Write-Host ('  (The page says: {0})' -f $state.reason)
    }
    'slots_available' {
        Write-Host '  Working -- and there are openings on the page RIGHT NOW.' -ForegroundColor Green
        foreach ($s in @($state.slots | Select-Object -First 5)) { Write-Host "    $s" }
    }
    'login_required' {
        Write-Problem 'It could not stay signed in.'
        Write-Host '  Run INSTALL.cmd again and tick "Remember me" when you sign in.' -ForegroundColor Yellow
        Read-Host '  Press Enter to close'
        exit 1
    }
    default {
        Write-Host '  It read a page, but not one it recognises.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  This usually means the browser was left on the wrong page --'
        Write-Host '  "My Schedule" instead of "Schedule My Drive".'
        Write-Host ''
        Write-Host '  Look at the newest picture in the snapshots folder to see'
        Write-Host '  exactly what it saw:'
        Write-Host ('    {0}' -f (Join-Path $Root 'snapshots')) -ForegroundColor DarkGray
        Write-Host ''
        $again = Read-Host '  Try signing in again and picking the right page? (Y/n)'
        if ($again -notmatch '^(n|no)$') {
            & (Join-Path $Root 'Setup-Login.ps1') -StartUrl $loginUrl
            & (Join-Path $Root 'Check-Slots.ps1') -NoJitter | Out-Null
            $state = Get-Content (Join-Path $Root 'state\last-state.json') -Raw | ConvertFrom-Json
            Write-Host ("  Now reporting: {0}" -f $state.status)
        }
    }
}


# --------------------------------------------------------- 6. Phone alerts ---

Write-Step 6 $TOTAL 'Alerts on your phone'

Write-Host '  A pop-up on this PC is no use if you are out of the house, so the'
Write-Host '  watcher can push alerts straight to your phone. It is free, needs'
Write-Host '  no account, and takes about a minute.'
Write-Host ''
$wantPush = Read-Host '  Set that up now? (Y/n)'

if ($wantPush -notmatch '^(n|no)$') {
    & (Join-Path $Root 'Set-PushAlerts.ps1')
}
else {
    Write-Host '  Skipped. You can do it later by running SET-UP-PHONE-ALERTS.cmd' -ForegroundColor Yellow
}


# ------------------------------------------------------------ The schedule ---

if (-not $SkipTask) {
    Write-Host ''
    Write-Host ('  Starting the every-{0}-minutes schedule...' -f $IntervalMinutes) -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 62)) -ForegroundColor DarkGray
    & (Join-Path $Root 'Install-Task.ps1') -IntervalMinutes $IntervalMinutes
}

Write-Host ''
Write-Host '  ==============================================================' -ForegroundColor Green
Write-Host '     SET UP AND RUNNING' -ForegroundColor Green
Write-Host '  ==============================================================' -ForegroundColor Green
Write-Host ''
Write-Host ('  It now checks every {0} minutes and will alert you the moment' -f $IntervalMinutes)
Write-Host '  an opening appears. You do not need to keep any window open.'
Write-Host ''
Write-Host '  Two things worth knowing:'
Write-Host ''
Write-Host '   * It only runs while you are signed in to this PC. If it sleeps'
Write-Host '     or you sign out, checking pauses until you are back.'
Write-Host ''
Write-Host '   * Every morning around 8am you get a quiet "still working"'
Write-Host '     message. If that message ever stops arriving, something is'
Write-Host '     wrong -- that silence is the warning.'
Write-Host ''
Write-Host '  Shortcuts in this folder, and in your Start Menu:'
Write-Host '    CHECK-NOW.cmd             check immediately, do not wait'
Write-Host '    STATUS.cmd                is it working? what did it last see?'
Write-Host '    RE-SIGN-IN.cmd            when it says it needs a fresh login'
Write-Host '    SET-UP-PHONE-ALERTS.cmd   add or change phone alerts'
Write-Host '    UNINSTALL.cmd             stop and remove it completely'
Write-Host ''
Write-Host '  ' + ('-' * 62) -ForegroundColor DarkGray
Write-Host ''
Write-Host '  This is free, and stays free. If it saves you a scramble and you' -ForegroundColor Cyan
Write-Host '  feel like buying the author a coffee, the page is here:' -ForegroundColor Cyan
Write-Host ''
Write-Host '      https://buymeacoffee.com/ctaylor23' -ForegroundColor White
Write-Host ''
Write-Host '  Entirely optional -- nothing is held back if you do not, and there'
Write-Host '  is a Start Menu shortcut for it if you would rather do it later.'
Write-Host ''

$coffee = Read-Host '  Open that page in your browser now? (y/N)'
if ($coffee -match '^(y|yes)$') {
    Start-Process 'https://buymeacoffee.com/ctaylor23' | Out-Null
    Write-Host '  Opened. Thank you.' -ForegroundColor Green
}

Write-Host ''
Read-Host '  Press Enter to close'
