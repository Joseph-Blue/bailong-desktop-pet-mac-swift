#!/bin/zsh
set -eu
cd "${0:A:h:h}"

if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--reuse-assets" ]]; }; then
    print -u2 "用法：$0 [--reuse-assets]"; exit 2
fi

host_arch="$(uname -m)"
case "$host_arch" in
    arm64) encoder="local-assets/tools/ffmpeg" ;;
    x86_64) encoder="local-assets/tools/x86_64/ffmpeg" ;;
    *) print -u2 "不支持的构建主机：$host_arch"; exit 2 ;;
esac
workspace=".build/native-hevc"
samples="local-assets/native-hevc/samples"
mkdir -p "$workspace/module-cache" local-assets/native-hevc

if [[ "${1:-}" != "--reuse-assets" ]]; then
    [[ -x "$encoder" ]] || { print -u2 "缺少构建时转码器：$encoder"; exit 1; }
    xcrun lipo -verify_arch "$host_arch" "$encoder"
    xcrun swiftc -O -swift-version 5 -parse-as-library \
        -target "$host_arch-apple-macosx14.0" -module-cache-path "$workspace/module-cache" \
        Tools/NativeHEVC/AssetInfo.swift -framework AVFoundation \
        -o "$workspace/PrepareNativeSamples"
    "$workspace/PrepareNativeSamples" \
        "local-assets/outputs/白龙桌宠素材" "$encoder" "$samples"
else
    [[ -f "$samples/samples.json" ]] || { print -u2 "尚无已完成的素材，请先不带参数运行。"; exit 1; }
fi

# 预览与正式桌宠使用不同名称、包标识和输出目录；无 FFmpeg 运行依赖。
for target_arch in arm64 x86_64; do
    output="dist/native-hevc/$target_arch"
    mkdir -p "$output"
    app="$output/白龙娘原生动画预览.app"
    staging="$(mktemp -d "$output/.preview-XXXXXX")"
    mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
    xcrun swiftc -O -swift-version 5 -parse-as-library \
        -target "$target_arch-apple-macosx14.0" -module-cache-path "$workspace/module-cache" \
        Tools/NativeHEVC/Preview.swift -framework AppKit -framework AVFoundation \
        -o "$staging/Contents/MacOS/NativeHEVCPreview"
    cp -R "$samples" "$staging/Contents/Resources/samples"
    cp local-assets/BailongPet.icns "$staging/Contents/Resources/"
    cat > "$staging/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.native-hevc-preview</string>
<key>CFBundleName</key><string>白龙娘原生动画预览</string>
<key>CFBundleExecutable</key><string>NativeHEVCPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>BailongVersion</key><string>0.3.0-dev.1</string>
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
