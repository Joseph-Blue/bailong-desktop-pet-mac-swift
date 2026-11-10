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
    local developer error
    if ! developer="$(xcode-select -p 2>&1)"; then
        bailong_error "未找到 Apple 开发工具。"
        print -r -- "$developer"
        print -r -- "安装：xcode-select --install"
        if bailong_interactive; then
            local answer
            read -r "answer?输入 1 打开系统安装窗口，回车退出："
            [[ "$answer" != 1 ]] || xcode-select --install
        fi
        return 1
    fi
    if [[ ! -d "${DEVELOPER_DIR:-$developer}" ]]; then
        bailong_error "开发工具目录不存在：${DEVELOPER_DIR:-$developer}"
        print -r -- "在 Xcode → Settings → Locations 中选择 Command Line Tools。"
        [[ -z "${DEVELOPER_DIR:-}" ]] || print -r -- "本次设置了 DEVELOPER_DIR；请修正或取消该变量。"
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
