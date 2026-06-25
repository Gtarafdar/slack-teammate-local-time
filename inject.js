/*
 * inject.js  (runs inside Slack's renderer)
 *
 * Adds each teammate's CURRENT local time inline next to their name in the
 * message list, e.g.:
 *
 *     Alex Rivera   8:52 PM   / 5:03 PM local time
 *
 * How it gets timezones:
 *   - Reads Slack's own in-page API token from localStorage.localConfig_v2.
 *   - Calls the same-origin Web API (/api/users.info) to fetch each user's
 *     IANA timezone (e.g. "Europe/Belgrade"), caching results in localStorage.
 *   - A small manual OVERRIDES map can force a timezone for any user id when
 *     the API can't resolve one.
 *
 * The displayed time is computed live with Intl.DateTimeFormat and refreshed
 * every minute, so it always reflects the teammate's *current* local time
 * (not the message's send time).
 *
 * This file is injected over the Chrome DevTools Protocol by injector.js and
 * never modifies Slack itself.
 */

(function () {
  'use strict';

  // Idempotency guard: re-injection (reloads, multiple Runtime.evaluate calls)
  // must not stack observers/intervals.
  if (window.__slackTeammateTime && window.__slackTeammateTime.installed) {
    window.__slackTeammateTime.refreshAll();
    return;
  }

  // ----------------------------------------------------------------------------
  // Config
  // ----------------------------------------------------------------------------
  const CONFIG = {
    // Manually force a timezone (IANA name) for a given Slack user id.
    // Example: OVERRIDES: { 'U09667NPTUN': 'Europe/Belgrade' }
    OVERRIDES: {},
    // Hide the label for your own messages (your local time == system time).
    HIDE_SELF: true,
    // How long a fetched timezone stays cached before re-checking (ms).
    CACHE_TTL_MS: 12 * 60 * 60 * 1000, // 12 hours
    // How often the displayed times tick over (ms).
    REFRESH_MS: 60 * 1000,
    // If a message was sent at least this long ago, also show the sender's
    // local time WHEN it was sent (in addition to their current local time).
    SENT_VS_NOW_THRESHOLD_MS: 60 * 1000, // 1 minute
    // localStorage key for the persistent timezone cache.
    CACHE_KEY: '__teammate_tz_cache_v1',
    // Text shown while a timezone is still being resolved (kept empty = nothing).
    LOADING_TEXT: '',
    LABEL_SUFFIX: ' local time',
  };

  const SELECTORS = {
    sender: '[data-qa="message_sender_name"]',
    timestamp: 'a.c-timestamp',
  };

  const LABEL_CLASS = 'tmt-localtime';

  // ----------------------------------------------------------------------------
  // Timezone cache (memory + localStorage)
  // ----------------------------------------------------------------------------
  const tzCache = loadCache(); // userId -> { tz, tz_offset, tz_label, ts, notFound? }
  const pending = new Map(); // userId -> Promise

  function loadCache() {
    try {
      const raw = localStorage.getItem(CONFIG.CACHE_KEY);
      return raw ? JSON.parse(raw) : {};
    } catch (_) {
      return {};
    }
  }

  let saveTimer = null;
  function saveCacheSoon() {
    if (saveTimer) return;
    saveTimer = setTimeout(() => {
      saveTimer = null;
      try {
        localStorage.setItem(CONFIG.CACHE_KEY, JSON.stringify(tzCache));
      } catch (_) {}
    }, 1000);
  }

  // ----------------------------------------------------------------------------
  // Auth: pull Slack's own API token from local config
  // ----------------------------------------------------------------------------
  function getAuth() {
    const m = location.pathname.match(/\/client\/(T[A-Z0-9]+)/);
    const teamId = m ? m[1] : null;
    if (!teamId) return null;
    let lc;
    try {
      lc = JSON.parse(localStorage.localConfig_v2 || '{}');
    } catch (_) {
      return null;
    }
    const team = lc.teams && lc.teams[teamId];
    if (!team || !team.token) return null;
    return { teamId, token: team.token, selfId: team.user_id };
  }

  // ----------------------------------------------------------------------------
  // Timezone resolution
  // ----------------------------------------------------------------------------
  function isFresh(entry) {
    return entry && !entry.notFound && entry.tz && Date.now() - (entry.ts || 0) < CONFIG.CACHE_TTL_MS;
  }

  function resolveTz(userId) {
    // Manual override always wins.
    if (CONFIG.OVERRIDES[userId]) {
      return Promise.resolve({ tz: CONFIG.OVERRIDES[userId], tz_label: CONFIG.OVERRIDES[userId] });
    }
    const cached = tzCache[userId];
    if (isFresh(cached)) return Promise.resolve(cached);
    // Negative cache: don't hammer the API for ids that don't resolve
    // (bots/apps). Re-check only after the TTL.
    if (cached && cached.notFound && Date.now() - (cached.ts || 0) < CONFIG.CACHE_TTL_MS) {
      return Promise.resolve(null);
    }
    if (pending.has(userId)) return pending.get(userId);

    const p = fetchTz(userId)
      .then((info) => {
        if (info && info.tz) {
          tzCache[userId] = { ...info, ts: Date.now() };
        } else {
          tzCache[userId] = { notFound: true, ts: Date.now() };
        }
        saveCacheSoon();
        pending.delete(userId);
        return info && info.tz ? tzCache[userId] : null;
      })
      .catch(() => {
        pending.delete(userId);
        return null;
      });
    pending.set(userId, p);
    return p;
  }

  async function fetchTz(userId) {
    const auth = getAuth();
    if (!auth) return null;
    const body = new URLSearchParams();
    body.set('token', auth.token);
    body.set('user', userId);
    const resp = await fetch(location.origin + '/api/users.info', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      credentials: 'include',
      body: body.toString(),
    });
    const data = await resp.json();
    if (!data || !data.ok || !data.user) return null;
    const u = data.user;
    return { tz: u.tz || null, tz_offset: u.tz_offset, tz_label: u.tz_label || u.tz || null };
  }

  // ----------------------------------------------------------------------------
  // Time formatting
  // ----------------------------------------------------------------------------
  function normalizeMeridiem(s) {
    // Match Slack's style: uppercase AM/PM (e.g. "5:14 PM").
    return s.replace(/\s*(am|pm)\b/i, (_, p) => ' ' + p.toUpperCase());
  }

  // Format the given instant (ms since epoch) in the user's timezone.
  // `when` defaults to "now".
  function formatTimeAt(info, when) {
    if (!info) return '';
    const at = typeof when === 'number' ? new Date(when) : new Date();
    // Prefer IANA tz (DST-correct). Fall back to fixed offset.
    if (info.tz) {
      try {
        return normalizeMeridiem(
          new Intl.DateTimeFormat(undefined, {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true,
            timeZone: info.tz,
          }).format(at)
        );
      } catch (_) {
        /* fall through to offset */
      }
    }
    if (typeof info.tz_offset === 'number') {
      const utcMs = at.getTime() + at.getTimezoneOffset() * 60000;
      const d = new Date(utcMs + info.tz_offset * 1000);
      return normalizeMeridiem(
        d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit', hour12: true })
      );
    }
    return '';
  }

  // ----------------------------------------------------------------------------
  // DOM rendering
  // ----------------------------------------------------------------------------
  function ensureStyle() {
    if (document.getElementById('tmt-style')) return;
    const style = document.createElement('style');
    style.id = 'tmt-style';
    style.textContent =
      '.' + LABEL_CLASS + '{' +
      'margin-left:6px;' +
      'font-size:12px;' +
      'font-weight:400;' +
      'opacity:0.62;' +
      'white-space:nowrap;' +
      'cursor:default;' +
      '}';
    document.head && document.head.appendChild(style);
  }

  function setLabel(span, info) {
    const nowStr = formatTimeAt(info);
    if (!nowStr) {
      span.textContent = CONFIG.LOADING_TEXT;
      return;
    }

    // The message send time is stored on the span (epoch seconds, from Slack's
    // timestamp element). For older messages, show the sender's local time WHEN
    // the message was sent, plus their current local time.
    const tsAttr = span.getAttribute('data-ts');
    const sentMs = tsAttr ? Math.round(parseFloat(tsAttr) * 1000) : NaN;
    const haveSent = Number.isFinite(sentMs);

    if (haveSent && Math.abs(Date.now() - sentMs) >= CONFIG.SENT_VS_NOW_THRESHOLD_MS) {
      const sentStr = formatTimeAt(info, sentMs);
      span.textContent = '/ ' + sentStr + CONFIG.LABEL_SUFFIX + ' (now ' + nowStr + ')';
    } else {
      span.textContent = '/ ' + nowStr + CONFIG.LABEL_SUFFIX;
    }

    if (info.tz_label) {
      span.title = haveSent
        ? info.tz_label + ' — sent ' + formatTimeAt(info, sentMs) + ', now ' + nowStr
        : info.tz_label;
    }
  }

  function decorate(senderBtn) {
    if (senderBtn.getAttribute('data-tmt-done') === '1') return;
    const userId = senderBtn.getAttribute('data-message-sender');
    if (!userId) return;
    senderBtn.setAttribute('data-tmt-done', '1');

    const auth = getAuth();
    if (CONFIG.HIDE_SELF && auth && auth.selfId && userId === auth.selfId) return;

    // The message header (sender name + timestamp) lives in [data-qa="message_content"].
    const content = senderBtn.closest('[data-qa="message_content"]');
    const container = content || senderBtn.parentElement;
    if (!container) return;
    if (container.querySelector('.' + LABEL_CLASS)) return;

    const span = document.createElement('span');
    span.className = LABEL_CLASS;
    span.setAttribute('data-user-id', userId);
    span.textContent = CONFIG.LOADING_TEXT;

    // Prefer inserting right after the header timestamp so the order reads
    // "Name  8:52 PM  / 5:03 PM local time".
    const ts = content
      ? content.querySelector(':scope > a.c-timestamp, :scope > .c-timestamp')
      : null;
    if (ts) {
      // Record the message's send time (epoch seconds) so we can show the
      // sender's local time at the moment they sent it.
      const tsVal = ts.getAttribute('data-ts');
      if (tsVal) span.setAttribute('data-ts', tsVal);
      ts.insertAdjacentElement('afterend', span);
    } else {
      // Fallback: after the sender name wrapper.
      const senderWrap = senderBtn.closest('[data-qa="message_sender"]') || senderBtn;
      senderWrap.insertAdjacentElement('afterend', span);
    }

    resolveTz(userId).then((info) => {
      if (info) setLabel(span, info);
      else span.remove(); // unknown (bot/app) -> no clutter
    });
  }

  function scan(root) {
    const scope = root && root.querySelectorAll ? root : document;
    const buttons = scope.querySelectorAll(SELECTORS.sender + ':not([data-tmt-done])');
    buttons.forEach(decorate);
  }

  function refreshAll() {
    const spans = document.querySelectorAll('.' + LABEL_CLASS);
    spans.forEach((span) => {
      const userId = span.getAttribute('data-user-id');
      if (!userId) return;
      const info = CONFIG.OVERRIDES[userId]
        ? { tz: CONFIG.OVERRIDES[userId], tz_label: CONFIG.OVERRIDES[userId] }
        : tzCache[userId];
      if (info && info.tz) setLabel(span, info);
    });
  }

  // ----------------------------------------------------------------------------
  // Bootstrap
  // ----------------------------------------------------------------------------
  let observer = null;
  let refreshInterval = null;

  function start() {
    ensureStyle();
    scan(document);

    observer = new MutationObserver((mutations) => {
      for (const mut of mutations) {
        for (const node of mut.addedNodes) {
          if (node.nodeType !== 1) continue;
          if (node.matches && node.matches(SELECTORS.sender)) {
            decorate(node);
          } else {
            scan(node);
          }
        }
      }
    });
    observer.observe(document.body, { childList: true, subtree: true });

    refreshInterval = setInterval(refreshAll, CONFIG.REFRESH_MS);

    window.__slackTeammateTime = {
      installed: true,
      version: 1,
      config: CONFIG,
      cache: tzCache,
      refreshAll,
      rescan: () => scan(document),
      // Clear the persistent cache (e.g. after someone changes timezone).
      clearCache: () => {
        for (const k of Object.keys(tzCache)) delete tzCache[k];
        try { localStorage.removeItem(CONFIG.CACHE_KEY); } catch (_) {}
      },
    };

    console.log('[slack-teammate-time] installed.');
  }

  function waitForBody() {
    if (document.body) {
      start();
    } else {
      const t = setInterval(() => {
        if (document.body) {
          clearInterval(t);
          start();
        }
      }, 200);
    }
  }

  waitForBody();
})();
