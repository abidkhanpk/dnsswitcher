#!/bin/bash
set -euo pipefail

/usr/sbin/spctl --assess --type execute --verbose Build/DNSChanger.pkg || true
/usr/sbin/spctl --assess --type open --verbose Build/DNSChanger.dmg || true

echo "Gatekeeper assessment commands executed. Non-zero exit code can occur for unsigned/non-notarized artifacts during local testing."
