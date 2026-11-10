# 资源清单、下载和导入共用于 App 与开发入口。
typeset -g bailong_resource_manifest="scripts/resource-manifest.json"
typeset -g bailong_resource_tool=".build/resource-tools/BuildResources"
bailong_prepare_resource_tool() {
    bailong_check_output .build/resource-tools
    mkdir -p .build/module-cache
    if [[ ! -x "$bailong_resource_tool" || Tools/BuildResources/main.swift -nt "$bailong_resource_tool" ||
          ! -f .build/resource-tools/environment.txt || "$(<.build/resource-tools/environment.txt)" != "$bailong_build_environment" ]]; then
        bailong_phase_begin "准备" "编译资源检查工具"
        bailong_compile "$bailong_swiftc" -sdk "$bailong_sdk_path" -O -swift-version 5 \
            -module-cache-path .build/module-cache Tools/BuildResources/main.swift -o "$bailong_resource_tool.next"
        mv "$bailong_resource_tool.next" "$bailong_resource_tool"
        print -r -- "$bailong_build_environment" > .build/resource-tools/environment.txt
        bailong_phase_end
    fi
    local info
    info="$("$bailong_resource_tool" info "$bailong_resource_manifest")"
    local -a fields=("${(@f)info}")
    bailong_resource_version="$fields[1]"; bailong_resource_archive="$fields[2]"
    bailong_resource_published="$fields[3]"; bailong_resource_url="$fields[4]"; bailong_resource_bytes="$fields[5]"
}
bailong_resource_source() {
    print -r -- "素材来源：jingh12312-rgb 的《GPT白龙娘动态桌宠》"
    print -r -- "原作仓库：https://github.com/jingh12312-rgb/bailong-desktop-pet"
    print -r -- "Mac 版素材由 Joseph Blue（约瑟Blue）整理，完整来源见包内 local-assets/资源来源.md。"
}
bailong_resource_download_info() {
    print -r -- "下载来源：本项目的 GitHub Release · 资源包 $bailong_resource_version"
    print -r -- "资源包：$bailong_resource_archive · 约 $((bailong_resource_bytes/1048576)) MiB"
    print -r -- "下载地址：$bailong_resource_url"
    print -r -- "请确认终端可以访问 GitHub，并检查终端代理设置和所用节点是否可用。"
}
bailong_resource_manual_commands() {
    local entry="${bailong_entry_command:-build.command}" arch="${target_arch:-arm64}"
    print -r -- "手动下载命令："
    print -r -- "  curl --fail --location --output ${(q)bailong_resource_archive} ${(q)bailong_resource_url}"
    print -r -- "下载后导入并继续："
    print -r -- "  ./$entry $arch --resources-zip ${(q)bailong_resource_archive}"
}
bailong_download_resources() {
    setopt localoptions nobgnice
    if [[ "$bailong_resource_published" != yes ]]; then
        bailong_error "资源包 $bailong_resource_version 尚未发布。请选择本地 ZIP。"
        return 1
    fi
    (( bailong_resource_bytes > 0 )) || { bailong_error "资源清单缺少下载大小。"; return 1; }
    mkdir -p .build/downloads
    bailong_download_zip="$PWD/.build/downloads/$bailong_resource_archive"
    local partial="$bailong_download_zip.partial" result bytes=0 previous=0 elapsed=0 rate=0 line
    local -i began=$SECONDS previous_time=$SECONDS last_print=-5
    bailong_phase_begin "资源" "下载资源包"
    bailong_stop_spinner
    # 只使用 HTTPS；不改代理设置。失败保留 curl 原始错误。
    curl --fail --location --proto '=https' --proto-redir '=https' --silent --show-error \
        --connect-timeout 20 --speed-time 60 --speed-limit 1 \
        --output "$partial" "$bailong_resource_url" > "$bailong_phase_log" 2>&1 &
    bailong_download_pid=$!
    while kill -0 "$bailong_download_pid" 2>/dev/null; do
        [[ ! -f "$partial" ]] || bytes="$(stat -f '%z' "$partial")"
        elapsed=$((SECONDS-began))
        if (( SECONDS > previous_time )); then
            rate=$(((bytes-previous)/(SECONDS-previous_time)))
            previous=$bytes; previous_time=$SECONDS
        fi
        if (( bailong_animated || elapsed-last_print >= 5 )); then
            line="$(awk -v b="$bytes" -v total="$bailong_resource_bytes" -v speed="$rate" 'BEGIN {
                p=b*100/total; if(p>99.9)p=99.9; n=int(p/5); bar="";
                for(i=0;i<20;i++)bar=bar (i<n?"━":"─");
                printf "[%s] %5.1f%%  %.1f / %.1f MiB  %.1f MiB/s",bar,p,b/1048576,total/1048576,speed/1048576
            }')"
            if (( bailong_animated )); then printf '\r\033[2K%s' "$line" >&$bailong_ui_fd
            else print -ru "$bailong_ui_fd" -- "$line"; fi
            last_print=$elapsed
        fi
        sleep 1
    done
    if wait "$bailong_download_pid"; then result=0; else result=$?; fi
    bailong_download_pid=""
    (( ! bailong_animated )) || print -u "$bailong_ui_fd"
    if (( result != 0 )); then
        bailong_phase_finish "✗" "下载失败（退出码 $result）"
        print -r -- "请检查终端网络、代理设置和节点后重试。"
        bailong_resource_manual_commands
        return "$result"
    fi
    bytes="$(stat -f '%z' "$partial")"
    if (( bytes != bailong_resource_bytes )); then
        print -r -- "下载大小不符：$bytes / $bailong_resource_bytes 字节" >> "$bailong_phase_log"
        bailong_phase_finish "✗" "下载失败"
        return 1
    fi
    mv "$partial" "$bailong_download_zip"
    elapsed=$((SECONDS-began)); (( elapsed > 0 )) || elapsed=1
    awk -v b="$bytes" -v t="$elapsed" 'BEGIN {printf "[━━━━━━━━━━━━━━━━━━━━] 100.0%%  %.1f / %.1f MiB  平均 %.1f MiB/s\n",b/1048576,b/1048576,b/t/1048576}' >&$bailong_ui_fd
    bailong_phase_end
}
bailong_import_resources() {
    local archive="${1:A}" mode="$2"
    [[ -f "$archive" ]] || { bailong_error "找不到 ZIP：$archive"; return 1; }
    bailong_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/bailong-import-XXXXXX")"
    bailong_phase_begin "资源" "检查并导入资源"
    # 系统 bsdtar 默认拒绝上级路径及通过符号链接向解压目录外写入。
    if ! /usr/bin/tar -xf "$archive" -C "$bailong_temp_dir" --no-same-owner > "$bailong_phase_log" 2>&1; then
        bailong_phase_finish "✗" "ZIP 解压失败"
        rm -rf "$bailong_temp_dir"; bailong_temp_dir=""
        return 1
    fi
    if ! "$bailong_resource_tool" import "$bailong_resource_manifest" "$bailong_temp_dir/local-assets" "$PWD/local-assets" "$mode" >> "$bailong_phase_log" 2>&1; then
        bailong_phase_finish "✗" "资源导入失败"
        rm -rf "$bailong_temp_dir"; bailong_temp_dir=""
        return 1
    fi
    rm -rf "$bailong_temp_dir"; bailong_temp_dir=""
    bailong_phase_end
}
bailong_ensure_resources() {
    local zip="$1" mode="$2" download="$3" report
    bailong_resource_source
    bailong_prepare_resource_tool
    if [[ "$download" == 1 ]]; then
        bailong_resource_download_info
        bailong_download_resources || return $?
        zip="$bailong_download_zip"
    fi
    if [[ -n "$zip" ]]; then bailong_import_resources "$zip" "$mode" || return $?; fi
    if report="$("$bailong_resource_tool" check "$bailong_resource_manifest" local-assets 2>&1)"; then
        bailong_ok "$report"; return 0
    fi
    bailong_error "资源不完整"
    print -r -- "$report"
    if [[ "$bailong_resource_published" != yes ]]; then
        print -r -- "资源包尚未发布，请准备本地 ZIP 后导入："
        print -r -- "  ./${bailong_entry_command:-build.command} ${target_arch:-arm64} --resources-zip /路径/${(q)bailong_resource_archive}"
        return 1
    fi
    if ! bailong_interactive || [[ "${bailong_check_only:-0}" == 1 ]]; then
        bailong_resource_download_info
        bailong_resource_manual_commands
        return 1
    fi
    bailong_resource_download_info
    print -r -- "下载后只补齐缺失文件，已有同名素材保留。"
    if ! bailong_confirm "现在下载并补齐素材吗？"; then
        bailong_resource_manual_commands
        return 1
    fi
    bailong_download_resources || return $?
    bailong_import_resources "$bailong_download_zip" "$mode" || return $?
    if report="$("$bailong_resource_tool" check "$bailong_resource_manifest" local-assets 2>&1)"; then
        bailong_ok "$report"; return 0
    fi
    bailong_error "$report"
    print -r -- "更新同名素材并继续（替换前会备份）："
    print -r -- "  ./${bailong_entry_command:-build.command} ${target_arch:-arm64} --resources-zip ${(q)bailong_download_zip} --replace-resources"
    return 1
}
