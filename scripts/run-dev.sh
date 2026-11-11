#!/bin/zsh
set -eu
cd "${0:A:h:h}"
source scripts/terminal-ui.sh

source scripts/build-preflight.sh
source scripts/build-resources.sh
source scripts/build-options.sh
bailong_entry=dev; bailong_entry_command=run-dev.command
bailong_parse_options "$@"
bailong_header "开发程序" "$target_arch"
bailong_check_tools
source scripts/swift-sources.sh
(( ${#swift_sources} > 0 )) || { bailong_error "未找到 Swift 源码。请完整解压仓库。"; exit 1; }
source scripts/swift-environment.sh
bailong_show_build_environment
if (( ! bailong_build_only )); then
    bailong_ensure_resources "$bailong_resource_zip" "$bailong_resource_mode" "$bailong_download_requested"
fi
# 沿用 arm64 既有路径，Intel 缓存独立。
dev_dir=".build/dev"
[[ "$target_arch" != x86_64 ]] || dev_dir=".build/dev-x86_64"
binary="$dev_dir/BailongPetDev"
bailong_check_output "$dev_dir"
if (( bailong_check_only )); then bailong_ok "检查通过"; exit 0; fi
mkdir -p .build/module-cache
rebuild=0
[[ -x "$binary" ]] || rebuild=1
source_manifest="${(F)swift_sources}"
[[ -f "$dev_dir/sources.txt" && "$(<"$dev_dir/sources.txt")" == "$source_manifest" ]] || rebuild=1
[[ -f "$dev_dir/environment.txt" && "$(<"$dev_dir/environment.txt")" == "$bailong_build_environment" ]] || rebuild=1
for source in $swift_sources VERSION scripts/swift-sources.sh scripts/swift-environment.sh "${0:A}"; do
    if [[ "$source" -nt "$binary" ]]; then rebuild=1; break; fi
done

if (( rebuild )); then
    bailong_phase_begin "1/1" "编译开发程序"
    version="$(<VERSION)"
    # 将应用身份与系统语言设置嵌入可执行文件，直接运行也使用原生框架本地化。
    cat > "$dev_dir/Info.plist" <<PLIST
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
    bailong_compile "$bailong_swiftc" $bailong_sdk_flags -O -whole-module-optimization -swift-version 5 \
        -target "$target_arch-apple-macosx14.0" -module-cache-path .build/module-cache \
        $swift_sources -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal -lsqlite3 \
        -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$dev_dir/Info.plist" \
        -o "$binary.next"
    mv "$binary.next" "$binary"
    print -r -- "$source_manifest" > "$dev_dir/sources.txt"
    print -r -- "$bailong_build_environment" > "$dev_dir/environment.txt"
    bailong_phase_end
else
    print "源码与构建环境未变化，复用上次编译结果。"
fi

bailong_artifact "开发程序" "$binary"
if (( bailong_build_only )); then
    print "编译完成 · 总用时 $((SECONDS-bailong_started)) 秒"
    exit 0
fi
export BAILONG_DEV_RUN=1
# 保留父脚本处理 ^C；不再 exec 替换为应用，才能执行超时终止。
setopt nobgnice
"$binary" <&0 &
bailong_dev_pid=$!
bailong_exit_waited=1
print "开发程序已启动 · PID $bailong_dev_pid · 按 ^C 停止"
if wait "$bailong_dev_pid"; then
    bailong_ok "开发程序已退出 · PID $bailong_dev_pid"
    bailong_dev_pid=""
else
    dev_result=$?
    bailong_error "开发程序已退出 · PID $bailong_dev_pid · 退出码 $dev_result"
    bailong_dev_pid=""
    exit "$dev_result"
fi
