#!/bin/zsh
set -eu
cd "${0:A:h:h}"

(( $# == 0 )) || { print -u2 "用法：$0"; exit 2; }
workspace=".build/native-hevc"
samples="local-assets/native-hevc/catalog"
version="$(<VERSION)"
[[ -f "$samples/samples.json" ]] || { print -u2 "请先按 README 准备原生素材目录。"; exit 1; }
mkdir -p "$workspace/module-cache"

# 预览只复用原生素材，独立包标识，不读取桌宠数据。
for target_arch in arm64 x86_64; do
    output="dist/native-hevc/$version/$target_arch"
    mkdir -p "$output"
    app="$output/白龙娘原生动画预览.app"
    staging="$(mktemp -d "$output/.preview-XXXXXX")"
    mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
    xcrun swiftc -O -swift-version 5 -parse-as-library \
        -target "$target_arch-apple-macosx14.0" -module-cache-path "$workspace/module-cache" \
        Tools/NativeHEVC/Preview.swift -framework AppKit -framework AVFoundation \
        -o "$staging/Contents/MacOS/NativeHEVCPreview"
    mkdir -p "$staging/Contents/Resources/samples"
    cp "$samples/samples.json" "$staging/Contents/Resources/samples/"
    cp "$samples/透明HEVC/"*.mov "$staging/Contents/Resources/samples/"
    cp local-assets/BailongPet.icns "$staging/Contents/Resources/"
    cat > "$staging/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.native-hevc-preview</string>
<key>CFBundleName</key><string>白龙娘原生动画预览</string>
<key>CFBundleExecutable</key><string>NativeHEVCPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${version%%-*}</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>BailongVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>BailongPet</string>
</dict></plist>
PLIST
    codesign --force --sign - "$staging"
    # 只替换本脚本专用的预览包，不触及正式应用。
    if [[ -d "$app" ]]; then rm -rf "$app"; fi
    mv "$staging" "$app"
    print "已构建 $app（未自动启动）"
done
