'use strict';

// Headless check of the scheduling page. Reads the session saved by
// Setup-Login.ps1, decides whether slots are open, and writes
// state/last-result.json. Never books anything.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const detect = require('./lib/detect');

const ROOT = __dirname;

// --config lets the self-test run against its own config, state and snapshots
// so it can never read or overwrite the real ones. An earlier version shared
// them, and a scheduled check that fired mid-test saved an empty session over
// the real sign-in.
const argv = process.argv.slice(2);
const configFlag = argv.indexOf('--config');
const CONFIG_PATH =
  configFlag >= 0 && argv[configFlag + 1]
    ? path.resolve(argv[configFlag + 1])
    : path.join(ROOT, 'config.json');

const CFG = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));

function resolveDir(value, fallback) {
  if (!value) return fallback;
  return path.isAbsolute(value) ? value : path.join(ROOT, value);
}

const RUNTIME = CFG.runtime || {};
const STATE_DIR = resolveDir(RUNTIME.stateDir, path.join(ROOT, 'state'));
const SNAP_DIR = resolveDir(RUNTIME.snapshotDir, path.join(ROOT, 'snapshots'));
const STORAGE_PATH = path.join(STATE_DIR, 'storage.json');
const RESULT_PATH = path.join(STATE_DIR, 'last-result.json');

const stamp = new Date().toISOString().replace(/[:.]/g, '-');

function log(msg) {
  process.stderr.write('[check] ' + msg + '\n');
}

function ensureDir(d) {
  fs.mkdirSync(d, { recursive: true });
}

function writeResult(result) {
  ensureDir(path.dirname(RESULT_PATH));
  result.checkedAt = new Date().toISOString();
  fs.writeFileSync(RESULT_PATH, JSON.stringify(result, null, 2), 'utf8');
  process.stdout.write('RESULT:' + JSON.stringify(result) + '\n');
  return result;
}

function pruneSnapshots(keep) {
  if (!keep || keep < 1) return;
  try {
    const files = fs
      .readdirSync(SNAP_DIR)
      .filter((f) => f.endsWith('.png') || f.endsWith('.html') || f.endsWith('.txt'))
      .map((f) => ({ f, t: fs.statSync(path.join(SNAP_DIR, f)).mtimeMs }))
      .sort((a, b) => b.t - a.t);
    for (const old of files.slice(keep * 3)) {
      fs.unlinkSync(path.join(SNAP_DIR, old.f));
    }
  } catch (e) {
    /* pruning is best-effort */
  }
}

async function runPreActions(page, actions, warnings) {
  for (const step of actions || []) {
    const kind = String(step.action || '').toLowerCase();
    try {
      if (kind === 'wait') {
        await page.waitForTimeout(Number(step.ms) || 1000);
      } else if (kind === 'waitfor') {
        await page.waitForSelector(step.selector, { timeout: Number(step.timeoutMs) || 15000 });
      } else if (kind === 'click') {
        await page.click(step.selector, { timeout: Number(step.timeoutMs) || 10000 });
      } else if (kind === 'clicktext') {
        await page
          .getByText(step.text, { exact: !!step.exact })
          .first()
          .click({ timeout: Number(step.timeoutMs) || 10000 });
      } else if (kind === 'select') {
        await page.selectOption(step.selector, String(step.value));
      } else if (kind === 'fill') {
        await page.fill(step.selector, String(step.value));
      } else if (kind === 'goto') {
        await page.goto(step.url, { waitUntil: 'domcontentloaded' });
      } else {
        warnings.push('Unknown preAction "' + step.action + '" was skipped.');
        continue;
      }
      log('preAction ok: ' + kind + ' ' + (step.selector || step.text || step.url || ''));
    } catch (err) {
      const msg =
        'preAction "' + kind + ' ' + (step.selector || step.text || '') + '" failed: ' + err.message;
      if (step.required) throw new Error(msg);
      warnings.push(msg);
      log('WARN ' + msg);
    }
  }
}

async function looksLikeLogin(page, loginHostPattern) {
  const url = page.url();
  if (loginHostPattern) {
    try {
      if (new RegExp(loginHostPattern, 'i').test(url)) return true;
    } catch (e) {
      /* ignore bad pattern */
    }
  }
  const pw = await page
    .locator('input[type="password"]:visible')
    .count()
    .catch(() => 0);
  return pw > 0;
}

// This site does not redirect a signed-out visitor to its login page -- it
// serves ErrorPage.html with "Oops! Something went wrong." So an expired
// session looks like neither a login form nor a scheduling page, and without
// this check it reads as "the page changed" and raises a false alarm.
function looksLikeSessionLost(page, text, det) {
  for (const pattern of det.sessionLostUrlPatterns || []) {
    try {
      if (new RegExp(pattern, 'i').test(page.url())) return true;
    } catch (e) {
      /* a bad pattern in config should never take the run down */
    }
  }

  const hay = String(text || '')
    .replace(/\s+/g, ' ')
    .toLowerCase();
  for (const phrase of det.sessionLostPhrases || []) {
    const needle = String(phrase).replace(/\s+/g, ' ').trim().toLowerCase();
    if (needle && hay.includes(needle)) return true;
  }
  return false;
}

async function main() {
  const cfg = CFG;
  const det = cfg.detection || {};
  const rt = RUNTIME;
  const warnings = [];

  if (!cfg.schedulingUrl) {
    return writeResult({
      status: 'error',
      reason: 'config.json has no schedulingUrl. Run Setup-Login.ps1 first.',
      warnings,
    });
  }
  if (!fs.existsSync(STORAGE_PATH)) {
    return writeResult({
      status: 'error',
      reason: 'No saved session at state/storage.json. Run Setup-Login.ps1 first.',
      warnings,
    });
  }

  ensureDir(SNAP_DIR);

  const launchOpts = { headless: rt.headless !== false };
  if (rt.channel) launchOpts.channel = rt.channel;

  const browser = await chromium.launch(launchOpts);
  const context = await browser.newContext({
    storageState: STORAGE_PATH,
    viewport: { width: 1400, height: 1000 },
  });
  const page = await context.newPage();
  page.setDefaultTimeout(Number(det.timeoutMs) || 45000);

  try {
    log('navigating to ' + cfg.schedulingUrl);
    await page.goto(cfg.schedulingUrl, {
      waitUntil: 'domcontentloaded',
      timeout: Number(det.timeoutMs) || 45000,
    });

    // Settle briefly, then decide whether we are even signed in. Doing this
    // before the readySelector wait matters: on a signed-out page that
    // selector never appears, and waiting the full timeout wasted ~45s of
    // every run.
    await page.waitForTimeout(1200);
    const earlyText = await page.evaluate(() => document.body.innerText).catch(() => '');

    const onLogin = await looksLikeLogin(page, cfg.loginHostPattern);
    const sessionLost = looksLikeSessionLost(page, earlyText, det);

    if (onLogin || sessionLost) {
      const shot = path.join(SNAP_DIR, stamp + '_login.png');
      await page.screenshot({ path: shot, fullPage: true }).catch(() => {});
      fs.writeFileSync(path.join(SNAP_DIR, stamp + '_login.txt'), earlyText, 'utf8');
      await browser.close();
      return writeResult({
        status: 'login_required',
        reason: onLogin
          ? 'Landed on a login page -- the saved session has expired.'
          : 'The site served its error page, which is what it shows a signed-out visitor. ' +
            'The saved session has almost certainly expired (it can also mean the site itself is erroring).',
        url: page.url(),
        screenshot: shot,
        warnings,
      });
    }

    await runPreActions(page, cfg.preActions, warnings);

    if (det.readySelector) {
      await page
        .waitForSelector(det.readySelector, { timeout: Number(det.timeoutMs) || 45000 })
        .catch((e) => warnings.push('readySelector never appeared: ' + e.message));
    }

    // Let client-side rendering finish.
    await page.waitForLoadState('networkidle').catch(() => {});
    await page.waitForTimeout(Number(det.settleMs) || 3500);

    let bodyText = await page.evaluate(() => document.body.innerText);

    // Optionally walk forward through weeks/months, appending each view.
    const pg = cfg.pagination || {};
    let clicks = 0;
    if (pg.nextSelector && Number(pg.maxClicks) > 0) {
      while (clicks < Number(pg.maxClicks)) {
        const next = page.locator(pg.nextSelector).first();
        const usable = await next.isEnabled().catch(() => false);
        if (!usable) break;
        await next.click({ timeout: 8000 }).catch(() => {});
        await page.waitForTimeout(Number(pg.waitAfterClickMs) || 1500);
        const more = await page.evaluate(() => document.body.innerText).catch(() => '');
        bodyText += '\n----- next view -----\n' + more;
        clicks += 1;
      }
      log('paginated ' + clicks + ' view(s)');
    }

    let selectorCount = null;
    if (det.slotSelector) {
      selectorCount = await page
        .locator(det.slotSelector)
        .count()
        .catch(() => 0);
    }

    const cleaned = detect.stripIgnored(bodyText, det.ignorePatterns);

    const verdict = detect.decide({
      text: cleaned,
      mode: det.mode || 'auto',
      noSlotsPhrases: det.noSlotsPhrases || [],
      loginRequired: false,
      selectorCount,
      scanDatesAndTimes: det.scanDatesAndTimes !== false,
    });

    const shot = path.join(SNAP_DIR, stamp + '_' + verdict.status + '.png');
    const htmlPath = path.join(SNAP_DIR, stamp + '_' + verdict.status + '.html');
    const txtPath = path.join(SNAP_DIR, stamp + '_' + verdict.status + '.txt');
    await page.screenshot({ path: shot, fullPage: true }).catch(() => {});
    fs.writeFileSync(htmlPath, await page.content(), 'utf8');
    fs.writeFileSync(txtPath, bodyText, 'utf8');

    // Refresh the saved session so rotating cookies do not go stale.
    await context.storageState({ path: STORAGE_PATH }).catch(() => {});

    await browser.close();
    pruneSnapshots(Number(rt.keepSnapshots) || 60);

    return writeResult({
      status: verdict.status,
      reason: verdict.reason,
      matchedPhrase: verdict.matchedPhrase,
      slots: verdict.slots.map((s) => s.text),
      slotCount: verdict.slots.length,
      selectorCount,
      paginatedViews: clicks,
      fingerprint: detect.fingerprint(cleaned),
      url: page.url(),
      screenshot: shot,
      htmlSnapshot: htmlPath,
      textSnapshot: txtPath,
      warnings,
    });
  } catch (err) {
    const shot = path.join(SNAP_DIR, stamp + '_error.png');
    await page.screenshot({ path: shot, fullPage: true }).catch(() => {});
    await browser.close().catch(() => {});
    return writeResult({
      status: 'error',
      reason: err.message,
      screenshot: shot,
      warnings,
    });
  }
}

main().catch((err) => {
  writeResult({ status: 'error', reason: 'Unhandled: ' + err.message, warnings: [] });
  process.exit(1);
});
