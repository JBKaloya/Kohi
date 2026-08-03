#!/bin/bash
# Builds Kohi for the simulator and prints only warnings, errors and the result.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."
LOG=$(mktemp)
xcodebuild -scheme Kohi \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  build >"$LOG" 2>&1
STATUS=$?
grep -E "(error:|warning:)" "$LOG" | sed 's|/Users/jbkstudio/Documents/Kohi/||g' | sort -u
rm -f "$LOG"
if [ $STATUS -eq 0 ]; then echo "BUILD SUCCEEDED"; else echo "BUILD FAILED ($STATUS)"; fi
exit $STATUS
