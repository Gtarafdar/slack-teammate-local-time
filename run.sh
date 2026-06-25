#!/usr/bin/env bash
#
# run.sh
# Entry point used both for manual runs and by the LaunchAgent.
# - Ensures Slack is running with the remote-debugging port (relaunches it
#   only if the port is not already reachable, so it won't disrupt a healthy
#   session on restarts).
# - Then runs the injector daemon in the foreground (so launchd can supervise).

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

PORT="${SLACK_DEBUG_PORT:-9229}"

# Make sure node is findable when launched from launchd (minimal PATH).
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
if [ -s "$HOME/.nvm/nvm.sh" ] && ! command -v node >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true
fi

if ! command -v node >/dev/null 2>&1; then
  echo "[run] ERROR: node not found on PATH." >&2
  exit 1
fi

# Relaunch Slack with the debug flag only if the port isn't already up.
if ! curl -s "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
  echo "[run] Debug port ${PORT} not reachable; (re)launching Slack with it..."
  "$DIR/launch-slack.sh" || true
else
  echo "[run] Debug port ${PORT} already reachable; leaving Slack as-is."
fi

echo "[run] Starting injector..."
exec node "$DIR/injector.js"
