#!/usr/bin/env bash
#
# launch-slack.sh
# Relaunch the native macOS Slack desktop app with the Chrome DevTools Protocol
# remote-debugging port enabled, so injector.js can attach and add inline
# teammate local times. Does NOT modify Slack itself.
#
# Recent Chromium (Slack uses Electron 42 / Chromium 148) requires the
# --remote-allow-origins flag in addition to --remote-debugging-port before it
# will accept CDP websocket connections.

set -euo pipefail

PORT="${SLACK_DEBUG_PORT:-9229}"
ALLOW_ORIGIN="http://127.0.0.1:${PORT}"

echo "[launch-slack] Quitting any running Slack instance..."
osascript -e 'quit app "Slack"' >/dev/null 2>&1 || true

# Wait for Slack to fully exit so the relaunch picks up the new flags.
for _ in $(seq 1 20); do
  if ! pgrep -x Slack >/dev/null 2>&1; then
    break
  fi
  sleep 0.5
done

# Force-kill if it is still hanging around.
if pgrep -x Slack >/dev/null 2>&1; then
  echo "[launch-slack] Slack still running, forcing quit..."
  pkill -x Slack >/dev/null 2>&1 || true
  sleep 1
fi

echo "[launch-slack] Launching Slack with remote debugging on port ${PORT}..."
open -a Slack --args \
  --remote-debugging-port="${PORT}" \
  --remote-allow-origins="${ALLOW_ORIGIN}"

# Wait until the CDP endpoint responds (Slack can take several seconds to boot).
echo "[launch-slack] Waiting for the debug port to come up..."
for _ in $(seq 1 30); do
  if curl -s "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
    echo "[launch-slack] Slack is up and the debug port (${PORT}) is reachable."
    exit 0
  fi
  sleep 0.5
done

echo "[launch-slack] WARNING: debug port ${PORT} did not respond in time." >&2
echo "[launch-slack] Slack may still be starting; try running 'node injector.js' shortly." >&2
exit 1
