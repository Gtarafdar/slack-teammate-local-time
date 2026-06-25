#!/usr/bin/env node
/*
 * injector.js
 *
 * Connects to the native macOS Slack desktop app over the Chrome DevTools
 * Protocol (CDP) and injects inject.js into Slack's renderer so that each
 * teammate's current local time is shown inline next to their name/timestamp.
 *
 * It does NOT modify Slack itself. Slack must have been launched with the
 * remote debugging port enabled (see launch-slack.sh).
 *
 * The daemon:
 *   - Polls the CDP target list and attaches to every Slack client page.
 *   - Injects inject.js into the current document and into every future
 *     document (via Page.addScriptToEvaluateOnNewDocument), so it survives
 *     in-app reloads and navigation.
 *   - Auto-reconnects if Slack restarts or the debug port disappears.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const CDP = require('chrome-remote-interface');

const PORT = parseInt(process.env.SLACK_DEBUG_PORT || '9229', 10);
const HOST = '127.0.0.1';
const POLL_MS = 3000;
const INJECT_PATH = path.join(__dirname, 'inject.js');
// On/off state written by the menu bar app: { "enabled": true|false }.
const STATE_PATH = path.join(__dirname, 'state.json');

// targetId -> { client, injecting }
const attached = new Map();

// Current on/off state (kept in sync with state.json).
let currentEnabled = readEnabled();

function log(...args) {
  const ts = new Date().toLocaleTimeString();
  console.log(`[injector ${ts}]`, ...args);
}

// Read the on/off state from state.json. Defaults to ON when the file is
// missing or unreadable (e.g. the developer/Terminal flow without the app).
function readEnabled() {
  try {
    const raw = fs.readFileSync(STATE_PATH, 'utf8');
    const obj = JSON.parse(raw);
    return obj.enabled !== false;
  } catch (_) {
    return true;
  }
}

function readInjectSource() {
  // Re-read on every injection so edits to inject.js take effect on reload
  // without restarting the daemon.
  return fs.readFileSync(INJECT_PATH, 'utf8');
}

// Prefix the page script with the current on/off flag so a fresh document
// renders in the right state immediately.
function buildSource(enabled) {
  return 'window.__SLACKTIME_ENABLED__ = ' + (enabled !== false) + ';\n' + readInjectSource();
}

// Push an on/off change to every attached Slack page, live (no reload).
async function applyEnabledToAll(enabled) {
  const expr =
    'window.__SLACKTIME_ENABLED__ = ' + (enabled !== false) + ';' +
    'window.__slackTeammateTime && window.__slackTeammateTime.setEnabled(' + (enabled !== false) + ');';
  for (const { client } of attached.values()) {
    if (!client) continue;
    try {
      await client.Runtime.evaluate({ expression: expr, returnByValue: true });
    } catch (_) {
      /* page tearing down; ignore */
    }
  }
}

// Watch state.json for menu bar toggles and apply them live.
function watchEnabled() {
  fs.watchFile(STATE_PATH, { interval: 1000 }, () => {
    const next = readEnabled();
    if (next === currentEnabled) return;
    currentEnabled = next;
    log('Toggle ->', next ? 'ON' : 'OFF');
    applyEnabledToAll(next).catch(() => {});
  });
}

function isSlackClientTarget(t) {
  return (
    t.type === 'page' &&
    typeof t.url === 'string' &&
    t.url.includes('app.slack.com')
  );
}

async function injectInto(client) {
  const { Page, Runtime } = client;
  await Page.enable();
  await Runtime.enable();

  // Persist across future reloads / navigations (uses the state at attach time;
  // loadEventFired below re-applies the current state on every reload).
  await Page.addScriptToEvaluateOnNewDocument({ source: buildSource(currentEnabled) });

  // Run once in the document that is already loaded.
  const result = await Runtime.evaluate({
    expression: buildSource(currentEnabled),
    awaitPromise: false,
    returnByValue: true,
  });
  if (result && result.exceptionDetails) {
    log('inject.js threw:', result.exceptionDetails.text || result.exceptionDetails);
  }

  // Re-run after each full navigation as a belt-and-suspenders measure
  // (addScriptToEvaluateOnNewDocument should already cover this).
  Page.loadEventFired(async () => {
    try {
      await Runtime.evaluate({ expression: buildSource(currentEnabled), returnByValue: true });
      log('Re-injected after page load.');
    } catch (err) {
      // Page/connection may be tearing down; ignore.
    }
  });
}

async function attachToTarget(target) {
  if (attached.has(target.id)) return;
  attached.set(target.id, { client: null, injecting: true });

  let client;
  try {
    client = await CDP({ host: HOST, port: PORT, target: target.webSocketDebuggerUrl || target.id });
    attached.set(target.id, { client, injecting: false });

    client.on('disconnect', () => {
      log(`Detached from target: ${truncate(target.title)}`);
      attached.delete(target.id);
    });

    await injectInto(client);
    log(`Injected into: ${truncate(target.title)}`);
  } catch (err) {
    log(`Failed to attach/inject (${truncate(target.title)}):`, err.message);
    if (client) {
      try { await client.close(); } catch (_) {}
    }
    attached.delete(target.id);
  }
}

function truncate(s, n = 48) {
  s = s || '(untitled)';
  return s.length > n ? s.slice(0, n) + '\u2026' : s;
}

async function tick() {
  let targets;
  try {
    targets = await CDP.List({ host: HOST, port: PORT });
  } catch (err) {
    // Debug port not up (Slack closed or not launched with the flag).
    return;
  }

  const slackTargets = targets.filter(isSlackClientTarget);
  for (const t of slackTargets) {
    if (!attached.has(t.id)) {
      await attachToTarget(t);
    }
  }
}

async function main() {
  if (!fs.existsSync(INJECT_PATH)) {
    console.error(`Cannot find inject.js at ${INJECT_PATH}`);
    process.exit(1);
  }

  log(`Watching for Slack client targets on ${HOST}:${PORT} ...`);
  log('If nothing attaches, run ./launch-slack.sh first.');
  log('Initial state:', currentEnabled ? 'ON' : 'OFF');

  // React to menu bar on/off toggles.
  watchEnabled();

  // Initial pass + steady polling.
  await tick();
  const interval = setInterval(() => {
    tick().catch((err) => log('tick error:', err.message));
  }, POLL_MS);

  const shutdown = async () => {
    clearInterval(interval);
    log('Shutting down, detaching from all targets...');
    for (const { client } of attached.values()) {
      if (client) {
        try { await client.close(); } catch (_) {}
      }
    }
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
