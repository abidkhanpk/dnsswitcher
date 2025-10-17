#!/usr/bin/env bash
set -euo pipefail

# Install the DNSChangerHelper as a root LaunchDaemon without SMJobBless.
# This script will:
# 1) Build the DNSChangerHelper binary (Release)
# 2) Copy it to /Library/PrivilegedHelperTools/com.pacman.DNSChangerHelper
# 3) Install a LaunchDaemon plist at /Library/LaunchDaemons/com.pacman.DNSChangerHelper.plist
# 4) Bootstrap and start the daemon (Mach service: com.pacman.DNSChangerHelper.mach)

PROJECT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
BUILD_DIR="${PROJECT_DIR}/DerivedDataManual"
PLIST_TMP="/tmp/com.pacman.DNSChangerHelper.plist"
DAEMON_PLIST="/Library/LaunchDaemons/com.pacman.DNSChangerHelper.plist"
HELPER_DST="/Library/PrivilegedHelperTools/com.pacman.DNSChangerHelper"
LABEL="com.pacman.DNSChangerHelper"
MACH="com.pacman.DNSChangerHelper.mach"

echo "[1/6] Building DNSChangerHelper (Release)"
/usr/bin/xcodebuild \
  -project "${PROJECT_DIR}/XcodeProject/DNSChanger.xcodeproj" \
  -target DNSChangerHelper \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build >/dev/null

BIN="${BUILD_DIR}/Build/Products/Release/DNSChangerHelper"
if [[ ! -x "${BIN}" ]]; then
  echo "ERROR: Built helper not found at ${BIN}" >&2
  exit 1
fi

echo "[2/6] Installing helper to ${HELPER_DST}"
sudo /bin/mkdir -p "/Library/PrivilegedHelperTools"
sudo /bin/cp -f "${BIN}" "${HELPER_DST}"
sudo /usr/sbin/chown root:wheel "${HELPER_DST}"
sudo /bin/chmod 755 "${HELPER_DST}"
sudo /usr/bin/xattr -dr com.apple.quarantine "${HELPER_DST}" || true

cat >"${PLIST_TMP}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${HELPER_DST}</string>
  </array>
  <key>MachServices</key>
  <dict>
    <key>${MACH}</key>
    <true/>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/${LABEL}.out.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/${LABEL}.err.log</string>
</dict>
</plist>
PLIST

echo "[3/6] Installing LaunchDaemon plist to ${DAEMON_PLIST}"
sudo /bin/mv -f "${PLIST_TMP}" "${DAEMON_PLIST}"
sudo /usr/sbin/chown root:wheel "${DAEMON_PLIST}"
sudo /bin/chmod 644 "${DAEMON_PLIST}"

echo "[4/6] Unloading existing daemon (if any)"
sudo /bin/launchctl bootout system/${LABEL} >/dev/null 2>&1 || true

echo "[5/6] Bootstrapping daemon"
sudo /bin/launchctl bootstrap system "${DAEMON_PLIST}"

echo "[6/6] Starting daemon"
sudo /bin/launchctl kickstart -k system/${LABEL}

sleep 1

echo "--- LaunchCtl Status ---"
sudo /bin/launchctl print system/${LABEL} | /usr/bin/head -n 80 || true

echo "\nInstallation complete. The helper Mach service '${MACH}' should now be available system-wide."
