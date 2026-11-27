#!/bin/zsh
# Builds "build/Steady Laser.app" (release, ad-hoc signed).
#   ./build.sh            build only
#   ./build.sh --install  also copy to /Applications, turn on launch at login, and start it
#   ./build.sh --icon     redraw the app icon into Resources/AppIcon.icns
set -euo pipefail
cd "${0:A:h}"

swift build -c release

if [[ "${1:-}" == "--icon" ]]; then
  TMP=$(mktemp -d)
  ICONSET="$TMP/AppIcon.iconset"
  mkdir -p "$ICONSET"
  .build/release/SteadyLaser --render-icon "$TMP/icon.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
  rm -rf "$TMP"
  echo "Icon: $PWD/Resources/AppIcon.icns"
  exit 0
fi

APP="build/Steady Laser.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SteadyLaser "$APP/Contents/MacOS/SteadyLaser"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
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
