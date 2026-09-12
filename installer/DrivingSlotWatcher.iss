; Inno Setup script for the Driving Lesson Slot Watcher.
;
; Builds a single DrivingSlotWatcher-Setup.exe so a non-technical user gets the
; Next-Next-Finish wizard they already know, instead of downloading a zip,
; unblocking it, extracting it and hunting for a .cmd file.
;
; Installs under %LOCALAPPDATA% on purpose: no administrator rights, no UAC
; prompt, and the folder stays writable so the app can keep its config, logs
; and page snapshots beside itself.
;
; Build with:  ISCC.exe installer\DrivingSlotWatcher.iss

#define AppName       "Driving Lesson Slot Watcher"
#define AppShortName  "DrivingSlotWatcher"
#define AppVersion    "1.0.1"
#define AppPublisher  "Chris Taylor"
#define AppURL        "https://github.com/ctaylor232323/driving-slot-watcher"

[Setup]
AppId={{7C4B9E21-3A6D-4F18-9C2E-5D8A1B0F6E33}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}

; No admin. This is the whole point -- a parent on a home or work laptop
; should not need to argue with UAC to watch a scheduling page.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\{#AppShortName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=no

OutputDir=..\dist
OutputBaseFilename=DrivingSlotWatcher-Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes

LicenseFile=..\LICENSE
InfoBeforeFile=welcome.txt

UninstallDisplayName={#AppName}
UninstallDisplayIcon={sys}\WindowsPowerShell\v1.0\powershell.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Put a shortcut on my Desktop"; GroupDescription: "Shortcuts:"

[Files]
; The launchers people actually double-click.
Source: "..\app\CHECK-NOW.cmd";           DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\STATUS.cmd";              DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\RE-SIGN-IN.cmd";          DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\TEST-ALERT.cmd";          DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\SET-UP-PHONE-ALERTS.cmd"; DestDir: "{app}"; Flags: ignoreversion

; The program itself.
Source: "..\app\Install.ps1";             DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Uninstall.ps1";           DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Check-Slots.ps1";         DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Setup-Login.ps1";         DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Show-Status.ps1";         DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Install-Task.ps1";        DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Uninstall-Task.ps1";      DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Set-PushAlerts.ps1";      DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Set-TextAlerts.ps1";      DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\Set-EmailPassword.ps1";   DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\check-slots.js";          DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\login.js";                DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\open-page.js";            DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\test-detect.js";          DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\package.json";            DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\config.template.json";    DestDir: "{app}"; Flags: ignoreversion
Source: "..\app\lib\*";                   DestDir: "{app}\lib"; Flags: ignoreversion recursesubdirs

; Docs worth having locally.
Source: "..\docs\INSTRUCTIONS.md";         DestDir: "{app}"; Flags: ignoreversion
Source: "..\docs\SUPPORT.md";              DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE";                 DestDir: "{app}"; Flags: ignoreversion

[INI]
; A real internet shortcut, so "buy the author a coffee" is something you can
; click from the Start Menu later rather than text you have to retype.
Filename: "{app}\Buy the author a coffee.url"; Section: "InternetShortcut"; \
  Key: "URL"; String: "https://buymeacoffee.com/ctaylor23"

[Icons]
Name: "{group}\Set up the watcher";      Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Install.ps1"""; WorkingDir: "{app}"
Name: "{group}\Check for openings now";  Filename: "{app}\CHECK-NOW.cmd";  WorkingDir: "{app}"
Name: "{group}\Is it working?";          Filename: "{app}\STATUS.cmd";     WorkingDir: "{app}"
Name: "{group}\Sign in again";           Filename: "{app}\RE-SIGN-IN.cmd"; WorkingDir: "{app}"
Name: "{group}\Test my alerts";          Filename: "{app}\TEST-ALERT.cmd"; WorkingDir: "{app}"
Name: "{group}\Instructions";            Filename: "{app}\INSTRUCTIONS.md"; WorkingDir: "{app}"
Name: "{group}\Buy the author a coffee"; Filename: "{app}\Buy the author a coffee.url"
Name: "{group}\Uninstall";               Filename: "{uninstallexe}"

Name: "{autodesktop}\Driving Slot Watcher - Status"; Filename: "{app}\STATUS.cmd"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; Launch setup straight after install, so there is no "now find the folder" gap.
;
; skipifsilent matters: without it a /VERYSILENT install still fires this, and
; because setup asks questions it blocks forever with no window to answer in.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Install.ps1"""; \
  WorkingDir: "{app}"; \
  Description: "Set it up now (recommended)"; \
  Flags: postinstall nowait skipifsilent

; Offered, not pushed: unchecked by default, so nobody donates by accident
; through habitually clicking Next.
Filename: "https://buymeacoffee.com/ctaylor23"; \
  Description: "This was free - buy the author a coffee (optional)"; \
  Flags: postinstall shellexec nowait skipifsilent unchecked

[UninstallRun]
; Stop the scheduled task and delete the saved sign-in before the files go.
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Uninstall.ps1"" -Quiet"; \
  WorkingDir: "{app}"; \
  RunOnceId: "StopWatcher"; \
  Flags: runhidden

[UninstallDelete]
; Anything setup created afterwards that Inno did not lay down itself.
Type: filesandordirs; Name: "{app}\state"
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\snapshots"
Type: filesandordirs; Name: "{app}\profile"
Type: filesandordirs; Name: "{app}\node_modules"
Type: files;          Name: "{app}\Buy the author a coffee.url"
Type: files;          Name: "{app}\config.json"
Type: files;          Name: "{app}\package-lock.json"
Type: dirifempty;     Name: "{app}"
