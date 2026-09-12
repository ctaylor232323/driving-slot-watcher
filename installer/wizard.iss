; ---------------------------------------------------------------------------
; Wizard logic.
;
; Everything setup used to ask in a console now happens in ordinary Windows
; pages. The only other window the user sees is the sign-in browser, and that
; one is deliberate: they type their password into the real driving school
; site, never into anything of ours.
; ---------------------------------------------------------------------------

[Code]

var
  UrlPage:      TInputQueryWizardPage;
  AlertPage:    TInputOptionWizardPage;
  NtfyTopic:    String;
  SetupOutcome: String;

// Runs one hidden stage of Setup-Headless.ps1 and reads back what it decided.
// The script writes its own result file, so there is no shell redirection to
// get wrong.
function RunStage(const Args: String; var Outcome: String): Boolean;
var
  ResultCode, P: Integer;
  ResultFile: String;
  Contents: AnsiString;
  PsExe, Params: String;
begin
  Outcome := '';
  ResultFile := ExpandConstant('{app}\state\stage-result.txt');
  DeleteFile(ResultFile);

  PsExe := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Params := '-NoProfile -ExecutionPolicy Bypass -File "' +
            ExpandConstant('{app}\Setup-Headless.ps1') + '" ' + Args;

  Result := Exec(PsExe, Params, ExpandConstant('{app}'),
                 SW_HIDE, ewWaitUntilTerminated, ResultCode);

  if LoadStringFromFile(ResultFile, Contents) then
    Outcome := Trim(String(Contents));

  // Strip anything after the first line break.
  P := Pos(#13, Outcome);
  if P > 0 then Outcome := Copy(Outcome, 1, P - 1);
  P := Pos(#10, Outcome);
  if P > 0 then Outcome := Copy(Outcome, 1, P - 1);

  Result := Result and (ResultCode = 0);
end;


procedure InitializeWizard;
begin
  UrlPage := CreateInputQueryPage(wpSelectTasks,
    'Your driving school',
    'Which page do you sign in to?',
    'Open your driving school''s student login page in your browser and copy the address ' +
    'from the bar at the top.' + #13#10 + #13#10 +
    'It usually looks like:   https://www.tds.ms/CentralizeSP/Student/Login/yourschoolname');
  UrlPage.Add('Login page address:', False);
  UrlPage.Values[0] := 'https://';

  AlertPage := CreateInputOptionPage(UrlPage.ID,
    'Alerts on your phone',
    'Where should it tell you about an opening?',
    'A pop-up on this PC is no use if you are out of the house. The watcher can push ' +
    'alerts straight to your phone using a free app called ntfy. No account, no cost.',
    True, False);
  AlertPage.Add('Send alerts to my phone as well (recommended)');
  AlertPage.Add('Only alert me on this PC');
  AlertPage.SelectedValueIndex := 0;
end;


function NextButtonClick(CurPageID: Integer): Boolean;
var
  Url: String;
begin
  Result := True;

  // A silent install has no one to answer a message box. Validating here
  // popped a modal with no user in front of it and hung the install.
  if WizardSilent then Exit;

  if CurPageID = UrlPage.ID then
  begin
    Url := Trim(UrlPage.Values[0]);

    if (Pos('http://', Url) <> 1) and (Pos('https://', Url) <> 1) then
    begin
      MsgBox('That does not look like a web address.' + #13#10 + #13#10 +
             'It should start with https:// and be the page where you normally sign in ' +
             'to the driving school.', mbError, MB_OK);
      Result := False;
      Exit;
    end;

    if Length(Url) < 20 then
    begin
      MsgBox('That address looks too short.' + #13#10 + #13#10 +
             'Please paste the whole thing from your browser''s address bar.',
             mbError, MB_OK);
      Result := False;
    end;
  end;
end;


procedure DoSetupWork();
var
  Progress: TOutputProgressWizardPage;
  Outcome, SignalFile, Topic, StartUrl, CapturedFile: String;
  TopicRaw: AnsiString;
  ResultCode, Waited: Integer;
begin
  SetupOutcome := '';

  // Silent install = files only. Signing in needs a human at the keyboard,
  // so there is nothing sensible to do here without one.
  if WizardSilent then
  begin
    SetupOutcome := 'SILENT';
    Exit;
  end;

  StartUrl := Trim(UrlPage.Values[0]);
  SignalFile := ExpandConstant('{app}\state\continue.signal');
  CapturedFile := ExpandConstant('{app}\state\captured-url.txt');

  Progress := CreateOutputProgressPage('Setting up', 'This usually takes two or three minutes.');
  Progress.Show;
  try
    Progress.SetText('Checking for Node.js...',
                     'If it is missing it will be installed for you. This can take a minute.');
    Progress.SetProgress(5, 100);
    if not RunStage('-Stage node', Outcome) then
    begin
      SetupOutcome := 'FAILED:' + Outcome;
      Exit;
    end;

    Progress.SetText('Installing the browser components...',
                     'This is the slow part. Please leave it running.');
    Progress.SetProgress(20, 100);
    if not RunStage('-Stage deps', Outcome) then
    begin
      SetupOutcome := 'FAILED:' + Outcome;
      Exit;
    end;

    Progress.SetText('Saving your settings...', '');
    Progress.SetProgress(35, 100);

    if AlertPage.SelectedValueIndex = 0 then
      Topic := ' -WantPush'
    else
      Topic := '';

    if not RunStage('-Stage config -LoginUrl "' + StartUrl + '"' + Topic, Outcome) then
    begin
      SetupOutcome := 'FAILED:' + Outcome;
      Exit;
    end;

    if not LoadStringFromFile(ExpandConstant('{app}\state\ntfy-topic.txt'), TopicRaw) then
      NtfyTopic := ''
    else
      NtfyTopic := Trim(String(TopicRaw));

    Progress.SetText('Opening a browser so you can sign in...', '');
    Progress.SetProgress(50, 100);

    DeleteFile(SignalFile);
    DeleteFile(CapturedFile);

    Exec(ExpandConstant('{app}\node-run.cmd'),
         'login-wizard.js "' + StartUrl + '" "' + SignalFile + '"',
         ExpandConstant('{app}'), SW_HIDE, ewNoWait, ResultCode);

    Progress.Hide;
    MsgBox('A browser window is opening. Give it a few seconds.' + #13#10 + #13#10 +
           'In THAT window:' + #13#10 + #13#10 +
           '1.  Sign in to your driving school as you normally would.' + #13#10 +
           '     Nothing here ever sees your password.' + #13#10 + #13#10 +
           '2.  Tick "Remember me" if you see it. It saves you having to' + #13#10 +
           '     repeat this every few days.' + #13#10 + #13#10 +
           '3.  Go to the page that lists lessons you can BOOK.' + #13#10 +
           '     Usually:  Scheduling  >  Schedule My Drive' + #13#10 +
           '     NOT "My Schedule", which only shows lessons you already have.' + #13#10 + #13#10 +
           '4.  Leave the browser on that page, then click OK here.',
           mbInformation, MB_OK);
    Progress.Show;

    Progress.SetText('Saving your sign-in...', '');
    Progress.SetProgress(70, 100);
    SaveStringToFile(SignalFile, 'go', False);

    Waited := 0;
    while (Waited < 120) and (not FileExists(CapturedFile)) do
    begin
      Sleep(500);
      Waited := Waited + 1;
    end;
    Sleep(2500);

    Progress.SetText('Starting the watcher...',
                     'Checking your scheduling page once, to prove it works.');
    Progress.SetProgress(85, 100);

    if not RunStage('-Stage finalize', Outcome) then
    begin
      SetupOutcome := 'FAILED:' + Outcome;
      Exit;
    end;

    Progress.SetProgress(100, 100);
    SetupOutcome := 'OK:' + Outcome;
  finally
    Progress.Hide;
  end;
end;


procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    DoSetupWork();
end;


procedure CurPageChanged(CurPageID: Integer);
var
  Msg: String;
begin
  if CurPageID <> wpFinished then Exit;

  if Pos('OK:', SetupOutcome) = 1 then
  begin
    Msg := 'It is running. From now on it checks every 15 minutes and will alert you ' +
           'the moment a lesson opens up. You do not need to keep anything open.';

    if Pos('no_slots', SetupOutcome) > 0 then
      Msg := Msg + #13#10 + #13#10 +
             'Right now there are no openings, which is the normal starting point.'
    else if Pos('slots_available', SetupOutcome) > 0 then
      Msg := Msg + #13#10 + #13#10 +
             'There are openings on the page RIGHT NOW. Go and look.'
    else if Pos('login_required', SetupOutcome) > 0 then
      Msg := Msg + #13#10 + #13#10 +
             'It could not stay signed in. Open "Sign in again" from the Start Menu ' +
             'and tick "Remember me" this time.'
    else
      Msg := Msg + #13#10 + #13#10 +
             'It read a page it did not recognise, which usually means the browser was ' +
             'left on "My Schedule" instead of "Schedule My Drive". Open "Sign in again" ' +
             'from the Start Menu to put that right.';

    if (AlertPage.SelectedValueIndex = 0) and (NtfyTopic <> '') then
      Msg := Msg + #13#10 + #13#10 +
             'FOR YOUR PHONE: install the free "ntfy" app, tap +, and subscribe to this ' +
             'exact name:' + #13#10 + #13#10 +
             '        ' + NtfyTopic + #13#10 + #13#10 +
             'Treat it like a password. It is also saved in the Start Menu under ' +
             '"Your phone alert name".';
  end
  else if SetupOutcome = 'SILENT' then
    Msg := 'Files installed. Open "Set up the watcher" from the Start Menu to finish.'
  else if SetupOutcome = '' then
    Msg := 'Setup did not finish.' + #13#10 + #13#10 +
           'Open "Set up the watcher" from the Start Menu to try again.'
  else
    Msg := 'Setup could not finish.' + #13#10 + #13#10 +
           SetupOutcome + #13#10 + #13#10 +
           'Open "Set up the watcher" from the Start Menu to try again, or send this ' +
           'message to Chris and he can sort it out.';

  WizardForm.FinishedLabel.Caption := Msg;
end;
