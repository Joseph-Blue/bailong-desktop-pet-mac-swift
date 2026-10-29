#!/bin/zsh
set -e
cd "${0:A:h}"
exec open "dist/$(uname -m)/白龙娘桌宠MacOS-Swift版.app"
