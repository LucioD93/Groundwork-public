#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/run-simulator.sh [--device UDID] [--no-open]

Build, install, and launch Groundwork in the iPhone simulator.
Specify a simulator with --device or SIMULATOR_UDID.
--no-open skips opening the simulator display (the app still launches).
Set DEVELOPER_DIR to use another Xcode installation.
Build output: output/simulator-build.log
EOF
}

SIMULATOR_UDID="${SIMULATOR_UDID:-}"
open_display=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo 'Error: --device requires a simulator identifier.' >&2
        exit 2
      fi
      SIMULATOR_UDID="$2"
      shift 2
      ;;
    --no-open) open_display=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$SIMULATOR_UDID" ]]; then
  echo 'Error: specify a simulator identifier with --device or SIMULATOR_UDID.' >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo 'Error: full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory.' >&2
  exit 1
fi

DERIVED_DATA="$ROOT/output/SimulatorDerivedData"
BUILD_LOG="$ROOT/output/simulator-build.log"
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Groundwork.app"
mkdir -p "$ROOT/output"

echo "Booting simulator ${SIMULATOR_UDID}..."
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
echo "Building Groundwork. Log: $BUILD_LOG"
if ! xcodebuild -project "$ROOT/Groundwork.xcodeproj" -scheme Groundwork \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -destination-timeout 30 -derivedDataPath "$DERIVED_DATA" \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build >"$BUILD_LOG" 2>&1; then
  tail -n 60 "$BUILD_LOG" >&2
  echo "Build failed. Full log: $BUILD_LOG" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
xcrun simctl install "$SIMULATOR_UDID" "$APP"
xcrun simctl launch --terminate-running-process "$SIMULATOR_UDID" "$BUNDLE_ID"
if "$open_display"; then
  if ! open "devices://device/open?id=${SIMULATOR_UDID}"; then
    echo 'Could not open Device Hub; opening Simulator instead.' >&2
    open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_UDID"
  fi
fi
echo 'Groundwork is running in the simulator.'
