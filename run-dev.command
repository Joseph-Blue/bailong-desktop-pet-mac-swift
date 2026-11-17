#!/bin/zsh
set -eu
cd "${0:A:h}"
if (( $# == 0 )) && [[ -t 0 && -t 1 ]]; then export BAILONG_INTERACTIVE="${BAILONG_INTERACTIVE:-1}"; fi
exec ./scripts/run-dev.sh "$@"
