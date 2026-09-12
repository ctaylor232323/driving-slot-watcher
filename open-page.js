'use strict';

// Opens the scheduling page in the monitor's own signed-in profile and leaves
// the window sitting there so you can book by hand. Used when
// alerts.openIn is "playwright".

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = __dirname;

async function main() {
  const cfg = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));
  if (!cfg.schedulingUrl) {
    console.error('config.json has no schedulingUrl.');
    process.exit(1);
  }

  const opts = { headless: false, viewport: null, args: ['--start-maximized'] };
  if (cfg.runtime && cfg.runtime.channel) opts.channel = cfg.runtime.channel;

  const context = await chromium.launchPersistentContext(path.join(ROOT, 'profile'), opts);
  const page = context.pages()[0] || (await context.newPage());
  await page.goto(cfg.schedulingUrl, { waitUntil: 'domcontentloaded' }).catch(() => {});

  // Stay open until the window is closed by hand.
  context.on('close', () => process.exit(0));
  await new Promise(() => {});
}

main().catch((err) => {
  console.error('Could not open the page: ' + err.message);
  process.exit(1);
});
