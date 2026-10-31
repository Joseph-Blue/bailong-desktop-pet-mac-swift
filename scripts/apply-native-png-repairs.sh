#!/bin/zsh
set -eu
cd "${0:A:h:h}"
(( $# == 1 || $# == 2 )) || { print -u2 "用法：$0 <修复 PNG 根目录> [--landing]"; exit 2; }
[[ "${2:-}" == "" || "$2" == "--landing" ]] || { print -u2 "不支持的选项：$2"; exit 2; }
repair_args=()
[[ "${2:-}" != "--landing" ]] || repair_args=(--landing)
frames="${1:A}"
host_arch="$(uname -m)"
version="$(<VERSION)"
catalog="local-assets/native-hevc/catalog"
output="local-assets/native-hevc/catalog-png-$version"
backup="local-assets/native-hevc/catalog-before-png-$version"
[[ -f "$catalog/素材清单.json" ]] || { print -u2 "请先准备完整原生素材目录。"; exit 1; }
[[ ! -e "$backup" && ! -e "$output" ]] || { print -u2 "本版本的备份或输出已存在，请检查后再操作。"; exit 1; }
mkdir -p .build/native-hevc/module-cache
xcrun swiftc -O -swift-version 5 -parse-as-library \
    -target "$host_arch-apple-macosx14.0" -module-cache-path .build/native-hevc/module-cache \
    Tools/NativeHEVC/ApplyPNGRepairs.swift -framework AVFoundation -framework CoreImage -o .build/native-hevc/ApplyPNGRepairs
.build/native-hevc/ApplyPNGRepairs "$catalog" "$frames" "$output" "$version" "${repair_args[@]}"
# 仅成功转码后切换当前目录；原生旧素材完整保留。
mv "$catalog" "$backup"
if ! mv "$output" "$catalog"; then
    mv "$backup" "$catalog"
    exit 1
fi
print "已启用修复素材；旧目录保留在 $backup"
