#!/usr/bin/env bash
#
# Builds Menu Bar Monitor.app without Xcode (Command Line Tools are enough).
#
#   ./build.sh              build build/MenuBarMonitor.app
#   ./build.sh --install    also copy it to /Applications and restart it
#   ./build.sh --debug      debug build instead of release
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/MenuBarMonitor.app"
BUNDLE_ID=com.robinwijnen.menubarmonitor
CONFIG=release

DO_INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) DO_INSTALL=1 ;;
    --debug) CONFIG=debug ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG" --product MenuBarMonitor
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MenuBarMonitor" "$APP/Contents/MacOS/MenuBarMonitor"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Building icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$ROOT/Tools/make-icon.swift" "$ICONSET" >/dev/null 2>&1 \
   && command -v iconutil >/dev/null 2>&1 \
   && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    AppIcon.icns"
else
  echo "    skipped (icon generation unavailable — the app still builds)"
fi

echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 \
  && echo "    signed" \
  || echo "    codesign failed; the app will still run locally"

echo "==> Built $APP"

if [[ "$DO_INSTALL" == 1 ]]; then
  TARGET_DIR=/Applications
  if ! mkdir -p "$TARGET_DIR" 2>/dev/null || [[ ! -w "$TARGET_DIR" ]]; then
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
    echo "==> /Applications is not writable; installing to $TARGET_DIR"
  fi
  INSTALLED="$TARGET_DIR/MenuBarMonitor.app"

  # It lives in the menu bar, so it is almost always running. Replacing the bundle
  # under a running copy leaves the old code in memory until the next login.
  if pgrep -x MenuBarMonitor >/dev/null; then
    echo "==> Quitting the running copy"
    pkill -x MenuBarMonitor || true
    sleep 1
  fi

  echo "==> Installing to $INSTALLED"
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"
  open "$INSTALLED"
  echo "==> Started $INSTALLED"
fi
