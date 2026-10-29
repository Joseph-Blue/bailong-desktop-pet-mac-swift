#!/bin/zsh
set -eu
cd "${0:A:h}"
exec ./scripts/run-dev.sh "$@"
