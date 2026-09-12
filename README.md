# Driving Lesson Slot Watcher

Behind-the-wheel lesson openings are first come, first served, and they appear
without warning. This watches your driving school's scheduling page every 15
minutes and pushes your phone the moment one shows up.

Built for the **DrivingSchoolSoftware / tds.ms** student portal that a lot of US
driving schools use. Runs entirely on your own Windows PC.

---

## It never books anything

That's deliberate. Grabbing a slot blind can land you a time your kid can't
make, and undoing that may cost a lesson off your package. It tells you, opens
the page, and the last click is yours.

## It never sees your password

You sign in yourself, in a real browser window, exactly as you always do. It
keeps the same "stay signed in" cookie your browser would keep anyway.

Nothing is uploaded anywhere. There's no account, no server, no cost. Your
sign-in, logs and page snapshots stay in the folder on your PC, and
[`.gitignore`](.gitignore) makes sure they can never be committed back here.

---

## Install

You need a Windows PC and about five minutes. You don't need to be technical,
and you don't need administrator rights.

1. **Download**: green **Code** button above → **Download ZIP**
2. **Right-click the zip → Properties → tick "Unblock"** (if the checkbox is
   there), then OK
3. **Extract** somewhere permanent like `C:\DrivingSlotWatcher` — not Downloads
4. **Double-click `INSTALL.cmd`**

Windows will show a blue *"Windows protected your PC"* box, because this isn't
signed by a software company. Click **More info** → **Run anyway**. Everything
here is plain text you can read in Notepad first.

Setup walks through six steps and installs what it needs (Node.js, a browser
library) as it goes.

Full walkthrough: **[INSTRUCTIONS.md](INSTRUCTIONS.md)**

### The two things people get wrong

**Tick "Remember me" when you sign in.** Without it the site logs you out after
a few hours and you'll be redoing setup constantly.

**Leave the browser on "Schedule My Drive"**, not "My Schedule". The first lists
openings you can book; the second lists lessons you already have. Setup warns
you if it spots the wrong one.

---

## Once it's running

No window has to stay open. You get:

- **A push the moment an opening appears** — on your phone, plus an alarm and a
  pop-up on the PC, and the scheduling page opens ready to book
- **A quiet "still working" message each morning**, with how many checks ran
  overnight. If that message ever stops arriving, that silence is your warning
  that something needs a look.

Alerts can go to your phone (free, no account), email, or as a text message.

| Double-click | What it does |
|---|---|
| `CHECK-NOW.cmd` | Check right now instead of waiting |
| `STATUS.cmd` | Is it working? What did it last see? |
| `RE-SIGN-IN.cmd` | When it says it needs a fresh login |
| `TEST-ALERT.cmd` | Confirm alerts still reach you |
| `SET-UP-PHONE-ALERTS.cmd` | Add or change how you're alerted |
| `UNINSTALL.cmd` | Stop and remove it completely |

---

## Known limits

Worth knowing before you rely on it:

- **It only runs while you're signed in to the PC.** A desktop that stays on is
  ideal; a laptop that sleeps overnight will have gaps.
- **You'll re-sign-in periodically.** The site expires sessions. It messages you
  when that happens; `RE-SIGN-IN.cmd` fixes it in a minute.
- **Some schools hide lessons near expiry dates.** If a temporary permit is
  close to expiring or the program end date has passed, the site shows "no
  openings" whether or not lessons exist. Nothing can see through that. If your
  child is near either date, call the school.
- **Checks run every 15 minutes**, roughly 96 a day, with a random offset. That's
  about what an anxious parent hitting refresh looks like. Please don't lower it
  — hammering the site risks the account you're trying to book with.

---

## Something not working?

Double-click **`STATUS.cmd`** first — it answers most questions on its own.

Then [open an issue](../../issues/new/choose). Include the `STATUS.cmd` output
and the newest `.txt` file from your `snapshots` folder, and it's usually
obvious what's happening.

**Never post your password or `state/storage.json`** — that file is a live
sign-in to your account. See [SUPPORT.md](SUPPORT.md).

---

## Support this

This is free and always will be. If it got your kid their hours faster, that's
payment enough.

A few people have asked about chipping in toward the time it took to build. If
you'd like to, get in touch and I'll point you at a link — and if you'd rather
not, genuinely, don't give it another thought.

---

## For the curious

[TECHNICAL-NOTES.md](TECHNICAL-NOTES.md) covers how detection works, why it
makes certain choices, and the failure modes found building it against a live
site — including several where it looked like it was working and wasn't.

Run the test suite with `powershell -ExecutionPolicy Bypass -File tests\Run-SelfTest.ps1`.
44 checks against a local fake page, in a sandbox that can't touch your real
config or sign-in.

MIT licensed. No warranty — it's a helper, not a guarantee you'll get a slot.
