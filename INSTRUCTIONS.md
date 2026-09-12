# Driving Lesson Slot Watcher

Behind-the-wheel openings are first come, first served, and they appear without
warning. This watches your driving school's scheduling page every 15 minutes and
alerts your phone the moment one shows up.

**It never books anything.** Booking blind could grab a time your child can't
make, and undoing that may cost a lesson from your package. It tells you, opens
the page, and the last click stays yours.

**It never sees your password.** You sign in yourself, in a normal browser
window, exactly as you always do. It only keeps the same "stay signed in" cookie
your browser would keep.

Everything runs on your own PC. Nothing is uploaded anywhere.

---

## What you need

- A Windows PC (Windows 10 or 11)
- Your driving school login, on the DrivingSchoolSoftware / tds.ms system
- About five minutes

You do **not** need to be technical, and you don't need administrator rights.

---

## Installing

1. **Unblock the zip first.** Right-click the zip file, choose *Properties*,
   and if you see an **Unblock** checkbox near the bottom, tick it and click OK.
   Windows adds that mark to anything downloaded, and unblocking once here saves
   you several warnings later. If there's no checkbox, nothing to do.

2. **Unzip the folder.** Right-click the zip → *Extract All*. Put it somewhere
   permanent like `C:\DrivingSlotWatcher` — not inside the zip, and not in your
   Downloads folder where you might clear it out later.

3. **Double-click `INSTALL.cmd`.**

   Windows may show a blue *"Windows protected your PC"* box, because the file
   came from the internet. Click **More info**, then **Run anyway**. (That
   warning appears for anything downloaded that isn't from a big publisher.)

4. **Follow the six steps.** It will:
   - install Node.js if you don't have it (free, from the OpenJS Foundation)
   - download the browser library it uses
   - ask for your school's login page address
   - open a browser so you can sign in
   - check that it can read the page
   - set up phone alerts and start the schedule

### The two steps people get wrong

**Tick "Remember me" when you sign in.** Without it the site signs you out after
a few hours and you'll have to sign in again. With it, you'll go days or weeks.

**Leave the browser on the page that lists *bookable openings*.** On this system
that's **Scheduling → Schedule My Drive**. It is *not* "My Schedule", which only
lists lessons already booked. Watching the wrong page is the single most common
setup mistake, and the installer will warn you if it spots it.

---

## Getting your school's login address

Open the page where you normally sign in, and copy the whole address out of the
bar at the top of the browser. It looks roughly like:

```
https://www.tds.ms/CentralizeSP/Student/Login/yourschoolname
```

Paste that in when the installer asks.

---

## Phone alerts

An alert on your PC is no use if you're at work. Setup offers to send them to
your phone instead, using a free app called **ntfy**:

1. Install **ntfy** from the App Store or Play Store. No account needed.
2. The installer shows you a private topic name like `drive-a6a2y8hjagsvk3`.
3. In the app, tap **+** and type that name exactly.

Alerts then arrive in about a second.

Treat the topic name like a password — anyone who knows it can read your alerts.
The only thing in them is the lesson dates and times already shown on your
school's site.

You can also get alerts by email or text message; run `SET-UP-PHONE-ALERTS.cmd`
and it explains the options.

---

## Day to day

Once installed you don't need to do anything. No window needs to stay open.

Every morning around 8am you get a quiet **"still working"** message telling you
it's alive and how many checks it ran. **If that message ever stops arriving,
something is wrong** — that silence is the warning. Everything else is silent
until an opening appears.

When one does, you get a push on your phone, a pop-up and an alarm on the PC,
and the scheduling page opens ready for you to book.

### The shortcuts in the folder

| Double-click | What it does |
|---|---|
| `CHECK-NOW.cmd` | Check right now instead of waiting |
| `STATUS.cmd` | Is it working? What did it last see? |
| `RE-SIGN-IN.cmd` | When it says it needs a fresh login |
| `TEST-ALERT.cmd` | Fire a test alert to check they still reach you |
| `SET-UP-PHONE-ALERTS.cmd` | Add or change how you're alerted |
| `UNINSTALL.cmd` | Stop and remove it completely |

---

## Things worth knowing up front

**It only runs while you're signed in to the PC.** If it sleeps or you sign out,
checking pauses until you're back. An always-on desktop is ideal; a laptop that
sleeps at night will have gaps.

**You'll occasionally need to sign in again.** The site expires the session. It
pushes you a message when that happens — just run `RE-SIGN-IN.cmd`. Ticking
"Remember me" makes this much rarer.

**Some schools hide lessons near expiry dates.** If a temporary permit is close
to expiring, or the program end date has passed, the site shows "no openings"
whether or not lessons exist. The watcher can't see through that, and will sit
quiet while lessons are genuinely being posted. If your child is near either
date, call the school and confirm — no amount of monitoring solves that one.

**It checks every 15 minutes,** about 96 times a day, with a random offset so
it doesn't hit the site on the same second each time. That's roughly what an
anxious parent hitting refresh would do. Please don't lower it; hammering the
site risks the account you're trying to book with.

---

## If something looks wrong

Double-click `STATUS.cmd`. It shows what it last saw, whether the schedule is
healthy, and the last few log lines.

| What you see | What to do |
|---|---|
| "needs a fresh login" | Run `RE-SIGN-IN.cmd`, tick "Remember me" |
| Alerts stopped arriving | Run `TEST-ALERT.cmd` |
| "page changed" messages | Probably watching "My Schedule" instead of "Schedule My Drive" — run `RE-SIGN-IN.cmd` and pick the right page |
| No morning message | Check the PC was on and signed in; then `STATUS.cmd` |
| Tapping an alert shows "Oops! Something went wrong" | You're signed out on the phone. The alert links to the login page — sign in there, then Scheduling → Schedule My Drive |

The `snapshots` folder holds a picture of every page it looked at, newest first.
That's the fastest way to see what it actually saw.

---

## Removing it

Double-click `UNINSTALL.cmd`. It stops the checking and deletes the saved
sign-in, the logs and the page snapshots. Then delete the folder.

It can't touch your driving school account and can't cancel a booked lesson.
