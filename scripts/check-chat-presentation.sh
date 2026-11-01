#!/bin/zsh
set -eu
cd "${0:A:h:h}"
source scripts/swift-sources.sh
[[ -f Tests/ChatPresentationRegression.swift ]] || { print -u2 "本地回归夹具不存在：Tests/ChatPresentationRegression.swift（Tests 不随公开仓库提供）。"; exit 1; }
mkdir -p .build/module-cache
xcrun swiftc -O -whole-module-optimization -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path .build/module-cache \
    $swift_library_sources Tests/ChatPresentationRegression.swift -o .build/ChatPresentationRegression -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal -lsqlite3
.build/ChatPresentationRegression "$@"
