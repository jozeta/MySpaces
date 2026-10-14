#!/bin/bash
# Builds build/MySpaces.app. Usage: scripts/build-app.sh [debug|release]
# Signs with MYSPACES_SIGN_IDENTITY (default "Apple Development") so TCC grants survive rebuilds.
set -euo pipefail
CONFIG="${1:-debug}"
IDENTITY="${MYSPACES_SIGN_IDENTITY:-Apple Development}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG" --product MySpaces
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MySpaces"

APP="build/MySpaces.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MySpaces"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "$ROOT/$APP"
