#!/bin/zsh
# Builds a Release app, signs it with your Developer ID, notarizes, staples, zips, and writes the
# Homebrew cask with the zip's sha256.
#
# One-time setup (asks for an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials ohmyandroid --apple-id <apple-id-email> --team-id <TEAM_ID>
# Usage:
#   TEAM_ID=<your team id> Scripts/release.sh [--skip-notarize]
set -euo pipefail
cd "$(dirname "$0")/.."
APP=OhMyAndroid              # project, scheme, zip name
BUNDLE="Oh My Android.app"
TEAM_ID=${TEAM_ID:?Set TEAM_ID to your Apple Developer team id}
NOTARY_PROFILE=${NOTARY_PROFILE:-ohmyandroid}
REPO=${REPO:-ateymoori/oh-my-android}
BUILD=build/DerivedData/Build/Products/Release

xcodegen generate >/dev/null
rm -rf "$BUILD/$BUNDLE"   # never ship a stale app from an earlier build
mkdir -p build
if ! xcodebuild -project $APP.xcodeproj -scheme $APP -configuration Release -derivedDataPath build/DerivedData \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Developer ID Application" build > build/release.log 2>&1; then
  grep -E "error:" build/release.log || tail -20 build/release.log
  echo "Build failed. Full log: build/release.log" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$BUILD/$BUNDLE/Contents/Info.plist")
ZIP=$APP-$VERSION.zip

# Notarization requires these; fail here instead of after a 5-minute upload.
# (Captured first: `grep -q` in a pipe exits early and trips pipefail.)
ENTITLEMENTS=$(codesign -d --entitlements - "$BUILD/$BUNDLE" 2>/dev/null)
SIGNATURE=$(codesign -dvv "$BUILD/$BUNDLE" 2>&1)
[[ "$ENTITLEMENTS" != *get-task-allow* ]] || { echo "get-task-allow is set; notarization would reject the app." >&2; exit 1; }
[[ "$SIGNATURE" == *$'\n'Timestamp=* ]] || { echo "Signature has no secure timestamp." >&2; exit 1; }
MCP="$BUILD/$BUNDLE/Contents/MacOS/ohmyandroid-mcp"
MCP_SIGNATURE=$(codesign -dvv "$MCP" 2>&1)
[[ "$MCP_SIGNATURE" == *$'\n'Timestamp=* && "$MCP_SIGNATURE" == *runtime* ]] || { echo "MCP server lacks timestamp or hardened runtime." >&2; exit 1; }
codesign --verify --deep --strict "$BUILD/$BUNDLE"
Scripts/test-mcp.py "$MCP"

rm -rf dist && mkdir -p dist
cp -R "$BUILD/$BUNDLE" dist/
cd dist
ditto -c -k --keepParent "$BUNDLE" "$ZIP"
if [[ "${1:-}" != "--skip-notarize" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$BUNDLE"
  rm "$ZIP" && ditto -c -k --keepParent "$BUNDLE" "$ZIP"   # re-zip with the ticket stapled
  spctl -a -vv "$BUNDLE"
fi

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
cat > oh-my-android.rb <<EOF
cask "oh-my-android" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/$APP-#{version}.zip"
  name "Oh My Android"
  desc "Control panel and MCP server for the Android emulator and devices"
  homepage "https://github.com/$REPO"

  depends_on macos: :tahoe

  app "$BUNDLE"
  binary "#{appdir}/$BUNDLE/Contents/MacOS/ohmyandroid-mcp"

  zap trash: "~/Library/Preferences/se.royan.ohmyandroid.plist"
end
EOF
echo "Ready: dist/$ZIP (sha256 $SHA)"
echo "Cask:  dist/oh-my-android.rb"
