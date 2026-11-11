# 由仓库根目录的 zsh 编译入口 source；SDKROOT 可指定已安装的 SDK 路径。
# 能力按实际传给 swiftc 的 SDK 判定，不以编译器版本代替 SDK 版本。
source scripts/build-preflight.sh
if ! bailong_sdk_path="$(xcrun --sdk "${SDKROOT:-macosx}" --show-sdk-path 2>&1)"; then
    print -u2 -- "无法读取 macOS SDK：$bailong_sdk_path"
    if [[ -n "${SDKROOT:-}" ]]; then
        print -u2 -- "检查 SDKROOT=$SDKROOT；使用默认 SDK：unset SDKROOT"
    fi
    [[ -z "${DEVELOPER_DIR:-}" ]] || print -u2 -- "使用系统工具路径：unset DEVELOPER_DIR"
    bailong_tools_help update
    bailong_tools_help select
    return 1
fi
if [[ ! -d "$bailong_sdk_path" ]]; then
    print -u2 -- "SDK 目录不存在：$bailong_sdk_path"
    print -u2 -- "检查 SDKROOT；使用默认 SDK：unset SDKROOT"
    bailong_tools_help update
    return 1
fi
if ! bailong_sdk_version="$(xcrun --sdk "$bailong_sdk_path" --show-sdk-version 2>&1)"; then
    print -u2 -- "无法读取 SDK 版本：$bailong_sdk_version"
    bailong_tools_help update
    return 1
fi
if ! bailong_swiftc="$(xcrun --find swiftc 2>&1)"; then
    print -u2 -- "未找到 Swift 编译器：$bailong_swiftc"
    bailong_tools_help update
    bailong_tools_help select
    return 1
fi
if ! bailong_swift_version="$("$bailong_swiftc" --version 2>&1)"; then
    print -u2 -- "Swift 编译器无法运行：$bailong_swift_version"
    print -u2 -- "使用 Xcode 时，先打开它并完成首次设置。"
    bailong_tools_help update
    return 1
fi
bailong_sdk_major="${bailong_sdk_version%%.*}"
if [[ "$bailong_sdk_major" != <-> ]]; then
    print -u2 -- "无法识别 SDK 版本：$bailong_sdk_version"
    bailong_tools_help update
    return 1
fi
print -r -- "当前 SDK $bailong_sdk_version 支持的构建档位："
for bailong_profile_option in full glass plain; do
    case "$bailong_profile_option" in
        full) bailong_profile_minimum=27; bailong_profile_label="完整"; bailong_profile_description="液态玻璃 + 菜单图标优先显示" ;;
        glass) bailong_profile_minimum=26; bailong_profile_label="玻璃"; bailong_profile_description="液态玻璃，菜单图标由系统决定" ;;
        plain) bailong_profile_minimum=14; bailong_profile_label="普通"; bailong_profile_description="普通材质，菜单图标由系统决定" ;;
    esac
    if (( bailong_sdk_major >= bailong_profile_minimum )); then bailong_profile_mark="✓"
    else bailong_profile_mark="✗"
    fi
    print -r -- "  $bailong_profile_mark $bailong_profile_option · $bailong_profile_label · SDK $bailong_profile_minimum+ · $bailong_profile_description"
done
print -r -- "三档均以 macOS 14 为最低运行目标；液态玻璃需 macOS 26+，菜单图标优先显示需 27+。"
if (( bailong_sdk_major < 14 )); then
    print -u2 -- "需要 macOS 14 或更新的 SDK，当前为：$bailong_sdk_version"
    bailong_tools_help update
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
    print -u2 -- "完整档需要 SDK 27+，当前为 $bailong_sdk_version。"
    print -u2 -- "自动选档：unset BAILONG_BUILD_PROFILE"
    bailong_tools_help update
    return 1
fi
if [[ "$bailong_build_profile" == glass ]] && (( bailong_sdk_major < 26 )); then
    print -u2 -- "玻璃档需要 SDK 26+，当前为 $bailong_sdk_version。"
    print -u2 -- "自动选档：unset BAILONG_BUILD_PROFILE"
    bailong_tools_help update
    return 1
fi
bailong_sdk_flags=(-sdk "$bailong_sdk_path")
if [[ "$bailong_build_profile" != plain ]]; then
    bailong_sdk_flags+=(-D BAILONG_SDK_GLASS)
fi
if [[ "$bailong_build_profile" == full ]]; then
    bailong_sdk_flags+=(-D BAILONG_SDK_MENU_IMAGES)
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
    case "$bailong_build_profile" in
        full) print -r -- "本次采用：full（完整）" ;;
        glass) print -r -- "本次采用：glass（玻璃）" ;;
        plain) print -r -- "本次采用：plain（普通）" ;;
    esac
}
