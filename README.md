# 白龙桌宠 · Swift + AppKit

从零实现的独立 Mac 桌宠，版本 `0.1.0-dev.1`。应用逻辑、窗口和界面均使用 Swift + AppKit；原透明 WebM 由随包的 arm64 FFmpeg 解码，无 Python、PySide6 或 PyObjC 运行依赖。

依据作者 [v0.5.1 源码 b102e73](https://github.com/jingh12312-rgb/bailong-desktop-pet/commit/b102e734f20bb50889af12df5778f1499109f41b) 实现动画、移动、任务和公开进展通知。保留用户选择的吸边拖出直接待机、原生窗口和系统键位。Mac 版独立使用 SemVer 与中文变更记录。

## 当前交付

本地开发应用：`dist/白龙桌宠.app`。已通过 Swift 编译并生成 arm64 本地签名应用；**尚未启动应用或调用模型验收，不将编译成功当作运行验证。** 当前仍是开发版本，完整目标保持进行中。

- 单击互动，双击查询额度；拖动移动，左右边缘吸附；吸边单击展开，吸边拖出后直接待机。
- 菜单栏和右键菜单提供显示、对话、历史、动作预览、大小设置、音效/任务气泡/自移动/全屏隐藏开关与退出。
- 桌宠 50%—200%、气泡 50%—150%，原生滑块和整数输入。
- 任务输入使用 ⌘Enter 发送、Enter 换行；真实停止、默认拒绝的命令/文件审批、可编辑选项和秘密字段、取消提问停止任务。
- 内置任务显示公开摘要、执行进展和结果；外部只读观察通过本机 Codex 数据库获取公开回复、工具状态和失败摘要，不读取外部 reasoning。
- 外部对话可以准备可见记录草稿，在新对话手动发送；不冒充原始上下文续接。
- 自启动默认未安装。只有在菜单中实际选择启用后，才安装用户 LaunchAgent 跟随 Codex/ChatGPT。

## 构建与启动

本机安装 Apple Command Line Tools，使用 Apple Silicon 原生工具链：

```sh
./scripts/build.sh
open dist/白龙桌宠.app
```

构建最低系统目标 macOS 14，仅 arm64。未构建或验证 Intel；未进行 Developer ID 签名或公证。

资源放在 Git 忽略目录 `local-assets/`：

```text
local-assets/
  outputs/白龙桌宠素材/素材清单.json
  outputs/白龙桌宠素材/透明WebM/*.webm
  tools/ffmpeg
  sounds/click.wav
  sounds/来源.txt
  sounds/Kenney-License.txt
  BailongPet.icns
```

本工作区已准备这些本地资源，来自现有 v0.5.1 素材和 imageio-ffmpeg 的 Mac arm64 二进制。克隆 Git 仓库不会自动带上素材与解码器。构建脚本将它们复制进 .app，无须用户全局安装 FFmpeg。素材和原作许可见 [来源记录](docs/来源与架构.md)。

## 数据和 Codex

独立保存到 `~/Library/Application Support/BailongPetAppKit`，不会读写旧 Python 版的 BailongPet 历史。可用 `BAILONG_DATA_DIR` 指定另一目录。设置使用新应用标识 `com.bailongpet.appkit`。

Codex 可执行文件优先取 `BAILONG_CODEX_BIN`，其次 PATH、常用 Mac 安装位置。沿用用户已安装 CLI 的登录，不读取或复制凭证；用户点击发送才产生模型任务。任务工作区默认是数据目录内的 Workspace，可在历史窗选择其他文件夹。

外部同步只读 `CODEX_HOME`（默认 ~/.codex）下的 `state_5.sqlite` 与 `thread_history_1.sqlite`。格式不兼容会显示同步不可用，不能据此报任务完成。停止只针对桌宠自己的任务和子进程。

## 开发状态

[实施记录与未完成项](docs/实施记录.md) · [来源与架构](docs/来源与架构.md) · [项目约束](AGENTS.md) · [中文变更记录](CHANGELOG.md)
