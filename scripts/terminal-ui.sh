# 由 zsh 入口 source。提示仅用于本次命令，不写入应用日志或用户数据。
typeset -g bailong_phase="" bailong_phase_log="" bailong_spinner_pid=""
typeset -gi bailong_started=$SECONDS bailong_phase_started=0 bailong_animated=0
exec {bailong_ui_fd}>&1
[[ -t 1 && "${TERM:-dumb}" != dumb ]] && bailong_animated=1

bailong_header() {
    local architecture="$2"
    case "$2" in
        arm64) architecture="Apple Silicon（arm64）" ;;
        x86_64) architecture="Intel（x86_64）" ;;
    esac
    print -ru "$bailong_ui_fd" -- "白龙桌宠Swift · $(<VERSION) · $architecture"
    print -ru "$bailong_ui_fd" -- "$1"
    print -u "$bailong_ui_fd"
}

bailong_stop_spinner() {
    if [[ -n "$bailong_spinner_pid" ]]; then
        kill "$bailong_spinner_pid" 2>/dev/null || true
        wait "$bailong_spinner_pid" 2>/dev/null || true
        bailong_spinner_pid=""
        printf '\r\033[2K' >&$bailong_ui_fd
    fi
}

bailong_phase_begin() {
    setopt localoptions nobgnice
    bailong_phase="[$1] $2"
    bailong_phase_started=$SECONDS
    bailong_phase_log="$(mktemp "${TMPDIR:-/tmp}/bailong-stage.XXXXXX")"
    if (( bailong_animated )); then
        (
            trap - EXIT ZERR INT TERM
            trap 'exit 0' TERM
            local -a frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
            local -i index=1
            while true; do
                printf '\r\033[2K%s %s…… 已用时 %d 秒' "$frames[$index]" "$bailong_phase" "$((SECONDS-bailong_phase_started))" >&$bailong_ui_fd
                sleep 0.125
                index=$((index % ${#frames} + 1))
            done
        ) &
        bailong_spinner_pid=$!
    else
        print -ru "$bailong_ui_fd" -- "$bailong_phase……"
    fi
}

bailong_phase_finish() {
    bailong_stop_spinner
    [[ -n "$bailong_phase_log" && -s "$bailong_phase_log" ]] && cat "$bailong_phase_log" >&$bailong_ui_fd
    if [[ -n "$bailong_phase" ]]; then
        print -ru "$bailong_ui_fd" -- "$1 $bailong_phase · $2 · $((SECONDS-bailong_phase_started)) 秒"
    fi
    [[ -z "$bailong_phase_log" ]] || rm -f "$bailong_phase_log"
    bailong_phase=""; bailong_phase_log=""
}

bailong_phase_end() { bailong_phase_finish "✓" "完成" }

bailong_directory() {
    # 直接输出 file:// URL，供终端的 ⌘ 单击识别；链接始终指向目录。
    emulate -L zsh
    setopt localoptions nomultibyte
    local directory="${2:A}" encoded="" byte escape
    for byte in ${(s::)directory}; do
        if [[ "$byte" == [a-zA-Z0-9/._~-] ]]; then
            encoded+="$byte"
        else
            printf -v escape '%%%02X' "'$byte"
            encoded+="$escape"
        fi
    done
    print -ru "$bailong_ui_fd" -- "$1：$directory"
    print -ru "$bailong_ui_fd" -- "访达目录（⌘ 单击）：file://$encoded/"
}

TRAPZERR() {
    local result=$?
    bailong_phase_finish "✗" "失败（退出码 $result）"
    print -ru "$bailong_ui_fd" -- "操作未完成，请根据上方错误处理后重试。"
    return "$result"
}
TRAPINT() { bailong_phase_finish "■" "已取消"; exit 130 }
TRAPTERM() { bailong_phase_finish "■" "已终止"; exit 143 }
TRAPEXIT() {
    bailong_stop_spinner
    [[ -z "$bailong_phase_log" ]] || rm -f "$bailong_phase_log"
}
