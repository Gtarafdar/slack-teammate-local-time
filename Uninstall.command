#!/usr/bin/env bash
#
# Uninstall.command
# Double-clickable uninstaller. Removes the login auto-start agent and the
# deployed runtime copy. Does NOT modify Slack itself.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

clear
printf "\033[1m%s\033[0m\n" "Slack Teammate Local Time — Uninstaller"
echo

chmod +x "$DIR/uninstall-agent.sh" 2>/dev/null || true
"$DIR/uninstall-agent.sh"

echo
echo "Quit and reopen Slack normally to clear the inline times."
read -r -p "Press Return to close this window." _ || true
