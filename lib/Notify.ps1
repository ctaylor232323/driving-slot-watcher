# Notification helpers for the driving school monitor.
# Dot-sourced by Check-Slots.ps1. Windows PowerShell 5.1 compatible.

function Write-MonitorLog {
    param(
        [Parameter(Mandatory = $true)][string] $Message,
        [ValidateSet('INFO', 'WARN', 'ALERT', 'ERROR')][string] $Level = 'INFO',
        [string] $LogDir
    )

    $line = ('{0}  {1,-5}  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)

    switch ($Level) {
        'ALERT' { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }

    if ($LogDir) {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        $file = Join-Path $LogDir ('monitor-{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))
        Add-Content -Path $file -Value $line -Encoding UTF8
    }
}

function Show-DesktopToast {
    param(
        [Parameter(Mandatory = $true)][string] $Title,
        [Parameter(Mandatory = $true)][string] $Message
    )

    # Preferred path: a real Windows toast, which also lands in Action Center
    # so it is still there if you were away from the desk.
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $safeTitle = [System.Security.SecurityElement]::Escape($Title)
        $safeBody = [System.Security.SecurityElement]::Escape($Message)

        $xml = @"
<toast scenario="reminder" duration="long">
  <visual>
    <binding template="ToastGeneric">
      <text>$safeTitle</text>
      <text>$safeBody</text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Looping.Alarm2" />
</toast>
"@

        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
        return $true
    }
    catch {
        Write-Verbose ('Toast failed: {0}' -f $_.Exception.Message)
    }

    # Fallback: tray balloon.
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.BalloonTipTitle = $Title
        $icon.BalloonTipText = $Message
        $icon.Visible = $true
        $icon.ShowBalloonTip(20000)
        Start-Sleep -Seconds 12
        $icon.Dispose()
        return $true
    }
    catch {
        Write-Verbose ('Balloon failed: {0}' -f $_.Exception.Message)
        return $false
    }
}

function Play-AlertSound {
    param([int] $Repeat = 6)

    $wav = Join-Path $env:WINDIR 'Media\Alarm01.wav'
    if (Test-Path $wav) {
        try {
            $player = New-Object System.Media.SoundPlayer $wav
            for ($i = 0; $i -lt $Repeat; $i++) {
                $player.PlaySync()
            }
            return
        }
        catch {
            Write-Verbose ('SoundPlayer failed: {0}' -f $_.Exception.Message)
        }
    }

    for ($i = 0; $i -lt $Repeat; $i++) {
        [console]::Beep(1200, 250)
        [console]::Beep(900, 250)
    }
}

function Show-AlertPopup {
    param(
        [Parameter(Mandatory = $true)][string] $Title,
        [Parameter(Mandatory = $true)][string] $Message
    )

    # Runs in its own process so a scheduled run is never left hanging on an
    # unclicked OK button. Title and body travel as base64 so punctuation in the
    # slot text cannot break out of the command string.
    $b64Title = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Title))
    $b64Body = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Message))

    $inner = @"
Add-Type -AssemblyName PresentationFramework
`$t = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64Title'))
`$b = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64Body'))
[void][System.Windows.MessageBox]::Show(`$b, `$t)
"@

    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-EncodedCommand', $encoded | Out-Null
}

function Send-NtfyPush {
    param(
        [Parameter(Mandatory = $true)][string] $Server,
        [Parameter(Mandatory = $true)][string] $Topic,
        [Parameter(Mandatory = $true)][string] $Title,
        [Parameter(Mandatory = $true)][string] $Message,
        [string] $ClickUrl,
        [string] $Priority = 'urgent'
    )

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $headers = @{
            'Title'    = $Title
            'Priority' = $Priority
            'Tags'     = 'car,calendar'
        }
        if ($ClickUrl) { $headers['Click'] = $ClickUrl }

        $uri = ('{0}/{1}' -f $Server.TrimEnd('/'), $Topic)
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers `
            -Body ([Text.Encoding]::UTF8.GetBytes($Message)) -TimeoutSec 20 | Out-Null
        return $true
    }
    catch {
        Write-Verbose ('ntfy push failed: {0}' -f $_.Exception.Message)
        return $false
    }
}

# Carrier email-to-SMS gateways. Mail sent here arrives as a text message.
# MMS gateways are listed where they exist -- they tolerate longer bodies and
# tend to survive carrier filtering better than the plain SMS ones.
$script:SmsGateways = [ordered]@{
    'att'                = 'mms.att.net'
    'att-sms'            = 'txt.att.net'
    'verizon'            = 'vzwpix.com'
    'verizon-sms'        = 'vtext.com'
    't-mobile'           = 'tmomail.net'
    'sprint'             = 'messaging.sprintpcs.com'
    'us-cellular'        = 'mms.uscc.net'
    'cricket'            = 'mms.cricketwireless.net'
    'metro'              = 'mymetropcs.com'
    'boost'              = 'myboostmobile.com'
    'google-fi'          = 'msg.fi.google.com'
    'mint'               = 'tmomail.net'
    'visible'            = 'vzwpix.com'
    'xfinity'            = 'vzwpix.com'
    'consumer-cellular'  = 'mailmymobile.net'
    'straight-talk'      = 'mypixmessages.com'
    'tracfone'           = 'mmst5.tracfone.com'
}

function Get-SmsGatewayTable {
    return $script:SmsGateways
}

function Test-IsSmsAddress {
    param([Parameter(Mandatory = $true)][string] $Address)

    $domain = ($Address -split '@')[-1]
    if (-not $domain) { return $false }
    return ($script:SmsGateways.Values -contains $domain.Trim().ToLower())
}

# Splits a recipient list into real mailboxes and phone gateways, so each can
# get a body sized for it.
function Split-AlertRecipients {
    param([string] $To)

    $all = @()
    if ($To) {
        $all = @($To -split '\s*[;,]\s*' | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() })
    }

    return [pscustomobject]@{
        Email = @($all | Where-Object { -not (Test-IsSmsAddress $_) })
        Sms   = @($all | Where-Object { Test-IsSmsAddress $_ })
    }
}

# A text message has no room for the full alert. Keep the lesson times, which
# are the only part you act on, and drop the prose.
function Get-ShortAlertBody {
    param(
        [Parameter(Mandatory = $true)][string] $Body,
        [string] $Url,
        [int] $MaxLength = 300
    )

    $lines = @($Body -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # Prefer the bulleted slot times if the alert carried any.
    $bullets = @($lines | Where-Object { $_ -like '-*' } | ForEach-Object { $_.TrimStart('-', ' ') })
    if ($bullets.Count -gt 0) {
        $text = 'OPEN: ' + ($bullets -join '; ')
    }
    else {
        $text = ($lines | Select-Object -First 2) -join ' '
    }

    if ($Url) {
        $room = $MaxLength - ($Url.Length + 1)
        if ($room -lt 40) { $room = 40 }
        if ($text.Length -gt $room) { $text = $text.Substring(0, $room - 3).TrimEnd() + '...' }
        $text = $text + ' ' + $Url
    }
    elseif ($text.Length -gt $MaxLength) {
        $text = $text.Substring(0, $MaxLength - 3).TrimEnd() + '...'
    }

    return $text
}

# Which URL to put in an alert that leaves this machine.
#
# A phone has no saved session, and this site does not redirect signed-out
# visitors to its login page -- it throws them onto ErrorPage.html with "Oops!
# Something went wrong." So a deep link to the scheduling page is useless off
# this desk. The login page is the only address that works from anywhere.
function Get-RemoteAlertUrl {
    param(
        [string] $ClickUrl,
        [string] $LoginUrl,
        [string] $SchedulingUrl
    )

    if ($ClickUrl) { return $ClickUrl }
    if ($LoginUrl) { return $LoginUrl }
    return $SchedulingUrl
}

function Send-AlertEmail {
    param(
        [Parameter(Mandatory = $true)] $EmailConfig,
        [Parameter(Mandatory = $true)][string[]] $To,
        [Parameter(Mandatory = $true)][string] $Subject,
        [Parameter(Mandatory = $true)][string] $Body,
        [Parameter(Mandatory = $true)][string] $CredentialPath
    )

    if (-not (Test-Path $CredentialPath)) {
        Write-Verbose 'No stored mail credential; run Set-EmailPassword.ps1.'
        return $false
    }
    if (-not $To -or $To.Count -eq 0) { return $false }

    try {
        $stored = Get-Content -Path $CredentialPath -Raw
        $secure = ConvertTo-SecureString -String $stored
        $cred = New-Object System.Management.Automation.PSCredential($EmailConfig.from, $secure)

        Send-MailMessage -SmtpServer $EmailConfig.smtpServer -Port $EmailConfig.port `
            -UseSsl:([bool]$EmailConfig.useSsl) -Credential $cred `
            -From $EmailConfig.from -To $To `
            -Subject $Subject -Body $Body -ErrorAction Stop
        return $true
    }
    catch {
        Write-Verbose ('Email failed: {0}' -f $_.Exception.Message)
        return $false
    }
}

function Open-SchedulingPage {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [string] $Mode = 'default',
        [string] $Root
    )

    if ($Mode -eq 'playwright') {
        # Uses the monitor's own signed-in profile.
        Start-Process -FilePath 'node' -ArgumentList (Join-Path $Root 'open-page.js') `
            -WorkingDirectory $Root -WindowStyle Normal | Out-Null
    }
    else {
        # Your everyday browser, where you are already signed in and can book.
        Start-Process $Url | Out-Null
    }
}
