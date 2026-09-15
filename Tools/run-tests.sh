#!/bin/bash
# Runs KohiTests on iOS 18.2 and (when asked) iOS 26.2.
# Usage:
#   Tools/run-tests.sh              # iOS 18.2
#   Tools/run-tests.sh 26            # iOS 26.2
#   Tools/run-tests.sh both         # both runtimes
#   Tools/run-tests.sh 18 RecipeScalingTests  # filter
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$(dirname "$0")/.."

DEST_18="platform=iOS Simulator,name=iPhone 16,OS=18.2"
DEST_26="platform=iOS Simulator,name=iPhone 16,OS=26.2"

run_one() {
  local dest="$1"
  shift
  local extra=()
  if [ -n "$1" ]; then extra=(-only-testing "KohiTests/$1"); fi
  echo "=== test $dest ${1:-all} ==="
  xcodebuild -scheme Kohi \
    -destination "$dest" \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    test "${extra[@]}"
}

case "${1:-18}" in
  18|18.2)
    run_one "$DEST_18" "$2"
    ;;
  26|26.2)
    run_one "$DEST_26" "$2"
    ;;
  both)
    run_one "$DEST_18" "$2" && run_one "$DEST_26" "$2"
    ;;
  *)
    # Treat first arg as a test filter on 18.2
    run_one "$DEST_18" "$1"
    ;;
esac
