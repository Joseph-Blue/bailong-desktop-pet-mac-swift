#!/bin/sh
# 创建供其他 Git 状态模块复用的离线工作区，标准输出仅返回新目录。
set -eu
temp_base=${TMPDIR:-/tmp}
fixture=$(mktemp -d "${temp_base%/}/geminya-git.XXXXXX")
workspace="$fixture/workspace"
core="$workspace/geminya-core"
mkdir -p "$core"
# 仓库身份、配置与 hooks 限于夹具，所有 clone 都来自本地目录。
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
git_fixture() {
    git -c user.name=Fixture -c user.email=fixture@example.invalid -c core.hooksPath=/dev/null "$@"
}
git_fixture -C "$core" init -q -b core-dev
echo base > "$core/tracked.txt"
git_fixture -C "$core" add tracked.txt
git_fixture -C "$core" commit -qm base
git_fixture -C "$core" tag base
# 两个提交的树完全相同，可以只更改真实 Git 元数据验证刷新。
git_fixture -C "$core" commit -q --allow-empty -m next
git_fixture -C "$core" tag next
for platform in macos windows; do
    repo="$workspace/geminya-$platform"
    git_fixture init -q -b "$platform" "$repo"
    git_fixture -C "$repo" -c protocol.file.allow=always submodule add -q "$core" core
    git_fixture -C "$repo/core" checkout -q --detach base
    git_fixture -C "$repo" add core
    git_fixture -C "$repo" commit -qm platform
done
git_fixture -C "$workspace/geminya-macos/core" checkout -q --detach next
echo dirty >> "$workspace/geminya-windows/core/tracked.txt"
git_fixture -C "$core" branch alternate next
git_fixture -C "$core" worktree add -q -b linked "$fixture/linked"
printf '%s\n' "$fixture"
