#!/bin/zsh
set -eu
cd "${0:A:h:h}"
[[ -f Tests/QuotaQueryRegression.swift ]] || { print -u2 "缺少本地 Tests/QuotaQueryRegression.swift 夹具。"; exit 1; }
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path .build/module-cache \
    Sources/BailongPet/Codex/QuotaQuery.swift Sources/BailongPet/Codex/QuotaResetCards.swift Tests/QuotaQueryRegression.swift -o .build/QuotaQueryRegression
.build/QuotaQueryRegression
