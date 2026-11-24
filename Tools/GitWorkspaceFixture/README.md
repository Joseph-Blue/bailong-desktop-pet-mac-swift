# Geminya Git 状态复现工作区

执行 `fixture=$(sh Tools/GitWorkspaceFixture/create.sh)`。脚本在新临时目录中创建本地 Git 仓库和两个内容相同的提交 `base`、`next`。以下路径均相对于 `$fixture`。用 Git 对照时可运行 `git --no-optional-locks -C <路径> status --porcelain=v2 --branch --ignore-submodules=none`。

| 入口 | 初始预期 |
| --- | --- |
| `workspace` | 列出 `geminya-core`、`geminya-macos`、`geminya-windows` 三仓，各自的分支、文件和计数与进入单仓时一致 |
| `workspace/geminya-core` | 分支 `core-dev`，工作树干净 |
| `workspace/geminya-macos` | 分支 `macos`，仅 `core` 未暂存，`SC..`，子模块 HEAD 与父仓索引中的 gitlink 不同 |
| `workspace/geminya-windows` | 分支 `windows`，仅 `core` 未暂存，`S.M.`，子模块内部有跟踪文件修改 |
| 两个平台的 `core/` | 以该子模块为根读取自身状态；`.git` 文件指向各自父仓的 `.git/modules/core` |
| `linked` | 分支 `linked`，工作树干净；私有 HEAD 和共享引用位于 `geminya-core/.git` 下 |

## 状态转换与自动刷新

保持工作区根、macOS 子模块和链接工作树的观察器开启。每次操作后等待该入口的状态变化，再执行下一步。以下命令只用于上面创建的夹具。

```sh
module="$fixture/workspace/geminya-macos/core"
linked="$fixture/linked"

# SC.U，提交不一致且有未跟踪文件。父仓仍按一个未暂存条目计数。
echo new > "$module/new.txt"

# S..U，仅内部有修改。只写子模块真实 gitdir 中的 HEAD。
git -C "$module" update-ref --no-deref HEAD base

# 父仓与子模块都恢复干净。
rm "$module/new.txt"

# 工作树出现一个未跟踪文件。
echo new > "$linked/new.txt"

# 只动共享分支引用，linked 的提交变为 base。
git -C "$linked" update-ref refs/heads/linked base

# 只动链接工作树私有 HEAD，分支变为 alternate，提交变为 next。
git -C "$linked" symbolic-ref HEAD refs/heads/alternate

# 父仓已暂存 gitlink，子模块内部有未暂存修改。分别出现在两个分组。
git -C "$module" checkout --detach next
git -C "$module/.." add core
echo dirty >> "$module/tracked.txt"
```

这些步骤可直接用于 Geminya 的 Git 状态模块。验证监听时，由文件系统事件驱动下一次查询，逐次断言状态。手动刷新会掩盖监听路径遗漏。
