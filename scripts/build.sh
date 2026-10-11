#!/bin/zsh
# 构建 MissionCloser.app（通用二进制，macOS 13+），只需要 Xcode Command Line Tools。
# 用法：scripts/build.sh            构建到 build/MissionCloser.app
#       scripts/build.sh --dmg      额外打包安装镜像 build/MissionCloser.dmg
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

[[ "${1:-}" == "--dmg" ]] || exit 0

# 安装镜像：左边是应用，右边是「应用程序」快捷方式，拖过去即可安装
VOL=MissionCloser
rm -rf build/dmg && mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname "$VOL" -srcfolder build/dmg -fs HFS+ -format UDRW -ov build/rw.dmg
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen build/rw.dmg | awk -F'\t' '/\/Volumes\//{print $NF}')

# 窗口布局（需要 Finder，失败时只是少了布局，不影响安装）
osascript <<APPLESCRIPT || echo "⚠️  跳过 DMG 窗口布局"
tell application "Finder"
    tell disk "$VOL"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 800, 520}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set position of item "MissionCloser.app" of container window to {160, 180}
        set position of item "Applications" of container window to {440, 180}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# 卷图标（放在 Finder 布局之后，否则会被 Finder 丢掉）
cp Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || true
rm -rf "$MOUNT/.fseventsd"

sync
for i in 1 2 3 4 5; do hdiutil detach -quiet "$MOUNT" && break || sleep 2; done
hdiutil convert -quiet build/rw.dmg -format UDZO -imagekey zlib-level=9 -ov -o build/MissionCloser.dmg
rm -rf build/rw.dmg build/dmg
echo "💿 $PWD/build/MissionCloser.dmg"
