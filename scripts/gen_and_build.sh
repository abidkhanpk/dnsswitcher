#!/usr/bin/env bash
set -euo pipefail

# This script generates the Xcode project and builds the app.
# - It uses XcodeGen with XcodeProject/project.yml.
# - It builds with xcodebuild using the DNSChanger scheme.
# - It disables code signing to avoid signing failures by default.
#
# Usage:
#   ./scripts/gen_and_build.sh            # build Release (default)
#   CONFIGURATION=Debug ./scripts/gen_and_build.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SPEC="$ROOT_DIR/XcodeProject/project.yml"
PROJECT_NAME="DNSChanger"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_ROOT="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
LOG_FILE="$BUILD_ROOT/build.log"

mkdir -p "$BUILD_ROOT"

# Ensure XcodeGen is installed
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "[info] xcodegen not found."
  if command -v brew >/dev/null 2>&1; then
    echo "[info] Installing xcodegen via Homebrew..."
    brew install xcodegen
  else
    echo "[error] Homebrew not found. Please install XcodeGen: https://github.com/yonaskolb/XcodeGen" >&2
    exit 1
  fi
fi

# Generate the Xcode project
if [ ! -f "$SPEC" ]; then
  echo "[error] Spec not found: $SPEC" >&2
  exit 1
fi

echo "[info] Generating Xcode project from $SPEC"
xcodegen generate --spec "$SPEC"

XCODEPROJ="$ROOT_DIR/XcodeProject/$PROJECT_NAME.xcodeproj"
if [ ! -d "$XCODEPROJ" ]; then
  echo "[error] Xcode project not generated at $XCODEPROJ" >&2
  echo "[hint] XcodeGen created: $(ls -1 "$ROOT_DIR"/*.xcodeproj 2>/dev/null || true) and $(ls -1 "$ROOT_DIR/XcodeProject"/*.xcodeproj 2>/dev/null || true)" >&2
  exit 1
fi

# Build the app
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$PROJECT_NAME.app"

echo "[info] Building scheme '$PROJECT_NAME' (configuration: $CONFIGURATION)"
set -o pipefail
xcodebuild \
  -project "$XCODEPROJ" \
  -scheme "$PROJECT_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  | tee "$LOG_FILE"

if [ ! -d "$APP_PATH" ]; then
  echo "[error] Build completed but app not found at: $APP_PATH" >&2
  echo "[hint] See log: $LOG_FILE" >&2
  exit 2
fi

echo "[success] Build succeeded. App path: $APP_PATH"
echo "[info] To run the app: open \"$APP_PATH\""
