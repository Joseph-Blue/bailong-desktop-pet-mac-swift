#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache \
    Sources/BailongPet/QuotaQuery.swift Sources/BailongPet/QuotaResetCards.swift Tests/QuotaQueryRegression.swift -o .build/QuotaQueryRegression
.build/QuotaQueryRegression
