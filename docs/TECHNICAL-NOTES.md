# Technical notes

**Setting this up? Read INSTRUCTIONS.md instead.** This file is the
engineering detail: how detection works, why certain choices were made,
and the failure modes found while building it against a live site.

---

Watches the behind-the-wheel scheduling page and tells you the moment an
opening appears. **It never books anything** — it alerts you and opens the page
so you can grab the slot yourself.

Everything runs locally on this machine. Built and tested on 2026-09-04.

---

## What is here

| File | What it does |
|---|---|
| `config.json` | Everything you can tune. The only file you normally edit. Your login URL is already in it. |
| `Setup-Login.ps1` | Opens a browser so you sign in by hand; saves the session. |
| `Check-Slots.ps1` | **The main script.** One check, then alerts if warranted. |
| `Install-Task.ps1` | Registers the Task Scheduler job (every 15 min by default). |
| `Uninstall-Task.ps1` | Removes that job. |
| `Show-Status.ps1` | What it last saw, task health, recent log lines. |
| `Set-PushAlerts.ps1` | Phone push setup. No password needed. |
| `Set-TextAlerts.ps1` | Guided setup for email + text alerts. |
| `Set-EmailPassword.ps1` | Just re-saves the mail app password on its own. |
| `tests\Run-SelfTest.ps1` | 44 checks in a sandbox, against a local fake page. No noise, no website. |
| `test-detect.js` | Replay detection against a saved snapshot while tuning. |
| `logs\` | One log file per day. |
| `snapshots\` | Screenshot + HTML + text of every check, newest 60 kept. |
| `state\` | Saved session and last-known state. Not for hand editing. |

---

## Step 1 — Sign in once

```powershell
cd C:\DrivingSchoolMonitor
.\Setup-Login.ps1
```

Your login URL is already saved in `config.json`, so it goes straight to
opening an Edge window. In **that** window:

1. Sign in. It opens on the login page, which is the one page that loads
   whether or not your session is still alive.
2. Go to **Scheduling -> Schedule My Drive** (the open-slots page). Not
   *My Schedule*, which lists lessons already booked -- see the site notes below.
3. Leave it sitting there and come back to PowerShell and press Enter.

It saves the session cookies to `state\storage.json` and offers to record the
scheduling page URL in `config.json`.

**Your password is never asked for, seen, or stored by any of these scripts.**
You type it into the real site; only the cookies the site hands back get saved.

Re-run this whenever the monitor says it needs a fresh login. On this site the
session lasts about four days, so this is a recurring chore -- you will get a
phone push when it is due.

## Step 2 — Test a check by hand

```powershell
.\Check-Slots.ps1 -NoJitter -Verbose
```

You want to see `Result: no_slots -- Matched "No Available Open Slots"`.

Then open the newest PNG in `snapshots\` and confirm it shows the real
scheduling page — not a login screen, not a half-loaded page. This is the one
step worth being fussy about: if the screenshot is wrong, every later alert is
noise.

### If the snapshot looks wrong

| Symptom | Fix in `config.json` |
|---|---|
| Page still spinning / half-rendered | Raise `detection.settleMs` to `8000`. |
| Slots live behind a tab or dropdown | Add `preActions`, see below. |
| Lands on a login page | Re-run `Setup-Login.ps1`. |
| Times out | Raise `detection.timeoutMs`. |

`preActions` replays clicks before reading the page:

```json
"preActions": [
  { "action": "clickText", "text": "Behind The Wheel" },
  { "action": "wait", "ms": 2000 },
  { "action": "waitFor", "selector": "#scheduleGrid" }
]
```

Supported actions: `click` / `clickText` / `waitFor` / `wait` / `select` /
`fill` / `goto`. A step that fails is logged as a warning and the run continues;
add `"required": true` to make a failure stop the check instead.

To also scan future weeks, point `pagination.nextSelector` at the page's Next
button and set `maxClicks` to how many weeks ahead to look.

## Step 3 — Confirm the alerts reach you

```powershell
.\Check-Slots.ps1 -TestAlert
```

Fires a sample alert through every enabled channel without touching the site.

A desktop toast is useless if you are out of the house, so pick at least one
channel that reaches your phone. There are three, and they are not equally
reliable.

### Phone push — easiest, and no password

```powershell
.\Set-PushAlerts.ps1
```

Generates a private topic, saves it, and offers to send a test push. Install the
free **ntfy** app (App Store / Play Store, no account), subscribe to that topic,
done. Arrives in about a second and needs no credentials of any kind.

Treat the topic name like a password — anyone who knows it can read your
alerts, and they pass through the public ntfy.sh server. The only thing in them
is the lesson dates and times already shown on the school website.

### Email and text — one setup, needs a Gmail sender

```powershell
.\Set-TextAlerts.ps1
```

Asks for the sending mailbox, its app password, and who to alert — any mix of
email addresses and phone numbers. It knows the carrier gateway domains, so you
just pick your carrier from a list.

A text message *is* an email here: sent to your carrier's email-to-SMS gateway
(`6145550100@vzwpix.com` and friends), it lands as a normal text. No account, no
signup, no cost.

Phone recipients automatically get a trimmed one-line body, because carriers
drop over-long messages:

```
Subject: Driving slots open
OPEN: Thu 09/11/2026 4:00 PM - 6:00 PM Instructor: R. Hall; Sat 09/13/2026
9:00 AM - 11:00 AM Instructor: T. Nguyen https://www.tds.ms/...
```

Email recipients still get the full detail. Both go out in the same run.

Two things to know:

- **The sending account must be Gmail** (or another provider that still allows
  a password-based SMTP login). Gmail needs an **app password**, which requires
  2-Step Verification; your normal password will be refused.
- **Hotmail / Outlook.com cannot send.** Microsoft retired password sign-in for
  third-party apps on consumer accounts and no longer issues app passwords for
  them, so no password exists that this would accept. Their server advertises
  only `AUTH LOGIN XOAUTH2`, and the password half is closed to consumer
  accounts. A Hotmail address is perfectly fine as a **recipient**.
- **A work Microsoft 365 mailbox usually cannot send either**, because most
  tenants disable SMTP sign-in.
- **Carrier gateways are free but best-effort.** Carriers filter them and
  occasionally drop messages silently, and they have been quietly degrading for
  years. Fine as a second channel; I would not make it the only one. If a text
  never arrives, re-run `Set-TextAlerts.ps1` and pick the `-sms` variant for
  your carrier.

## The daily "still working" message

Once a day, at `alerts.dailySummary.atHour` (8am by default), you get a quiet
push telling you the monitor is alive and what it has been doing:

```
Driving monitor: all good
Monitor is alive and can see the scheduling page. Right now: no openings.
Last 24h: 94 checks, 0 failed. Last check: 7:52 AM.
```

If something is wrong it leads with that instead, and comes through at a higher
priority:

```
Driving monitor: needs attention
NOT WATCHING: the session expired. Run Setup-Login.ps1 to fix it.
Last 24h: 44 checks, 6 failed.
```

It also says so when the day looks thin, which usually means the laptop slept:

```
Fewer checks than a full day would give -- the laptop was probably asleep.
```

**The checker itself sends it, deliberately.** A separate scheduled task would
only prove that the second task works. Sent from inside the checker, silence at
8am means the checker stopped -- which is the thing you actually want to know.
Treat a missing morning message as a real signal.

It never makes noise, pops a toast, or opens a browser. If a send fails (no
internet, say) it stays due and goes out on a later check rather than skipping
the day.

Send one right now:

```powershell
.\Check-Slots.ps1 -Digest
```

Settings live under `alerts.dailySummary`: `enabled`, `atHour` (0-23, local
time), `priority` (`low` normally, raised automatically when action is needed),
`expectedChecksPerDay`, and `includeEmail` if you want it emailed/texted too.

Counts come from the log files, not a running tally -- the logs cannot claim a
check happened while the machine was asleep.

## Step 4 — Schedule it

```powershell
.\Install-Task.ps1
```

Every 15 minutes, plus once at logon so it restarts itself after a reboot. Use
`-IntervalMinutes 30` or `60` if you would rather be gentler on the site.

The task runs as you and only while you are logged on — that is what lets it
raise a toast, make noise, and open a browser on your desktop. Phone pushes and
email still arrive when the screen is locked.

```powershell
.\Show-Status.ps1                                        # health check
schtasks /Run    /TN DrivingSchoolSlotMonitor            # run one check now
schtasks /Change /TN DrivingSchoolSlotMonitor /DISABLE   # pause
schtasks /Change /TN DrivingSchoolSlotMonitor /ENABLE    # resume
.\Uninstall-Task.ps1                                     # remove
```

### The self-test runs in a sandbox, and why that matters

`tests\Run-SelfTest.ps1` creates a temp directory with its own `config.json`,
`state\`, `logs\` and `snapshots\`, and runs the checker with `-ConfigPath`
pointed at it. It reads your real config for the detection settings and touches
nothing else.

It used to back up and restore the real `config.json` and `storage.json`
instead. That held until 2026-09-09, when a scheduled check fired in the middle
of a test run, picked up the test's fake config, and then saved an empty session
over the real sign-in -- silently logging the monitor out and making it look
like the site had expired the session after 30 minutes. The test also wrote
`slots_available` lines into the real logs, which made it look as though real
openings had appeared.

Two guards now: the sandbox above, and a `state\check.lock` file so two checks
cannot run against the same state directory at once (a stale lock older than
12 minutes is taken over, so a crashed run cannot wedge it).

If you ever want to confirm the isolation holds, fingerprint the real files
before and after:

```powershell
Get-FileHash config.json, state\storage.json
.\tests\Run-SelfTest.ps1
Get-FileHash config.json, state\storage.json
```

### Why schtasks.exe and not the PowerShell cmdlets

On this machine `Register-ScheduledTask` is refused with **"Access is denied"**
unless PowerShell is elevated -- with or without an explicit principal. Your
account is in Administrators, but UAC hands out a filtered token, so an ordinary
window does not carry those rights. `schtasks.exe` succeeds as a normal user, so
both `Install-Task.ps1` and `Uninstall-Task.ps1` go through it.

Use the `schtasks` commands above rather than `Start-ScheduledTask` /
`Disable-ScheduledTask`, which hit the same denial. Reading is unaffected --
`Get-ScheduledTask` and `Show-Status.ps1` work either way.

The task XML deliberately has **no `<Duration>`** under `<Repetition>`, which is
how Task Scheduler spells "repeat forever". Passing `[TimeSpan]::MaxValue` to
the cmdlet instead produces `P99999999DT23H59M59S`, which the scheduler rejects
as out of range.

Registered and verified working on 2026-09-04: ran from the scheduler with
result code 0, reporting `no_slots`.

---

## How it decides

Playwright drives a headless Edge using the session from step 1, waits for
the JavaScript to render, then reads the page text. In the default `auto` mode:

| What the page shows | Status | Alert? |
|---|---|---|
| A "no slots" phrase from `noSlotsPhrases` | `no_slots` | No |
| No such phrase, and lines with lesson times | `slots_available` | **Yes** |
| No such phrase, nothing recognisable either | `page_changed` | Yes, once |
| A login form | `login_required` | Yes, at most every 6 h |
| Crash or timeout | `error` | After 3 in a row |

The site's own "no slots" message always wins when present — calendars keep
rendering dates even when nothing is bookable, so trusting dates alone would
alert constantly.

Repeat alerts are suppressed for `alerts.cooldownMinutes` (45), but a **change**
in the openings breaks through immediately. `-Force` bypasses the cooldown.

Other modes, if `auto` proves noisy on this particular site:

- `"mode": "phrase"` — alert purely on the phrase disappearing. Simplest.
- `"mode": "selector"` — alert on `detection.slotSelector` matching. Most
  precise, once you know the page's HTML. Right-click a slot in Chrome →
  Inspect to find a stable class.

Every check writes a `.png`, `.html`, and `.txt` snapshot. To retune detection
against one without re-hitting the site:

```powershell
node test-detect.js snapshots\2026-09-04T16-23-08-123Z_no_slots.txt
```

## This site specifically (tds.ms / DrivingSchoolSoftware)

Two pages look almost identical and it is easy to watch the wrong one:

| URL | Page | What it shows |
|---|---|---|
| `...BtwScheduling/Lessons?SchedulingTypeId=-1` | **My Schedule** | Lessons the student has already booked. Says *"No appointments found."* when she has none. **Not the page to watch.** |
| `...BtwScheduling/Lessons?SchedulingTypeId=1` | **Schedule My Drive** | Open slots. Says *"No Available Open Slots"*. **This is the one**, and it is what `schedulingUrl` is set to. |

Confirmed working against the live site on 2026-09-04: `no_slots -- Matched
"No Available Open Slots"`, with a byte-identical fingerprint across repeated
runs, so there is no fingerprint drift to cause phantom alerts.

Useful landmarks in that page, if detection ever needs retuning:

- `#OpenSlotdata` — the container holding either the "no slots" warning or the
  real slots. Used as `readySelector`, so a half-loaded page is never judged.
- `#hdnAvailableDates` — a hidden field, **empty** while nothing is open. It
  should fill with dates when lessons appear, which would make an even more
  precise signal. Untested, because there have been no openings to see yet.
- `#btnScheduleAppointment` — the "Schedule Lesson" button, inside a modal that
  is always in the DOM. Do **not** use it as `slotSelector`; it would match even
  when hidden.

### Why alerts link to the login page, not the scheduling page

This site does **not** redirect signed-out visitors to its login screen. It
throws them onto `ErrorPage.html` with *"Oops! Something went wrong."* -- which
is exactly what you get if you tap an alert on a phone that has no session.

So alerts that leave this machine (phone push, email, text) link to the **login
page**, which loads correctly from anywhere. The desktop browser still opens the
scheduling page directly, since this machine may already be signed in.

The login page ignores `returnUrl` and carries no return-url field, so it cannot
hand you off to the scheduling page automatically. Alerts therefore include the
two taps you need: **sign in, then Scheduling > Schedule My Drive**.

Tick **"Remember me"** when you sign in on your phone. It keeps the session
alive so later alerts are a shorter trip.

Override the link with `alerts.clickUrl` if you ever want it pointed elsewhere.
Blank means "use the login page".

### An expired session looks like a site error, not a login page

Signed out, this site serves `ErrorPage.html` -- *"Oops! Something went wrong."*
-- rather than redirecting to its login form. So an expired session shows up as
neither a login page nor a scheduling page.

Until 2026-09-09 that fell through to `page_changed`, which raised a false
"something changed, go look" alert and then went quiet on cooldown, leaving the
monitor blind without saying so. `detection.sessionLostPhrases` and
`detection.sessionLostUrlPatterns` now catch it and report `login_required`,
which is the alert that actually tells you to sign in again.

That check runs immediately after page load, before the `readySelector` wait.
On a signed-out page that selector never appears, so waiting for it burned about
45 seconds of every run for nothing. A signed-out check now finishes in about
4 seconds.

Observed session lifetime: signed in 2026-09-04, expired after 2026-09-08
15:46 -- roughly four days. Re-running `Setup-Login.ps1` is a recurring chore,
not a one-off, and you will now get a push when it is due.

### The one thing that could make this monitor silent forever

The site's own message says lessons are hidden — not merely absent — when:

- the temporary permit is close to expiring, or
- the program expiration date is close or past.

In that case the page shows the same "No Available Open Slots" wording, the
monitor correctly reports `no_slots`, and no alert ever fires even while
lessons are genuinely being posted. The current message carries `Message Code:
108`.

So confirm the student's permit expiry and program expiration dates with the school.
No amount of monitoring can see through that filter.

## Which browser this drives

`config.json` sets `runtime.channel` to `msedge`, so everything runs through the
Microsoft Edge already installed on this machine.

Playwright's own bundled Chromium **cannot start here** — it fails with *"the
side-by-side configuration is incorrect"*, meaning the Microsoft Visual C++
Redistributable is missing. Its headless shell has fewer dependencies and does
run, which is why headless checks worked while the first sign-in window did not.
Edge ships its own runtime and needs no admin rights, so it sidesteps this
entirely.

If you ever want the bundled Chromium instead, install the x64 Visual C++
Redistributable (needs admin) and set `runtime.channel` back to `""`. There is
no reason to bother — Edge is arguably the better choice anyway, since it looks
like an ordinary browser to the site.

## Two things worth knowing

**Politeness.** 15-minute polling with a random 0–60 s offset is roughly 96
page loads a day — about what an anxious parent hitting refresh would do. Don't
lower the interval much below that; a hammered site can get your account
blocked, which costs you the slot you are trying to win. If the school's terms
prohibit automated access, that's their call to enforce, and the interval is
what keeps this in reasonable territory.

**No auto-booking, by design.** Booking blind can grab a lesson at a time your
daughter can't make, and unwinding that may cost a session from the package.
The alert plus an already-open browser is the fast part; the last click should
be yours.

## Troubleshooting

| Symptom | Where to look |
|---|---|
| Nothing seems to run | `.\Show-Status.ps1` — check `LastTaskResult` (0 = fine). |
| Alerts never arrive | `.\Check-Slots.ps1 -TestAlert`. |
| Tapping an alert shows "Oops! Something went wrong" | You are signed out on that device. The alert link goes to the login page; sign in, then Scheduling > Schedule My Drive. |
| Constant false alarms | The newest `snapshots\*.txt`, then add the site's exact wording to `noSlotsPhrases`. |
| "session expired" / needs a fresh login | `.\Setup-Login.ps1` again. Expect this every few days. |
| Alerts saying the page "changed" with nothing on it | Was a detection gap, fixed 2026-09-09. See below. |
| Checker won't start | `logs\checker-stderr.log`. |
| Confirm nothing is broken after edits | `.\tests\Run-SelfTest.ps1` — expect 12 of 12. |
