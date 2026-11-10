# 共用终端输出；非终端不输出光标控制，NO_COLOR 关闭配色。
typeset -g bailong_phase="" bailong_phase_log="" bailong_spinner_pid="" bailong_download_pid=""
typeset -g bailong_temp_dir="" bailong_diagnostic_dir=""
typeset -gi bailong_started=$SECONDS bailong_phase_started=0 bailong_animated=0 bailong_exit_waited=0
exec {bailong_ui_fd}>&1
[[ -t 1 && "${TERM:-dumb}" != dumb ]] && bailong_animated=1
typeset -g bl_reset="" bl_accent="" bl_dim="" bl_green="" bl_red=""
if (( bailong_animated )) && [[ -z "${NO_COLOR+x}" ]]; then
    bl_reset=$'\e[0m'; bl_accent=$'\e[1;36m'; bl_dim=$'\e[2m'
    bl_green=$'\e[32m'; bl_red=$'\e[31m'
fi
bailong_interactive() { [[ "${BAILONG_INTERACTIVE:-0}" == 1 && -t 0 && -t 1 ]] }
bailong_confirm() {
    local answer
    while true; do
        if ! read -r "answer?$1 [Y/N]："; then print; return 1; fi
        case "$answer" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) print -r -- "请输入 Y 或 N。" ;;
        esac
    done
}
bailong_wait_key() {
    bailong_interactive || return 0
    (( ! bailong_exit_waited )) || return 0
    bailong_exit_waited=1
    local key
    print -n -r -- "按任意键继续..."
    if read -r -s -k 1 key; then :; fi
    print
}
bailong_header() {
    local architecture="$2"
    case "$2" in
        arm64) architecture="Apple Silicon · arm64" ;;
        x86_64) architecture="Intel · x86_64" ;;
    esac
    print -ru "$bailong_ui_fd" -- "
${bl_accent}白龙桌宠Swift${bl_reset}     版本：${bl_accent}$(<VERSION)${bl_reset}"
    print -ru "$bailong_ui_fd" -- "${bl_dim}────────────────────────────────────────${bl_reset}"
    print -ru "$bailong_ui_fd" -- "$1  ·  $architecture
"
}
bailong_note() { print -ru "$bailong_ui_fd" -- "${bl_accent}›${bl_reset} $*" }
bailong_ok() { print -ru "$bailong_ui_fd" -- "${bl_green}✓${bl_reset} $*" }
bailong_error() { print -ru "$bailong_ui_fd" -- "${bl_red}✗${bl_reset} $*" }
bailong_init_diagnostics() {
    [[ -n "$bailong_diagnostic_dir" ]] && return 0
    bailong_diagnostic_dir="$(mktemp -d "${TMPDIR:-/tmp}/bailong-diagnostics-XXXXXX")"
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
    bailong_init_diagnostics
    bailong_phase="[$1] $2"
    bailong_phase_started=$SECONDS
    bailong_phase_log="$(mktemp "$bailong_diagnostic_dir/stage-XXXXXX")"
    print -ru "$bailong_ui_fd" -- "${bl_accent}${bailong_phase}${bl_reset}"
    if (( bailong_animated )); then
        (
            trap - EXIT ZERR INT TERM
            trap 'exit 0' TERM
            local -a frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
            local -i index=1
            while true; do
                printf '\r\033[2K%s 进行中 · %d 秒' "$frames[$index]" "$((SECONDS-bailong_phase_started))" >&$bailong_ui_fd
                sleep 0.125
                index=$((index % ${#frames} + 1))
            done
        ) &
        bailong_spinner_pid=$!
    fi
}
bailong_phase_finish() {
    bailong_stop_spinner
    if [[ -n "$bailong_phase" ]]; then
        local counts=""
        if [[ -s "$bailong_phase_log" ]]; then
            counts="$(awk '/^[[:space:]0-9]*\|/{next} /warning:/{w++} /error:/{e++} END {if(w+e>0) printf " · %d warning / %d error", w, e}' "$bailong_phase_log")"
            # 实时编译输出已显示；其他阶段在结束时显示诊断。
            [[ "${bailong_live_output:-0}" == 1 ]] || cat "$bailong_phase_log" >&$bailong_ui_fd
        fi
        print -ru "$bailong_ui_fd" -- "$1 $bailong_phase · $2 · $((SECONDS-bailong_phase_started)) 秒$counts"
        if [[ "$2" != 完成 && -s "$bailong_phase_log" && "${bailong_live_output:-0}" == 1 ]]; then
            local reason
            reason="$(awk '/error:/{print; found=1; exit} END {if(!found) print "编译器返回失败，诊断见上方。"}' "$bailong_phase_log")"
            print -ru "$bailong_ui_fd" -- "原因：$reason"
        fi
    fi
    [[ -z "$bailong_phase_log" ]] || rm -f "$bailong_phase_log"
    bailong_phase=""; bailong_phase_log=""; bailong_live_output=0
}
bailong_phase_end() { bailong_phase_finish "${bl_green}✓${bl_reset}" "完成" }
# swiftc 默认不输出逐文件 info；所有实际诊断实时显示，完整保留上下文。
bailong_compile() {
    setopt localoptions pipefail
    bailong_live_output=1
    "$@" 2>&1 | while IFS= read -r line || [[ -n "$line" ]]; do
        print -r -- "$line" >> "$bailong_phase_log"
        bailong_stop_spinner
        print -ru "$bailong_ui_fd" -- "$line"
    done
    local result=$?
    return "$result"
}
bailong_artifact() {
    setopt localoptions pipefail
    local artifact="${2:A}" bytes size
    if [[ -d "$artifact" ]]; then
        bytes="$(find "$artifact" -type f -exec stat -f '%z' {} + | awk '{sum += $1} END {printf "%.0f", sum}')"
    else
        bytes="$(stat -f '%z' "$artifact")"
    fi
    size="$(awk -v bytes="$bytes" 'BEGIN {printf "%.2f MiB", bytes / 1048576}')"
    print -ru "$bailong_ui_fd" -- "
$1：$artifact
大小：$size"
}
bailong_completed_actions() {
    bailong_interactive || return 0
    local answer
    print -r -- "
1 在访达中显示    2 启动应用    回车 结束"
    read -r "answer?选择："
    case "$answer" in
        1) open -R "$1" ;;
        2) open "$1" ;;
    esac
}
TRAPZERR() {
    local result=$?
    (( ZSH_SUBSHELL == 0 )) || return "$result"
    bailong_phase_finish "${bl_red}✗${bl_reset}" "失败（退出码 $result）"
    # 函数内的 errexit 路径在这里停留；显式 exit 交给 EXIT，只等待一次。
    if [[ -o errexit ]] && (( result != 130 && result != 143 )); then bailong_wait_key; fi
    return "$result"
}
TRAPINT() { bailong_phase_finish "■" "已取消"; exit 130 }
TRAPTERM() { bailong_phase_finish "■" "已终止"; exit 143 }
TRAPEXIT() {
    local result=$?
    (( ZSH_SUBSHELL == 0 )) || return "$result"
    bailong_stop_spinner
    if [[ -n "$bailong_download_pid" ]]; then
        kill "$bailong_download_pid" 2>/dev/null || true
        wait "$bailong_download_pid" 2>/dev/null || true
    fi
    [[ -z "$bailong_temp_dir" ]] || rm -rf "$bailong_temp_dir"
    [[ -z "$bailong_diagnostic_dir" ]] || rm -rf "$bailong_diagnostic_dir"
    if (( result != 0 && result != 130 && result != 143 )) && bailong_interactive; then
        bailong_wait_key
    fi
}
