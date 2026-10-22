#!/bin/zsh
# Builds BatteryMeter.app. Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/BatteryMeter.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/BatteryMeter"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x BatteryMeter || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/BatteryMeter.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/BatteryMeter.app
  echo "Installed to ~/Applications/BatteryMeter.app"
fi
