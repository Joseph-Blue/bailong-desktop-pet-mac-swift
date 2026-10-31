#!/bin/zsh
set -eu
cd "${0:A:h:h}"
# 只用内存样例和临时原生窗口，不访问账号、聊天记录或模型服务。
mkdir -p .build/module-cache
xcrun swiftc -O -swift-version 5 -module-cache-path .build/module-cache \
    Sources/BailongPet/{ChatUI,NativeUI,History,Resources,StreamingAnimation,Codex,Presentation,QuotaResetCards,BubbleMotion,Appearance,StreamingText,ModelSelection,MarkdownText,AppIcons,Updates,SemanticVersion,HistoryViews,Preferences,Settings,Autostart,FollowMonitor}.swift \
    Tests/QuotaInterfaceRegression.swift -o .build/QuotaInterfaceRegression -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal
.build/QuotaInterfaceRegression "$@"
