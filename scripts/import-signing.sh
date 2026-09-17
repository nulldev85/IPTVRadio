#!/usr/bin/env bash
# Imports the distribution certificate into a temporary keychain and installs
# the provisioning profile. All inputs come from GitHub Actions secrets.
#
# Usage: import-signing.sh --team-id TEAM --profile-name NAME [--certificate-identity IDENT]
set -euo pipefail

TEAM_ID=""
PROFILE_NAME=""
CERT_IDENTITY="Apple Distribution"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team-id) TEAM_ID="$2"; shift 2 ;;
    --profile-name) PROFILE_NAME="$2"; shift 2 ;;
    --certificate-identity) CERT_IDENTITY="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "${APPLE_CERT_P12_BASE64:-}" ] || [ -z "${APPLE_CERT_P12_PASSWORD:-}" ]; then
  echo "APPLE_CERT_P12_BASE64 / APPLE_CERT_P12_PASSWORD secrets are not set" >&2
  exit 1
fi
if [ -z "${APPLE_PROVISIONING_PROFILE_BASE64:-}" ]; then
  echo "APPLE_PROVISIONING_PROFILE_BASE64 secret is not set" >&2
  exit 1
fi
if [ -z "$TEAM_ID" ] || [ -z "$PROFILE_NAME" ]; then
  echo "Team ID and provisioning profile name are required" >&2
  exit 1
fi

CERT_PATH="$RUNNER_TEMP/dist-cert.p12"
PROFILE_PATH="$RUNNER_TEMP/profile.mobileprovision"
KEYCHAIN_PATH="$RUNNER_TEMP/iptvradio-signing.keychain-db"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-$(openssl rand -hex 24)}"

# Never echo the secrets themselves.
printf '%s' "$APPLE_CERT_P12_BASE64" | base64 --decode > "$CERT_PATH"
printf '%s' "$APPLE_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -P "$APPLE_CERT_P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychain -d user -s "$KEYCHAIN_PATH" "$(security default-keychain | awk -F'[\" ]+' '{print $2}' || true)"

PROFILE_UUID=$(security cms -D -i "$PROFILE_PATH" 2>/dev/null | plutil -extract UUID raw -o - - || true)
if [ -z "$PROFILE_UUID" ]; then
  echo "Could not read UUID from provisioning profile" >&2
  exit 1
fi

PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
cp "$PROFILE_PATH" "$PROFILE_DIR/$PROFILE_UUID.mobileprovision"

rm -f "$CERT_PATH"
echo "::add-mask::$TEAM_ID"
echo "Signing certificate imported into temporary keychain; profile $PROFILE_NAME installed."
