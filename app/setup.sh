#!/bin/bash
#
# setup.sh  —  silent engine installer/uninstaller used by the menu bar app.
#
# Usage:
#   setup.sh install <RUNTIME_SRC_DIR>   deploy runtime + load login agent
#   setup.sh uninstall                   stop + remove engine and menu agents
#
# It is arch-aware: it picks node-arm64 or node-x64 from the bundled runtime so
# the same app works on both Apple Silicon and Intel Macs. No GUI, no sudo.

set -uo pipefail

APP_DIR="$HOME/Library/Application Support/SlackTeammateTime"
LA_DIR="$HOME/Library/LaunchAgents"
ENGINE_LABEL="com.user.slacktime"
MENU_LABEL="com.user.slacktime.menubar"
ENGINE_PLIST="$LA_DIR/${ENGINE_LABEL}.plist"
MENU_PLIST="$LA_DIR/${MENU_LABEL}.plist"
STATE="$APP_DIR/state.json"

err() { echo "setup: $*" >&2; exit 1; }

# Escape a string for safe inclusion inside an XML <string> element.
xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
  printf '%s' "$s"
}

cmd="${1:-}"

case "$cmd" in
  install)
    SRC="${2:-}"
    [ -n "$SRC" ] && [ -d "$SRC" ] || err "runtime source dir missing"

    mkdir -p "$APP_DIR" || err "cannot create $APP_DIR"

    # Copy the arch-independent runtime.
    for f in injector.js inject.js launch-slack.sh run.sh package.json package-lock.json; do
      [ -e "$SRC/$f" ] && cp -f "$SRC/$f" "$APP_DIR/"
    done
    if [ -d "$SRC/node_modules" ]; then
      rm -rf "$APP_DIR/node_modules"
      cp -R "$SRC/node_modules" "$APP_DIR/node_modules" || err "failed to copy node_modules"
    fi

    # Pick the right Node binary for this Mac's CPU.
    arch="$(uname -m)"
    case "$arch" in
      arm64)  NODE_SRC="$SRC/node-arm64" ;;
      x86_64) NODE_SRC="$SRC/node-x64" ;;
      *)      NODE_SRC="$SRC/node-$arch" ;;
    esac
    [ -x "$NODE_SRC" ] || NODE_SRC="$SRC/node"   # fallback to a single bundled node
    [ -x "$NODE_SRC" ] || err "no bundled node for arch '$arch'"
    cp -f "$NODE_SRC" "$APP_DIR/node"

    # Seed the on/off state only if it doesn't exist (preserve user's choice).
    [ -f "$STATE" ] || printf '{"enabled": true}\n' > "$STATE"

    chmod +x "$APP_DIR/launch-slack.sh" "$APP_DIR/run.sh" "$APP_DIR/injector.js" "$APP_DIR/node" 2>/dev/null || true

    # Clear quarantine so the bundled node runs without Gatekeeper prompts, then
    # lock the runtime down to the current user.
    /usr/bin/xattr -dr com.apple.quarantine "$APP_DIR" >/dev/null 2>&1 || true
    chmod -R go-rwx "$APP_DIR" 2>/dev/null || true

    # Engine LaunchAgent: starts the injector at login. Paths are XML-escaped
    # so an unusual home path can't break (or inject into) the plist.
    mkdir -p "$LA_DIR"
    APP_DIR_X="$(xml_escape "$APP_DIR")"
    cat > "$ENGINE_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>Label</key><string>${ENGINE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${APP_DIR_X}/run.sh</string>
    </array>
    <key>WorkingDirectory</key><string>${APP_DIR_X}</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>StandardOutPath</key><string>${APP_DIR_X}/agent.out.log</string>
    <key>StandardErrorPath</key><string>${APP_DIR_X}/agent.err.log</string>
</dict>
</plist>
PLIST

    launchctl unload "$ENGINE_PLIST" >/dev/null 2>&1 || true
    launchctl load "$ENGINE_PLIST" || err "could not load engine agent"
    echo "installed"
    ;;

  uninstall)
    launchctl unload "$ENGINE_PLIST" >/dev/null 2>&1 || true
    launchctl unload "$MENU_PLIST"   >/dev/null 2>&1 || true
    rm -f "$ENGINE_PLIST" "$MENU_PLIST"
    rm -rf "$APP_DIR"
    echo "uninstalled"
    ;;

  *)
    err "usage: setup.sh install <runtime-src> | uninstall"
    ;;
esac
