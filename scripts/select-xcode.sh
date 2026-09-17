#!/usr/bin/env bash
# Selects the newest suitable Xcode installed on the runner.
# Preference order: latest stable major release available.
set -euo pipefail

candidates=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V -r)
if [ -z "$candidates" ]; then
  echo "No Xcode installations found in /Applications" >&2
  exit 1
fi

selected=""
for app in $candidates; do
  version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist" 2>/dev/null || echo 0)
  major=${version%%.*}
  if [ "$major" -ge 16 ]; then
    selected="$app"
    break
  fi
done

if [ -z "$selected" ]; then
  selected=$(echo "$candidates" | head -n 1)
fi

echo "Selecting $selected"
sudo xcode-select -s "$selected/Contents/Developer"
xcodebuild -version
