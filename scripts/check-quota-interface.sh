#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# 只用内存样例和临时原生窗口，不访问账号、聊天记录或模型服务。
source scripts/swift-sources.sh
source scripts/swift-environment.sh
[[ -f Tests/QuotaInterfaceRegression.swift ]] || { print -u2 "本地回归夹具不存在：Tests/QuotaInterfaceRegression.swift（Tests 不随公开仓库提供）。"; exit 1; }
mkdir -p .build/module-cache
"$bailong_swiftc" $bailong_sdk_flags -O -whole-module-optimization -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/module-cache \
    $swift_library_sources Tests/QuotaInterfaceRegression.swift -o .build/QuotaInterfaceRegression -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal -lsqlite3
.build/QuotaInterfaceRegression "$@"
