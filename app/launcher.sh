#!/bin/bash
#
# launcher.sh -> becomes SlackTeammateTime.app/Contents/MacOS/SlackTeammateTime
#
# This is what runs when a user double-clicks the app icon. It is a friendly,
# dialog-driven installer (no Terminal): it deploys the bundled runtime
# (including a bundled Node.js, so no prerequisites) and sets up the login
# auto-start agent. Re-running offers Update or Uninstall.

set -uo pipefail

# --- locate bundled resources -------------------------------------------------
HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$(cd "$HERE/../Resources" && pwd)"
RUNTIME="$RES/runtime"

APP_DIR="$HOME/Library/Application Support/SlackTeammateTime"
LABEL="com.user.slacktime"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG="$APP_DIR/install.log"

TITLE="Slack Teammate Time"

# SLACKTIME_SILENT=1 turns the GUI dialogs into plain stdout/stderr and always
# proceeds with a (re)install. Used for automated end-to-end testing only.
SILENT="${SLACKTIME_SILENT:-0}"

# --- helpers ------------------------------------------------------------------
dialog() { # message
  local msg="$1"
  if [ "$SILENT" = "1" ]; then printf 'INFO: %s\n' "$msg"; return 0; fi
  /usr/bin/osascript -e "display dialog \"$msg\" with title \"$TITLE\" buttons {\"OK\"} default button \"OK\" with icon note" >/dev/null 2>&1
}

errexit() {
  if [ "$SILENT" = "1" ]; then printf 'ERROR: %s\n' "$1" >&2; exit 1; fi
  /usr/bin/osascript -e "display dialog \"$1\" with title \"$TITLE\" buttons {\"OK\"} default button \"OK\" with icon stop" >/dev/null 2>&1
  exit 1
}

log() { mkdir -p "$APP_DIR" 2>/dev/null; echo "[$(date '+%H:%M:%S')] $*" >> "$LOG" 2>/dev/null; }

# --- preflight: Slack present? ------------------------------------------------
if [ ! -d "/Applications/Slack.app" ] && ! /usr/bin/mdfind "kMDItemCFBundleIdentifier == 'com.tinyspeck.slackmacgap'" 2>/dev/null | grep -q Slack; then
  errexit "The Slack desktop app was not found.\n\nPlease install Slack for Mac first, then open this app again."
fi

# --- already installed? offer Update / Uninstall ------------------------------
if [ -f "$PLIST" ] && [ "$SILENT" != "1" ]; then
  CHOICE="$(/usr/bin/osascript -e "button returned of (display dialog \"Slack Teammate Time is already installed.\n\nWhat would you like to do?\" with title \"$TITLE\" buttons {\"Cancel\", \"Uninstall\", \"Update\"} default button \"Update\" with icon note)" 2>/dev/null)"
  case "$CHOICE" in
    Uninstall)
      launchctl unload "$PLIST" >/dev/null 2>&1 || true
      rm -f "$PLIST"
      rm -rf "$APP_DIR"
      dialog "Removed. Quit and reopen Slack to clear the inline times."
      exit 0
      ;;
    Update) : ;;  # fall through to (re)install
    *) exit 0 ;;
  esac
fi

# --- install ------------------------------------------------------------------
log "Installing from $RUNTIME"
mkdir -p "$APP_DIR" || errexit "Could not create the application support folder."

# Copy runtime files (scripts, JS, deps, bundled node).
for f in injector.js inject.js launch-slack.sh run.sh package.json package-lock.json node; do
  if [ -e "$RUNTIME/$f" ]; then
    cp -R "$RUNTIME/$f" "$APP_DIR/" || errexit "Failed to copy $f."
  fi
done
if [ -d "$RUNTIME/node_modules" ]; then
  rm -rf "$APP_DIR/node_modules"
  cp -R "$RUNTIME/node_modules" "$APP_DIR/node_modules" || errexit "Failed to copy dependencies."
fi

chmod +x "$APP_DIR/launch-slack.sh" "$APP_DIR/run.sh" "$APP_DIR/injector.js" "$APP_DIR/node" 2>/dev/null || true

# Clear quarantine on the deployed copy so the bundled node runs without prompts.
/usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true

# Lock down to the current user (inject.js runs verbatim in the Slack session).
chmod -R go-rwx "$APP_DIR" 2>/dev/null || true

# Write the LaunchAgent.
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${APP_DIR}/run.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${APP_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>${APP_DIR}/agent.out.log</string>
    <key>StandardErrorPath</key>
    <string>${APP_DIR}/agent.err.log</string>
</dict>
</plist>
PLISTEOF

launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST" || errexit "Could not start the background agent."

log "Installed OK"
dialog "Installed! Slack will restart to turn on teammate local times.\n\nTip: switch to a channel or DM and you'll see each person's local time next to their name within a few seconds.\n\nIt now starts automatically every time you log in. To remove it later, just open this app again and choose Uninstall."
exit 0
