# 🚗 Driving Lesson Slot Watcher

### Behind-the-wheel openings disappear in minutes. This watches for them and texts your phone the second one appears.

<br>

## ⬇️ Step 1 — Download it

# **[👉 CLICK HERE TO DOWNLOAD 👈](https://github.com/ctaylor232323/driving-slot-watcher/releases/latest/download/DrivingSlotWatcher-Setup.exe)**

That downloads one file: `DrivingSlotWatcher-Setup.exe`. You don't need a GitHub
account, and you can ignore everything else on this page.

## ▶️ Step 2 — Run it

Double-click the file you just downloaded.

Windows will show a blue **"Windows protected your PC"** box. That's normal — it
appears for anything not published by a big software company. Click
**More info**, then **Run anyway**.

Then click through the installer the way you would any other program. It needs
no administrator rights.

## ⚙️ Step 3 — Let it set itself up

When the installer finishes it opens a short setup that asks for your driving
school's web address, opens a browser so you can sign in, and offers to send
alerts to your phone. About five minutes.

**Stuck?** The full walkthrough is in **[INSTRUCTIONS.md](INSTRUCTIONS.md)**, and
you can [ask me here](../../issues/new/choose).

<br>

---

## ☕ Was this useful?

It's free and always will be. If it got your kid their hours faster, that's
payment enough.

A few people asked how to chip in for the time it took, so if you'd like to:

### **[☕ Buy me a coffee](https://buymeacoffee.com/ctaylor23)**

Completely optional. Nothing sits behind it, there's no nagging, and you get
exactly the same help either way.

---

<br>

## What it actually does

Every 15 minutes it signs in to your driving school's scheduling page, checks
whether any behind-the-wheel lessons have opened up, and alerts you the moment
one appears. Openings are first come, first served and show up without warning,
so a few minutes of notice is the whole game.

**It never books anything.** That's deliberate. Grabbing a slot blind can land
you a time your kid can't make, and undoing that may cost a lesson off your
package. It tells you, opens the page, and the last click is yours.

**It never sees your password.** You sign in yourself, in a real browser window,
exactly as you always do. It keeps the same "stay signed in" cookie your browser
would keep anyway.

Nothing is uploaded anywhere. No account, no server, no cost. Your sign-in, logs
and page snapshots stay in the folder on your PC.

Built for the **DrivingSchoolSoftware / tds.ms** student portal that a lot of US
driving schools use. Windows 10 or 11.

## Once it's running

No window has to stay open. You get:

- **A push the moment an opening appears** — on your phone, plus an alarm and a
  pop-up on the PC, and the scheduling page opens ready to book
- **A quiet "still working" message each morning**, with how many checks ran
  overnight. If that message ever stops arriving, that silence is your warning
  that something needs a look.

Alerts can go to your phone (free, no account), email, or as a text message.

After installing, the folder has these — just double-click them:

| | |
|---|---|
| **CHECK-NOW** | Check right now instead of waiting |
| **STATUS** | Is it working? What did it last see? |
| **RE-SIGN-IN** | When it says it needs a fresh login |
| **TEST-ALERT** | Confirm alerts still reach you |
| **SET-UP-PHONE-ALERTS** | Add or change how you're alerted |
| **UNINSTALL** | Stop and remove it completely |

## The two things people get wrong

**Tick "Remember me" when you sign in.** Without it the site logs you out after
a few hours and you'll be redoing setup constantly.

**Leave the browser on "Schedule My Drive"**, not "My Schedule". The first lists
openings you can book; the second lists lessons you already have. Setup warns
you if it spots the wrong one.

## Known limits

- **It only runs while you're signed in to the PC.** A desktop that stays on is
  ideal; a laptop that sleeps overnight will have gaps.
- **You'll re-sign-in periodically.** The site expires sessions. It messages you
  when that happens; `RE-SIGN-IN` fixes it in a minute.
- **Some schools hide lessons near expiry dates.** If a temporary permit is
  close to expiring or the program end date has passed, the site shows "no
  openings" whether or not lessons exist. Nothing can see through that. If your
  child is near either date, call the school.
- **Checks run every 15 minutes**, roughly 96 a day. That's about what an
  anxious parent hitting refresh looks like. Please don't lower it — hammering
  the site risks the account you're trying to book with.

## Something not working?

Double-click **STATUS** first — it answers most questions on its own.

Then [open an issue](../../issues/new/choose) and paste what STATUS printed. You
need a free GitHub account to post one; if you'd rather not, just send it to me
directly.

**Never post your password or `state\storage.json`** — that file is a live
sign-in to your account. See [SUPPORT.md](SUPPORT.md).

## For the curious

[TECHNICAL-NOTES.md](TECHNICAL-NOTES.md) covers how detection works and the
failure modes found building it against a live site — including several where it
looked like it was working and wasn't.

Run the tests with `powershell -ExecutionPolicy Bypass -File tests\Run-SelfTest.ps1`.
44 checks against a local fake page, sandboxed so they can't touch your real
config or sign-in.

MIT licensed. No warranty — it's a helper, not a guarantee you'll get a slot.
