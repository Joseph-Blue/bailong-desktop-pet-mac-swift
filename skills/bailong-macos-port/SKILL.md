---
name: bailong-macos-port
description: 维护白龙娘桌宠的 macOS 移植，按目标工程区分 Swift/AppKit 与旧 Python/PySide6 路线；用于原生界面、动画交互、Codex 对接、架构打包和来源对照。
---

# 白龙娘桌宠 macOS 维护

## 先确定工程

读取目标仓库 AGENTS.md、VERSION 与 Git 状态，再查看相关函数。当前 Swift 仓库名为 `bailong-desktop-pet-mac-swift`，本地旧目录名可能仍为 `bailong-desktop-pet-appkit`。旧 `bailong-desktop-pet-mac` 为 Python/PySide6 路线，不能把两者的运行依赖、数据路径或构建命令混用。

- Swift 工程使用 Swift + AppKit，动画也使用原生视图；透明 WebM 由随包 FFmpeg 解码，不引入 Python/PySide6 运行依赖。
- 只有明确在旧 Python 工程工作时，才保留 PySide6 动画和 AppKit 辅助窗口；不得据旧路线结论回退 Swift 工程。
- 作者 `jingh12312-rgb/bailong-desktop-pet` 只读参考，已采用基线为 v0.5.1 / b102e73。行为对照只读相关函数，不整仓复制、不默认更新基线，不运行 Windows EXE。
- 用户本轮指令优先；未要求运行验收或发布时，不自动执行这些操作。当前工程不派发其他 agent。

## Swift 实施入口

| 改动 | 入口 |
| --- | --- |
| 动画、吸边、移动、鼠标、气泡调度 | Sources/BailongPet/Pet.swift、Resources.swift |
| 分类设置、重置、偏好与快捷键规则 | Settings.swift、Preferences.swift |
| 临时聊天、历史、输入、侧栏 | ChatUI.swift、HistoryViews.swift、History.swift |
| 气泡与 Markdown、逐步显示 | NativeUI.swift、MarkdownText.swift、StreamingText.swift |
| 内置任务、模型选择 | ChatController.swift、Codex.swift、ModelSelection.swift |
| 外部只读观察 | DesktopSync.swift |
| 名称、图标、关于、启动 | AppIcons.swift、main.swift、Autostart.swift |
| 打包 | scripts/build.sh、VERSION |

## 交互约定

- 只有吸边状态保留 250ms：单击松手后到期只召回，不执行自定义单击动作；期间第二次按下取消召回并执行双击动作，默认查询额度。吸边拖动立即召回，不受等待限制。普通拖动保留拖拽及落地动画。
- 普通单击不延迟，因此双击第一下已执行单击动作。右键按下立即弹菜单；右键双击先关闭菜单，再执行所选动作，默认临时聊天。不要重加所有点击的统一等待。
- 移动按整条路径缩短，保持方向；播放速度同时影响帧和位移时间窗。随机频率不代替拖拽、落地、额度等事件触发。不要为修边默认重生成素材；原素材和试修输出分开，试修被停用时保持原素材路径。
- 名字默认白龙娘，可自定义。固定界面文案使用偏好；用户消息、模型正文、原作署名、资源目录和持久化标识不作全局替换。应用包名为“白龙娘桌宠MacOS-Swift版”。
- 设置项左侧名称／说明、右侧控件，动画用影片符号，设置不单列关于。页脚文案“恢复本页设置为默认值”；全部恢复只处理已知偏好，不删除历史、素材或改变系统登录项。
- 两处输入共用 SendShortcut；写全按键：默认 ⌘ Command + ↩ Enter 发送、↩ Enter 换行；备选 ↩ Enter 发送、⇧ Shift + ↩ Enter 或 ⌥ Option + ↩ Enter 换行。输入法组字时不发送，所有提示随设置更新。

## 任务与数据边界

- 内置任务与外部只读观察分开；只有 completed 宣告成功。真实停止、默认拒绝审批、取消补充输入停止任务、历史保护和自有进程回收必须保留。
- 外部工具中间失败不再自动包装为桌宠错误通知；保留公开进展、最终回复、待审批／输入及最终失败。过滤旧合成提醒只作用展示，不删原始记录。
- Swift 数据目录是 `~/Library/Application Support/BailongPetAppKit`，包标识 `com.bailongpet.appkit`；改名和版本更新不迁移到旧 Python 数据目录。不得读取凭证或更改全局 Codex 配置，登录项只在用户主动启用时注册。

## 构建、验证与提交

- 开发运行使用 `scripts/run-dev.sh`；仅编译使用 `scripts/run-dev.sh --build-only`，当前开发脚本面向 arm64。
- 打包使用 `scripts/build.sh arm64` 或 `scripts/build.sh x86_64`。输出在 `dist/<架构>/白龙娘桌宠MacOS-Swift版.app`；Intel FFmpeg 位于 `local-assets/tools/x86_64/ffmpeg`，arm64 位于 `local-assets/tools/ffmpeg`。包内统一 `Contents/Resources/tools/ffmpeg`，不能混装架构。
- 当前 imageio-ffmpeg 0.6.0 的 Intel 7.1 二进制自带 nonfree and unredistributable 声明；仅用于本地构建，公开分发前需替换。不要将 arm64 的 GPL 说明套用到 Intel 关于页。
- 关于页按编译目标显示 Apple Silicon（arm64）或 Intel（x86_64）。交叉编译、签名和架构静态检查不等于 Intel 真机验收；本地 ad-hoc 签名不等于 Developer ID 或公证。
- 按改动做必要编译和静态检查；不自动跑 SHA-256、截图、视觉、自检、冒烟或模型请求。已有测试按授权范围使用，证据不足要明确未验收。
- 独立 SemVer；以 VERSION 为准。中文 commit 与 CHANGELOG。提交、推送和 Release 是分别授权的操作，已有明确授权时直接完成，不反复确认。
- 素材、FFmpeg、应用包、用户数据、备份、内部计划／对比／调查／实施记录不进 Git；只有可复用 skill、源码、构建说明及正式来源文档参与版本。旧历史已含排除内容时，仅取消追踪不够；首次远端发布按用户选择使用干净快照，旧历史只留本地，不推备份分支或 tags。
