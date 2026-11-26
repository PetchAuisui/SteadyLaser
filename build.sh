#!/bin/zsh
# Builds "build/Steady Laser.app" (release, ad-hoc signed).
#   ./build.sh            build only
#   ./build.sh --install  also copy to /Applications, turn on launch at login, and start it
set -euo pipefail
cd "${0:A:h}"

swift build -c release

APP="build/Steady Laser.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SteadyLaser "$APP/Contents/MacOS/SteadyLaser"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/Steady Laser.app"
  pkill -f "Steady Laser.app/Contents/MacOS/SteadyLaser" || true
  sleep 0.5
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  "$DEST/Contents/MacOS/SteadyLaser" --login-item on || true
  open "$DEST"
  echo "Installed: $DEST"
fi
