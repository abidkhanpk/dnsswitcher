#!/bin/bash
set -euo pipefail

if [[ -z "${APPLE_ID:-}" || -z "${APP_SPECIFIC_PASSWORD:-}" || -z "${TEAM_ID:-}" ]]; then
  echo "Apple notarization credentials not set; skipping notarization."
  exit 0
fi

xcrun notarytool submit Build/DNSChanger.pkg \
  --apple-id "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

xcrun notarytool submit Build/DNSChanger.dmg \
  --apple-id "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

echo "Notarization submitted and completed for PKG and DMG."
