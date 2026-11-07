#!/bin/zsh
set -eu
cd "${0:A:h}"
source scripts/terminal-ui.sh
version="$(<VERSION)"
target_arch="$(uname -m)"
app="$PWD/dist/native-hevc/$version/$target_arch/白龙桌宠Swift.app"
bailong_header "打开应用" "$target_arch"
print -r -- "应用：$app"
if [[ ! -d "$app" ]]; then
    print -u2 "未找到此应用。请先运行：./build.command $target_arch"
    exit 1
fi
open "$app"
