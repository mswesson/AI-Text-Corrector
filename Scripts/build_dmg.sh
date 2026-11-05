#!/bin/bash
# Builds a drag-and-drop disk image containing the app and an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")/.."

bash Scripts/build_app.sh

STAGING=$(mktemp -d "$(pwd)/.build/dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

ditto build/TextCorrect.app "$STAGING/TextCorrect.app"
ln -s /Applications "$STAGING/Applications"

DMG="build/TextCorrect-macOS-arm64.dmg"
hdiutil create -volname TextCorrect -srcfolder "$STAGING" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
printf 'Built %s\n' "$DMG"
