# Slack inline teammate local time (native macOS desktop)

Show each teammate's **current local time** right next to their name in the
native macOS Slack desktop app, e.g.:

```
Alex Rivera     9:02 PM   / 6:18 PM local time
Priya Sharma    8:15 AM   / 11:45 AM local time (now 9:48 PM)
```

Slack only shows a person's local time on their profile. This puts it inline in
the conversation so you never have to open a profile to know "is it a good time
to ping them?".

- **Recent message:** shows the sender's **current** local time
  (e.g. `6:18 PM local time`).
- **Older message:** also shows the sender's local time **when they sent it**,
  plus their current time
  (e.g. `11:45 AM local time (now 9:48 PM)`). Slack's own timestamp is still
  your time, so you get all three at a glance: your time / their time when sent /
  their time now.

- **No admin approval** and **no Slack Marketplace app** required.
- **Slack itself is never modified** (survives Slack auto-updates).
- Works on any workspace; nothing to configure per teammate.

> Note: this is an unofficial, local enhancement. It reads timezone info that
> Slack already exposes on profiles. Modifying client behavior is technically
> outside Slack's ToS — use at your own discretion.

## Requirements

- A **Mac** (works on both **Apple Silicon** *and* **Intel**) running the
  **native Slack desktop app** (the browser version is not covered).
- For the one-click app (Option A): **nothing else** — the right Node.js for your
  CPU is bundled inside the app. For Options B/C you need **Node.js** 18+
  (`node -v`).

## Install

### Option A — One-click Mac app (recommended, no Terminal, no code)

Best for everyone. The app is **universal** (Intel + Apple Silicon) and bundles
its own Node.js, so there's nothing to install first.

1. Download **`SlackTeammateTime.dmg`** from the
   [latest release](https://github.com/Gtarafdar/slack-teammate-local-time/releases/latest).
2. Open the `.dmg` and **double-click the `SlackTeammateTime` app**.
   - First launch only: macOS Gatekeeper will say it "can't be opened because
     Apple cannot check it for malware" (the app is free and unsigned).
     **Right-click the app → Open → Open.** You only do this once.
3. Click **OK** in the install dialog.

That's it — a **clock icon appears in your menu bar**, Slack shows teammate times,
and it starts automatically at every login.

#### Turning it on/off (menu bar)

Click the **clock icon in the menu bar** for a small menu:

- **Show teammate times** — toggle the inline times **on or off instantly**.
  Slack updates live (no reload, no restart) — labels appear or disappear right
  away.
- **Uninstall…** — completely removes the helper and its login item (Slack itself
  is never touched).
- **Quit** — closes the menu bar app for this session (it returns at next login).

> Why the Gatekeeper prompt? Distributing a Mac app that opens with a plain
> double-click requires a paid Apple Developer signature. This app is free and
> unsigned, so macOS asks you to confirm the first time via right-click → Open.

### Option B — Double-click installer from source (needs Node.js)

1. Download the project ZIP from GitHub (**Code -> Download ZIP**) and unzip it,
   or `git clone` (Option C).
2. Double-click **`Install.command`**.
   - First launch, macOS Gatekeeper may block it. **Right-click -> Open**, then
     confirm. (Or run once: `xattr -dr com.apple.quarantine <the-folder>`.)
3. The installer checks for Node.js (offers to install it via Homebrew if
   missing), installs the one dependency, and sets up login auto-start. To
   remove: double-click **`Uninstall.command`**.

### Option C — Developer (Terminal)

```bash
git clone https://github.com/Gtarafdar/slack-teammate-local-time.git
cd slack-teammate-local-time
npm install
./install-agent.sh        # set up login auto-start (recommended)
```

Or run it once without auto-start:

```bash
npm run go                # = ./launch-slack.sh && node injector.js
```

Return to Slack — within a few seconds teammates' local times appear next to
their names. Leave `node injector.js` running (it re-injects after reloads).

## How to use it (after install)

There's nothing to do day-to-day:

- It starts automatically at login.
- It launches Slack with the required debug port if needed.
- Times refresh every minute and resolve new teammates automatically.

If you ever open Slack manually and don't see times, run `./launch-slack.sh`
(Slack needs to be started with the debug port).

## What gets installed (auto-start)

`./install-agent.sh` (and `Install.command`) install a **per-user** LaunchAgent
at `~/Library/LaunchAgents/com.user.slacktime.plist` that starts at login,
launches Slack with the debug port if needed, and keeps the injector running.

Because macOS privacy protection (TCC) blocks login agents from running code in
`~/Downloads`, `~/Desktop` and `~/Documents`, the installer deploys a **copy** of
the runtime to a non-protected location and points the agent there:

```
~/Library/Application Support/SlackTeammateTime
```

Logs live there too: `agent.out.log` and `agent.err.log`. If you edit
`inject.js` in your project folder, re-run `./install-agent.sh` to redeploy.

Remove everything with `./uninstall-agent.sh` (or `Uninstall.command`).

## How it works

```
menu bar app ──> writes state.json {"enabled": true|false}
launch-slack.sh ──> Slack (Electron) with --remote-debugging-port=9229
injector.js (node) ──CDP──> injects inject.js into Slack's page
               └─> watches state.json ──> toggles labels live (no reload)
inject.js ──> reads in-page Slack token ──> /api/users.info ──> teammate tz
          └─> MutationObserver adds the sender's local time next to each name
              (current time, plus their time-when-sent for older messages)
              and refreshes every minute
```

- **Menu bar toggle.** The bundled menu bar app (universal Intel + Apple Silicon)
  just writes an on/off flag to `state.json`. The injector watches that file and
  calls into the page to add or remove the labels **instantly**, so toggling is
  live — no Slack reload or restart.

- **Timezones** are pulled automatically from Slack's own Web API
  (`users.info`) using the token already present in the page, then cached in
  `localStorage` for 12 hours. Nothing to configure per person.
- **Your own messages** are not labeled (your local time = your system time).
- **Bots/apps** are skipped automatically.

### Why CDP injection (not patching `app.asar`)

The common "patch Slack's `app.asar`" trick breaks on the Mac App Store build
(sandboxed, code-signed) and is wiped on every update. Attaching over the Chrome
DevTools Protocol touches nothing inside the app, so it keeps working across
updates and needs no admin rights.

## Files

| File | Purpose |
| --- | --- |
| `Install.command` / `Uninstall.command` | Double-click install / uninstall. |
| `launch-slack.sh` | Relaunches Slack with the debug + allow-origins flags. |
| `injector.js` | Node daemon: attaches to Slack via CDP and injects the script; re-injects on reload. |
| `inject.js` | The in-page script (timezone lookup + inline labels + minute refresh). |
| `run.sh` | Ensures Slack is up with the port, then runs the injector (used by the LaunchAgent). |
| `com.user.slacktime.plist` | LaunchAgent template for auto-start at login. |
| `install-agent.sh` / `uninstall-agent.sh` | Install / remove the login auto-start. |
| `package-for-sharing.sh` | Builds a clean shareable zip in `dist/`. |
| `build-mac-app.sh` | Builds the universal one-click `SlackTeammateTime.app` + `.dmg`. |
| `app/SlackTeammateTime.swift` | The menu bar app (toggle, install/uninstall, login item). |
| `app/setup.sh` | Silent, arch-aware engine deploy/uninstall used by the app. |
| `app/Info.plist`, `app/AppIcon.icns` | App bundle metadata and icon. |
| `verify.js` | Diagnostic: prints the labels currently rendered in Slack. |

### Building the one-click app (maintainers)

```bash
./build-mac-app.sh   # downloads Node (arm64 + x64), compiles a universal app, builds the .dmg
```

Outputs `dist/SlackTeammateTime.app` and `dist/SlackTeammateTime.dmg`. The app is
self-contained (bundled Node for both CPUs + dependencies), is a **universal
binary** (Intel + Apple Silicon), and is **ad-hoc signed but not notarized** —
users approve it once via right-click → Open. Publish the `.dmg` as a GitHub
Release asset so teammates download a single file. On first launch the app copies
itself to `~/Applications`, deploys the engine, and registers a login item.

## Verifying / troubleshooting

Check what's rendered live:

```bash
node verify.js
```

- **No labels appear:** make sure Slack was launched via `./launch-slack.sh`
  (a normally-opened Slack has no debug port). Confirm with:
  `curl -s http://127.0.0.1:9229/json/version`.
- **A teammate shows no time:** they may have no timezone set in Slack, or be a
  bot/app. You can force a timezone — see "Manual overrides".
- **Times look stale:** they refresh every 60s; reopening the conversation also
  refreshes immediately.

## Manual overrides

If the API can't resolve someone, edit `inject.js` and add their Slack user id
(the `data-message-sender` value) to `OVERRIDES` with an IANA timezone:

```js
OVERRIDES: {
  'U09667NPTUN': 'Europe/Belgrade',
},
```

The daemon re-reads `inject.js` on each (re)injection, so reload Slack (Cmd+R)
or restart `injector.js` to apply. If you use auto-start, re-run
`./install-agent.sh` to redeploy the edited file.

## Sharing with teammates

Nothing personal is stored in these files — each person's copy reads *their own*
Slack session token at runtime — so the same files work for anyone on any
workspace. Either point them at this repo (Option A/B above) or build a zip:

```bash
./package-for-sharing.sh   # creates dist/SlackTeammateTime.zip
```

## Security

This project was security-reviewed. Summary of how the check was run, what was
found, and what was hardened.

### How we ran the security check

1. **Dependency scan** — `npm audit` (result: **0 vulnerabilities**). The only
   runtime dependency is `chrome-remote-interface` (→ `commander`, `ws`).
   Re-run any time with:
   ```bash
   npm audit
   npm ls --all
   ```
2. **Manual code review** of every file, focused on: the CDP debug-port attack
   surface, Slack token handling, the same-origin API call, DOM/XSS safety in
   the injected script, the shell scripts / LaunchAgents (command injection,
   PATH, quoting, privileges, file permissions), and the menu bar app
   (`SlackTeammateTime.swift`) + its on/off state file.
3. **Static checks** — `bash -n` syntax validation on every script,
   `node --check` on the JS, `plutil -lint` on the generated plists, and
   `codesign --verify` on the built app.

### What was hardened

- **Integrity-checked installs:** installers now prefer `npm ci` (verifies the
  lockfile's integrity hashes) over `npm install` when a lockfile is present.
- **Safe plist generation:** the LaunchAgent is rendered with an XML-escaped
  substitution instead of `sed`, avoiding delimiter/XML-injection edge cases for
  unusual home paths.
- **Locked-down runtime:** the deployed copy in
  `~/Library/Application Support/SlackTeammateTime` is set to `700` (user-only),
  since `inject.js` is executed verbatim inside your Slack session.
- **Toggle carries no code.** The menu bar on/off control only writes a plain
  boolean to `state.json` (`{"enabled": true|false}`); the injector reads just
  that boolean — it never evaluates anything from the file — so the toggle path
  can't be used to inject code.
- **Universal app, ad-hoc signed.** The shipped app is code-signed (ad-hoc) and
  built from the source in `app/`. It is not notarized (no paid Apple account),
  hence the one-time right-click → Open.

### Built-in protections (already in place)

- **Token never leaves Slack's origin.** `inject.js` reads Slack's own in-page
  token and only POSTs it to the **same-origin** `/api/users.info`. It is never
  sent anywhere else, never logged, and never written to disk.
- **No XSS.** All injected text uses `textContent` / element properties (never
  `innerHTML`), so API/profile data cannot execute as markup.
- **Debug port is localhost-only.** Chromium binds `--remote-debugging-port` to
  `127.0.0.1` by default (not the network), and we set
  `--remote-allow-origins=http://127.0.0.1:<port>` (a specific origin, **not**
  `*`). Combined with Chromium's `Host`-header validation, this blocks remote
  websites and DNS-rebinding from connecting.
- **No elevated privileges.** Everything runs as your user — no `sudo`, no
  setuid, and Slack itself is never modified.

### Residual risk you should know about (by design)

Enabling the Chrome DevTools Protocol port gives **full control of your Slack
session to anything that can connect to it**. We restrict it to localhost + a
single allowed origin, which stops remote/web attackers — but **another program
already running on your Mac as your user** could connect to `127.0.0.1:9229` and
read/act in Slack. This is inherent to any CDP-based approach. If that risk is
unacceptable for your threat model, don't run this (or only run it on demand and
stop it when finished via `./uninstall-agent.sh`). A local attacker with code
execution as your user can generally already access your data regardless.

> Reminder: this is an unofficial, local enhancement and is technically outside
> Slack's ToS. It only reads timezone info Slack already shows on profiles.

## Notes / caveats

- Slack's DOM class names are obfuscated and can change; selectors live at the
  top of `inject.js` (`SELECTORS`) and are easy to adjust if a future update
  moves things around.
- The debug port is bound to `127.0.0.1` only (localhost), and CDP connections
  are restricted via `--remote-allow-origins`.
- Tested on Slack 4.50.x (Electron 42) on macOS. Other versions should work but
  may need selector tweaks.
