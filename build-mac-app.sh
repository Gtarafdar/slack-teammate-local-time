#!/usr/bin/env bash
#
# build-mac-app.sh
# Assembles a self-contained, UNIVERSAL (Intel + Apple Silicon)
# SlackTeammateTime.app — a menu bar app with an on/off toggle and a bundled
# Node.js for each architecture — and packages it as a .dmg.
#
# Output:
#   dist/SlackTeammateTime.app   (universal)
#   dist/SlackTeammateTime.dmg
#
# Build requirements (not needed by end users): macOS with Xcode toolchain
# (swiftc, lipo, codesign) and hdiutil. Node binaries are downloaded into
# build-cache/ automatically.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

NAME="SlackTeammateTime"
NODE_VER="${NODE_VER:-v22.12.0}"
CACHE="$DIR/build-cache"
DIST="$DIR/dist"
APP="$DIST/$NAME.app"
MIN_MACOS="11.0"

echo "[build] Cleaning previous build..."
rm -rf "$APP" "$DIST/$NAME.dmg" "$DIST/dmgroot"
mkdir -p "$DIST" "$CACHE"

# --- download bundled node for both architectures ----------------------------
fetch_node() { # arch (arm64|x64)
  local arch="$1"
  local pkg="node-${NODE_VER}-darwin-${arch}"
  if [ ! -x "$CACHE/$pkg/bin/node" ]; then
    echo "[build] Downloading Node ${NODE_VER} (${arch})..."
    curl -fsSL -o "$CACHE/${pkg}.tar.gz" "https://nodejs.org/dist/${NODE_VER}/${pkg}.tar.gz"
    tar -xzf "$CACHE/${pkg}.tar.gz" -C "$CACHE"
  fi
}
fetch_node arm64
fetch_node x64
NODE_ARM64="$CACHE/node-${NODE_VER}-darwin-arm64/bin/node"
NODE_X64="$CACHE/node-${NODE_VER}-darwin-x64/bin/node"

# --- ensure dependencies are installed (to bundle) ---------------------------
if [ ! -d "$DIR/node_modules/chrome-remote-interface" ]; then
  echo "[build] Installing dependencies..."
  if [ -f "$DIR/package-lock.json" ]; then npm ci --omit=dev; else npm install --omit=dev; fi
fi

# --- compile the universal menu bar binary -----------------------------------
echo "[build] Compiling Swift menu bar app (arm64 + x86_64)..."
swiftc -O -target "arm64-apple-macosx${MIN_MACOS}"  -o "$CACHE/stt-arm64" app/SlackTeammateTime.swift
swiftc -O -target "x86_64-apple-macosx${MIN_MACOS}" -o "$CACHE/stt-x64"   app/SlackTeammateTime.swift

# --- assemble the .app bundle ------------------------------------------------
echo "[build] Assembling $APP ..."
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources/runtime"

cp "$DIR/app/Info.plist"   "$APP/Contents/Info.plist"
cp "$DIR/app/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$DIR/app/setup.sh"     "$APP/Contents/Resources/setup.sh"
chmod +x "$APP/Contents/Resources/setup.sh"

lipo -create "$CACHE/stt-arm64" "$CACHE/stt-x64" -output "$APP/Contents/MacOS/$NAME"
chmod +x "$APP/Contents/MacOS/$NAME"

# Runtime payload (arch-independent + both node binaries; setup.sh picks one).
for f in injector.js inject.js launch-slack.sh run.sh package.json package-lock.json; do
  cp "$DIR/$f" "$APP/Contents/Resources/runtime/"
done
cp -R "$DIR/node_modules" "$APP/Contents/Resources/runtime/node_modules"
cp "$NODE_ARM64" "$APP/Contents/Resources/runtime/node-arm64"
cp "$NODE_X64"   "$APP/Contents/Resources/runtime/node-x64"
chmod +x "$APP/Contents/Resources/runtime/node-arm64" \
         "$APP/Contents/Resources/runtime/node-x64" \
         "$APP/Contents/Resources/runtime/launch-slack.sh" \
         "$APP/Contents/Resources/runtime/run.sh" \
         "$APP/Contents/Resources/runtime/injector.js"

# --- ad-hoc code signature (lets it run locally; not notarized) --------------
echo "[build] Ad-hoc signing..."
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "[build] (codesign skipped)"
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 && echo "[build] signature OK" || true
lipo -info "$APP/Contents/MacOS/$NAME"

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
