#!/usr/bin/env bash
#
# uninstall-agent.sh
# Removes the per-user LaunchAgent and the deployed runtime copy.
# Does NOT touch Slack itself.

set -uo pipefail

LABEL="com.user.slacktime"
DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_DIR="$HOME/Library/Application Support/SlackTeammateTime"

if [ -f "$DEST" ]; then
  launchctl unload "$DEST" >/dev/null 2>&1 || true
  rm -f "$DEST"
  echo "[uninstall] Removed LaunchAgent '${LABEL}'."
else
  echo "[uninstall] No LaunchAgent found at $DEST"
fi

if [ -d "$APP_DIR" ]; then
  rm -rf "$APP_DIR"
  echo "[uninstall] Removed deployed runtime at $APP_DIR"
fi

echo "[uninstall] To fully revert, just quit and reopen Slack normally"
echo "[uninstall] (the injected labels disappear on a clean relaunch)."
