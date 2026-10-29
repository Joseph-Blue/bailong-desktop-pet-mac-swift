#!/bin/zsh
set -eu
cd "${0:A:h:h}"
if (( $# > 1 )); then
    print -u2 "用法：$0 [arm64|x86_64]"; exit 2
fi
target_arch="${1:-arm64}"
case "$target_arch" in
    arm64) decoder="local-assets/tools/ffmpeg" ;;
    x86_64) decoder="local-assets/tools/x86_64/ffmpeg" ;;
    *) print -u2 "不支持的架构：$target_arch"; exit 2 ;;
esac
# 两份应用各自携带对应架构的解码器，避免 Intel 包误装 arm64 二进制。
[[ -x "$decoder" ]] || { print -u2 "缺少 $target_arch 解码器：$decoder"; exit 1; }
xcrun lipo -verify_arch "$target_arch" "$decoder"
mkdir -p ".build/$target_arch" .build/module-cache "dist/$target_arch"
xcrun swiftc -O -whole-module-optimization -swift-version 5 -target "$target_arch-apple-macosx14.0" -module-cache-path .build/module-cache Sources/BailongPet/*.swift -o ".build/$target_arch/BailongPet" -framework AppKit -lsqlite3
app="dist/$target_arch/白龙娘桌宠MacOS-Swift版.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/tools"
cp ".build/$target_arch/BailongPet" "$app/Contents/MacOS/BailongPet"
# 仅打包运行资源；素材试修、源码副本和离线脚本不进入应用包。
for resource in outputs sounds BailongPet.icns; do
    cp -R "local-assets/$resource" "$app/Contents/Resources/"
done
cp "$decoder" "$app/Contents/Resources/tools/ffmpeg"
cp VERSION "$app/Contents/Resources/VERSION"
version="$(cat VERSION)"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.appkit</string>
<key>CFBundleName</key><string>白龙娘桌宠MacOS-Swift版</string>
<key>CFBundleDisplayName</key><string>白龙娘桌宠MacOS-Swift版</string>
<key>CFBundleExecutable</key><string>BailongPet</string>
<key>CFBundleShortVersionString</key><string>${version%%-*}</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>BailongVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>BailongPet</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
print "已构建 $app（$version，$target_arch，本地签名）"
