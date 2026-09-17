#!/usr/bin/env bash
# Archives the app and exports a signed IPA using an ExportOptions.plist that
# is generated from environment/secrets-supplied values. Nothing is hardcoded.
#
# Usage: export-ipa.sh --bundle-id ID --team-id TEAM --export-method METHOD --profile-name NAME
set -euo pipefail

BUNDLE_ID=""
TEAM_ID=""
EXPORT_METHOD="ad-hoc"
PROFILE_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --export-method) EXPORT_METHOD="$2"; shift 2 ;;
    --profile-name) PROFILE_NAME="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$BUNDLE_ID" ] || [ -z "$TEAM_ID" ] || [ -z "$PROFILE_NAME" ]; then
  echo "bundle-id, team-id and profile-name are required" >&2
  exit 1
fi

case "$EXPORT_METHOD" in
  app-store|ad-hoc|development|enterprise) ;;
  *) echo "Unsupported export method: $EXPORT_METHOD" >&2; exit 1 ;;
esac

mkdir -p build/logs

# Generate ExportOptions.plist from the current configuration.
./scripts/make-export-options.sh \
  --method "$EXPORT_METHOD" \
  --team-id "$TEAM_ID" \
  --bundle-id "$BUNDLE_ID" \
  --profile-name "$PROFILE_NAME" \
  --output build/ExportOptions.plist

set -o pipefail
xcodebuild archive \
  -project IPTVRadio.xcodeproj \
  -scheme IPTVRadio \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/IPTVRadio.xcarchive \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
  | tee build/logs/xcodebuild-archive.log

rm -rf build/export
xcodebuild -exportArchive \
  -archivePath build/IPTVRadio.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  | tee build/logs/xcodebuild-export.log

IPA=$(find build/export -name "*.ipa" | head -n 1)
if [ -z "$IPA" ]; then
  echo "::error::IPA export produced no .ipa file. Check codesigning and the profile's bundle ID." >&2
  exit 1
fi
echo "Exported $IPA"
