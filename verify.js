'use strict';
const CDP = require('chrome-remote-interface');

const expr = `(() => {
  const spans = Array.from(document.querySelectorAll('.tmt-localtime'));
  return {
    installed: !!(window.__slackTeammateTime && window.__slackTeammateTime.installed),
    labelCount: spans.length,
    samples: spans.slice(0, 8).map(s => ({ user: s.getAttribute('data-user-id'), text: s.textContent, title: s.title })),
    cacheKeys: window.__slackTeammateTime ? Object.keys(window.__slackTeammateTime.cache) : [],
  };
})()`;

(async () => {
  const targets = await CDP.List({ host: '127.0.0.1', port: 9229 });
  const t = targets.find(x => x.type === 'page' && x.url.includes('app.slack.com'));
  if (!t) { console.log('no slack target'); process.exit(1); }
  const client = await CDP({ host: '127.0.0.1', port: 9229, target: t.webSocketDebuggerUrl });
  const { Runtime } = client;
  await Runtime.enable();
  const r = await Runtime.evaluate({ expression: expr, returnByValue: true, awaitPromise: true });
  console.log(JSON.stringify(r.result.value, null, 2));
  await client.close();
  process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
