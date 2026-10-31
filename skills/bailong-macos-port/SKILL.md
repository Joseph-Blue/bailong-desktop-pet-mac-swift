---
name: bailong-macos-port
description: 维护白龙娘桌宠的 macOS 移植，按目标工程区分 Swift/AppKit 与旧 Python/PySide6 路线；用于原生界面、动画交互、Codex 对接、架构打包和来源对照。
---

# 白龙娘桌宠 macOS 维护

## 先确定工程

读取目标仓库 AGENTS.md、VERSION 与 Git 状态，再查看相关函数。当前 Swift 仓库名为 `bailong-desktop-pet-mac-swift`，本地旧目录名可能仍为 `bailong-desktop-pet-appkit`。旧 `bailong-desktop-pet-mac` 为 Python/PySide6 路线，不能把两者的运行依赖、数据路径或构建命令混用。

- Swift 工程使用 Swift + AppKit，动画也使用原生视图；`codex/native-hevc-alpha` 分支使用透明 HEVC、AVFoundation 与 Core Image，FFmpeg 仅用于离线素材准备，包内不携带。旧 0.2.x 的随包 FFmpeg 路线只作历史，不引入 Python/PySide6 运行依赖。
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
| 名称、图标、关于、启动 | AppIcons.swift、main.swift、Autostart.swift、FollowMonitor.swift、Tools/FollowHelper/main.swift |
| 完整素材准备、打包 | Tools/NativeHEVC/AssetInfo.swift、scripts/prepare-native-assets.sh、scripts/build.sh、VERSION |
| 独立预览 | Tools/NativeHEVC/Preview.swift、Tools/NativeHEVC/VERSION、scripts/prepare-native-hevc.sh |

## 原生动画路线

- 完整桌宠使用 AVAssetReader 输出 BGRA，Core Image Lanczos 缩放为 512×512 的预乘 RGBA CGImage；显示与透明命中读取同一帧。保留首帧回调、基础动作预热和整段帧缓存，非固定缓存预算 192 MiB 不等于进程总内存上限，也不代表流式播放或内存改善已验收。
- 解码取消使用 generation 和 cancelReading，过期回调不能进入界面；退出等待本进程内解码结束。不得重新引入 FFmpeg 运行子进程。
- 离线链路为原 VP9 alpha WebM → FFmpeg 的 ProRes 4444 中间文件 → 系统 avconvert 的 PresetHEVCHighestQualityWithAlpha → MOV。保留原 WebM、清单参数及顺序；不宣称无损。生成工具已有原生首帧解码检查，元数据正常不代表可解码。
- 独立预览使用 AVPlayerLooper / AVPlayerLayer，与完整桌宠的 AVAssetReader 链路不同；预览可播放不代表完整交互已验收。技术栈与来源见目标仓库 `docs/来源与架构.md`，阶段证据见本地 `docs/实施记录.md`。

## 交互约定

- 只有吸边状态保留 250ms：单击松手后到期只召回，不执行自定义单击动作；期间第二次按下取消召回并执行双击动作，默认查询额度。吸边拖动立即召回，不受等待限制。普通拖动保留拖拽及落地动画。
- 普通单击不延迟，因此双击第一下已执行单击动作。右键按下立即弹菜单；右键双击先关闭菜单，再执行所选动作，默认临时聊天。不要重加所有点击的统一等待。
- 移动按整条路径缩短，保持方向；播放速度同时影响帧和位移时间窗。随机频率不代替拖拽、落地、额度等事件触发。不要为修边默认重生成素材；原素材和试修输出分开，试修被停用时保持原素材路径。
- 角色名字默认白龙娘，可自定义，仅用于角色称呼与互动文案；菜单、关于、设置导出、历史标题等产品身份保持固定，应用包名为“白龙娘桌宠MacOS-Swift版”。用户消息、模型正文、原作署名、资源目录和持久化标识不作全局替换。
- 设置项左侧名称／说明、右侧控件，动画用影片符号，设置不单列关于。页脚文案“恢复本页设置为默认值”；全部恢复只处理已知偏好，不删除历史、素材或改变系统登录项。
- 两处输入共用 SendShortcut；写全按键：默认 ⌘ Command + ↩ Enter 发送、↩ Enter 换行；备选 ↩ Enter 发送、⇧ Shift + ↩ Enter 或 ⌥ Option + ↩ Enter 换行。输入法组字时不发送，所有提示随设置更新。

## 任务与数据边界

- 内置任务与外部只读观察分开；只有 completed 宣告成功。真实停止、默认拒绝审批、取消补充输入停止任务、历史保护和自有进程回收必须保留。
- 外部工具中间失败不再自动包装为桌宠错误通知；保留公开进展、最终回复、待审批／输入及最终失败。过滤旧合成提醒只作用展示，不删原始记录。
- Swift 数据目录是 `~/Library/Application Support/BailongPetAppKit`，包标识 `com.bailongpet.appkit`；改名和版本更新不迁移到旧 Python 数据目录。不得读取凭证或更改全局 Codex 配置，登录项只在用户主动启用时注册。
- 跟随启动仅面向 Codex／ChatGPT 桌面应用，不识别 CLI；独立 BailongFollow.app 通过 bundle identifier（com.openai.codex / com.openai.chat）、PID 与启动时间识别运行周期，手动退出只抑制当前周期。拒绝注册 AppTranslocation 临时路径；旧配置由用户从固定位置打开完整应用后，在设置中修复／更新，不自动修改 LaunchAgent。

## 构建、验证与提交

- 开发运行使用 `scripts/run-dev.sh`；仅编译使用 `scripts/run-dev.sh --build-only`，当前开发脚本面向 arm64。
- 首次运行 `scripts/prepare-native-assets.sh` 准备完整素材，输出 `local-assets/native-hevc/catalog`；已有目录时停止，重新转码前保留并移走旧目录。FFmpeg 按构建主机架构选用 `local-assets/tools/ffmpeg` 或 `local-assets/tools/x86_64/ffmpeg`，不是按应用目标架构选择；只用于离线转码，其许可不等同于应用运行依赖。
- 打包使用 `scripts/build.sh arm64` 或 `scripts/build.sh x86_64`，最低 macOS 14。输出在 `dist/native-hevc/<VERSION>/<架构>/白龙娘桌宠MacOS-Swift版.app`；主程序与 `Contents/Library/Helpers/BailongFollow.app` 必须同架构，包内不携带 FFmpeg、WebM 或 ProRes 中间文件。
- 关于页按编译目标显示 Apple Silicon（arm64）或 Intel（x86_64）。交叉编译、签名和架构静态检查不等于 Intel 真机验收；本地 ad-hoc 签名不等于 Developer ID 或公证。
- 按改动做必要编译和静态检查；不自动跑 SHA-256、截图、视觉、自检、冒烟或模型请求。已有测试按授权范围使用，证据不足要明确未验收。
- 独立 SemVer；以 VERSION 为准。中文 commit 与 CHANGELOG。提交、推送和 Release 是分别授权的操作，已有明确授权时直接完成，不反复确认。
- 原生 HEVC 分支完成后构建两架构完整应用供用户 review；未经 review 后的新指令不合并 main。完整应用与预览分别使用根目录 VERSION 和 Tools/NativeHEVC/VERSION，不能混用；纯文档更新不重复构建。
- 素材、FFmpeg、应用包、用户数据、备份、内部计划／对比／调查／实施记录不进 Git；只有可复用 skill、源码、构建说明及正式来源文档参与版本。旧历史已含排除内容时，仅取消追踪不够；首次远端发布按用户选择使用干净快照，旧历史只留本地，不推备份分支或 tags。
- 独立仓库维护，不创建上游 Fork；远端现状与操作授权分开，以当轮指令为准，不凭旧文档断言可见性，不自动改变可见性或创建 Release。保留原作来源，不能擅自给素材或原作添加许可。实施进展写入本地 `docs/实施记录.md`，该文件由 Git 忽略。
