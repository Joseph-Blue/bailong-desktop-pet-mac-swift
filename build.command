#!/bin/zsh
set -eu
if (( $# == 0 )) && [[ -t 0 && -t 1 ]]; then export BAILONG_INTERACTIVE="${BAILONG_INTERACTIVE:-1}"; fi
exec "${0:A:h}/scripts/build.sh" "$@"
