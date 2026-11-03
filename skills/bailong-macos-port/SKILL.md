---
name: bailong-macos-port
description: 维护白龙桌宠Swift 的 Swift/AppKit 工程，处理气泡与会话、Codex 对接、原生界面、动画性能、构建及开发文档；与历史 Python/PySide6 工程严格区分。
---

# 白龙桌宠Swift 维护

## 先确定范围

1. 读取目标仓库的 [AGENTS.md](../../AGENTS.md)、[VERSION](../../VERSION) 和 Git 状态，保留已有改动。当前工程为 `bailong-desktop-pet-appkit`，远端为 `Joseph-Blue/bailong-desktop-pet-mac-swift`。
2. 根据下表找到状态拥有者、显示组件及实际调用方，再读相关函数。原作参考为相邻 `bailong-desktop-pet` 的 v0.5.1 / b102e73，只读需要对照的实现，不修改参考仓库。
3. 优先修正已有共用组件。内置任务和外部 Codex 会话保留各自发送语义，复用显示能力；不为跨文件拆分增加通用消息总线、插件框架或纯转发层。文件接近 500 行时评估职责，不按行数强拆。
4. 更新对应文档，执行当次授权范围内的必要编译与静态检查。进度、结果及待手动验收项写入本机 `docs/实施记录.md`。

不派发其他 agent，不未经批准回滚。禁止静默吞错、猜测性兼容层和防御性文案；直接说明行为、影响与操作。区分源码实现、编译通过和运行验收，不自动执行截图、视觉、自检、冒烟、SHA-256 或真实模型请求。

## 分支与文档

- `joseph/dev` 跟踪 `origin/joseph/dev`，保留开发 README、完整 CHANGELOG 与历史索引；跟踪范围以 `.gitignore` 和 [开发分支维护](../../docs/开发分支.md) 为准。main 保留正式版，不自动合并、变基或推送。
- 开发线不发布程序 Release 或应用版本标签。素材资源经用户授权可用独立 `dev-assets-*` Pre-release，显式设为非 Latest。提交、推送、跨分支合并和发布分别按当次授权执行。
- VERSION 是应用与工具版本来源，使用 SemVer 和中文变更记录。文档整理本身不升版本；正式版汇总不删除开发线的历史记录。
- 素材、构建产物、用户数据、原始本机实施流水及本地 Tests 不进 Git。资源下载与制作方法维护在 [开发资源获取](../../docs/开发资源获取.md)，不将资源包混作程序发行包。
- README 面向当前分支读者；现行设计写入 [来源与架构](../../docs/来源与架构.md)，未来计划写入 [todo](../../todo.md)。本 skill 保留维护入口，精确产品参数与完整交互规则引用 AGENTS，避免再次逐版本追加重复规则。

## 代码职责地图

以下路径相对 `Sources/BailongPet/`，构建脚本除外：

| 职责 | 入口 |
| --- | --- |
| 启动、退出与菜单 | `App/main.swift`、`App/RunLifecycle.swift`、`Pet/PetMenu.swift` |
| 动画与素材 | `Pet/Pet.swift`、`Pet/Resources.swift`、`Pet/StreamingAnimation.swift` |
| 气泡展示与几何 | `UI/Bubble/Bubble.swift`、`BubblePresentation.swift`、`BubbleBodyScrollView.swift`（后两者同目录） |
| 卡片、倒计时与表单 | `UI/Bubble/BubbleCardStore.swift`、`BubbleCountdown.swift`、`BubbleTaskList.swift`、`QuestionForm.swift`（后三者同目录） |
| 内置任务与消息聚合 | `Conversation/ChatController.swift`、`Conversation/TaskMessageAccumulator.swift`、`Conversation/CommandSummary.swift` |
| 外部会话与请求 | `Conversation/DesktopConversationSession.swift`、`Codex/DesktopHistoryReader.swift`、`Codex/DesktopSync.swift`、`Codex/RequestCoordinator.swift` |
| 公开进展与审批 | `Codex/DesktopRuntimeProjection.swift`、`Codex/DesktopApprovalReader.swift`、`Codex/DesktopApproval.swift`、`Codex/DesktopQuestionReply.swift` |
| 历史与输入窗 | `Conversation/History.swift`、`Conversation/HistorySearch.swift`、`UI/Chat/ChatUI.swift`、`UI/Chat/ChatComposer.swift`、`UI/Chat/TranscriptRenderer.swift` |
| 共用显示 | `UI/Shared/MarkdownText.swift`、`MessageTextView.swift`、`CodeBlockRendering.swift`、`ProgressTextEffects.swift`、`InlineStatusLayout.swift`、`CopyFeedback.swift`（后五者同目录） |
| 文件产物与修改统计 | `UI/Shared/CodexFileCitation.swift`、`Conversation/FileEditSummary.swift`、`UI/Shared/FileEditRendering.swift`、`UI/Shared/FileEditPresentation.swift`、`UI/MessageFileLink.swift`、`UI/FinderFileReveal.swift` |
| 额度 | `Conversation/QuotaCoordinator.swift`、`Codex/QuotaQuery.swift`、`Codex/QuotaResetCards.swift`、`UI/SubscriptionManagement.swift` |
| 设置 | `Settings/Preferences.swift`、`Settings/Settings.swift`、`Settings/SettingsForm.swift`、`Settings/Pages/`、`Settings/SettingsSearch.swift` |
| 更新、启动项与恢复 | `Infrastructure/Updates.swift`、`Infrastructure/Autostart.swift`、`Infrastructure/FollowMonitor.swift`、`Infrastructure/Recovery.swift` |
| 构建与 PNG 接入（仓库根目录） | `scripts/swift-sources.sh`、`scripts/build.sh`、`Tools/NativeHEVC/ApplyPNGRepairs.swift` |

保持单 Swift target。源码通过 `scripts/swift-sources.sh` 递归收集；移动文件时检查引用和 helper 的独立构建路径，不另维护一套手写主程序清单。

## 气泡、文本与复用

- `BubbleCardStore` 拥有身份合并、保留上限、优先级和选卡；`BubbleCountdown` 拥有停留时间。正文视图不管理发送或任务生命周期，拆分不能重建已有问卷草稿。
- `BubbleBodyScrollView` 管理气泡实际文档高度、纵向视口和阅读位置；只有内容溢出才启用原生滚动条，不自绘轨道。`BubbleBodyLayout` 统一正文与视口宽度，左右正文边距对称，轨道使用右边距，禁止重复扣除 gutter。
- 气泡 `lineFragmentPadding` 为 0，输入框及历史保留自身边距。滚动条显隐不改变换行宽度，气泡比例或字号真实变化才重新排版；多行阅读与输入容器禁止横向偏移，单行系统编辑器保持原生行为。
- 普通气泡打开、切卡及正文变化从顶部显示；历史进入会话或重新打开窗口时到最下方，同会话刷新保留阅读位置，搜索显式定位优先。配色刷新不视为进入会话，不用持续锁顶或自动追尾修复布局。
- `MessageTextView` 用同一 TextKit 容器测量富文本，只替换变化尾部；未变化文本不重新排版。`TranscriptRenderer` 缓存包含全部显示内容，新增结构化字段须同步签名和搜索。
- `ProgressTextEffects` 共用标题流水与概览跑马灯，盲文仅在显示层生成。超宽才滚动，同文刷新保留相位；隐藏停止，动态效果关闭或减少动态效果时静态显示。正文打字机当前停用，保留并置灰原偏好。
- `InlineStatusLayout` 共用文字基线、盲文与秒表定位；`CopyFeedback` 共用写入剪贴板及反馈，恢复原标题、图标和 imagePosition，纯图标按钮保持空标题与 imageOnly。
- 代码块使用原生 NSTextTableBlock，语言标签与拷贝按钮共用 `CodeBlockHeaderLayout`。拷贝与关闭按钮复用 `HoverIconButton` 的悬停和按压反馈；不新增代码执行或远程高亮依赖。

## 会话入口与选择状态

- `ChatNavigation` 负责目标切换，`ChatDraftCache` 按入口和会话分别保留内存草稿；历史浏览目标、临时发送目标与运行任务不可共用一个选择变量。
- `ChatInputState` 只提供显示状态；发送传递明确会话与入口，异步回执不得清空或关闭后来选择的会话。主按钮统一“发送”，停止任务独立且核对目标身份。
- `ChatModelLoader` 每入口独立，并核对工作区请求身份；外部会话原设置只读。`AccentTabSelector` 共用关于页和输入窗的主题色原生分页。
- 临时输入窗继续独立于消息卡片；窗口展示协调、Dock 关闭及误召唤待处理，勿把当前代码描述为已经修复。

## 两种会话与数据

- 内置任务由 `ChatController` 管理连接和真实生命周期，`TaskMessageAccumulator` 聚合公开消息；同连接复用已加载线程身份，不反复 resume 或抢占其他 writer。每轮沿用用户选择的模型和思考档位。
- 外部观察通过 `DesktopHistoryReader`／`DesktopSync`，设置、明确回复及插话由 `DesktopConversationSession` 管理。发送沿用原会话设置，不附加桌宠人格；按原请求、轮次和窗口身份处理回执，超时保留草稿及待确认状态，不自动重发或改成新会话。
- 仅 completed 表示成功。中间工具错误不冒充整轮失败，缺少助手正文不以用户输入或会话标题回填。新命令记录只保存状态及命令摘要，不写 aggregatedOutput；已有历史保持原文。
- 实时进展只采用公开 reasoning.summary 和工具结构化字段。敏感问题仅跳转 Codex，不显示或保存答案；审批默认拒绝，真实停止、请求身份校验和进程清理必须保留。
- 历史关闭时冻结快照，重新开启不补录关闭期间变化。损坏或不支持的数据保持只读，不以空历史覆盖；保存失败暂停自动写入，提供显式重试。详细迁移与恢复行为遵循 AGENTS。

## 文件引用与链接链路

- `CodexFileCitation` 在 `MarkdownText` 入口将 `:codex-file-citation{path="…" ...}` 转为文件名链接，使用绝对路径，不按扩展名限制。用 Foundation 源码位置排除代码块、行内代码及已有链接；不完整标记保留原文，历史源文本不改写。
- Markdown 链接、图片入口、imageGeneration 的公开 savedPath、产物引用及文件修改摘要共用 `MessageTextView → MessageFileLink → FinderFileReveal`。相对路径取所属会话 cwd，仅点击时检查文件；非本机链接交给系统，`sandbox:` 保留下载提示。
- 文件点击复用访达目标目录窗口、取消该窗口最小化并选中文件；没有对应窗口才创建。固定脚本通过参数接收路径，不恢复全部窗口，`.app` 只定位不运行，不新增无关 App 权限。
- `FileEditSummary` 共用内外来源的 completed fileChange：内置按 item ID 替换，轮次内同路径合并；add／delete 按完整文本行数，update 按 diff hunk 统计。数值是本轮完成修改的累计量，不是最终 Git 净差异；缺少 diff 仅显示路径。
- `FileEditRendering` 在气泡和历史中共用原生摘要，标题下显示总计，默认 3 项并支持展开／收起。`FileEditPresentation` 只管理显示层展开状态，同身份更新保留，离开当前正文清理；搜索展开隐藏匹配项。复用 TextKit 与原滚动容器，不添加撤销或 diff 操作。摘要存入可选 `Turn.fileEdits`，不保存原始 diff、不拼进助手正文；快照、搜索和缓存签名同步维护。外部文件汇总读取完整轮次，不受近期消息数量限制。

## 原生界面与设置

界面修改采用已安装的 `macos-golden-gate-design` skill，继续使用 AppKit。设置和历史保留原生分栏、工具栏与列表，液态玻璃只影响背景，正文与输入框保持稳定挂载；不顺带修改第三方 skill。

- `SettingsForm` 统一控件、编辑回调和搜索锚点；设置页增删改名或移动时同步 `SettingsSearchEntry.all`，标题、分组和条件须对应真实控件。建立搜索索引不得创建页面或触发预览、存储扫描和登录项查询。
- 临时输入、历史回复与问卷复用 `MessageEditor`／`MessageInputBox`，发送快捷键来自 `SendShortcut`，保留中文组字保护。NSBox 与焦点层为同级视图，建立共同父视图后再激活约束。
- 危险确认无默认回车操作；普通按钮用强调色，危险与警告保留语义色。应用 hover 使用 `HoverHelp`，关闭按钮与卡片箭头不新增 tooltip，保留辅助功能名称。
- 模板使用 `{用户名}`／`{桌宠名}`／`{特定称呼}`，迁移仅处理指定模板字段，不替换名字字面值或历史。留空恢复与特定称呼占位规则见 AGENTS。

## 动画、额度与系统集成

- 使用透明 HEVC、AVFoundation 与 Core Image，不重新引入 FFmpeg。PNG 接入使用 AVAssetWriter 和系统 avconvert；原素材与修复副本保留在本地。
- 默认 720×720、流式 24 帧缓冲、满帧，满帧按真实素材帧率调度；整段预加载默认关闭，不预热全素材库。素材解码与几何 displayLink 分离，隐藏和结束释放相应计时器，不以屏幕刷新率增加解码。
- 性能窗口关闭即停止统计。产品统一写“运行内存 (RAM)”，不将像素估算、旧版反馈或系统 Swap 写成当前进程实测。
- 每次额度重新请求，先额度、并行账号，晚到数据仅补同次查询；不缓存旧结果冒充新查询。remaining ≤5% 红色、≤10% 橙色，同时作用于百分比和进度条，无百分比行不套阈值。
- 不读取凭证、Keychain、auth.json 或修改全局 Codex 配置，不为额度增加登录。启动更新检查默认关闭，仅接收正式 Release，不自动安装应用。
- 登录／跟随启动只维护用户已启用项，尊重系统撤销许可；不要求安装到 /Applications，不接受 AppTranslocation，跟随仅识别 Codex／ChatGPT 桌面端。

## 构建与交付

资源准备见 [开发资源获取](../../docs/开发资源获取.md)。构建入口：

```sh
./scripts/run-dev.sh --build-only  # 仅编译
./scripts/build.sh arm64           # Apple Silicon App 与跟随助手
```

按用户当次范围选择命令；文档修改不触发应用构建。Intel 缺少合适真机，保留源码入口，不追加构建。交付说明列出具体改动、执行过的检查、产物位置及待手动验收事项。提交或发布前核对范围，不将构建通过写成界面或真实 Codex 链路已验收。
