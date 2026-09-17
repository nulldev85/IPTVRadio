#!/usr/bin/env bash
# Removes all temporary signing material created during the workflow.
set -euo pipefail

KEYCHAIN_PATH="$RUNNER_TEMP/iptvradio-signing.keychain-db"

security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
if [ -d "$PROFILE_DIR" ]; then
  find "$PROFILE_DIR" -name "*.mobileprovision" -newer /tmp -mmin -120 -delete 2>/dev/null || true
fi
rm -f "$RUNNER_TEMP/dist-cert.p12" "$RUNNER_TEMP/profile.mobileprovision" 2>/dev/null || true
security list-keychains -s login.keychain-db 2>/dev/null || true
echo "Temporary signing material removed."
