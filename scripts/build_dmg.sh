#!/bin/bash
set -euo pipefail

DMG_PATH="Build/DNSChanger.dmg"
APP_PATH="Build/DNSChanger.app"

mkdir -p Build

/usr/bin/hdiutil create -volname "DNSChanger" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

echo "DMG built at $DMG_PATH"
