#!/bin/bash
# Builds a runnable TextCorrect.app from the SwiftPM release binary.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build/tmp .build/clang-cache .build/swiftpm-cache
export TMPDIR="$(pwd)/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$(pwd)/.build/clang-cache"
export SWIFTPM_CACHE_DIR="$(pwd)/.build/swiftpm-cache"

swift build -c release --disable-sandbox --scratch-path "$(pwd)/.build"

APP="build/TextCorrect.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TextCorrect "$APP/Contents/MacOS/TextCorrect"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
