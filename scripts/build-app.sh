#!/usr/bin/env bash
# Chiikawa_in_myMac.app 번들을 만든다. (macOS 전용)
#
#   ./scripts/build-app.sh            # build/Chiikawa_in_myMac.app 생성
#   ./scripts/build-app.sh --install  # /Applications 에 복사까지
#   UNIVERSAL=1 ./scripts/build-app.sh # Apple Silicon + Intel 유니버설 바이너리
#
# ad-hoc 서명이라 다른 Mac 에서 처음 열 때는 Gatekeeper 가 막는다.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_ARGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}" --product Chiikawa_in_myMac
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/Chiikawa_in_myMac"

APP="build/Chiikawa_in_myMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Chiikawa_in_myMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/MenuIcon.png "$APP/Contents/Resources/MenuIcon.png"
cp -R Resources/Pets "$APP/Contents/Resources/Pets"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
cp -R Resources/Voices "$APP/Contents/Resources/Voices"
codesign --force --sign - "$APP" >/dev/null
echo "✔ $APP"

if [ "${1:-}" = "--install" ]; then
  rm -rf "/Applications/Chiikawa_in_myMac.app"
  ditto "$APP" "/Applications/Chiikawa_in_myMac.app"
  echo "✔ /Applications/Chiikawa_in_myMac.app"
fi
