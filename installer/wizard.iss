; ---------------------------------------------------------------------------
; Wizard logic.
;
; One question, then it gets on with it. Phone alerts are just switched on --
; everybody wants them, so asking was a question with one sensible answer.
;
; The only window besides this wizard is the sign-in browser, and that stays on
; purpose: the password goes into the real driving school site, never into
; anything of ours.
; ---------------------------------------------------------------------------

[Code]

var
  UrlPage:      TInputQueryWizardPage;
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

  P := Pos(#13, Outcome);
  if P > 0 then Outcome := Copy(Outcome, 1, P - 1);
  P := Pos(#10, Outcome);
  if P > 0 then Outcome := Copy(Outcome, 1, P - 1);

  Result := Result and (ResultCode = 0);
end;


function ReadTextFile(const Path: String): String;
var
  Contents: AnsiString;
begin
  if LoadStringFromFile(Path, Contents) then
    Result := Trim(String(Contents))
  else
    Result := '';
end;


procedure InitializeWizard;
begin
  UrlPage := CreateInputQueryPage(wpSelectTasks,
    'Your driving school',
    'Where do you sign in?',
    'Open the page where you sign in to your driving school, and copy the address ' +
    'from your browser''s address bar.');
  UrlPage.Add('Address:', False);
  UrlPage.Values[0] := 'https://';
end;


function NextButtonClick(CurPageID: Integer): Boolean;
var
  Url: String;
begin
  Result := True;

  // A silent install has no one to answer a message box.
  if WizardSilent then Exit;

  if CurPageID = UrlPage.ID then
  begin
    Url := Trim(UrlPage.Values[0]);
    if (Pos('http://', Url) <> 1) and (Pos('https://', Url) <> 1) or (Length(Url) < 20) then
    begin
      MsgBox('That does not look like a web address.' + #13#10 + #13#10 +
             'Paste the whole thing from your browser''s address bar. It starts ' +
             'with https://', mbError, MB_OK);
      Result := False;
    end;
  end;
end;


// Opens the browser, waits for the user, and returns True only if a page was
// actually captured. Closing the browser early used to end setup with an
// error and no way back; now it just asks if you want another go.
function DoSignIn(Progress: TOutputProgressWizardPage; const StartUrl: String): Boolean;
var
  SignalFile, CapturedFile, Captured: String;
  ResultCode, Waited, Attempt: Integer;
begin
  Result := False;
  SignalFile := ExpandConstant('{app}\state\continue.signal');
  CapturedFile := ExpandConstant('{app}\state\captured-url.txt');
  Attempt := 0;

  while (not Result) and (Attempt < 4) do
  begin
    Attempt := Attempt + 1;

    DeleteFile(SignalFile);
    DeleteFile(CapturedFile);

    Progress.SetText('Opening a browser so you can sign in...', '');
    Exec(ExpandConstant('{app}\node-run.cmd'),
         'login-wizard.js "' + StartUrl + '" "' + SignalFile + '"',
         ExpandConstant('{app}'), SW_HIDE, ewNoWait, ResultCode);

    Progress.Hide;
    MsgBox('A browser is opening. Give it a few seconds.' + #13#10 + #13#10 +
           '1.  Sign in to your driving school.' + #13#10 +
           '2.  Check "Remember me" if you see it.' + #13#10 +
           '3.  Go to Scheduling, then Schedule My Drive.' + #13#10 +
           '4.  Leave it there and click OK below.' + #13#10 + #13#10 +
           'Leave the browser open until you have clicked OK.',
           mbInformation, MB_OK);
    Progress.Show;

    Progress.SetText('Saving your sign-in...', '');
    SaveStringToFile(SignalFile, 'go', False);

    Waited := 0;
    while (Waited < 120) and (not FileExists(CapturedFile)) do
    begin
      Sleep(500);
      Waited := Waited + 1;
    end;
    Sleep(2000);

    Captured := ReadTextFile(CapturedFile);
    if Captured <> '' then
      Result := True
    else
    begin
      Progress.Hide;
      if MsgBox('Setup did not get your sign-in.' + #13#10 + #13#10 +
                'That usually means the browser was closed too early. It needs to ' +
                'stay open until you click OK.' + #13#10 + #13#10 +
                'Open the browser and try again?',
                mbConfirmation, MB_YESNO) = IDNO then
      begin
        Progress.Show;
        Exit;
      end;
      Progress.Show;
    end;
  end;
end;


procedure DoSetupWork();
var
  Progress: TOutputProgressWizardPage;
  Outcome, StartUrl: String;
begin
  SetupOutcome := '';

  if WizardSilent then
  begin
    SetupOutcome := 'SILENT';
    Exit;
  end;

  StartUrl := Trim(UrlPage.Values[0]);

  Progress := CreateOutputProgressPage('Setting up', 'This takes a couple of minutes.');
  Progress.Show;
  try
    Progress.SetText('Checking for Node.js...', 'Installing it if you do not have it.');
    Progress.SetProgress(5, 100);
    if not RunStage('-Stage node', Outcome) then
    begin
      SetupOutcome := 'FAILED:' + Outcome;
      Exit;
    end;

    Progress.SetText('Installing browser components...', 'This is the slow part.');
    Progress.SetProgress(20, 100);
    if not RunStage('-Stage deps', Outcome) then
    begin
      SetupOutcome := 'FAILED:' + Outcome;
      Exit;
    end;

    Progress.SetText('Saving settings...', '');
    Progress.SetProgress(35, 100);
    if not RunStage('-Stage config -LoginUrl "' + StartUrl + '" -WantPush', Outcome) then
    begin
      SetupOutcome := 'FAILED:' + Outcome;
      Exit;
    end;
    NtfyTopic := ReadTextFile(ExpandConstant('{app}\state\ntfy-topic.txt'));

    Progress.SetProgress(50, 100);
    if not DoSignIn(Progress, StartUrl) then
    begin
      SetupOutcome := 'NOSIGNIN';
      Exit;
    end;

    Progress.SetText('Starting the watcher...', 'Checking your page once, to prove it works.');
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
    Msg := 'It is running. It checks every 15 minutes and will alert you when a lesson opens up.';

    if Pos('slots_available', SetupOutcome) > 0 then
      Msg := Msg + #13#10 + #13#10 + 'There are openings right now. Go and look.'
    else if Pos('login_required', SetupOutcome) > 0 then
      Msg := Msg + #13#10 + #13#10 +
             'It could not stay signed in. Open "Sign in again" from the Start Menu ' +
             'and check "Remember me".'
    else if Pos('no_slots', SetupOutcome) = 0 then
      Msg := Msg + #13#10 + #13#10 +
             'It did not recognize that page. You were probably left on "My Schedule" ' +
             'instead of "Schedule My Drive". Open "Sign in again" from the Start Menu.';

    if NtfyTopic <> '' then
      Msg := Msg + #13#10 + #13#10 +
             'FOR YOUR PHONE: install the free app "ntfy", tap +, and enter:' + #13#10 + #13#10 +
             '        ' + NtfyTopic + #13#10 + #13#10 +
             'Saved for you in the Start Menu under "Your phone alert name".';
  end
  else if SetupOutcome = 'SILENT' then
    Msg := 'Files installed. Open "Set up the watcher" from the Start Menu to finish.'
  else if SetupOutcome = 'NOSIGNIN' then
    Msg := 'Almost there - it just needs your sign-in.' + #13#10 + #13#10 +
           'Open "Sign in again" from the Start Menu when you are ready. Everything ' +
           'else is installed and waiting.'
  else if SetupOutcome = '' then
    Msg := 'Setup did not finish. Open "Set up the watcher" from the Start Menu to try again.'
  else
    Msg := 'Setup could not finish.' + #13#10 + #13#10 + SetupOutcome + #13#10 + #13#10 +
           'Open "Set up the watcher" from the Start Menu to try again, or send this to Chris.';

  WizardForm.FinishedLabel.Caption := Msg;
end;
