# 由仓库根目录的 zsh 编译入口 source；SDKROOT 可指定已安装的 SDK 路径。
# 能力按实际传给 swiftc 的 SDK 判定，不以编译器版本代替 SDK 版本。
if ! bailong_sdk_path="$(xcrun --sdk "${SDKROOT:-macosx}" --show-sdk-path 2>&1)"; then
    print -u2 -- "无法读取 macOS SDK：$bailong_sdk_path"
    if [[ -n "${SDKROOT:-}" ]]; then
        print -u2 -- "检查 SDKROOT=$SDKROOT；使用默认 SDK：unset SDKROOT"
    else
        print -u2 -- "请安装或更新 Apple 开发工具，并检查 Xcode 的 Command Line Tools 选择。"
    fi
    return 1
fi
if [[ ! -d "$bailong_sdk_path" ]]; then
    print -u2 -- "SDK 目录不存在：$bailong_sdk_path"
    print -u2 -- "检查 SDKROOT；使用默认 SDK：unset SDKROOT"
    return 1
fi
if ! bailong_sdk_version="$(xcrun --sdk "$bailong_sdk_path" --show-sdk-version 2>&1)"; then
    print -u2 -- "无法读取 SDK 版本：$bailong_sdk_version"; return 1
fi
if ! bailong_swiftc="$(xcrun --find swiftc 2>&1)"; then
    print -u2 -- "未找到 Swift 编译器：$bailong_swiftc"; return 1
fi
if ! bailong_swift_version="$("$bailong_swiftc" --version 2>&1)"; then
    print -u2 -- "Swift 编译器无法运行：$bailong_swift_version"; return 1
fi
bailong_sdk_major="${bailong_sdk_version%%.*}"
if [[ "$bailong_sdk_major" != <-> ]] || (( bailong_sdk_major < 14 )); then
    print -u2 -- "需要 macOS 14 或更新的 SDK，当前为：$bailong_sdk_version"
    return 1
fi
# swiftc 的 -sdk 选择编译 SDK；clang 链接阶段还需继承 SDKROOT，
# 否则此工具链会把部署目标误写为 LC_BUILD_VERSION 的 SDK 版本。
export SDKROOT="$bailong_sdk_path"
bailong_build_profile="${BAILONG_BUILD_PROFILE:-auto}"
case "$bailong_build_profile" in
    auto)
        if (( bailong_sdk_major >= 27 )); then bailong_build_profile=full
        elif (( bailong_sdk_major >= 26 )); then bailong_build_profile=glass
        else bailong_build_profile=plain
        fi ;;
    full|glass|plain) ;;
    *) print -u2 -- "不支持的构建档位：$bailong_build_profile（可选 auto、full、glass、plain）"; return 1 ;;
esac
if [[ "$bailong_build_profile" == full ]] && (( bailong_sdk_major < 27 )); then
    print -u2 -- "完整档需要 macOS 27 或更新 SDK，当前为：$bailong_sdk_version"; return 1
fi
if [[ "$bailong_build_profile" == glass ]] && (( bailong_sdk_major < 26 )); then
    print -u2 -- "玻璃档需要 macOS 26 或更新 SDK，当前为：$bailong_sdk_version"; return 1
fi
bailong_sdk_flags=(-sdk "$bailong_sdk_path")
bailong_build_features=("普通材质")
if [[ "$bailong_build_profile" != plain ]]; then
    bailong_sdk_flags+=(-D BAILONG_SDK_GLASS)
    bailong_build_features+=("液态玻璃（运行时需 macOS 26+）")
fi
if [[ "$bailong_build_profile" == full ]]; then
    bailong_sdk_flags+=(-D BAILONG_SDK_MENU_IMAGES)
    bailong_build_features+=("菜单图标显式显示（运行时需 macOS 27+）")
fi
# 开发程序切换 SDK、编译器或能力后必须重建，不能只比较源文件时间。
bailong_build_environment="${bailong_sdk_path}
${bailong_sdk_version}
SDKROOT=${SDKROOT}
profile=${bailong_build_profile}
${bailong_swiftc}
${bailong_swift_version}
${(F)bailong_sdk_flags}"

bailong_show_build_environment() {
    print -r -- "构建 SDK：macOS $bailong_sdk_version"
    print -r -- "SDK 路径：$bailong_sdk_path"
    print -r -- "Swift 编译器：${bailong_swift_version%%$'\n'*}"
    print -r -- "最低运行目标：macOS 14.0"
    case "$bailong_build_profile" in
        full) print -r -- "构建档位：完整档（full）" ;;
        glass) print -r -- "构建档位：玻璃档（glass）" ;;
        plain) print -r -- "构建档位：普通档（plain）" ;;
    esac
    print -r -- "本次编入的外观功能：${(j:、:)bailong_build_features}"
    if [[ "$bailong_build_profile" == plain ]]; then
        print -r -- "液态玻璃未编入：此产物在新系统上也使用普通材质。"
    fi
    if [[ "$bailong_build_profile" != full ]]; then
        print -r -- "菜单图标显示由系统决定，未编入 macOS 27 专用控制。"
    fi
}
