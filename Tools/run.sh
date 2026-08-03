#!/bin/bash
# Builds, installs and launches Kohi on the booted simulator, then grabs a screenshot.
# Usage: Tools/run.sh [screenshot.png]
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
DEVICE=${KOHI_DEVICE:-2F4E4923-BEE2-4936-9CB9-AA938E11EF79}
SHOT=${1:-/tmp/kohi.png}
# Pass app env through with SIMCTL_CHILD_ prefixed variables, e.g.
#   SIMCTL_CHILD_KOHI_OPEN_FIRST=1 Tools/run.sh
LOG=$(mktemp)

xcodebuild -scheme Kohi -configuration Debug \
  -destination "id=$DEVICE" -quiet build >"$LOG" 2>&1
STATUS=$?
grep -E "(error:|warning:)" "$LOG" | sed 's|/Users/jbkstudio/Documents/Kohi/||g' | sort -u
rm -f "$LOG"
if [ $STATUS -ne 0 ]; then echo "BUILD FAILED ($STATUS)"; exit $STATUS; fi

APP=$(xcodebuild -scheme Kohi -configuration Debug -destination "id=$DEVICE" \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')/Kohi.app

xcrun simctl terminate "$DEVICE" studio.jbk.Kohi >/dev/null 2>&1
xcrun simctl install "$DEVICE" "$APP" || exit 1
xcrun simctl launch "$DEVICE" studio.jbk.Kohi || exit 1
sleep "${KOHI_SETTLE:-3}"
xcrun simctl io "$DEVICE" screenshot "$SHOT" >/dev/null 2>&1
echo "screenshot: $SHOT"
