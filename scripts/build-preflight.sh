# 由构建入口 source。
bailong_host_arch() {
    # Rosetta 终端仍选择实际 Apple Silicon 主机架构。
    if [[ "$(uname -m)" == arm64 ]] || [[ "$(/usr/sbin/sysctl -in hw.optional.arm64 2>/dev/null)" == 1 ]]; then
        print arm64
    else
        uname -m
    fi
}
bailong_check_tools() {
    [[ "$(uname -s)" == Darwin ]] || { bailong_error "仅支持 macOS。"; return 1; }
    local developer
    if ! developer="$(xcode-select -p 2>&1)"; then
        bailong_error "未找到 Apple 开发工具。"
        print -r -- "构建需要 Swift 编译器和 macOS SDK，可通过安装 Command Line Tools 补齐。"
        print -r -- "检测信息：$developer"
        print -r -- "下载来源：Apple 官方，由 macOS 系统安装窗口下载。"
        print -r -- "请检查网络和代理节点是否可用；系统安装窗口使用 macOS 的网络设置。"
        if bailong_interactive && [[ "${bailong_check_only:-0}" != 1 ]]; then
            if bailong_confirm "现在打开 Apple 开发工具安装窗口吗？"; then
                if xcode-select --install; then
                    print -r -- "请在系统窗口中完成安装，然后重新运行脚本。"
                else
                    bailong_error "未能打开系统安装窗口。"
                    print -r -- "手动安装：xcode-select --install"
                fi
            else
                print -r -- "手动安装：xcode-select --install"
                print -r -- "安装后重新运行：./${bailong_entry_command:-build.command} ${target_arch:-arm64}"
            fi
        else
            print -r -- "手动安装：xcode-select --install"
        fi
        return 1
    fi
    if [[ ! -d "${DEVELOPER_DIR:-$developer}" ]]; then
        bailong_error "开发工具目录不存在：${DEVELOPER_DIR:-$developer}"
        print -r -- "在 Xcode → Settings → Locations 中选择 Command Line Tools。"
        [[ -z "${DEVELOPER_DIR:-}" ]] || print -r -- "当前指定了 DEVELOPER_DIR；使用系统选择的工具：unset DEVELOPER_DIR"
        return 1
    fi
    for tool in xcrun codesign ditto curl tar; do
        command -v "$tool" >/dev/null || { bailong_error "缺少命令：$tool"; return 1; }
    done
    bailong_ok "开发工具：${DEVELOPER_DIR:-$developer}"
}
bailong_check_output() {
    local directory="$1" probe
    mkdir -p "$directory" || { bailong_error "无法创建目录：$directory"; return 1; }
    probe="$(mktemp "$directory/.write-check-XXXXXX")" || { bailong_error "目录不可写：$directory"; return 1; }
    rm "$probe"
}
