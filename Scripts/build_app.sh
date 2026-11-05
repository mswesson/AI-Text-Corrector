#!/bin/bash
# Packages the arm64 app with native runtimes and no speech model weights.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build/tmp .build/clang-cache .build/swiftpm-cache
export TMPDIR="$(pwd)/.build/tmp"
export CLANG_MODULE_CACHE_PATH="$(pwd)/.build/clang-cache"
export SWIFTPM_CACHE_DIR="$(pwd)/.build/swiftpm-cache"

swift build -c release --product TextCorrect --disable-sandbox --scratch-path "$(pwd)/.build"

APP="build/TextCorrect.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/TextCorrect "$APP/Contents/MacOS/TextCorrect"
cp Resources/Info.plist "$APP/Contents/Info.plist"
for localization in Resources/*.lproj; do
    ditto "$localization" "$APP/Contents/Resources/$(basename "$localization")"
done
for bundle in .build/release/*.bundle; do
    [ -d "$bundle" ] && ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
WHISPER=".build/release/whisper.framework"
ditto "$WHISPER" "$APP/Contents/Frameworks/whisper.framework"
lipo "$APP/Contents/Frameworks/whisper.framework/Versions/A/whisper" -thin arm64 -output .build/whisper-arm64
mv .build/whisper-arm64 "$APP/Contents/Frameworks/whisper.framework/Versions/A/whisper"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/TextCorrect"
if [ -d Resources/Licenses ]; then ditto Resources/Licenses "$APP/Contents/Resources/Licenses"; fi
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" build/TextCorrect-macOS-arm64.zip
printf 'Built %s and build/TextCorrect-macOS-arm64.zip\n' "$APP"
