#!/usr/bin/env bash
#
# build-mac-app.sh
# Assembles a self-contained SlackTeammateTime.app (with a bundled Node.js, so
# end users need no prerequisites) and packages it as a .dmg for distribution.
#
# Output:
#   dist/SlackTeammateTime.app
#   dist/SlackTeammateTime.dmg
#
# Requirements to BUILD (not to run): macOS with hdiutil, and the bundled Node
# tarball (downloaded automatically into build-cache/).

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

NAME="SlackTeammateTime"
NODE_VER="${NODE_VER:-v22.12.0}"
NODE_PKG="node-${NODE_VER}-darwin-arm64"
CACHE="$DIR/build-cache"
DIST="$DIR/dist"
APP="$DIST/$NAME.app"

echo "[build] Cleaning previous build..."
rm -rf "$APP" "$DIST/$NAME.dmg" "$DIST/dmgroot"
mkdir -p "$DIST"

# --- ensure bundled node is available ----------------------------------------
mkdir -p "$CACHE"
if [ ! -x "$CACHE/$NODE_PKG/bin/node" ]; then
  echo "[build] Downloading Node ${NODE_VER} (arm64)..."
  curl -fsSL -o "$CACHE/${NODE_PKG}.tar.gz" "https://nodejs.org/dist/${NODE_VER}/${NODE_PKG}.tar.gz"
  tar -xzf "$CACHE/${NODE_PKG}.tar.gz" -C "$CACHE"
fi
NODE_BIN="$CACHE/$NODE_PKG/bin/node"

# --- ensure dependencies are installed (to bundle) ---------------------------
if [ ! -d "$DIR/node_modules/chrome-remote-interface" ]; then
  echo "[build] Installing dependencies..."
  if [ -f "$DIR/package-lock.json" ]; then npm ci --omit=dev; else npm install --omit=dev; fi
fi

# --- assemble the .app bundle ------------------------------------------------
echo "[build] Assembling $APP ..."
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/runtime"

cp "$DIR/app/Info.plist"  "$APP/Contents/Info.plist"
cp "$DIR/app/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cp "$DIR/app/launcher.sh" "$APP/Contents/MacOS/$NAME"
chmod +x "$APP/Contents/MacOS/$NAME"

# Runtime payload
for f in injector.js inject.js launch-slack.sh run.sh package.json package-lock.json; do
  cp "$DIR/$f" "$APP/Contents/Resources/runtime/"
done
cp -R "$DIR/node_modules" "$APP/Contents/Resources/runtime/node_modules"
cp "$NODE_BIN" "$APP/Contents/Resources/runtime/node"
chmod +x "$APP/Contents/Resources/runtime/node" \
         "$APP/Contents/Resources/runtime/launch-slack.sh" \
         "$APP/Contents/Resources/runtime/run.sh" \
         "$APP/Contents/Resources/runtime/injector.js"

# --- package a .dmg ----------------------------------------------------------
echo "[build] Building DMG..."
mkdir -p "$DIST/dmgroot"
cp -R "$APP" "$DIST/dmgroot/"
ln -sf /Applications "$DIST/dmgroot/Applications"

hdiutil create \
  -volname "Slack Teammate Time" \
  -srcfolder "$DIST/dmgroot" \
  -ov -format UDZO \
  "$DIST/$NAME.dmg" >/dev/null

rm -rf "$DIST/dmgroot"

echo "[build] Done."
echo "  App: $APP"
echo "  DMG: $DIST/$NAME.dmg"
du -h "$DIST/$NAME.dmg" | awk '{print "  DMG size: " $1}'
