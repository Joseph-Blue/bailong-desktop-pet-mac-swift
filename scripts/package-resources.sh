#!/bin/zsh
set -eu
cd "${0:A:h:h}"
source scripts/terminal-ui.sh
source scripts/build-preflight.sh
source scripts/build-resources.sh
if (( $# != 0 )); then print '用法：./scripts/package-resources.sh（仅生成本地 ZIP）'; exit 2; fi
bailong_header "打包开发资源" "HEVC · 图标 · 音效"
bailong_check_tools
source scripts/swift-environment.sh
bailong_prepare_resource_tool
[[ "$bailong_resource_published" == no ]] || { bailong_error "当前资源版本已发布，请先更新清单版本。"; exit 1; }
output="$PWD/dist/dev-assets/$bailong_resource_version"
mkdir -p "$output"
archive="$output/$bailong_resource_archive"
[[ ! -e "$archive" ]] || { bailong_error "文件已存在：$archive"; exit 1; }
bailong_temp_dir="$(mktemp -d "$output/.resources-XXXXXX")"
bailong_phase_begin "1/2" "整理资源"
{
"$bailong_resource_tool" stage "$bailong_resource_manifest" "$PWD/local-assets" "$bailong_temp_dir/local-assets"
cp docs/开发资源获取.md "$bailong_temp_dir/DEV-ASSETS.md"
} > "$bailong_phase_log" 2>&1
bailong_phase_end
bailong_phase_begin "2/2" "压缩 ZIP"
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc "$bailong_temp_dir" "$archive" > "$bailong_phase_log" 2>&1
bailong_phase_end
"$bailong_resource_tool" record-size "$bailong_resource_manifest" "$archive"
bailong_artifact "资源包" "$archive"
print -r -- "下载大小：$(stat -f '%z' "$archive") 字节 · 尚未上传"
