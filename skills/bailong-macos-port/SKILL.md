---
name: bailong-macos-port
description: 维护白龙桌宠Swift（Swift + AppKit 原生工程），覆盖气泡与会话双通道、Codex 桌面端同步、原生玻璃界面、透明 HEVC 动画、构建脚本及工程文档；与早期 Python/PySide6 原作严格区分。
---

# 白龙桌宠Swift 维护指南

## 1. 工作前核对

1. 阅读仓库根目录 [AGENTS.md](../../AGENTS.md)、[VERSION](../../VERSION) 与当前 Git 状态，保留工作区已有改动。本工程公开仓库为 `Joseph-Blue/bailong-desktop-pet-mac-swift`。
2. 按下表定位状态拥有者、显示组件与调用入口后再阅读源码。行为对照基线为相邻目录 `../bailong-desktop-pet`（`v0.5.1 / b102e73`），仅按需只读参考函数，不修改参考仓库。
3. 优先复用并修正既有公共组件。内置人设对话与外部 Codex 会话保持各自的连接、发送与生命周期语义，共用展示组件；不引入通用消息总线、插件框架或纯转发层，不按文件行数机械拆分。
4. 按当次明确授权执行必要的类型检查、编译或定向验证；不派发子 agent，未经批准不回滚提交。报告时区分源码实现、编译检查与真机运行验收；界面与文档直陈功能、状态和错误原因，不写免责声明、假设性风险或重复叮嘱。

## 2. 分支与文档分工

- **分支策略**：`joseph/dev`（跟踪 `origin/joseph/dev`）维护开发源码、完整 [CHANGELOG](../../CHANGELOG.md)、[来源与架构](../../docs/来源与架构.md) 与 [TODO](../../todo.md)；`main` 保留正式版源码与普通用户说明，跨分支合并、变基、打标签与推送均按当次授权执行。
- **发布边界**：开发分支不创建程序 Release 或应用版本标签；开发素材包经授权后使用独立 `dev-assets-*` 标签发布 Pre-release（标记为非 Latest）。纯文档整理不递增 [VERSION](../../VERSION)。
- **跟踪范围**：运行素材、构建产物、用户数据、本机 `docs/实施记录.md` 与 `Tests/` 均不进 Git；公开开发文档范围见 `.gitignore` 与 [开发分支维护](../../docs/开发分支.md)，素材导入与制作流程见 [开发资源获取](../../docs/开发资源获取.md)。
- **单一事实源**：细粒度产品参数与现行交互规则统一维护在 [来源与架构](../../docs/来源与架构.md) 顶部的 `#current-*` 章节，原地更新所属主题，避免多处复制不同步。

## 3. 源码职责地图

以下路径相对 `Sources/BailongPet/`（根目录脚本与工具除外），保持单 Swift target，由 `scripts/swift-sources.sh` 递归收集：

| 模块 | 核心文件 |
| --- | --- |
| 启动、退出与菜单 | `App/main.swift`、`App/RunLifecycle.swift`、`Pet/PetMenu.swift` |
| 动画解码、图层与吸边 | `Pet/Pet.swift`、`Pet/Resources.swift`、`Pet/StreamingAnimation.swift`、`Pet/CPUFrameConverter.swift`、`Pet/SpriteView.swift`、`Pet/NotchDock.swift` |
| 气泡布局、滚动与动效 | `UI/Bubble/Bubble.swift`、`BubblePresentation.swift`、`BubbleBodyScrollView.swift`、`Pet/BubbleMotion.swift` |
| 卡片栈、倒计时与问卷 | `UI/Bubble/BubbleCardStore.swift`、`BubbleCountdown.swift`、`BubbleTaskList.swift`、`QuestionForm.swift` |
| 内置任务与消息聚合 | `Conversation/ChatController.swift`、`Conversation/TaskMessageAccumulator.swift`、`Conversation/CommandSummary.swift` |
| 外部会话观察与提交 | `Conversation/DesktopConversationSession.swift`、`Codex/DesktopHistoryReader.swift`、`Codex/DesktopSync.swift`、`Codex/DesktopReply.swift`、`Codex/RequestCoordinator.swift` |
| 公开进展、审批与问答 | `Codex/TaskActivity.swift`、`Codex/DesktopRuntimeProjection.swift`、`Codex/DesktopApprovalReader.swift`、`Codex/DesktopApproval.swift`、`Codex/DesktopQuestionReply.swift` |
| 历史存储、搜索与输入面板 | `Conversation/History.swift`、`Conversation/HistorySearch.swift`、`Conversation/ConversationOrder.swift`、`UI/Chat/ChatUI.swift`、`UI/Chat/ChatComposer.swift`、`UI/Chat/TranscriptRenderer.swift`、`UI/Chat/TranscriptPresentation.swift` |
| 用户消息整理与模型选择 | `Codex/UserInputText.swift`、`UI/Chat/ChatComposerComponents.swift`、`UI/Chat/ChatViewLayout.swift`、`Codex/ModelSelection.swift` |
| 窗口、玻璃材质与公共控件 | `App/InterfaceWindows.swift`、`UI/Shared/NativeControls.swift`、`UI/Shared/GlassEdgeHighlight.swift`、`UI/Shared/PanelPresentation.swift` |
| 富文本、代码块与动效 | `UI/Shared/MarkdownText.swift`、`MessageTextView.swift`、`CodeBlockRendering.swift`、`ProgressTextEffects.swift`、`InlineStatusLayout.swift`、`CopyFeedback.swift` |
| 工作区状态条与任务信息栏 | `UI/Chat/WorkspaceStatusView.swift`、`WorkspaceStatusPanel.swift`、`WorkspaceFileList.swift`、`Infrastructure/GitWorkspace.swift`、`GitWorkspaceObservation.swift` |
| 文件引用与修改统计 | `UI/Shared/CodexFileCitation.swift`、`Conversation/FileEditSummary.swift`、`UI/Shared/FileEditRendering.swift`、`UI/Shared/FileEditPresentation.swift`、`UI/MessageFileLink.swift`、`UI/FinderFileReveal.swift` |
| 额度与 Token 用量控件 | `Conversation/QuotaCoordinator.swift`、`Codex/QuotaQuery.swift`、`Codex/QuotaResetCards.swift`、`Conversation/TokenUsage.swift`、`Codex/TurnTokenReader.swift`、`Codex/LocalDailyTokenReader.swift`、`UI/Shared/TokenDisclosureControl.swift`、`UI/Shared/TokenUsageView.swift` |
| 图标、关于页与设置系统 | `App/GitIcons.swift`、`App/AppIcons.swift`、`Settings/AboutPage.swift`、`Settings/Preferences.swift`、`Settings/Settings.swift`、`Settings/SettingsForm.swift`、`Settings/Pages/`、`Settings/SettingsSearch.swift` |
| 更新、启动项、诊断与恢复 | `Infrastructure/Updates.swift`、`Infrastructure/Autostart.swift`、`Infrastructure/FollowMonitor.swift`、`Infrastructure/Diagnostics.swift`、`Infrastructure/Recovery.swift` |
| 构建脚本与素材工具 | `scripts/swift-sources.sh`、`scripts/swift-environment.sh`、`scripts/build.sh`、`Tools/NativeHEVC/ApplyPNGRepairs.swift` |

## 4. 核心模块实现要点

### 气泡、文本排版与 Token 控件

- 卡片渲染直接使用 `BubbleCard` 和 `BubbleContent`。外部与内置任务提交 `TurnCompletion` 数据，气泡与历史负责 TextKit 字体、底栏和操作按钮。
- **卡片与计时**：`BubbleCardStore` 负责卡片去重、上限淘汰与优先级排序，`BubbleCountdown` 管理倒计时；正文视图不持有会话发送生命周期，重排不得丢失未提交问卷草稿。
- **滚动与首行稳定**：`BubbleBodyScrollView` 与 `BubbleBodyLayout` 保证左右边距对称、纵向滚动条位于右边距内且显隐不改变换行宽度。`MessageTextView` 增量替换变化尾部；无选区写入后将插入点重置到 `{0, 0}` 并拦截容器尺寸变化触发的自动滚向文末，`documentView` 原点固定为 `.zero`。普通气泡打开、切卡或换新内容时在布局完成后单次回顶，用户主动滚动即取消待执行回顶；2 秒短进展气泡按自然高度排版、超宽文本由 TextKit 单行尾部省略，专用 clip 锁定顶部且禁用滚动。
- **Token 汇总与展开**：额度弹窗、历史底栏与任务完成气泡底栏统一复用 `TokenDisclosureControl`（以文字大写字高中心对齐 SF Symbol `alignmentRect.midY`，悬停文字或箭头呈现整块圆角背景，点击整块切换展开）；展开明细使用独立 TextKit 视图（`TranscriptTokenText`）与真实 `NSTextTab` 对齐列宽并支持文本选择。
- **动效与代码块**：`ProgressTextEffects` 提供标题扫光与超宽跑马灯，主气泡进展、任务概览与 2 秒气泡首行共用 `TaskActivity.groupActivity` 的标题、图标及结果角标，短气泡第二行只放新增的公开细节，有内容时显示；代码块采用原生 `NSTextTableBlock` 与 `CodeBlockHeaderLayout`。用户输入由 `UserInputText` 剥离附件包装后渲染，外部执行中插话按 `userMessage` ID 合并卡片并沿用原任务计时。

### 任务信息栏与工作区状态条

- **两套独立入口**：气泡内「任务信息栏」（`taskInfoBarEnabled`，默认开启）在正文与操作按钮之间展示 Git 状态与本轮文件增删（隐藏目录名，同会话主气泡与短进展自动去重）。独立「工作区状态条」（`WorkspaceStatusPanel`，`gitWindowEnabled` 默认关闭）仅设**常驻显示**与**隐藏**二态，无倒计时或变化召回；右键与状态栏菜单动态切换「显示工作区状态条」／「隐藏工作区状态条」，点击状态条关闭按钮同步将 `gitWindowEnabled` 设为 `false`。
- **双数据源严格区分**：Git 仓库状态通过只读 `/usr/bin/git --no-optional-locks` 查询并配合 `FSEvents` `400ms` 防抖监听刷新；本轮文件增删来自所属轮次已完成的 `fileChange` 累计（`Turn.fileEdits`）。两类详情弹窗共用透明 `WorkspaceFileTable` 与 `PopoverDismissal`（单击选中、双击访达定位、右键定位或复制完整路径）。

### 双通道会话、审批与历史

- 外部回复由 `DesktopConversationSession` 按 `ObservedDesktopTurn` 选原轮次，开始新轮与插话共用 `DesktopReply.mode(for:)`，终态集合在 `TaskOutcome`。内置流式刷新走 `ChatInterface.refreshTurn`，历史顺序由 `ConversationOrder` 维护。

- **输入隔离**：`ChatNavigation` 与 `ChatDraftCache` 按入口和会话隔离草稿，异步回执核对目标身份。临时输入与历史回复共用 `MessageEditor`／`MessageInputBox` 与 `SendShortcut`，保持 `.nonactivatingPanel` 非激活交互与中文组字保护。
- **连接与冷启动**：内置会话复用单条 `codex app-server` 子进程连接；外部会话通过 `DesktopConversationSession` 经桌面 IPC 提交 `start-turn` v2／`steer-turn` v1（沿用原会话模型与权限，不加人设）。桌面端未运行或启动不足 10 秒时进入冷启动准备：受控后台补投递 `codex://threads/<id>`（`activates = false`）以应对冷启动换窗丢路由，配合短窗口 `thread-owner-discovery` 与会话广播即时唤醒，连上后同连接读取设置并提交；提交后回执不明归入 `Unconfirmed`，严禁自动重发。
- **审批与历史保护**：外部审批兼容 `thread-stream-state-changed` v11～v13，默认拒绝且气泡内无键盘默认允许；敏感提问仅跳转 Codex。历史采用 SQLite schema 3 按需加载正文（`16` 条／`2 MiB` LRU，每页 `20` 轮），关闭记录时冻结快照，损坏或迁移失败时进入只读保护，写入失败暂停自动保存并提供重试。

### 原生界面、动画与额度

- **界面与设置**：遵循 `macos-golden-gate-design`，共 9 个设置分类（原“性能”页已整合为“画质与性能”）。“消息与提醒”通过 `MessageSettingsPage` 的行定义生成表单、静态搜索和本页恢复范围，管理台词与管理动作通过 `SettingsListItem` 共用表格和搜索项目身份，`SettingsItemList` 只为选中项挂载编辑控件。其余页面在 `SettingsSearchEntry.all` 维护索引。改动偏好键时核对迁移、导入导出与恢复范围。前景强调文字使用 `AppAccent.foregroundColor` 保证明暗对比度，分段与开关控件经 `contentFilters` 映射 8 组预设取样色。
- **动画与吸边**：`AVAssetReader` + `vImage` 解码透明 HEVC，交由 `SpriteView` `CALayer.contents` 显示；旧流续播至新流满足起播余量后再按 `generation` 交接，默认开启 `24 MiB` 开头缓存、平滑过渡与孤立杂点清理。素材选帧 `Timer` 与几何 `NSView.displayLink` 分离，内建屏幕刘海位置按 `safeAreaInsets.top` 与 auxiliary 区域实时读取。内存指标统一表述为“运行内存 (RAM)”。
- **多套餐额度**：区分 Free（`ChatGPT 免费用户`＋单条 `30 天额度`）、Go（单条 `30 天额度`）、3 档 Business（`Business Standard`／`Business Premium`／`Business 按量计费`，优先取 `account/read` 具体子档）及双窗口套餐（`≤10%` 橙、`≤5%` 红），支持可选运行内存 (RAM) 缓存与强调色「立即刷新」。不读凭证文件，更新检查仅读取公开正式 Release。

## 5. 按需构建命令（须经当次授权）

```sh
./scripts/run-dev.sh --build-only  # 仅编译开发可执行文件（输出至 .build/dev/BailongPetDev）
./scripts/build.sh arm64           # 构建 Apple Silicon App 与跟随启动 helper
```

纯文档修改不触发应用编译或测试；默认仅构建 Apple Silicon（Intel 构建须经当次明确授权）。详细环境、档位与素材参数见 [开发资源获取](../../docs/开发资源获取.md) 与 [来源与架构](../../docs/来源与架构.md#current-build)。
