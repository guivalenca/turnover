#!/bin/zsh
# Build the spike app (ad-hoc signed, with its Finder Sync extension) and the spikectl test driver.
#   ./build.sh            ad-hoc ("Sign to Run Locally", CODE_SIGN_IDENTITY=-)
#   ./build.sh team       free personal team instead (fallback path, not needed on macOS 27)
set -euo pipefail
cd "${0:A:h}"

xcodegen generate --quiet

signing=()
if [[ "${1:-}" == "team" ]]; then
  signing=(CODE_SIGN_IDENTITY="Apple Development" DEVELOPMENT_TEAM=CG55MLZF8K CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
fi

xcodebuild -project TurnoverSpike.xcodeproj -target TurnoverSpike -configuration Debug \
  SYMROOT="$PWD/build" "${signing[@]}" build | grep -E "error|warning: |BUILD" || true

app="$PWD/build/Debug/TurnoverSpike.app"
echo "--- signatures"
codesign -dv "$app" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier|Authority" || true
codesign -dv "$app/Contents/PlugIns/TurnoverSpikeFinder.appex" 2>&1 | grep -E "Identifier|Signature|TeamIdentifier|Authority" || true
codesign -d --entitlements - "$app/Contents/PlugIns/TurnoverSpikeFinder.appex" 2>/dev/null | tail -n +1
codesign --verify --deep --strict "$app" && echo "codesign --verify --deep --strict: OK"

swiftc -O tools/spikectl.swift -o build/spikectl
echo "built $app and build/spikectl"
