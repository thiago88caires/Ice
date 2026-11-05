#!/bin/bash
# Build Ice, ad-hoc sign it, install it to ~/Applications, reset its TCC
# permissions (ad-hoc signatures change every build, so old grants go stale),
# and launch it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD="$ROOT/build/DD"
APP="$DD/Build/Products/Release/Ice.app"
DEST="$HOME/Applications/Ice.app"
BUNDLE_ID="com.jordanbaird.Ice"

mkdir -p "$ROOT/build"
echo "==> Building"
xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -derivedDataPath "$DD" CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build \
    > "$ROOT/build/xcodebuild.log" 2>&1 || {
        grep "error:" "$ROOT/build/xcodebuild.log" | sort -u
        echo "Build failed; see build/xcodebuild.log" >&2
        exit 1
    }

# Re-sign inside-out without hardened runtime: with runtime on, library
# validation rejects the ad-hoc Sparkle framework ("different Team IDs").
echo "==> Signing (ad-hoc)"
sign() { codesign --force --sign - --preserve-metadata=entitlements "$1" 2>&1 | grep -v "replacing existing signature" || true; }
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$SPARKLE/XPCServices/Downloader.xpc" "$SPARKLE/XPCServices/Installer.xpc" \
            "$SPARKLE/Updater.app" "$SPARKLE/Autoupdate" "$SPARKLE" \
            "$APP/Contents/XPCServices/MenuBarItemService.xpc" "$APP"; do
    [[ -e "$item" ]] && sign "$item"
done
codesign --verify --deep --strict "$APP"

echo "==> Installing to $DEST"
pkill -x Ice || true
sleep 1
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "==> Resetting TCC permissions for $BUNDLE_ID"
for service in Accessibility ScreenCapture ListenEvent PostEvent; do
    out=$(tccutil reset "$service" "$BUNDLE_ID" 2>&1) && echo "  $service: reset" || echo "  $service: $out"
done

echo "==> Launching"
open "$DEST"
echo "Done. Grant Accessibility and Screen Recording again when Ice asks."
