#!/usr/bin/env bash
# Runs the ScanLabKit test suite. Works with Xcode or with Command Line Tools only
# (CLT ships Testing.framework outside the default search path).
set -euo pipefail
cd "$(dirname "$0")/../Packages/ScanLabKit"
FLAGS=()
CLT_FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if [[ "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
  # CLT ships _Testing_Foundation without a module interface; skip cross-import overlays.
  FLAGS=(-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays -Xswiftc -F"$CLT_FW" -Xlinker -F"$CLT_FW" -Xlinker -rpath -Xlinker "$CLT_FW")
fi
swift test "${FLAGS[@]}" "$@"
