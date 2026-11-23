# 仅由 App 构建在请求制作 DMG 时加载。
bailong_dmg_default_background="$PWD/local-assets/dmg-20261104/package-v5/staging/.background/background.tiff"
bailong_dmg_background_requirements='头图格式为 PNG 或 TIFF，尺寸为 920×430 或 1840×860 像素。'

bailong_load_dmg_background() {
    local candidate="$1" metadata format pixel_width pixel_height
    [[ "$candidate" == /* ]] || candidate="$bailong_invocation_dir/$candidate"
    if [[ ! -f "$candidate" ]]; then
        bailong_error "找不到 DMG 头图：$candidate"
        return 1
    fi
    metadata="$(/usr/bin/sips -g format -g pixelWidth -g pixelHeight "$candidate")" || return 1
    read -r format pixel_width pixel_height <<< "$(awk '
        $1 == "format:"      { format = $2 }
        $1 == "pixelWidth:"  { width = $2 }
        $1 == "pixelHeight:" { height = $2 }
        END { print format, width, height }
    ' <<< "$metadata")"
    case "$format:$pixel_width:$pixel_height" in
        png:920:430|tiff:920:430|png:1840:860|tiff:1840:860) ;;
        *) bailong_error "DMG 头图的格式或尺寸不符：$candidate"; return 1 ;;
    esac
    bailong_dmg_background="$candidate"
    bailong_dmg_background_format="$format"
    bailong_dmg_background_width="$pixel_width"
}

bailong_select_dmg_background() {
    local candidate="${bailong_dmg_background:-$bailong_dmg_default_background}"
    while ! bailong_load_dmg_background "$candidate"; do
        print -r -- "$bailong_dmg_background_requirements"
        if [[ ! -t 0 || ! -t 1 || "${BAILONG_INTERACTIVE:-1}" == 0 ]]; then
            print -ru2 -- '请用 --dmg-background <文件> 指定头图。'
            return 1
        fi
        IFS= read -r 'candidate?输入相对或绝对路径（可直接粘贴，回车取消）：' || return 1
        [[ -n "$candidate" ]] || return 1
    done
}

bailong_stage_dmg_background() {
    local destination="$1" work="$2"
    if (( bailong_dmg_background_width == 1840 )); then
        /usr/bin/sips -s format tiff -s dpiWidth 72 -s dpiHeight 72 -z 430 920 \
            "$bailong_dmg_background" --out "$work/background-1x.tiff"
        /usr/bin/sips -s format tiff -s dpiWidth 72 -s dpiHeight 72 -z 860 1840 \
            "$bailong_dmg_background" --out "$work/background-2x.tiff"
        /usr/bin/tiffutil -cathidpicheck "$work/background-1x.tiff" "$work/background-2x.tiff" -out "$destination"
    elif [[ "$bailong_dmg_background_format" == tiff ]]; then
        cp "$bailong_dmg_background" "$destination"
    else
        /usr/bin/sips -s format tiff -s dpiWidth 72 -s dpiHeight 72 "$bailong_dmg_background" --out "$destination"
    fi
}

bailong_dmg_cleanup() {
    local work="$1" mounted_volume="$2"
    if [[ -n "$mounted_volume" ]] && ! /usr/bin/hdiutil detach "$mounted_volume"; then
        print -ru2 -- "未能卸载 DMG 制作卷，暂存目录：$work"
        return 1
    fi
    rm -rf "$work"
}

bailong_package_dmg() (
    local app="$1" destination="$2" label="$3" artwork="$4"
    local work mounted_volume="" content image
    # 错误交给外层构建阶段报告，子进程先完成卷卸载和暂存清理。
    trap - ZERR
    work="$(mktemp -d "${destination:A:h}/.dmg-XXXXXX")"
    trap 'bailong_dmg_cleanup "$work" "$mounted_volume"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    content="$work/content"
    image="$work/final.dmg"
    mkdir "$content"
    /usr/bin/ditto "$app" "$content/${app:t}"
    ln -s /Applications "$content/应用程序"

    if (( artwork )); then
        local editable="$work/layout.dmg" mount_path="$work/volume" device
        mkdir "$content/.background" "$mount_path"
        bailong_stage_dmg_background "$content/.background/background.tiff" "$work"
        # Finder 写入图标位置和背景时使用独立制作卷，避免同名安装卷干扰。
        /usr/bin/hdiutil create -srcfolder "$content" -fs HFS+ -format UDRW -volname "白龙桌宠Swift ${work:t}" "$editable"
        /usr/bin/hdiutil attach -noautoopen -mountpoint "$mount_path" "$editable"
        mounted_volume="$mount_path"
        /usr/bin/osascript scripts/dmg-layout.applescript "$mount_path"
        if [[ ! -s "$mount_path/.DS_Store" ]]; then
            print -ru2 -- 'Finder 未保存 DMG 安装窗口布局。'
            exit 1
        fi
        device="$(/usr/sbin/diskutil info -plist "$mount_path" | /usr/bin/plutil -extract DeviceNode raw -o - -)"
        mounted_volume="$device"
        /usr/sbin/diskutil rename "$mounted_volume" "$label"
        /usr/bin/hdiutil detach "$mounted_volume"
        mounted_volume=""
        /usr/bin/hdiutil convert "$editable" -format UDZO -o "$image"
    else
        /usr/bin/hdiutil create -srcfolder "$content" -fs HFS+ -format UDZO -volname "$label" "$image"
    fi

    # 打包成功后再替换同档位产物，失败时保留已有 DMG。
    mv -f "$image" "$destination"
)
