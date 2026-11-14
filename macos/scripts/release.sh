#!/usr/bin/env bash
# release.sh: everything a Varta download release needs, ready to upload.
#
#   scripts/release.sh
#
# 1. Archives and exports Varta.app for Developer ID (scripts/build-app.sh release)
# 2. Packs a drag-to-install DMG (the app next to an Applications shortcut)
# 3. Signs the DMG, notarizes it, staples the ticket, and asks Gatekeeper
# 4. Signs the DMG for Sparkle and writes appcast.xml, the update feed that
#    installed copies read from the latest GitHub release
# 5. Writes the Homebrew cask with the DMG's checksum
#
# Output in build/release/: Varta-<version>.dmg, appcast.xml, varta.rb.
# Nothing is uploaded; the last lines print the commands that publish it.
#
# Notary credentials, stored once in the keychain (the same Apple account as
# Whiz, so its profile works):
#   xcrun notarytool store-credentials <profile> --apple-id <email> --team-id <TEAM> --password <app-specific>
# VARTA_NOTARY_PROFILE picks the profile (default whiz-notary).
#
# The update feed is read from the repo's *latest* release. Linux releases of
# the plugin, if it ever gets any, must be published with --latest=false, or
# every installed Mac copy will look for appcast.xml in the wrong release.
#
# The Sparkle key lives in the login keychain (account app.duduphudu.varta),
# with a backup at ~/.config/varta-sparkle/update-signing.key. Lose both and
# installed copies can no longer be updated. Restore the backup with
#   <Sparkle bin>/generate_keys --account app.duduphudu.varta -f <file>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/release"
PROFILE="${VARTA_NOTARY_PROFILE:-whiz-notary}"
REPO="ReidenXerx/omarchy-varta"
cd "$ROOT"

# Checked before building: a notarization bound to fail should not cost a
# release build first.
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>"$ROOT/build/notary-check.txt"; then
  echo "release.sh: notarytool cannot use profile '$PROFILE':" >&2
  sed 's/^/  /' "$ROOT/build/notary-check.txt" >&2
  echo "  (\"agreement missing or expired\" means accepting the new Apple Developer agreement at developer.apple.com/account)" >&2
  exit 1
fi

"$ROOT/scripts/build-app.sh" release
APP="$ROOT/build/export/Varta.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -1)"
[ -n "$IDENTITY" ] || { echo "release.sh: the export is not signed with a Developer ID" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"
DMG="$OUT/Varta-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
# The Applications symlink is what makes the volume "drag to install".
ln -s /Applications "$STAGE/Applications"
# UDZO: compressed, and readable by every macOS Varta supports. `hdiutil create`
# is deprecated on macOS 27 and its images no longer verify there.
diskutil image create from --format UDZO --volumeName "Varta" "$STAGE" "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "Notarizing $DMG (waits for Apple, usually a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

# Sparkle: an EdDSA signature over the exact DMG that is uploaded.
SPARKLE_BIN="$(find "$ROOT/build/DerivedData/SourcePackages/artifacts" -path '*Sparkle/bin' -type d | head -1)"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account app.duduphudu.varta "$DMG")"
URL="https://github.com/$REPO/releases/download/v$VERSION/Varta-$VERSION.dmg"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Varta</title>
    <item>
      <title>Varta $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML

SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHA256@/$SHA/g" "$ROOT/packaging/varta.rb.in" > "$OUT/varta.rb"

echo
echo "Ready in $OUT:"
ls -1 "$OUT" | sed 's/^/  /'
echo
echo "To publish:"
echo "  gh release create v$VERSION '$DMG' '$OUT/appcast.xml' --repo $REPO --title 'Varta $VERSION for Mac'"
echo "  then copy $OUT/varta.rb to Casks/varta.rb in github.com/ReidenXerx/homebrew-tap"
