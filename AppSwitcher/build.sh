#!/bin/bash
# Builds Switcher.app. Needs only Xcode's command line tools: xcode-select --install
# Usage: ./build.sh            build into build/Switcher.app
#        ./build.sh --install  also copy to /Applications and open it
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Switcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit -framework ApplicationServices -framework ServiceManagement \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Switcher"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Switcher 2>/dev/null || true
  rm -rf /Applications/Switcher.app
  cp -R "$APP" /Applications/
  open /Applications/Switcher.app
  echo "Installed to /Applications and opened"
fi
