#!/bin/zsh
set -eu
cd "${0:A:h:h}"
(( $# == 0 )) || { print -u2 "用法：$0"; exit 2; }
host_arch="$(uname -m)"
case "$host_arch" in
    arm64) encoder="local-assets/tools/ffmpeg" ;;
    x86_64) encoder="local-assets/tools/x86_64/ffmpeg" ;;
    *) print -u2 "不支持的构建主机：$host_arch"; exit 2 ;;
esac
[[ -x "$encoder" ]] || { print -u2 "缺少构建时转码器：$encoder"; exit 1; }
xcrun lipo -verify_arch "$host_arch" "$encoder"
mkdir -p .build/native-hevc/module-cache local-assets/native-hevc
xcrun swiftc -O -swift-version 5 -parse-as-library \
    -target "$host_arch-apple-macosx14.0" -module-cache-path .build/native-hevc/module-cache \
    Tools/NativeHEVC/AssetInfo.swift -framework AVFoundation -o .build/native-hevc/PrepareNativeSamples
.build/native-hevc/PrepareNativeSamples \
    "local-assets/outputs/白龙桌宠素材" "$encoder" "local-assets/native-hevc/catalog" "$(<VERSION)" --catalog
