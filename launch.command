#!/bin/zsh
set -eu
cd "${0:A:h}"
source scripts/terminal-ui.sh
version="$(<VERSION)"
target_arch="$(uname -m)"
app="$PWD/dist/native-hevc/$version/$target_arch/白龙桌宠Swift.app"
bailong_header "打开已构建的应用" "$target_arch"
print -r -- "应用：$app"
if [[ ! -d "$app" ]]; then
    print -u2 "未找到此应用。请先运行：./build.command $target_arch"
    exit 1
fi
bailong_directory "应用所在目录" "${app:h}"
bailong_phase_begin "1/1" "提交打开请求"
open "$app" > "$bailong_phase_log" 2>&1
bailong_phase_end
print "已提交打开请求。"
