# 白龙桌宠Swift · Dev

**这是 `joseph/dev` 开发分支，面向开发与调试，不属于普通用户的安装与使用说明。本分支不提供 Release 程序下载。**

当前源码版本：**0.6.3-dev.1**。基于 0.6.2 建立；本次只整理开发历史与文档，应用功能源码保持不变。

普通用户请前往 [main 主线说明](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/tree/main)。

基于 [jingh12312-rgb 的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet)，由 Codex 进行 Swift + AppKit 原生重写，独立维护。当前使用透明 HEVC、AVFoundation 与 Core Image。

## 分支与更新检查

- `main`：正式版源码与普通用户说明。
- `joseph/dev`：开发源码、完整开发变更、调查记录与待办；本地和 GitHub 使用相同分支名。
- 两条分支独立提交；需要同步时明确选取改动，不自动合并或变基，不把开发文档整体覆盖到主线。
- `-dev` 是源码版本的预发布后缀。本分支不创建 GitHub Release，也不发布可执行附件。
- 应用更新检查只读取 GitHub 的最新正式 Release，不读取分支中的 VERSION；同时排除草稿、预发布 Release 和带预发布后缀的版本。因此开发分支版本号更高也不会成为正式更新提醒。

## 开发资料

- [完整变更记录](CHANGELOG.md)：恢复开发迭代，保留正式版汇总。
- [历史变更索引](docs/开发变更索引.md)：逐份查看原始 CHANGELOG。
- [开发分支维护](docs/开发分支.md)：历史接入、分支同步与跟踪范围。
- [开发待办](todo.md)：后续功能、滚动实验与跨 App 隐私通知排查。
- [来源与架构](docs/来源与架构.md)：当前设计、技术栈与行为约束。
- [启动闪退调查](docs/启动闪退调查.md)：早期版本的故障与修复记录。
- [设置界面检查](docs/设置界面检查.md)：0.6.0-dev.10 的界面检查与验收范围。

## 从源码构建

需要 Apple Command Line Tools，以及以下本地资源：

```text
local-assets/
  native-hevc/catalog/素材清单.json
  native-hevc/catalog/透明HEVC/*.mov
  sounds/click.wav
  sounds/来源.txt
  glass-symbols/
  BailongPet.icns
  openai-logo.png
```

资源不存放在 Git 中，可从原生 HEVC 版 App 的 `Contents/Resources` 提取。PNG 素材接入见 [原生素材工具](Tools/NativeHEVC/README.md)。

```sh
./scripts/build.sh arm64           # 构建 Apple Silicon App
./scripts/run-dev.sh --build-only  # 仅编译
./scripts/run-dev.sh               # 开发运行
```

也可双击 `build.command`、`launch.command`、`run-dev.command`。构建版本取自 [VERSION](VERSION)，产物位于 `dist/native-hevc/<VERSION>/arm64/白龙桌宠Swift.app`。Intel 源码构建入口为 `./scripts/build.sh x86_64`。

## 来源与反馈

原作参考基线为 **v0.5.1 / b102e73**。动画、音效、图标与软件组件的来源见 [来源与架构](docs/来源与架构.md) 和设置中的“关于 → 开源项目、技术栈与致谢”。

反馈问题请提供应用版本、macOS 版本和复现步骤；Codex 问题另附桌面端版本，并注明桌宠内置对话或 Codex 原会话。[提交 Issue](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues)
