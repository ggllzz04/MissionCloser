#!/bin/zsh
# 构建 MissionCloser.app（通用二进制，macOS 13+），只需要 Xcode Command Line Tools。
# 用法：scripts/build.sh            构建到 build/MissionCloser.app
#       scripts/build.sh --zip      额外打包 build/MissionCloser.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/MissionCloser.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/tmp

# 图标
if [[ ! -f Resources/AppIcon.icns ]]; then
    swift scripts/make-icon.swift build/tmp
    iconutil -c icns build/tmp/AppIcon.iconset -o Resources/AppIcon.icns
fi

# 编译 arm64 + x86_64 并合并
for arch in arm64 x86_64; do
    swiftc -O -target $arch-apple-macos13.0 Sources/*.swift -o build/tmp/MissionCloser-$arch
done
lipo -create build/tmp/MissionCloser-arm64 build/tmp/MissionCloser-x86_64 -output "$APP/Contents/MacOS/MissionCloser"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
rm -rf build/tmp
echo "✅ $PWD/$APP"

if [[ "${1:-}" == "--zip" ]]; then
    ditto -c -k --keepParent "$APP" build/MissionCloser.zip
    echo "📦 $PWD/build/MissionCloser.zip"
fi
