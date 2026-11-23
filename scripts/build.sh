#!/bin/zsh
set -eu
bailong_invocation_dir="$PWD"
cd "${0:A:h:h}"
source scripts/terminal-ui.sh
source scripts/build-preflight.sh
source scripts/build-options.sh
bailong_entry=app; bailong_entry_command=build.command
bailong_parse_options "$@"
source scripts/build-resources.sh
phase_count=4
if (( bailong_build_dmg )); then
    source scripts/build-dmg.sh
    if (( bailong_dmg_artwork )); then bailong_select_dmg_background; fi
    phase_count=5
fi
source_commit="$(bailong_source_commit)"
bailong_header "构建应用" "$target_arch" "$source_commit"
bailong_check_tools
source scripts/swift-sources.sh
(( ${#swift_sources} > 0 )) || { bailong_error "未找到 Swift 源码。请完整解压仓库。"; exit 1; }
source scripts/swift-environment.sh
bailong_show_build_environment
bailong_ensure_resources "$bailong_resource_zip" "$bailong_resource_mode" "$bailong_download_requested"
version="$(<VERSION)"
output="dist/$version/$target_arch"
# 显式对比档位独立存放；无参构建继续使用默认目录。
if [[ "${BAILONG_BUILD_PROFILE:-auto}" != auto ]]; then
    output="$output/$bailong_build_profile"
fi
bailong_check_output "$output"
if (( bailong_check_only )); then bailong_ok "检查通过"; exit 0; fi
build_plist_entry="$(bailong_build_plist_entry "$source_commit" "$bailong_release_build")"
mkdir -p ".build/$target_arch" .build/module-cache
bailong_phase_begin "1/$phase_count" "编译主程序"
bailong_compile "$bailong_swiftc" $bailong_sdk_flags -O -whole-module-optimization -swift-version 5 -target "$target_arch-apple-macosx14.0" \
    -module-cache-path .build/module-cache $swift_sources \
    -o ".build/$target_arch/BailongPet" -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal -lsqlite3
bailong_phase_end
bailong_phase_begin "2/$phase_count" "编译跟随助手"
bailong_compile "$bailong_swiftc" $bailong_sdk_flags -O -swift-version 5 -target "$target_arch-apple-macosx14.0" \
    -module-cache-path .build/module-cache Sources/BailongPet/Infrastructure/FollowMonitor.swift Tools/FollowHelper/main.swift \
    -framework AppKit -o ".build/$target_arch/BailongFollow"
bailong_phase_end

app="$output/白龙桌宠Swift.app"
staging="$(mktemp -d "$output/.pet-XXXXXX")"
bailong_temp_dir="$staging"
bailong_phase_begin "3/$phase_count" "组装应用与资源"
{
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources/outputs/白龙桌宠素材"
cp ".build/$target_arch/BailongPet" "$staging/Contents/MacOS/BailongPet"
"$bailong_resource_tool" copy-app "$bailong_resource_manifest" "$PWD/local-assets" "$staging/Contents/Resources"
cp "${bailong_provider_icons[@]}" "$staging/Contents/Resources/"
cp VERSION THIRD-PARTY-NOTICES.md "$staging/Contents/Resources/"
cat > "$staging/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.appkit</string>
<key>CFBundleName</key><string>白龙桌宠Swift</string>
<key>CFBundleDisplayName</key><string>白龙桌宠Swift</string>
<key>CFBundleExecutable</key><string>BailongPet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${version%%-*}</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>BailongVersion</key><string>$version</string>
$build_plist_entry
<key>BailongAuthor</key><string>Joseph Blue</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>CFBundleAllowMixedLocalizations</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>点击本机文件链接时，恢复对应的访达窗口并选中文件。</string>
<key>CFBundleIconFile</key><string>BailongPet</string>
</dict></plist>
PLIST
helper="$staging/Contents/Library/Helpers/BailongFollow.app"
mkdir -p "$helper/Contents/MacOS"
cp ".build/$target_arch/BailongFollow" "$helper/Contents/MacOS/BailongFollow"
cat > "$helper/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.bailongpet.appkit.follow-helper</string>
<key>CFBundleName</key><string>白龙桌宠Swift跟随启动监测器</string>
<key>BailongAuthor</key><string>Joseph Blue</string>
<key>CFBundleExecutable</key><string>BailongFollow</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>${version%%-*}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
} > "$bailong_phase_log" 2>&1
bailong_phase_end
bailong_phase_begin "4/$phase_count" "本地签名并保存应用"
{
codesign --force --sign - "$helper"
codesign --force --sign - "$staging"
# 输出目录按版本隔离，只组装原生运行资源。
if [[ -d "$app" ]]; then rm -rf "$app"; fi
mv "$staging" "$app"
bailong_temp_dir=""
} > "$bailong_phase_log" 2>&1
bailong_phase_end
if (( bailong_build_dmg )); then
    dmg="$output/白龙桌宠Swift-$version-$target_arch.dmg"
    bailong_phase_begin "5/$phase_count" "制作 DMG"
    bailong_package_dmg "$app" "$dmg" "白龙桌宠Swift $version" "$bailong_dmg_artwork" > "$bailong_phase_log" 2>&1
    bailong_phase_end
fi
print "构建完成 · 总用时 $((SECONDS-bailong_started)) 秒"
bailong_artifact "应用" "$app"
if (( bailong_build_dmg )); then bailong_artifact "DMG" "$dmg"; fi

bailong_completed_actions "$app"
