# 白龙桌宠Swift · Dev

**这是 `joseph/dev` 开发分支，面向开发者，不属于普通用户的安装说明，也不提供开发版 Release 程序下载。** 普通用户请前往 [main 主线](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/tree/main)。

当前源码版本：**0.7.3-rc.1（开发分支候选版）**，本轮保留功能已整理为 main 的正式版 **0.7.3**，开发线保留 RC1 基线与完整迭代记录。当前 P0 是运行内存占用与释放机制，进度和验收条件见 [TODO](todo.md)。

基于 [jingh12312-rgb（風-隐）的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet)，由 Codex 使用 Swift + AppKit 原生重写，独立维护。动画使用透明 HEVC、AVFoundation 与 Core Image；界面支持液态玻璃和系统外观。

本项目作者：**Joseph Blue（约瑟Blue）**。

## 当前开发内容

| 方向 | 已落入源码的改动 |
| --- | --- |
| 运行内存 | 历史正文改为 SQLite 按需读取，缓存最多 16 条、合计 2 MiB；每页展示 20 轮。保存仅写变化正文，首次迁移保留旧 JSON；历史关闭释放显示缓存，外部同步减少重复快照，实时观察仅保留目标轮次正文。气泡隐藏释放富文本与临时视图，搜索弹出框关闭释放结果，任务结束释放消息聚合器。 |
| 气泡与滚动 | 共用正文尺寸和纵向滚动组件；按实际溢出显示原生滚动条，显隐不改变换行宽度。普通气泡从顶部阅读，历史进入会话时定位底部。 |
| 辅助窗口 | 文件浏览与保存、设置调色板打开时在发起屏幕居中，保留拖动；桌宠点击阻止默认应用窗口整体置前。 |
| 会话入口 | 临时输入窗用无围框的原生分段导航区分桌宠人设对话／Codex 项目对话，显示目标会话与工作区；历史列表显示来源类型。两入口分别缓存草稿，主按钮统一为发送，停止任务独立。 |
| 会话职责 | 内置桌宠对话与外部 Codex 会话分别处理发送、模型设置和状态；共用 Markdown、代码块、文件链接及显示组件。卡片管理、倒计时、历史渲染和输入窗已拆分。 |
| 模型与输入 | 两入口共用模型字段样式，人设对话可选模型，项目对话只读原设置；模型弹窗按内容和屏幕自适应，滑块松开提交。工作区链接、最多 200 字回复摘要 hover、发送按钮与快捷键提示共用组件。 |
| 进展与拷贝 | 复用标题流水、概览跑马灯、盲文及计时对齐；拷贝按钮统一反馈与恢复状态。正文打字机暂时停用，保留原设置值。 |
| 产物文件 | 将 Codex 的 `:codex-file-citation` 产物引用显示为文件名链接，与已有文件、图片入口共用访达定位逻辑。 |
| 文件修改摘要 | 气泡与历史共用文件列表，标题与总增减同排右对齐，默认展示 3 项并支持展开／收起；路径使用共用链接样式、文件名突出，右侧显示绿色 `+N`／红色 `−N`。历史搜索可展开隐藏的匹配项，无撤销或 diff 查看按钮。 |
| 设置与目录 | 外观模式和消息窗口材质采用原生分段选择；高级页可选择桌宠对话默认工作区，清理只将内置 Workspace 内容移到废纸篓。新对话提供默认／当前／其他工作区入口；已有会话目录不变。 |
| 显隐与召回 | 仅托盘菜单顶部提供带图标的隐藏／显示项；再次打开 App 召回原桌宠，保留任务，不重新打开已关闭的设置／历史。 |

沿用正式版的任务概览、额度查询、历史搜索、气泡审批与问卷、快捷回复／插话、原生代码块及本机文件定位。详细行为见 [来源与架构](docs/来源与架构.md)，开发迭代见 [CHANGELOG](CHANGELOG.md)。

当前开发版验证进度见 [P0 待办](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/blob/joseph/dev/todo.md)；本轮在保留按需加载、缓存边界和资源释放策略的基础上，修复跳转与界面布局、完善桌宠召回。

Silicon 版，最低目标机为 13 英寸 M1 MacBook Air，最低目标操作系统为 MacOS 14 Sonoma。

开发环境为16 英寸 M5 Pro MacBook Pro，当前操作系统为 MacOS 27.2 Golden Gate。

尚未完成最低要求机型运行验收，也没有能够实机测试 Intel Mac 社区测试版的设备。

## 分支与更新检查

- `main` 保留正式版源码和普通用户说明；`joseph/dev` 保留开发源码、完整开发变更、开发文档和待办。本地与远端使用相同开发分支名。
- 两条分支独立提交，不自动合并或变基。同步时明确选取改动，不把开发文档整体覆盖到主线。
- 本分支不创建程序 Release 或应用版本标签。开发素材通过独立的 `dev-assets-*` Pre-release 提供，不设为 Latest。
- 应用更新检查读取 GitHub 最新正式 Release，并排除草稿、预发布和带预发布后缀的版本；不读取分支中的 VERSION。开发分支版本号更高也不会进入正式更新提醒。

历史接入和文档跟踪范围见 [开发分支维护](docs/开发分支.md)。

## 获取资源与构建

先安装 Apple Command Line Tools，并使用包含 macOS 27 API 的 SDK。本项目当前使用 SDK 27.2、Apple Swift 6.4.2，应用运行目标为 macOS 14 起。

下载 [开发资源 ZIP](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/download/dev-assets-2026-11-02/bailong-dev-assets-2026-11-02.zip)，按 [开发资源获取](docs/开发资源获取.md) 解压到仓库。该文档还提供从已有 App 提取资源的方法、目录对应和素材制作入口。

```text
local-assets/
  native-hevc/catalog/素材清单.json
  native-hevc/catalog/samples.json
  native-hevc/catalog/透明HEVC/*.mov
  sounds/click.wav
  sounds/来源.txt
  sounds/Kenney-License.txt
  glass-symbols/
  BailongPet.icns
  openai-logo.png
```

资源不存放在 Git 中。`samples.json` 用于独立预览与 PNG 替换，不是 App 运行必需文件。

```sh
./scripts/run-dev.sh --build-only  # 仅编译
./scripts/build.sh arm64           # 构建 Apple Silicon App
./scripts/build.sh x86_64          # 按需构建 Intel App
./scripts/run-dev.sh               # 编译并开发运行
```

也可双击 `build.command`、`launch.command`、`run-dev.command`。版本取自 [VERSION](VERSION)，应用产物位于 `dist/native-hevc/<VERSION>/<架构>/白龙桌宠Swift.app`。正式版 0.7.3 提供 Apple Silicon 包与 Intel 社区测试包；Intel Mac 实机验收尚未完成，开发构建默认只选择 Apple Silicon。

三个入口会显示版本、目标架构、当前阶段和耗时。交互终端显示盲文转圈，重定向日志时使用普通阶段文本；原始诊断在阶段结束时输出，失败保留退出码。产物目录提供 `file://` 链接，在终端按住 ⌘ 单击可打开访达目录。

- `build.command` 默认只构建 Apple Silicon；Intel 须显式执行 `./build.command x86_64`。构建替换当前版本、当前架构的产物，不自动安装到 `/Applications`。
- `launch.command` 按当前进程架构打开已有应用，成功提示仅表示已提交打开请求。
- `run-dev.command` 编译或复用 Apple Silicon 开发程序；开发运行沿用现有设置和历史，终端需保持打开，Ctrl+C 停止。`--build-only` 只编译。


## 代码与维护入口

源码位于 `Sources/BailongPet/`，保持单个 Swift target：

| 目录 | 职责 |
| --- | --- |
| `App/`、`Pet/` | 启动退出、桌宠动作、素材播放、菜单与位置 |
| `Conversation/` | 任务与会话协调、消息聚合、历史及额度 |
| `Codex/` | 协议连接、外部记录读取、请求与同步 |
| `UI/Bubble/`、`UI/Chat/` | 气泡卡片与正文布局、临时输入和历史界面 |
| `UI/Shared/` | 富文本、代码块、文件摘要、输入、复制反馈及文字动效 |
| `Settings/`、`Infrastructure/` | 偏好与设置页、更新、启动项、存储及恢复 |

- [维护 skill](skills/bailong-macos-port/SKILL.md)：修改入口、共用组件和维护流程。
- [AGENTS.md](AGENTS.md)：协作边界与具体产品规则。
- [来源与架构](docs/来源与架构.md)：技术方案、来源及现行行为。
- [todo](todo.md)：稳定性观察、解耦、资源优化与后续功能。
- [完整变更记录](CHANGELOG.md)与[历史变更索引](docs/开发变更索引.md)：保留开发过程及正式版汇总。
- 历史调查：[启动闪退](docs/启动闪退调查.md)、[0.6.0-dev.10 设置界面检查](docs/设置界面检查.md)。

## 来源与反馈

原作参考基线为 **v0.5.1 / b102e73**。动画、音效、图标与软件组件的来源见 [来源与架构](docs/来源与架构.md) 和应用设置中的“关于 → 开源项目、技术栈与致谢”。

[提交 Issue](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues) 时请提供应用版本、macOS 版本和复现步骤；Codex 问题另附桌面端版本，并注明是桌宠内置对话还是 Codex 原会话。
