#!/bin/sh
# Builds the app and packages it as dist/MailRem-<version>.dmg.
#
# To notarize the disk image with Apple (needed so it opens without a warning
# on other Macs), store credentials once:
#   xcrun notarytool store-credentials mailrem-notary
# and then run:
#   NOTARY_PROFILE=mailrem-notary scripts/package.sh
set -e
cd "$(dirname "$0")/.."

APP_NAME="MailRem"
APP="build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="dist/$APP_NAME-$VERSION.dmg"

sh scripts/build.sh

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

if [ -n "$NOTARY_PROFILE" ]; then
  echo "Submitting to Apple for notarization (this can take a few minutes)..."
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  echo "Notarized and stapled."
else
  echo "Not notarized. Set NOTARY_PROFILE to notarize (see the top of this script)."
fi

echo "Created $DMG"
shasum -a 256 "$DMG"
