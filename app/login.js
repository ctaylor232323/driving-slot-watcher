'use strict';

// Opens a real browser window using a dedicated profile so you can sign in by
// hand. Nothing about your password is read, typed, or stored by this script --
// it only saves the cookies the site hands your browser afterwards.

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { chromium } = require('playwright');

const ROOT = __dirname;
const CONFIG_PATH = path.join(ROOT, 'config.json');
const PROFILE_DIR = path.join(ROOT, 'profile');
const STORAGE_PATH = path.join(ROOT, 'state', 'storage.json');

function ask(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((resolve) => rl.question(question, (a) => (rl.close(), resolve(a))));
}

function lastRealPage(context) {
  const pages = context.pages().filter((p) => /^https?:/i.test(p.url()));
  return pages.length ? pages[pages.length - 1] : context.pages()[0];
}

async function main() {
  const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  const startUrl = process.argv[2] || cfg.schedulingUrl || 'about:blank';
  const rt = cfg.runtime || {};

  fs.mkdirSync(PROFILE_DIR, { recursive: true });
  fs.mkdirSync(path.dirname(STORAGE_PATH), { recursive: true });

  const opts = { headless: false, viewport: { width: 1400, height: 1000 } };
  if (rt.channel) opts.channel = rt.channel;

  const context = await chromium.launchPersistentContext(PROFILE_DIR, opts);
  const page = context.pages()[0] || (await context.newPage());

  if (startUrl !== 'about:blank') {
    await page.goto(startUrl, { waitUntil: 'domcontentloaded' }).catch((e) => {
      console.log('Could not load ' + startUrl + ': ' + e.message);
    });
  }

  console.log('');
  console.log('A browser window is open. In THAT window:');
  console.log('  1. Sign in to the driving school site.');
  console.log('  2. Navigate to the behind-the-wheel scheduling page you want watched.');
  console.log('  3. Leave it sitting on that page.');
  console.log('');
  await ask('Then press Enter here to save the session... ');

  const active = lastRealPage(context);
  const capturedUrl = active ? active.url() : '';

  await context.storageState({ path: STORAGE_PATH });
  fs.writeFileSync(path.join(ROOT, 'state', 'captured-url.txt'), capturedUrl, 'utf8');
  console.log('CAPTURED:' + capturedUrl);
  console.log('Session saved to ' + STORAGE_PATH);

  await context.close();
}

main().catch((err) => {
  console.error('Login setup failed: ' + err.message);
  process.exit(1);
});
