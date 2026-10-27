#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/update-device.sh [--device UDID] [--no-launch]

Build, sign, and update Groundwork on a paired iPhone over USB or Wi-Fi.
Specify a device with --device or DEVICE_UDID.
Set DEVELOPER_DIR to use a different Xcode installation.
Build output: output/device-build.log
EOF
}

DEVICE_UDID="${DEVICE_UDID:-}"
launch=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo 'Error: --device requires a device identifier.' >&2
        exit 2
      fi
      DEVICE_UDID="$2"
      shift 2
      ;;
    --no-launch) launch=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$DEVICE_UDID" ]]; then
  echo 'Error: specify a device identifier with --device or DEVICE_UDID.' >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo 'Error: full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 1
fi

DERIVED_DATA="$ROOT/output/DeviceDerivedData"
BUILD_LOG="$ROOT/output/device-build.log"
APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/Groundwork.app"
mkdir -p "$ROOT/output"

echo "Checking device ${DEVICE_UDID}..."
xcrun devicectl --timeout 30 device info details --device "$DEVICE_UDID"
echo "Building Groundwork. Log: $BUILD_LOG"
echo 'If macOS asks, authorize codesign to use your development certificate.'
if ! xcodebuild -project "$ROOT/Groundwork.xcodeproj" -scheme Groundwork \
  -configuration Debug -destination "platform=iOS,id=$DEVICE_UDID" \
  -destination-timeout 30 -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates ONLY_ACTIVE_ARCH=YES build >"$BUILD_LOG" 2>&1; then
  tail -n 60 "$BUILD_LOG" >&2
  echo "Build failed. Full log: $BUILD_LOG" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo 'Installing update...'
xcrun devicectl --timeout 120 device install app --device "$DEVICE_UDID" "$APP"
if "$launch"; then
  echo 'Launching Groundwork...'
  xcrun devicectl --timeout 30 device process launch --device "$DEVICE_UDID" "$BUNDLE_ID"
fi
echo 'Groundwork update complete.'
