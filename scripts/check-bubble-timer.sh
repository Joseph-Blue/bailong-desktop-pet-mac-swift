#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache \
    Sources/BailongPet/{ChatUI,NativeUI,History,Resources,StreamingAnimation,Codex,Presentation,QuotaResetCards,BubbleMotion,Appearance,StreamingText,ModelSelection,MarkdownText,AppIcons,Updates,SemanticVersion,HistoryViews,Preferences,Settings,Autostart,FollowMonitor}.swift \
    Tests/BubbleTimerRegression.swift -o .build/BubbleTimerRegression -framework AppKit -framework AVFoundation -framework CoreImage -framework Metal
.build/BubbleTimerRegression
