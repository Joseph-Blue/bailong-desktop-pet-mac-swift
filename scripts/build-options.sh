# 构建与开发入口共用参数，不在非交互调用中读取输入。
bailong_parse_options() {
    target_arch=arm64
    bailong_check_only=0; bailong_build_only=0; bailong_resource_zip=""; bailong_resource_mode=missing; bailong_download_requested=0
    local explicit_arch=0
    while (( $# )); do
        case "$1" in
            arm64|x86_64) target_arch="$1"; explicit_arch=1 ;;
            --check) bailong_check_only=1 ;;
            --build-only)
                [[ "$bailong_entry" == dev ]] || { bailong_error "--build-only 仅用于 run-dev.command"; return 2; }
                bailong_build_only=1 ;;
            --resources-zip)
                (( $# >= 2 )) || { bailong_error "--resources-zip 后需要 ZIP 路径"; return 2; }
                bailong_resource_zip="$2"; shift ;;
            --replace-resources) bailong_resource_mode=replace ;;
            --download-resources) bailong_download_requested=1 ;;
            --help|-h)
                print -r -- "用法：./${bailong_entry_command} [arm64|x86_64] [选项]
  --check                  只检查环境与资源，不构建应用
  --resources-zip <文件>    导入 ZIP，默认只补齐缺失文件
  --replace-resources      备份后替换 ZIP 包含的资源
  --download-resources     下载清单指定的资源包
  --help                   显示帮助"
                if [[ "$bailong_entry" == dev ]]; then
                    print '  --build-only             仅编译开发程序，不检查运行资源或启动'
                    print '运行时显示 PID；^C 请求退出，5 秒倒计时后强制结束未退出的进程。'
                fi
                print '环境变量：BAILONG_BUILD_PROFILE=auto|full|glass|plain；SDKROOT=<SDK 路径>'
                exit 0 ;;
            *) bailong_error "未知参数：$1；使用 --help 查看用法。"; return 2 ;;
        esac
        shift
    done
    if (( bailong_build_only && (bailong_check_only || bailong_download_requested) )) ||
       { (( bailong_build_only )) && [[ -n "$bailong_resource_zip" || "$bailong_resource_mode" == replace ]]; }; then
        bailong_error "--build-only 不与资源操作或 --check 同用。"; return 2
    fi
    if (( bailong_check_only && bailong_download_requested )) ||
       { (( bailong_check_only )) && [[ -n "$bailong_resource_zip" || "$bailong_resource_mode" == replace ]]; }; then
        bailong_error "--check 不与资源导入或下载同用。"; return 2
    fi
    if (( bailong_download_requested )) && [[ -n "$bailong_resource_zip" ]]; then
        bailong_error "请选择下载或本地 ZIP 中的一种。"; return 2
    fi
    if [[ "$bailong_resource_mode" == replace && -z "$bailong_resource_zip" && "$bailong_download_requested" == 0 ]]; then
        bailong_error "--replace-resources 需配合 --resources-zip 或 --download-resources。"; return 2
    fi
    if (( ! explicit_arch )) && [[ "$(bailong_host_arch)" == x86_64 ]]; then
        if bailong_interactive; then
            local answer
            read -r "answer?当前为 Intel Mac。输入 1 构建 Intel 版，回车退出："
            [[ "$answer" == 1 ]] || return 1
            target_arch=x86_64
        elif [[ "$bailong_entry" == dev && "$bailong_build_only" == 0 && "$bailong_check_only" == 0 ]]; then
            bailong_error "Intel 开发运行请指定 x86_64。"; return 2
        fi
    fi
    if [[ "$bailong_entry" == dev && "$target_arch" == arm64 && "$(bailong_host_arch)" == x86_64 && "$bailong_build_only" == 0 && "$bailong_check_only" == 0 ]]; then
        bailong_error "Intel Mac 无法运行 arm64 开发程序，请指定 x86_64。"; return 2
    fi
}
