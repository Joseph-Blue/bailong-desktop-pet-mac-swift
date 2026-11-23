#!/bin/zsh
set -eu
cd "${0:A:h}"
if (( $# == 0 )) && [[ -t 0 && -t 1 ]]; then export BAILONG_INTERACTIVE="${BAILONG_INTERACTIVE:-1}"; fi
source scripts/terminal-ui.sh
source scripts/build-preflight.sh
source scripts/build-options.sh
bailong_entry=launch; bailong_entry_command=launch.command
bailong_parse_options "$@"
version="$(<VERSION)"
output="$PWD/dist/$version/$target_arch"
case "${BAILONG_BUILD_PROFILE:-auto}" in
    auto) ;;
    full|glass|plain) output="$output/$BAILONG_BUILD_PROFILE" ;;
    *) bailong_usage_error "未知档位：$BAILONG_BUILD_PROFILE" ;;
esac
app="$output/白龙桌宠Swift.app"
bailong_header "打开应用" "$target_arch"
print -r -- "应用：$app"
if [[ ! -d "$app" ]]; then
    print -u2 "未找到此应用。先构建：./build.command $target_arch"
    print -u2 '中文环境教程：https://developer.apple.com/cn/documentation/xcode/installing-the-command-line-tools'
    exit 1
fi
open "$app"
bailong_ok "已提交打开请求"
