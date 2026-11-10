#!/bin/zsh
set -eu
cd "${0:A:h}"
if (( $# == 0 )) && [[ -t 0 && -t 1 ]]; then export BAILONG_INTERACTIVE="${BAILONG_INTERACTIVE:-1}"; fi
source scripts/terminal-ui.sh
source scripts/build-preflight.sh
if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != arm64 && "$1" != x86_64 ]]; }; then
    print '用法：./launch.command [arm64|x86_64]'; exit 2
fi
version="$(<VERSION)"
target_arch="${1:-$(bailong_host_arch)}"
output="$PWD/dist/$version/$target_arch"
case "${BAILONG_BUILD_PROFILE:-auto}" in
    auto) ;;
    full|glass|plain) output="$output/$BAILONG_BUILD_PROFILE" ;;
    *) bailong_error "未知档位：$BAILONG_BUILD_PROFILE"; exit 2 ;;
esac
app="$output/白龙桌宠Swift.app"
bailong_header "打开应用" "$target_arch"
print -r -- "应用：$app"
if [[ ! -d "$app" ]]; then
    print -u2 "未找到此应用。请先运行：./build.command $target_arch"
    exit 1
fi
open "$app"
bailong_ok "已提交打开请求"
