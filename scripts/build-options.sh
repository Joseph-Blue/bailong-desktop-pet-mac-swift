# 三个 .command 入口共用帮助和参数检查。
bailong_usage() {
    print -r -- "用法：./${bailong_entry_command} [arm64|x86_64] [选项]"
    print -r -- '
无参运行'
    case "$bailong_entry" in
        app) print -r -- '  检查开发工具和运行素材，默认构建 arm64 App 到 dist/<VERSION>/arm64/。
  构建完成后，可在交互终端选择在访达显示或打开 App。' ;;
        dev) print -r -- '  检查开发工具和运行素材，默认以 arm64 启动开发程序。
  源码与构建环境均未变化时复用上次编译结果。
  启动后显示协议、会话状态和逐段动画明细。' ;;
        launch) print -r -- '  按 VERSION 和本机架构打开 dist/<VERSION>/<架构>/ 下的 App。
  使用 full、glass 或 plain 档位时查找对应子目录。缺少产物时显示构建命令。' ;;
    esac
    if [[ "$bailong_entry" != launch ]]; then
        print -r -- '  在交互终端，Intel Mac 会提示选择 x86_64。缺少开发工具会询问是否安装。
  运行素材不全且素材包已发布时，会询问是否下载。'
    fi
    print -r -- "
选项
  --help, -h, help, '?'		显示帮助（zsh 中请给 ? 加单引号）"
    if [[ "$bailong_entry" != launch ]]; then
        print -r -- '  --check			只检查环境与资源
  --resources-zip <文件>	导入 ZIP，默认只补齐缺失文件
  --download-resources		下载并导入清单指定的资源包
  --replace-resources		导入时备份并替换包内同名资源'
    fi
    if [[ "$bailong_entry" == app ]]; then
        print -r -- '  --dmg				构建 App 后制作 DMG
  --dmg-artwork			使用默认头图，缺失时在终端询问路径
  --dmg-background <文件>	指定 PNG 或 TIFF 头图并打包 DMG
  --release			将构建标记为正式版 Release'
    fi
    if [[ "$bailong_entry" == dev ]]; then
        print -r -- '  --build-only			仅编译开发程序，跳过运行素材检查
  --monitor			启动时开启终端监视（默认）
  --no-monitor			启动时暂停终端监视
  --monitor-animation		显示逐段动画明细（默认）
  --no-monitor-animation	收起逐段动画明细，保留动画加载失败日志

终端快捷键：M 暂停或恢复监视，A 在监视开启时切换动画明细，^C 退出。'
    fi
    print -r -- '
环境变量
  BAILONG_BUILD_PROFILE		产物档位（auto、full、glass、plain）'
    if [[ "$bailong_entry" != launch ]]; then
        print -r -- '  SDKROOT			macOS SDK 路径'
    fi
}

bailong_usage_error() {
    print -ru2 -- "${bl_red}✗${bl_reset} $1"
    bailong_usage >&2
    exit 2
}

bailong_parse_options() {
    target_arch=""
    bailong_check_only=0; bailong_build_only=0; bailong_resource_zip=""; bailong_resource_mode=missing; bailong_download_requested=0
    bailong_monitor=""; bailong_monitor_animation=""
    bailong_build_dmg=0; bailong_dmg_artwork=0; bailong_dmg_background=""
    bailong_release_build=0
    while (( $# )); do
        case "$1" in
            --help|-h|help|'?') bailong_usage; exit 0 ;;
            arm64|x86_64)
                [[ -z "$target_arch" ]] || bailong_usage_error "只能指定一个架构：$target_arch、$1。"
                target_arch="$1"
                shift
                continue ;;
        esac
        case "$bailong_entry:$1" in
            app:--check|dev:--check) bailong_check_only=1 ;;
            app:--dmg) bailong_build_dmg=1 ;;
            app:--dmg-artwork) bailong_build_dmg=1; bailong_dmg_artwork=1 ;;
            app:--dmg-background)
                [[ -n "${2:-}" && "$2" != -* ]] || bailong_usage_error "--dmg-background 后需要 PNG 或 TIFF 路径。"
                bailong_build_dmg=1; bailong_dmg_artwork=1; bailong_dmg_background="$2"
                shift ;;
            app:--release) bailong_release_build=1 ;;
            dev:--build-only) bailong_build_only=1 ;;
            dev:--monitor|dev:--no-monitor) bailong_monitor="$1" ;;
            dev:--monitor-animation|dev:--no-monitor-animation) bailong_monitor_animation="$1" ;;
            app:--resources-zip|dev:--resources-zip)
                [[ -n "${2:-}" && "$2" != -* ]] || bailong_usage_error "--resources-zip 后需要 ZIP 路径。"
                bailong_resource_zip="$2"; shift ;;
            app:--download-resources|dev:--download-resources) bailong_download_requested=1 ;;
            app:--replace-resources|dev:--replace-resources) bailong_resource_mode=replace ;;
            *) bailong_usage_error "未知参数：$1" ;;
        esac
        shift
    done
    if [[ "$bailong_entry" == launch ]]; then
        target_arch="${target_arch:-$(bailong_host_arch)}"
        return 0
    fi
    if (( bailong_build_only || bailong_check_only )) && [[ -n "$bailong_monitor$bailong_monitor_animation" ]]; then
        bailong_usage_error "监视选项需要启动开发程序。"
    fi
    if (( bailong_check_only && bailong_build_dmg )); then
        bailong_usage_error "DMG 选项需要构建 App。"
    fi
    if (( bailong_check_only && bailong_release_build )); then
        bailong_usage_error "--release 需要构建 App。"
    fi
    if (( bailong_build_only && (bailong_check_only || bailong_download_requested) )) ||
       { (( bailong_build_only )) && [[ -n "$bailong_resource_zip" || "$bailong_resource_mode" == replace ]]; }; then
        bailong_usage_error "--build-only 不与资源操作或 --check 同用。"
    fi
    if (( bailong_check_only && bailong_download_requested )) ||
       { (( bailong_check_only )) && [[ -n "$bailong_resource_zip" || "$bailong_resource_mode" == replace ]]; }; then
        bailong_usage_error "--check 不与资源导入或下载同用。"
    fi
    if (( bailong_download_requested )) && [[ -n "$bailong_resource_zip" ]]; then
        bailong_usage_error "请选择下载或本地 ZIP 中的一种。"
    fi
    if [[ "$bailong_resource_mode" == replace && -z "$bailong_resource_zip" && "$bailong_download_requested" == 0 ]]; then
        bailong_usage_error "--replace-resources 需配合 --resources-zip 或 --download-resources。"
    fi
    local host_arch="$(bailong_host_arch)"
    if [[ -z "$target_arch" ]]; then
        target_arch=arm64
        if [[ "$host_arch" == x86_64 ]] && bailong_interactive; then
            local answer
            read -r "answer?当前为 Intel Mac。输入 1 构建 Intel 版，回车退出："
            [[ "$answer" == 1 ]] || return 1
            target_arch=x86_64
        fi
    fi
    if [[ "$bailong_entry" == dev && "$target_arch" == arm64 && "$host_arch" == x86_64 ]] && (( ! bailong_build_only && ! bailong_check_only )); then
        bailong_usage_error "Intel Mac 上请指定 x86_64 启动开发程序。"
    fi
}
