#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# 仅复现和回归启动崩溃，不访问真实会话、模型服务或桌宠资源。
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache \
    Sources/BailongPet/{ChatUI,NativeUI,History,Resources,Codex,Presentation,Appearance,StreamingText,ModelSelection,MarkdownText,AppIcons,HistoryViews,Preferences,Settings,Autostart}.swift \
    Tests/HistorySelectionRegression.swift -o .build/HistorySelectionRegression -framework AppKit
.build/HistorySelectionRegression
