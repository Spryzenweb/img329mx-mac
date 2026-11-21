#!/bin/zsh
# IMG-329MX.app derler (arm64 + x86_64) ve build/ altına koyar.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/IMG-329MX.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$arch-apple-macos14.0" \
    Sources/*.swift -o "build/obj/IMG-329MX-$arch"
done
lipo -create build/obj/IMG-329MX-arm64 build/obj/IMG-329MX-x86_64 -output "$APP/Contents/MacOS/IMG-329MX"

cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/mouse.png ]] && cp Resources/mouse.png "$APP/Contents/Resources/mouse.png"

# Simge
if [[ -f Resources/icon-src.png ]]; then
  ICONSET=build/obj/AppIcon.iconset
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon-src.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d Resources/icon-src.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP"
echo "Hazır: $PWD/$APP"
