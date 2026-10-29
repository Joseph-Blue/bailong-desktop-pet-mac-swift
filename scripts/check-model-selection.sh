#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/module-cache
sources=(Sources/BailongPet/*.swift)
sources=(${sources:#*/main.swift})
xcrun swiftc -O -whole-module-optimization -swift-version 5 -module-cache-path .build/module-cache \
    $sources Tests/ModelSelectionRegression.swift -o .build/ModelSelectionRegression -framework AppKit -lsqlite3
.build/ModelSelectionRegression
