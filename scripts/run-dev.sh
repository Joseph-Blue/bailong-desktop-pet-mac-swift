#!/bin/zsh
set -eu
cd "${0:A:h:h}"

if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--build-only" ]]; }; then
    print -u2 "用法：$0 [--build-only]"
    exit 2
fi

source scripts/swift-sources.sh
binary=".build/dev/BailongPetDev"
mkdir -p .build/dev .build/module-cache
rebuild=0
[[ -x "$binary" ]] || rebuild=1
source_manifest="${(F)swift_sources}"
[[ -f .build/dev/sources.txt && "$(<.build/dev/sources.txt)" == "$source_manifest" ]] || rebuild=1
for source in $swift_sources VERSION scripts/swift-sources.sh "${0:A}"; do
    if [[ "$source" -nt "$binary" ]]; then rebuild=1; break; fi
done

if (( rebuild )); then
    print "正在编译开发版（不打包 .app）…"
    version="$(<VERSION)"
    # 将应用身份与系统语言设置嵌入可执行文件，直接运行也使用原生框架本地化。
    cat > .build/dev/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.appkit</string>
<key>CFBundleName</key><string>白龙桌宠Swift（开发）</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>点击本机文件链接时，恢复对应的访达窗口并选中文件。</string>
</dict></plist>
PLIST
    xcrun swiftc -O -whole-module-optimization -swift-version 5 \
        -target arm64-apple-macosx14.0 -module-cache-path .build/module-cache \
        $swift_sources -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal -lsqlite3 \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker .build/dev/Info.plist \
        -o "$binary.next"
    mv "$binary.next" "$binary"
    print -r -- "$source_manifest" > .build/dev/sources.txt
else
    print "源码未变化，复用上次编译结果。"
fi

[[ "${1:-}" != "--build-only" ]] || exit 0
[[ -f "local-assets/native-hevc/catalog/素材清单.json" ]] || { print -u2 "请先按 README 准备 local-assets/native-hevc/catalog 原生素材。"; exit 1; }
print "前台运行中，按 Ctrl+C 退出。若已有桌宠在运行，请先从其菜单退出。"
export BAILONG_DEV_RUN=1
exec "$binary"
