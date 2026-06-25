#!/usr/bin/env bash
#
# Install.command
# Double-clickable installer for non-technical teammates.
# Double-click in Finder (first time: right-click -> Open to bypass Gatekeeper).
#
# It will:
#   1. Make sure Node.js is available (offer to install via Homebrew if missing).
#   2. Install the small dependency (chrome-remote-interface).
#   3. Set up the login auto-start agent (install-agent.sh).
#
# No admin/sudo is required for the tool itself.

set -uo pipefail

# Always work from the folder this script lives in (double-click starts in $HOME).
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Make sure common Node locations are on PATH (Homebrew, nvm, etc.).
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
if [ -s "$HOME/.nvm/nvm.sh" ]; then . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true; fi

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
line() { printf -- "------------------------------------------------------------\n"; }

clear
bold "Slack Teammate Local Time — Installer"
line
echo "This shows each teammate's current local time next to their name in"
echo "the Slack desktop app. Slack itself is never modified."
echo

# ---------------------------------------------------------------------------
# 1. Node.js
# ---------------------------------------------------------------------------
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required but was not found."
  if command -v brew >/dev/null 2>&1; then
    read -r -p "Install Node.js now via Homebrew? [y/N] " ans
    case "$ans" in
      y|Y)
        echo "Installing Node.js (this can take a few minutes)..."
        brew install node || { echo "Homebrew install failed. Please install Node from https://nodejs.org and re-run."; read -r -p "Press Return to close."; exit 1; }
        ;;
      *)
        echo "Skipping. Please install Node.js from https://nodejs.org then double-click this installer again."
        read -r -p "Press Return to close."
        exit 1
        ;;
    esac
  else
    echo "Homebrew is not installed either."
    echo "Please install Node.js from:  https://nodejs.org  (the macOS .pkg installer)"
    echo "then double-click this installer again."
    read -r -p "Press Return to close."
    exit 1
  fi
fi

echo "Using Node $(node -v) ($(command -v node))"
echo

# ---------------------------------------------------------------------------
# 2. Dependencies
# ---------------------------------------------------------------------------
if [ ! -d "$DIR/node_modules/chrome-remote-interface" ]; then
  bold "Installing dependency (chrome-remote-interface)..."
  # Prefer `npm ci` (verifies the lockfile's integrity hashes) when possible.
  if [ -f "$DIR/package-lock.json" ]; then
    npm ci --omit=dev || npm install --omit=dev || { echo "npm install failed."; read -r -p "Press Return to close." _ || true; exit 1; }
  else
    npm install --omit=dev || { echo "npm install failed."; read -r -p "Press Return to close." _ || true; exit 1; }
  fi
  echo
fi

# ---------------------------------------------------------------------------
# 3. Auto-start agent
# ---------------------------------------------------------------------------
bold "Setting up login auto-start..."
chmod +x "$DIR"/*.sh 2>/dev/null || true
"$DIR/install-agent.sh"

echo
line
bold "Done!"
echo "Slack will (re)launch with teammate times enabled, and it will start"
echo "automatically every time you log in."
echo
echo "If you don't see times yet, switch to a channel/DM and wait a few seconds,"
echo "or quit and reopen Slack."
echo
echo "To remove later: double-click 'Uninstall.command'."
line
read -r -p "Press Return to close this window." _ || true
