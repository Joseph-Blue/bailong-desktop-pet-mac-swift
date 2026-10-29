#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/module-cache
xcrun swiftc -O -swift-version 5 -module-cache-path .build/module-cache \
    Sources/BailongPet/{ChatUI,NativeUI,History,Resources,Codex,Presentation,Appearance,StreamingText,ModelSelection,MarkdownText,AppIcons,HistoryViews,Preferences,Settings,Autostart}.swift \
    Tests/ChatPresentationRegression.swift -o .build/ChatPresentationRegression -framework AppKit
.build/ChatPresentationRegression "$@"
