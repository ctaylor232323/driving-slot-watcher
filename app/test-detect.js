'use strict';

// Replays the detection logic against a saved page-text snapshot so you can
// tune config.json without hammering the website.
//
//   node test-detect.js snapshots\2026-09-04T...no_slots.txt

const fs = require('fs');
const path = require('path');
const detect = require('./lib/detect');

const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'config.json'), 'utf8'));
const det = cfg.detection || {};

const target = process.argv[2];
if (!target) {
  console.error('Usage: node test-detect.js <path-to-snapshot.txt>');
  process.exit(1);
}

const raw = fs.readFileSync(target, 'utf8');
const cleaned = detect.stripIgnored(raw, det.ignorePatterns);

const verdict = detect.decide({
  text: cleaned,
  mode: det.mode || 'auto',
  noSlotsPhrases: det.noSlotsPhrases || [],
  selectorCount: null,
  scanDatesAndTimes: det.scanDatesAndTimes !== false,
});

console.log('');
console.log('File        : ' + target);
console.log('Mode        : ' + (det.mode || 'auto'));
console.log('Status      : ' + verdict.status);
console.log('Reason      : ' + verdict.reason);
console.log('Phrase hit  : ' + (verdict.matchedPhrase || '(none)'));
console.log('Fingerprint : ' + detect.fingerprint(cleaned));
console.log('');
if (verdict.slots.length) {
  console.log('Date/time lines found:');
  for (const s of verdict.slots.slice(0, 25)) {
    console.log('  - ' + s.text);
  }
} else {
  console.log('No date/time lines recognized.');
}
console.log('');
