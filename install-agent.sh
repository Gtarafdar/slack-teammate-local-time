#!/usr/bin/env bash
#
# install-agent.sh
# Installs the per-user LaunchAgent so the teammate-time injector starts
# automatically at login. No admin / sudo required.
#
# IMPORTANT: macOS privacy protection (TCC) blocks launchd agents from running
# code inside ~/Downloads, ~/Desktop and ~/Documents. So this script deploys a
# copy of the runtime to a non-protected location:
#
#     ~/Library/Application Support/SlackTeammateTime
#
# and points the LaunchAgent there. The original project folder stays put and
# still works for manual runs (`node injector.js`).

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HOME/Library/Application Support/SlackTeammateTime"
LABEL="com.user.slacktime"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"

echo "[install] Deploying runtime to: $APP_DIR"
mkdir -p "$APP_DIR"

# Copy the files the agent needs to run.
for f in injector.js inject.js launch-slack.sh run.sh package.json package-lock.json; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" "$APP_DIR/"
done
chmod +x "$APP_DIR/launch-slack.sh" "$APP_DIR/run.sh" "$APP_DIR/injector.js" 2>/dev/null || true

# Dependencies: reuse the already-installed node_modules if present, else install.
# Prefer `npm ci` (verifies the lockfile's integrity hashes) when a lockfile exists.
if [ -d "$SRC/node_modules/chrome-remote-interface" ]; then
  echo "[install] Copying node_modules..."
  rm -rf "$APP_DIR/node_modules"
  cp -R "$SRC/node_modules" "$APP_DIR/node_modules"
elif [ -f "$APP_DIR/package-lock.json" ]; then
  echo "[install] Installing dependencies in $APP_DIR (npm ci)..."
  ( cd "$APP_DIR" && npm ci --omit=dev )
else
  echo "[install] Installing dependencies in $APP_DIR (npm install)..."
  ( cd "$APP_DIR" && npm install --omit=dev )
fi

# Restrict the deployed runtime to the current user only (defense in depth:
# inject.js is executed verbatim inside your Slack session, so prevent other
# local users from reading or tampering with it).
chmod -R go-rwx "$APP_DIR" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
echo "[install] Writing $DEST"

# Render the plist from the template with a safe, XML-escaped substitution
# (avoids sed delimiter issues and any XML injection if the path is unusual).
xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}
APP_DIR_XML="$(xml_escape "$APP_DIR")"
TEMPLATE="$(cat "$SRC/com.user.slacktime.plist")"
printf '%s\n' "${TEMPLATE//__PROJECT_DIR__/$APP_DIR_XML}" > "$DEST"

# (Re)load.
launchctl unload "$DEST" >/dev/null 2>&1 || true
launchctl load "$DEST"

echo "[install] Loaded LaunchAgent '${LABEL}'."
echo "[install] It will start at every login and keep the injector running."
echo "[install] Logs: $APP_DIR/agent.out.log and $APP_DIR/agent.err.log"
echo
echo "It also started just now. Return to Slack and you should see teammates'"
echo "local times next to their names within a few seconds."
echo
echo "NOTE: the agent runs the COPY in '$APP_DIR'. If you edit inject.js in the"
echo "project folder later, re-run ./install-agent.sh to redeploy."
