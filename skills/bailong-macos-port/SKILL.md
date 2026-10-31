---
name: bailong-macos-port
description: 维护白龙娘桌宠 macOS 原生 Swift/AppKit 工程的动画、界面、性能、Codex 对接、打包与来源记录；与历史 Python 工程严格区分。
---

# 白龙娘桌宠 macOS 维护

## 工程与授权

先读目标 AGENTS.md、VERSION 与 Git 状态。Swift 工程位于 bailong-desktop-pet-appkit，仓库名 bailong-desktop-pet-mac-swift；旧 bailong-desktop-pet-mac 的 Python/PySide6 路线只作参考，不混用依赖和数据目录。不派发其他 agent。

当前本地 main 为 0.3.0，运行采用 Swift + AppKit、AVFoundation、Core Image、透明 HEVC。FFmpeg 旧运行／打包及离线 WebM 转码入口已删除，禁止重新引入。原始 WebM、原始／修复 PNG、现有 HEVC 与旧素材备份保留本地，不追踪进 Git。

原作基线 v0.5.1 / b102e73；只读相关函数，不整仓复制、不修改参考仓库、不运行 Windows EXE。素材修复及反哺同意不扩大为其他许可，不擅自添加许可证。

## 入口

| 内容 | 文件 |
|---|---|
| 桌宠交互和调度 | Sources/BailongPet/Pet.swift |
| 动画解码与缓冲 | Resources.swift、StreamingAnimation.swift |
| 性能设置和窗口 | Preferences.swift、Settings.swift、Diagnostics.swift、GPUStatistics.swift |
| 气泡和盲文动画 | NativeUI.swift、Pet.swift、DesktopSync.swift |
| 内置任务与外部观察 | ChatController.swift、Codex.swift、DesktopSync.swift |
| 历史与对话界面 | History.swift、HistoryViews.swift、ChatUI.swift、StreamingText.swift |
| 跟随启动 | Autostart.swift、FollowMonitor.swift、Tools/FollowHelper/main.swift |
| 素材接入 | Tools/NativeHEVC/ApplyPNGRepairs.swift、scripts/apply-native-png-repairs.sh |
| 构建与架构 | scripts/build.sh、scripts/run-dev.sh、Package.swift、VERSION |
| 记录 | docs/来源与架构.md（追踪）；docs/实施记录.md（本地忽略） |

## 动画与性能约束

- 默认流式读取，首帧就绪即播放；512×512、24 帧后续缓冲、满帧。画质可选 384／256；缓冲为整数 6～240，右对齐刻度滑块和输入框，两端标注，非法值结束编辑恢复 24，滑块松开才提交。容量不预分配、不跨动作预读。
- FPS 上限可选满帧／30／24／20／15。满帧沿用 30 Hz 调度当前 24／30 fps 素材；不插帧、不改动作时长。拖动位置跟随鼠标，动画画面不绕过定时器。
- 画质、帧率上限、缓冲帧数、整段预加载依序排列。整段预加载默认关闭，启用后缓冲置灰且保留值，当前动作完整解码后播放，同动作循环复用；不预热整个素材库。提示“不推荐，会显著增加运行内存 (RAM) 占用。”
- 图像和 Alpha 命中同分辨率，首帧边界映射到 512 逻辑坐标，菜单栏剪影裁剪映射到实际像素。generation 取消过期任务，循环 epoch 丢弃旧帧，退出等待当前后台解码完成。
- 性能统计独立 NSWindow、默认关闭；开启显示 Dock，关闭销毁窗口及采样，禁用绿灯。设置开关保留设置 key window；Dock／菜单主动召回可激活统计。底栏 pin 开关与右侧关闭／拷贝 centerY 对齐，置顶默认 true 并记忆。
- FPS／HI／LO 醒目，CPU 总体在前、单核基准在后；GPU 明确应用资源组时间比例，失败不报零；Swap 区分系统交换空间、进程压缩和累计换入。运行内存 (RAM) 与磁盘存储分别标注。不把像素预算当进程总占用，也不把 dev.7 用户反馈的 280～300 MB 当新版测量结果。
- 统计窗口不添加 hover 废话，不留固定大块空白；拷贝只复制当前显示信息。页面不加重复的“显示窗口”行。

## 气泡、任务与数据

- 临时气泡“我还在留意进展…”及“让我看看额度…”前显示盲文滚动字符和一个空格。动画由 Bubble 的独立 Timer 更新，只改标签；正文更新不重置动画，标题替换／隐藏／销毁停止，不写入 History 或原任务文本。
- 吸边单击保留作者 250ms 判定，第二次按下取消召回并查询额度；吸边拖动召回，普通拖拽播放拖拽及落地。移动按射线裁短，不分轴剪裁。
- 产品身份固定为白龙娘桌宠MacOS-Swift版，自定义名字只用于称呼及互动。非交互文案不选中，历史、任务回复、输入与技术错误等保留复制。
- 内置任务和外部只读观察分开，真实停止、默认拒绝审批、历史保护及进程回收必须保留；仅 completed 可宣告成功。外部工具中间失败不生成额外失败提醒，保留最终失败、审批及补充输入。
- 数据目录 ~/Library/Application Support/BailongPetAppKit，不读凭证、不改全局 Codex 连接配置、不自动启用 LaunchAgent。跟随启动仅识别 Codex／ChatGPT 桌面应用，按标识与启动周期识别，拒绝临时路径；用户主动修复／更新配置。

## 原生素材与构建

准备已有 HEVC catalog、sounds 和图标后，运行 `scripts/build.sh arm64`。当前仅交付 Silicon；Intel 入口保留但不自动追加构建。主程序与 helper 同架构，包内不带原始素材、中间文件或用户数据，输出 `dist/native-hevc/<VERSION>/<架构>/白龙娘桌宠MacOS-Swift版.app`。

PNG 接入用 `scripts/apply-native-png-repairs.sh <PNG根目录>`；追加 `--landing` 仅处理落地。Core Image 读取透明 PNG，AVAssetWriter 输出 ProRes 4444，再由系统 avconvert 编码 HEVC with Alpha。成功后切换 catalog 并保留旧目录。新原生编码工具在 0.3.0 只完成编译，未重编码现有素材，不宣称已视觉验收。

独立预览 `scripts/prepare-native-hevc.sh` 只复制现有原生 MOV 和 samples.json，复用根 VERSION；AVPlayerLayer 预览不代表完整桌宠交互验收。没有旧 WebM 转码入口，不能把原版 WebM 目录直接当运行资源。

仅做必要编译和针对改动的静态检查，不自动执行截图、视觉、SHA-256、自检、冒烟或模型请求。历史本地 Tests 仅在用户授权时运行，不把构建成功写成运行验收。

## 版本、文档与下一步

SemVer 独立维护，新增功能升次版本、修复升补丁版本，开发中用 dev 标识；中文 commit 与 CHANGELOG。合并、推送和 Release 分别按用户授权执行，当前只授权本地 main 合并，不推送、不创建 Release、不改变可见性。

当前状态写入 README、CHANGELOG、追踪的 docs/来源与架构.md 和 AGENTS.md；过程细节留在本地实施记录，不把预发布流水堆入当前架构说明。技能项目副本与个人副本同步。

下一项功能为“检查更新”，尚未实现。不要把计划写成已具备网络版本查询、自动下载或安装。
