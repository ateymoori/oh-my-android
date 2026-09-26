#!/bin/zsh
# Builds a Release app, signs it with your Developer ID, notarizes, staples, zips, and writes the
# Homebrew cask with the zip's sha256 and the signed Sparkle appcast.
#
# One-time setup (asks for an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials ohmyandroid --apple-id <apple-id-email> --team-id <TEAM_ID>
# Sparkle's private EdDSA key must be in the login Keychain (generate_keys; its public key is SUPublicEDKey).
# Usage:
#   TEAM_ID=<your team id> [NOTES=notes.md] Scripts/release.sh [--skip-notarize]
# NOTES: Markdown release notes, shown in the update window (and usable for `gh release create --notes-file`).
set -euo pipefail
NOTES=${NOTES:+${NOTES:A}}   # absolute, before the cd
cd "$(dirname "$0")/.."
APP=OhMyAndroid              # project, scheme, zip name
BUNDLE="Oh My Android.app"
TEAM_ID=${TEAM_ID:?Set TEAM_ID to your Apple Developer team id}
NOTARY_PROFILE=${NOTARY_PROFILE:-ohmyandroid}
REPO=${REPO:-ateymoori/oh-my-android}
BUILD=build/DerivedData/Build/Products/Release
SPARKLE_BIN=build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin
[[ -z "$NOTES" || -f "$NOTES" ]] || { echo "No release notes at $NOTES." >&2; exit 1; }

xcodegen generate >/dev/null
rm -rf "$BUILD/$BUNDLE"   # never ship a stale app from an earlier build
mkdir -p build
if ! xcodebuild -project $APP.xcodeproj -scheme $APP -configuration Release -derivedDataPath build/DerivedData \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Developer ID Application" build > build/release.log 2>&1; then
  grep -E "error:" build/release.log || tail -20 build/release.log
  echo "Build failed. Full log: build/release.log" >&2
  exit 1
fi

# Xcode signs the embedded Sparkle.framework but not its helpers, which ship ad-hoc signed.
# Sign them inside-out with the Developer ID, then re-seal the app (entitlements kept).
IDENTITY=$(security find-identity -v -p codesigning | awk -v team="($TEAM_ID)" '/Developer ID Application/ && index($0, team) { print $2; exit }')
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application identity for team $TEAM_ID." >&2; exit 1; }
SPARKLE="$BUILD/$BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
SIGN=(codesign --force --timestamp --options runtime --sign "$IDENTITY")
"${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Updater.app"
"${SIGN[@]}" "$BUILD/$BUNDLE/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" --preserve-metadata=entitlements,requirements,flags "$BUILD/$BUNDLE"

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

# Sparkle feed: one item, EdDSA-signed zip and feed. Uploaded with each release as appcast.xml;
# the app reads it from releases/latest/download.
mkdir updates && cp "$ZIP" updates/
[[ -z "$NOTES" ]] || cp "$NOTES" "updates/${ZIP%.zip}.md"
"../$SPARKLE_BIN/generate_appcast" --maximum-versions 1 --embed-release-notes \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --full-release-notes-url "https://github.com/$REPO/releases/tag/v$VERSION" \
  --link "https://github.com/$REPO" -o appcast.xml updates
"../$SPARKLE_BIN/sign_update" --verify appcast.xml
grep -q "releases/download/v$VERSION/$ZIP" appcast.xml || { echo "appcast.xml does not point at $ZIP." >&2; exit 1; }
rm -rf updates

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

  auto_updates true

  app "$BUNDLE"
  binary "#{appdir}/$BUNDLE/Contents/MacOS/ohmyandroid-mcp"

  zap trash: [
    "~/Library/Caches/se.royan.ohmyandroid",
    "~/Library/HTTPStorages/se.royan.ohmyandroid",
    "~/Library/Preferences/se.royan.ohmyandroid.plist",
  ]
end
EOF
# MCP bundle (.mcpb): the signed, notarized server alone, for Claude Desktop and the MCP Registry.
# server.json (repo root) points the registry at it; commit it after the release.
MCPB=oh-my-android-$VERSION.mcpb
mkdir -p mcpb/server
cp "$BUNDLE/Contents/MacOS/ohmyandroid-mcp" mcpb/server/
cp ../mcpb/icon.png mcpb/
jq --arg v "$VERSION" '.version = $v' ../mcpb/manifest.json > mcpb/manifest.json
(cd mcpb && zip -qrX "../$MCPB" manifest.json icon.png server)
rm -rf mcpb
MCPB_SHA=$(shasum -a 256 "$MCPB" | cut -d' ' -f1)
jq --arg v "$VERSION" --arg url "https://github.com/$REPO/releases/download/v$VERSION/$MCPB" --arg sha "$MCPB_SHA" \
  '.version = $v | .packages[0].identifier = $url | .packages[0].fileSha256 = $sha' ../server.json > server.json
cp server.json ../server.json

echo "Ready: dist/$ZIP (sha256 $SHA)"
echo "Cask:  dist/oh-my-android.rb"
echo "Feed:  dist/appcast.xml (upload with the zip)"
echo "MCP:   dist/$MCPB (upload with the zip), then commit server.json and run: mcp-publisher publish"
