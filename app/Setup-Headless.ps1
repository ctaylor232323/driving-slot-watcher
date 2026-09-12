<#
.SYNOPSIS
    The non-interactive half of setup, driven by the installer wizard.

.DESCRIPTION
    Every stage here runs hidden, with no console shown to the user. The wizard
    calls the stages in order and reports progress in its own window, so nobody
    has to look at a command box.

    Each stage prints a single line beginning with RESULT: so the wizard can
    read the outcome, and exits non-zero on failure.

.PARAMETER Stage
    deps     - install the browser library (and a browser if Edge is absent)
    config   - write config.json from the wizard's answers
    finalize - record the captured scheduling URL, register the schedule, check once

.EXAMPLE
    powershell -File Setup-Headless.ps1 -Stage deps
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('node', 'deps', 'config', 'finalize')]
    [string] $Stage,

    [string] $LoginUrl,
    [switch] $WantPush,
    [int]    $IntervalMinutes = 15
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $Root 'lib\Common.ps1')

# The wizard reads this file rather than trying to capture stdout, which keeps
# it clear of shell-redirection quoting entirely.
$ResultFile = Join-Path $Root 'state\stage-result.txt'
if (-not (Test-Path (Split-Path $ResultFile))) {
    New-Item -ItemType Directory -Path (Split-Path $ResultFile) -Force | Out-Null
}
if (Test-Path $ResultFile) { Remove-Item $ResultFile -Force }

function Say {
    param([string] $Text)
    Write-Utf8NoBom -Path $ResultFile -Content $Text
    Write-Output ("RESULT:" + $Text)
}

function Fail {
    param([string] $Text)
    Write-Utf8NoBom -Path $ResultFile -Content ("ERROR " + $Text)
    Write-Output ("RESULT:ERROR " + $Text)
    exit 1
}

trap {
    Write-Utf8NoBom -Path $ResultFile -Content ("ERROR " + $_.Exception.Message)
    Write-Output ("RESULT:ERROR " + $_.Exception.Message)
    exit 1
}

function Get-NodeExe {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { return $node.Source }

    # A fresh Node install is not on this process's PATH yet.
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { return $node.Source }

    foreach ($guess in @(
            (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe'))) {
        if ($guess -and (Test-Path $guess)) { return $guess }
    }
    return $null
}


switch ($Stage) {

    'node' {
        # Node.js is the one outside dependency. Install it here, inside the
        # wizard's progress bar, rather than making someone go and find it.
        if (Get-NodeExe) {
            Say 'OK already-present'
            break
        }

        $winget = Get-Command winget -ErrorAction SilentlyContinue
        if (-not $winget) {
            Fail 'Node.js is missing and this PC has no automatic installer. Install Node.js LTS from nodejs.org, then run setup again.'
        }

        & $winget.Source install -e --id OpenJS.NodeJS.LTS `
            --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null

        if (-not (Get-NodeExe)) {
            Fail 'Node.js was installed but Windows has not picked it up yet. Restart the PC and run setup again from the Start Menu.'
        }
        Say 'OK installed'
    }

    'deps' {
        $node = Get-NodeExe
        if (-not $node) { Fail 'Node.js is not available.' }

        $npm = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $npm) { Fail 'npm is not available.' }

        Push-Location $Root
        try {
            & $npm.Source install --no-fund --no-audit --loglevel=error 2>&1 | Out-Null
            if (-not (Test-Path (Join-Path $Root 'node_modules\playwright'))) {
                Fail 'The browser library did not install. Check the internet connection.'
            }

            # Use the Edge that is already here when we can: no 150 MB download,
            # and it looks like an ordinary browser to the website.
            $edge = @(
                (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
                (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
            ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

            if ($edge) {
                Say 'OK using-edge'
            }
            else {
                & npx playwright install chromium 2>&1 | Out-Null
                Say 'OK downloaded-chromium'
            }
        }
        finally {
            Pop-Location
        }
    }

    'config' {
        if (-not $LoginUrl) { Fail 'No login address was supplied.' }

        $template = Join-Path $Root 'config.template.json'
        $configPath = Join-Path $Root 'config.json'
        if (-not (Test-Path $template)) { Fail 'config.template.json is missing.' }

        $cfg = Get-Content $template -Raw | ConvertFrom-Json
        $cfg.loginUrl = $LoginUrl

        # Blank until sign-in tells us which page they actually landed on.
        $cfg.schedulingUrl = ''

        $edge = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
        ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        $cfg.runtime.channel = $(if ($edge) { 'msedge' } else { '' })

        # Generated here, not in the installer's scripting language, which has
        # no cryptographic RNG. This name is the only thing protecting someone's
        # alerts, so it needs real entropy rather than a tick-count seed.
        $NtfyTopic = ''
        if ($WantPush) {
            $chars = 'abcdefghijkmnopqrstuvwxyz23456789'
            $bytes = New-Object 'byte[]' 14
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($bytes)
            $rng.Dispose()

            $sb = New-Object System.Text.StringBuilder
            foreach ($b in $bytes) { [void]$sb.Append($chars[$b % $chars.Length]) }
            $NtfyTopic = 'drive-' + $sb.ToString()

            $cfg.alerts.ntfy.enabled = $true
            $cfg.alerts.ntfy.topic = $NtfyTopic

            # The wizard reads this back to show on its last page.
            Write-Utf8NoBom -Path (Join-Path $Root 'state\ntfy-topic.txt') -Content $NtfyTopic
        }

        Write-Utf8NoBom -Path $configPath -Content ($cfg | ConvertTo-Json -Depth 10)

        # Somewhere to look the topic up later, since it is shown once on the
        # wizard's last page and then gone.
        $notePath = Join-Path $Root 'Your phone alert name.txt'
        if ($NtfyTopic) {
            $note = @(
                'YOUR PHONE ALERT NAME',
                '',
                '    ' + $NtfyTopic,
                '',
                'To get driving lesson alerts on your phone:',
                '',
                '  1. Install the free app "ntfy" from the App Store or Play Store.',
                '     You do not need an account.',
                '  2. Open it, tap the + button.',
                '  3. Type the name above, exactly. Leave the server as ntfy.sh.',
                '  4. Allow notifications when it asks.',
                '',
                'Treat this name like a password. Anyone who knows it can read your',
                'alerts. The only thing in them is the lesson dates and times already',
                'shown on your driving school website.'
            ) -join [Environment]::NewLine
            Write-Utf8NoBom -Path $notePath -Content $note
        }

        Say 'OK config-written'
    }

    'finalize' {
        $configPath = Join-Path $Root 'config.json'
        if (-not (Test-Path $configPath)) { Fail 'config.json is missing.' }

        $capturedPath = Join-Path $Root 'state\captured-url.txt'
        if (-not (Test-Path $capturedPath)) { Fail 'Sign-in did not record a page.' }

        $captured = (Get-Content $capturedPath -Raw).Trim()
        if (-not $captured) { Fail 'Sign-in did not record a page.' }

        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        $cfg.schedulingUrl = $captured
        Write-Utf8NoBom -Path $configPath -Content ($cfg | ConvertTo-Json -Depth 10)

        if (-not (Test-Path (Join-Path $Root 'state\storage.json'))) {
            Fail 'No sign-in was saved.'
        }

        # One real check, so the wizard can tell the user whether this actually
        # works rather than just claiming success.
        & (Join-Path $Root 'Check-Slots.ps1') -NoJitter | Out-Null

        $statePath = Join-Path $Root 'state\last-state.json'
        $status = 'unknown'
        if (Test-Path $statePath) {
            $status = (Get-Content $statePath -Raw | ConvertFrom-Json).status
        }

        & (Join-Path $Root 'Install-Task.ps1') -IntervalMinutes $IntervalMinutes | Out-Null

        $task = Get-ScheduledTask -TaskName 'DrivingSchoolSlotMonitor' -ErrorAction SilentlyContinue
        if (-not $task) { Fail 'The 15-minute schedule could not be registered.' }

        Say ('OK ' + $status)
    }
}

exit 0
