'use strict';

// Sign-in for the installer wizard.
//
// The original login.js waited on Enter at a console prompt, which is exactly
// the black box we are trying to get rid of. This version waits on a signal
// file instead: the wizard writes it when the user clicks OK on a normal
// Windows dialog, and this process then saves the session and exits.
//
// Usage:  node login-wizard.js <startUrl> <signalFile>

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = __dirname;
const PROFILE_DIR = path.join(ROOT, 'profile');
const STATE_DIR = path.join(ROOT, 'state');
const STORAGE_PATH = path.join(STATE_DIR, 'storage.json');
const CAPTURED_PATH = path.join(STATE_DIR, 'captured-url.txt');

const startUrl = process.argv[2];
const signalFile = process.argv[3];

if (!startUrl || !signalFile) {
  console.error('Usage: node login-wizard.js <startUrl> <signalFile>');
  process.exit(2);
}

function lastRealPage(context) {
  const pages = context.pages().filter((p) => /^https?:/i.test(p.url()));
  return pages.length ? pages[pages.length - 1] : context.pages()[0];
}

async function main() {
  fs.mkdirSync(PROFILE_DIR, { recursive: true });
  fs.mkdirSync(STATE_DIR, { recursive: true });
  if (fs.existsSync(signalFile)) fs.unlinkSync(signalFile);

  let channel = 'msedge';
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));
    if (cfg.runtime && typeof cfg.runtime.channel === 'string') channel = cfg.runtime.channel;
  } catch (e) {
    /* config may not exist yet; msedge is the right default on Windows */
  }

  const opts = { headless: false, viewport: null, args: ['--start-maximized'] };
  if (channel) opts.channel = channel;

  const context = await chromium.launchPersistentContext(PROFILE_DIR, opts);
  const page = context.pages()[0] || (await context.newPage());
  await page.goto(startUrl, { waitUntil: 'domcontentloaded' }).catch(() => {});

  // Wait for the wizard to say the user is done. Give up after 20 minutes so a
  // forgotten window cannot hang the installer forever.
  const deadline = Date.now() + 20 * 60 * 1000;
  let signalled = false;

  while (Date.now() < deadline) {
    if (fs.existsSync(signalFile)) {
      signalled = true;
      break;
    }
    // If the user closes the browser themselves, treat that as "done too".
    if (context.pages().length === 0) break;
    await new Promise((r) => setTimeout(r, 400));
  }

  let capturedUrl = '';
  try {
    const active = lastRealPage(context);
    if (active) capturedUrl = active.url();
  } catch (e) {
    /* browser may already be closing */
  }

  try {
    await context.storageState({ path: STORAGE_PATH });
  } catch (e) {
    console.error('Could not save the session: ' + e.message);
  }

  // Only write this when we actually got a page. The wizard treats its
  // absence as "the browser was closed too early" and offers to retry, which
  // it cannot do if we leave an empty file behind.
  if (capturedUrl) {
    fs.writeFileSync(CAPTURED_PATH, capturedUrl, 'utf8');
  }
  await context.close().catch(() => {});

  if (!signalled && !capturedUrl) {
    console.error('No session captured.');
    process.exit(1);
  }
  process.exit(0);
}

main().catch((err) => {
  console.error('Sign-in failed: ' + err.message);
  process.exit(1);
});
