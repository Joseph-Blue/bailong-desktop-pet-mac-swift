#!/bin/zsh
set -eu
cd "${0:A:h:h}"
source scripts/terminal-ui.sh
if (( $# > 1 )); then
    print -u2 "用法：$0 [arm64|x86_64]"; exit 2
fi
source scripts/swift-sources.sh
target_arch="${1:-arm64}"
case "$target_arch" in
    arm64|x86_64) ;;
    *) print -u2 "不支持的架构：$target_arch"; exit 2 ;;
esac
bailong_header "构建应用包" "$target_arch"
assets="local-assets/native-hevc/catalog"
[[ -f "$assets/素材清单.json" ]] || { print -u2 "缺少原生素材清单。请按 docs/开发资源获取.md 准备 local-assets/native-hevc/catalog。"; exit 1; }
version="$(<VERSION)"
output="dist/native-hevc/$version/$target_arch"
mkdir -p ".build/$target_arch" .build/module-cache "$output"
bailong_phase_begin "1/4" "编译主程序"
xcrun swiftc -O -whole-module-optimization -swift-version 5 -target "$target_arch-apple-macosx14.0" \
    -module-cache-path .build/module-cache $swift_sources \
    -o ".build/$target_arch/BailongPet" -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal -lsqlite3 > "$bailong_phase_log" 2>&1
bailong_phase_end
bailong_phase_begin "2/4" "编译跟随助手"
xcrun swiftc -O -swift-version 5 -target "$target_arch-apple-macosx14.0" \
    -module-cache-path .build/module-cache Sources/BailongPet/Infrastructure/FollowMonitor.swift Tools/FollowHelper/main.swift \
    -framework AppKit -o ".build/$target_arch/BailongFollow" > "$bailong_phase_log" 2>&1
bailong_phase_end

app="$output/白龙桌宠Swift.app"
staging="$(mktemp -d "$output/.pet-XXXXXX")"
bailong_phase_begin "3/4" "组装应用与资源"
{
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources/outputs/白龙桌宠素材"
cp ".build/$target_arch/BailongPet" "$staging/Contents/MacOS/BailongPet"
cp "$assets/素材清单.json" "$staging/Contents/Resources/outputs/白龙桌宠素材/"
cp -R "$assets/透明HEVC" "$staging/Contents/Resources/outputs/白龙桌宠素材/"
for resource in sounds BailongPet.icns glass-symbols openai-logo.png; do
    cp -R "local-assets/$resource" "$staging/Contents/Resources/"
done
cp VERSION "$staging/Contents/Resources/VERSION"
cat > "$staging/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.appkit</string>
<key>CFBundleName</key><string>白龙桌宠Swift</string>
<key>CFBundleDisplayName</key><string>白龙桌宠Swift</string>
<key>CFBundleExecutable</key><string>BailongPet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${version%%-*}</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>BailongVersion</key><string>$version</string>
<key>BailongAuthor</key><string>Joseph Blue</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>点击本机文件链接时，恢复对应的访达窗口并选中文件。</string>
<key>CFBundleIconFile</key><string>BailongPet</string>
</dict></plist>
PLIST
helper="$staging/Contents/Library/Helpers/BailongFollow.app"
mkdir -p "$helper/Contents/MacOS"
cp ".build/$target_arch/BailongFollow" "$helper/Contents/MacOS/BailongFollow"
cat > "$helper/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.appkit.follow-helper</string>
<key>CFBundleName</key><string>白龙桌宠Swift跟随启动监测器</string>
<key>BailongAuthor</key><string>Joseph Blue</string>
<key>CFBundleExecutable</key><string>BailongFollow</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
} > "$bailong_phase_log" 2>&1
bailong_phase_end
bailong_phase_begin "4/4" "本地签名并保存应用"
{
codesign --force --sign - "$helper"
codesign --force --sign - "$staging"
# 输出目录按版本隔离，只组装原生运行资源。
if [[ -d "$app" ]]; then rm -rf "$app"; fi
mv "$staging" "$app"
} > "$bailong_phase_log" 2>&1
bailong_phase_end
print "构建完成 · 总用时 $((SECONDS-bailong_started)) 秒"
bailong_artifact "应用" "$app"
