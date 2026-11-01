#!/bin/zsh
set -eu
cd "${0:A:h}"
version="$(<VERSION)"
app="dist/native-hevc/$version/$(uname -m)/白龙桌宠Swift.app"
if [[ ! -d "$app" ]]; then
    print -u2 "未找到当前版本的应用，请先运行 build.command。"
    exit 1
fi
exec open "$app"
