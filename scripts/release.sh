#!/bin/bash
# Builds, signs with Developer ID, notarizes and staples MySpaces.app.
# One-time setup (interactive, run by the developer):
#   xcrun notarytool store-credentials MySpacesNotary --apple-id <id> --team-id 6W6TD6P8G3
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

MYSPACES_SIGN_IDENTITY="Developer ID Application" scripts/build-app.sh release
codesign --force --options runtime --timestamp --sign "Developer ID Application" build/MySpaces.app

ZIP="build/MySpaces-$VERSION.zip"
# Without --norsrc/--noextattr, extended attributes (macOS tags build output with
# com.apple.provenance) go into the zip as ._ files. Unzip tools other than Finder's
# leave those inside the app, which breaks its signature: "Apple could not verify…".
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent build/MySpaces.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile MySpacesNotary --wait
xcrun stapler staple build/MySpaces.app
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent build/MySpaces.app "$ZIP"
spctl --assess --type execute --verbose build/MySpaces.app
echo "$ROOT/$ZIP"
