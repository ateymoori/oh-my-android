#!/bin/zsh
# Builds a Release app, signs it with your Developer ID, notarizes, staples, zips, and writes the
# Homebrew cask with the zip's sha256.
#
# One-time setup (asks for an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials oyama --apple-id <apple-id-email> --team-id <TEAM_ID>
# Usage:
#   TEAM_ID=<your team id> Scripts/release.sh [--skip-notarize]
set -euo pipefail
cd "$(dirname "$0")/.."
APP=Oyama
TEAM_ID=${TEAM_ID:?Set TEAM_ID to your Apple Developer team id}
NOTARY_PROFILE=${NOTARY_PROFILE:-oyama}
REPO=${REPO:-ateymoori/oyama}
BUILD=build/DerivedData/Build/Products/Release

xcodegen generate >/dev/null
rm -rf "$BUILD/$APP.app"   # never ship a stale app from an earlier build
mkdir -p build
if ! xcodebuild -project $APP.xcodeproj -scheme $APP -configuration Release -derivedDataPath build/DerivedData \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Developer ID Application" build > build/release.log 2>&1; then
  grep -E "error:" build/release.log || tail -20 build/release.log
  echo "Build failed. Full log: build/release.log" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$BUILD/$APP.app/Contents/Info.plist")
ZIP=$APP-$VERSION.zip

# Notarization requires these; fail here instead of after a 5-minute upload.
# (Captured first: `grep -q` in a pipe exits early and trips pipefail.)
ENTITLEMENTS=$(codesign -d --entitlements - "$BUILD/$APP.app" 2>/dev/null)
SIGNATURE=$(codesign -dvv "$BUILD/$APP.app" 2>&1)
[[ "$ENTITLEMENTS" != *get-task-allow* ]] || { echo "get-task-allow is set; notarization would reject the app." >&2; exit 1; }
[[ "$SIGNATURE" == *$'\n'Timestamp=* ]] || { echo "Signature has no secure timestamp." >&2; exit 1; }

rm -rf dist && mkdir -p dist
cp -R "$BUILD/$APP.app" dist/
cd dist
ditto -c -k --keepParent $APP.app "$ZIP"
if [[ "${1:-}" != "--skip-notarize" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple $APP.app
  rm "$ZIP" && ditto -c -k --keepParent $APP.app "$ZIP"   # re-zip with the ticket stapled
  spctl -a -vv $APP.app
fi

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
cat > oyama.rb <<EOF
cask "oyama" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/$APP-#{version}.zip"
  name "Oyama"
  desc "Floating control panel for the Android emulator and devices"
  homepage "https://github.com/$REPO"

  depends_on macos: ">= :tahoe"

  app "$APP.app"

  zap trash: "~/Library/Preferences/se.royan.oyama.plist"
end
EOF
echo "Ready: dist/$ZIP (sha256 $SHA)"
echo "Cask:  dist/oyama.rb"
