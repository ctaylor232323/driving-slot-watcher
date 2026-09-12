'use strict';

// Pure detection helpers. No Playwright in here, so this file can be unit-tested
// against saved page text (see Test-Detection.ps1).

const crypto = require('crypto');

const TIME_RE = /\b(1[0-2]|0?[1-9]):[0-5]\d\s*(?:a\.?m\.?|p\.?m\.?)\b/i;
const TIME_RE_24 = /\b([01]?\d|2[0-3]):[0-5]\d\b/;
const DATE_NUM_RE = /\b(1[0-2]|0?[1-9])[/-](3[01]|[12]\d|0?[1-9])(?:[/-](?:\d{4}|\d{2}))?\b/;
const DATE_WORD_RE =
  /\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b/i;
const DOW_RE =
  /\b(?:mon|tues?|wed(?:nes)?|thur?s?|fri|sat(?:ur)?|sun)(?:day)?\b/i;

function collapse(text) {
  return String(text || '')
    .replace(/ /g, ' ')
    .replace(/[ \t]+/g, ' ')
    .replace(/\r/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function stripIgnored(text, patterns) {
  let out = text;
  for (const p of patterns || []) {
    try {
      out = out.replace(new RegExp(p, 'gi'), '');
    } catch (e) {
      // A bad regex in config should never take the run down.
    }
  }
  return out;
}

function fingerprint(text) {
  return crypto
    .createHash('sha1')
    .update(collapse(text).toLowerCase())
    .digest('hex')
    .slice(0, 16);
}

// Returns the phrase that matched, or null. Whitespace-insensitive and
// case-insensitive so "No  Available   Open Slots" still matches.
function findNoSlotsPhrase(text, phrases) {
  const hay = collapse(text).replace(/\s+/g, ' ').toLowerCase();
  for (const phrase of phrases || []) {
    const needle = String(phrase).replace(/\s+/g, ' ').trim().toLowerCase();
    if (needle && hay.includes(needle)) return phrase;
  }
  return null;
}

// Lines that look like they describe a bookable date/time.
function scanSlotLines(text, limit = 40) {
  const seen = new Set();
  const hits = [];
  for (const raw of collapse(text).split('\n')) {
    const line = raw.trim();
    if (!line || line.length > 200) continue;

    const hasTime = TIME_RE.test(line);
    const hasDate = DATE_NUM_RE.test(line) || DATE_WORD_RE.test(line);
    if (!hasTime && !hasDate) continue;

    // A bare weekday header row ("Mon Tue Wed") is calendar furniture, not a slot.
    if (!hasTime && !hasDate) continue;
    if (!hasTime && DOW_RE.test(line) && !DATE_NUM_RE.test(line) && !DATE_WORD_RE.test(line)) {
      continue;
    }

    const key = line.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    hits.push({ text: line, hasTime, hasDate });
    if (hits.length >= limit) break;
  }
  return hits;
}

/**
 * Decide what the page is telling us.
 * status: login_required | no_slots | slots_available | page_changed
 */
function decide(opts) {
  const {
    text = '',
    mode = 'auto',
    noSlotsPhrases = [],
    loginRequired = false,
    selectorCount = null,
    scanDatesAndTimes = true,
  } = opts;

  if (loginRequired) {
    return {
      status: 'login_required',
      reason: 'The page asked for a login, so the saved session is no longer valid.',
      matchedPhrase: null,
      slots: [],
    };
  }

  const matchedPhrase = findNoSlotsPhrase(text, noSlotsPhrases);
  const slots = scanDatesAndTimes ? scanSlotLines(text) : [];
  const timedSlots = slots.filter((s) => s.hasTime);

  if (mode === 'phrase') {
    return matchedPhrase
      ? { status: 'no_slots', reason: 'Matched "' + matchedPhrase + '".', matchedPhrase, slots: [] }
      : {
          status: 'slots_available',
          reason: 'The "no slots" message is gone.',
          matchedPhrase: null,
          slots,
        };
  }

  if (mode === 'selector') {
    const n = selectorCount || 0;
    return n > 0
      ? { status: 'slots_available', reason: n + ' element(s) matched slotSelector.', matchedPhrase, slots }
      : { status: 'no_slots', reason: 'No elements matched slotSelector.', matchedPhrase, slots: [] };
  }

  // mode: auto -- the "no slots" banner wins whenever it is present, because it
  // is the site's own explicit statement. Calendars often still render dates.
  if (matchedPhrase) {
    return {
      status: 'no_slots',
      reason: 'Matched "' + matchedPhrase + '".',
      matchedPhrase,
      slots: [],
    };
  }

  if (selectorCount && selectorCount > 0) {
    return {
      status: 'slots_available',
      reason:
        'The "no slots" message is gone and ' + selectorCount + ' element(s) matched slotSelector.',
      matchedPhrase: null,
      slots,
    };
  }

  if (timedSlots.length > 0) {
    return {
      status: 'slots_available',
      reason:
        'The "no slots" message is gone and ' +
        timedSlots.length +
        ' line(s) with a lesson time were found.',
      matchedPhrase: null,
      slots,
    };
  }

  return {
    status: 'page_changed',
    reason:
      'The "no slots" message is gone but no date/time was recognised. Worth a look -- check the snapshot.',
    matchedPhrase: null,
    slots,
  };
}

module.exports = {
  collapse,
  stripIgnored,
  fingerprint,
  findNoSlotsPhrase,
  scanSlotLines,
  decide,
};
