#!/bin/bash
set -euo pipefail

APP_PATH="Build/DNSChanger.app"
PKG_PATH="Build/DNSChanger.pkg"

mkdir -p Build

/usr/bin/pkgbuild --install-location "/Applications" --component "$APP_PATH" "$PKG_PATH"

echo "PKG built at $PKG_PATH"
