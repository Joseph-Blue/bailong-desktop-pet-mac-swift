# 由构建入口 source。
bailong_tools_help() {
    case "${1:-install}" in
        install)
            print -u2 -r -- "手动安装：xcode-select --install"
            print -u2 -r -- "安装失败时，从 Apple 下载适合当前 macOS 的 Command Line Tools："
            print -u2 -r -- "https://developer.apple.com/download/all/?q=command%20line%20tools"
            print -u2 -r -- "中文安装教程：https://developer.apple.com/cn/documentation/xcode/installing-the-command-line-tools"
            ;;
        update)
            print -u2 -r -- "请在「系统设置 → 通用 → 软件更新」更新开发工具，或安装包含所需 SDK 的 Xcode。"
            print -u2 -r -- "中文安装教程：https://developer.apple.com/cn/documentation/xcode/installing-the-command-line-tools"
            print -u2 -r -- "版本要求：https://developer.apple.com/cn/xcode/system-requirements"
            print -u2 -r -- "手动下载：https://developer.apple.com/download/all/"
            ;;
        select)
            print -u2 -r -- "在 Xcode → Settings → Locations 中选择 Command Line Tools。"
            print -u2 -r -- "中文配置教程：https://developer.apple.com/cn/documentation/xcode/configuring-command-line-tools-settings"
            ;;
    esac
}
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
        print -r -- "检测信息：$developer"
        print -r -- "来源：Apple 官方。安装窗口使用系统网络，请检查网络和代理。"
        if bailong_interactive && [[ "${bailong_check_only:-0}" != 1 ]]; then
            if bailong_confirm "现在打开 Apple 开发工具安装窗口吗？"; then
                if xcode-select --install; then
                    print -r -- "请在系统窗口中完成安装，然后重新运行脚本。"
                else
                    bailong_error "未能打开系统安装窗口。"
                fi
            fi
        fi
        bailong_tools_help install
        print -r -- "安装后重跑：./${bailong_entry_command:-build.command} ${target_arch:-arm64}"
        return 1
    fi
    if [[ ! -d "${DEVELOPER_DIR:-$developer}" ]]; then
        bailong_error "开发工具目录不存在：${DEVELOPER_DIR:-$developer}"
        bailong_tools_help select
        [[ -z "${DEVELOPER_DIR:-}" ]] || print -r -- "当前指定了 DEVELOPER_DIR；使用系统选择的工具：unset DEVELOPER_DIR"
        return 1
    fi
    for tool in xcrun codesign ditto curl tar; do
        if ! command -v "$tool" >/dev/null; then
            bailong_error "缺少系统命令：$tool"
            print -r -- '请检查 PATH 包含 /usr/bin、/bin、/usr/sbin、/sbin。'
            print -r -- "中文更新教程：https://support.apple.com/zh-cn/108382"
            return 1
        fi
    done
    bailong_ok "开发工具：${DEVELOPER_DIR:-$developer}"
}
bailong_check_output() {
    local directory="$1" probe
    mkdir -p "$directory" || { bailong_error "无法创建目录：$directory"; return 1; }
    probe="$(mktemp "$directory/.write-check-XXXXXX")" || { bailong_error "目录不可写：$directory"; return 1; }
    rm "$probe"
}
