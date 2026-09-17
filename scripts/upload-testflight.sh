#!/usr/bin/env bash
# Optional: uploads an IPA to TestFlight using an App Store Connect API key.
# Requires the API key secrets to be set; otherwise exits without error.
set -euo pipefail

IPA="$1"
KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-}"
ISSUER_ID="${APP_STORE_CONNECT_API_ISSUER_ID:-}"
KEY_P8_BASE64="${APP_STORE_CONNECT_API_KEY_P8_BASE64:-}"

if [ -z "$KEY_ID" ] || [ -z "$ISSUER_ID" ] || [ -z "$KEY_P8_BASE64" ]; then
  echo "TestFlight secrets not configured; skipping upload."
  exit 0
fi

KEY_DIR="$RUNNER_TEMP/private_keys"
mkdir -p "$KEY_DIR"
printf '%s' "$KEY_P8_BASE64" | base64 --decode > "$KEY_DIR/AuthKey_${KEY_ID}.p8"

cd "$RUNNER_TEMP"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID" \
  | tee "$GITHUB_WORKSPACE/build/logs/testflight-upload.log"
rm -f "$KEY_DIR/AuthKey_${KEY_ID}.p8"
