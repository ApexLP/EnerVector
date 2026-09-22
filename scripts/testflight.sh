#!/usr/bin/env bash
# Archive EnerVector and upload it to App Store Connect / TestFlight.
#
# Auth — either:
#   a) Sign in to Xcode › Settings › Accounts with the Apple ID on team Y9WQTJV82S, or
#   b) export an App Store Connect API key:
#        ASC_KEY_PATH=~/private_keys/AuthKey_XXXXXXXXXX.p8
#        ASC_KEY_ID=XXXXXXXXXX
#        ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Usage: scripts/testflight.sh            (build number = UTC timestamp)
#        BUILD_NUMBER=42 scripts/testflight.sh
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
# Keep build products out of the iCloud-synced Documents folder — codesign rejects
# the extended attributes iCloud adds.
WORK="${TMPDIR:-/tmp}/enervector-release"
ARCHIVE="$WORK/EnerVector.xcarchive"
rm -rf "$WORK" && mkdir -p "$WORK"

AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

echo "▸ Archiving EnerVector (build $BUILD_NUMBER)…"
xcodebuild archive \
  -project EnerVector.xcodeproj \
  -scheme EnerVector \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$WORK/DerivedData" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  > "$WORK/archive.log" 2>&1 || {
    grep -E "error:|Signing|provisioning" "$WORK/archive.log" | sort -u | tail -20
    echo "✗ Archive failed — full log: $WORK/archive.log"
    exit 1
  }

echo "▸ Uploading to App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$WORK/export" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

echo "✓ Uploaded build $BUILD_NUMBER. It appears in App Store Connect › TestFlight after processing (~5–15 min)."
