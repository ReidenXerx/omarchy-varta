#!/usr/bin/env bash
# Build and sign Varta.app with Xcode's automatic signing.
#
#   scripts/build-app.sh            Debug, "Apple Development", into build/Varta.app
#   scripts/build-app.sh release    Archive, exported for Developer ID into
#                                   build/export/Varta.app, ready to notarize
#
# Xcode, not SwiftPM: the time-sensitive notification entitlement has to be
# backed by a provisioning profile, and -allowProvisioningUpdates lets Xcode
# register the App ID and fetch that profile from the developer account it is
# signed into. The project is generated from project.yml.
set -euo pipefail

CONFIGURATION="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
cd "$ROOT"

command -v xcodegen >/dev/null || { echo "error: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

# Debug builds target this Mac, so Xcode registers it in the account and puts it
# in the development profile; "Any Mac" signs fine but then refuses to launch
# here (AMFI: "No matching profile found"). Archives stay generic.
COMMON=(-project Varta.xcodeproj -scheme Varta
        -derivedDataPath "$BUILD/DerivedData"
        -allowProvisioningUpdates -allowProvisioningDeviceRegistration)

if [ "$CONFIGURATION" = "release" ]; then
  rm -rf "$BUILD/Varta.xcarchive" "$BUILD/export"
  xcodebuild "${COMMON[@]}" -destination 'generic/platform=macOS' -configuration Release archive \
    -archivePath "$BUILD/Varta.xcarchive" -quiet
  cat > "$BUILD/export-options.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$BUILD/Varta.xcarchive" \
    -exportOptionsPlist "$BUILD/export-options.plist" -exportPath "$BUILD/export" \
    -allowProvisioningUpdates -quiet
  APP="$BUILD/export/Varta.app"
else
  xcodebuild "${COMMON[@]}" -destination "platform=macOS,arch=$(uname -m)" -configuration Debug build -quiet
  rm -rf "$BUILD/Varta.app"
  cp -R "$BUILD/DerivedData/Build/Products/Debug/Varta.app" "$BUILD/Varta.app"
  APP="$BUILD/Varta.app"
fi

codesign --verify --strict "$APP"
echo "entitlements:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | sed 's/^/  /'
echo "built $APP"
