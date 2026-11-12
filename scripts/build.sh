#!/bin/sh
# Builds build/MailRem.app as a universal (Apple Silicon + Intel) app and signs it.
#
# Signing uses a "Developer ID Application" certificate when one is in the
# keychain, and falls back to an ad-hoc signature otherwise. Override with:
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build.sh
set -e
cd "$(dirname "$0")/.."

APP_NAME="MailRem"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
MIN_MACOS="13.0"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos$MIN_MACOS" \
    Sources/MailRem/*.swift -o "$BUILD/$APP_NAME-$ARCH"
done
lipo -create "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64" \
  -output "$APP/Contents/MacOS/$APP_NAME"
rm -f "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --options runtime --timestamp \
    --entitlements Resources/MailRem.entitlements \
    --sign "$IDENTITY" "$APP"
  echo "Signed with: $IDENTITY"
else
  codesign --force --entitlements Resources/MailRem.entitlements --sign - "$APP"
  echo "No '$IDENTITY' certificate found; signed ad hoc (fine for local use only)."
fi

echo "Built $APP"
