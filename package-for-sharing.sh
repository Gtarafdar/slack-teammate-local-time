#!/usr/bin/env bash
#
# package-for-sharing.sh
# Builds a clean, shareable zip of this tool (excludes node_modules, logs,
# and local artifacts). Hand the resulting zip to teammates; they unzip and
# double-click Install.command.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

NAME="SlackTeammateTime"
OUT_DIR="$DIR/dist"
STAGE="$OUT_DIR/$NAME"
ZIP="$OUT_DIR/${NAME}.zip"

rm -rf "$STAGE" "$ZIP"
mkdir -p "$STAGE"

# Files to include in the share.
INCLUDE=(
  "Install.command"
  "Uninstall.command"
  "README.md"
  "inject.js"
  "injector.js"
  "launch-slack.sh"
  "run.sh"
  "install-agent.sh"
  "uninstall-agent.sh"
  "com.user.slacktime.plist"
  "verify.js"
  "package.json"
  "package-lock.json"
)

for f in "${INCLUDE[@]}"; do
  if [ -e "$DIR/$f" ]; then
    cp "$DIR/$f" "$STAGE/"
  else
    echo "[package] WARNING: missing $f (skipped)"
  fi
done

# Ensure the executables stay executable inside the archive.
chmod +x "$STAGE"/*.command "$STAGE"/*.sh "$STAGE"/injector.js 2>/dev/null || true

# Zip it up (run from dist so paths inside the zip are clean).
( cd "$OUT_DIR" && /usr/bin/zip -r -q "${NAME}.zip" "$NAME" )

echo "[package] Created: $ZIP"
echo "[package] Share that zip. Recipients: unzip, then double-click Install.command"
echo "[package] (first time they may need to right-click -> Open to bypass Gatekeeper)."
