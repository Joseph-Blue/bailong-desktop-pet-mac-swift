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

- `joseph/dev` 跟踪 `origin/joseph/dev`，保留开发 README、完整 CHANGELOG 与历史索引；跟踪范围以 `.gitignore` 和 [开发分支维护](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/blob/joseph/dev/docs/开发分支.md) 为准。main 保留正式版，不自动合并、变基或推送。
- 开发线不发布程序 Release 或应用版本标签。素材资源经用户授权可用独立 `dev-assets-*` Pre-release，显式设为非 Latest。提交、推送、跨分支合并和发布分别按当次授权执行。
- VERSION 是应用与工具版本来源，使用 SemVer 和中文变更记录。文档整理本身不升版本；用户要求进入候选阶段时使用 `rc.1` 等预发布标识，同步 VERSION、README、AGENTS 与 CHANGELOG。候选版仍遵守开发分支的发布边界，汇总不删除开发线历史记录。
- 素材、构建产物、用户数据、原始本机实施流水及本地 Tests 不进 Git。资源下载与制作方法维护在 [开发资源获取](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/blob/joseph/dev/docs/开发资源获取.md)，不将资源包混作程序发行包。
- 主线 CHANGELOG 只记录相较上一个正式 Release 的最终变化，不搬入开发迭代流水；README 保留功能、安装和升级说明，实施进度与未验证项仅记入本机实施记录，主线不新增 todo。
- README 面向当前分支读者；现行设计写入 [来源与架构](../../docs/来源与架构.md)，未来计划写入 [开发分支待办](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/blob/joseph/dev/todo.md)。本 skill 保留维护入口，精确产品参数与完整交互规则引用 AGENTS，避免再次逐版本追加重复规则。

## 代码职责地图

以下路径相对 `Sources/BailongPet/`，构建脚本除外：

| 职责 | 入口 |
| --- | --- |
| 启动、退出与菜单 | `App/main.swift`、`App/RunLifecycle.swift`、`Pet/PetMenu.swift` |
| 动画、素材与吸边 | `Pet/Pet.swift`、`Pet/Resources.swift`、`Pet/StreamingAnimation.swift`、`Pet/NotchDock.swift` |
| 气泡展示与几何 | `UI/Bubble/Bubble.swift`、`BubblePresentation.swift`、`BubbleBodyScrollView.swift`（后两者同目录） |
| 卡片、倒计时与表单 | `UI/Bubble/BubbleCardStore.swift`、`BubbleCountdown.swift`、`BubbleTaskList.swift`、`QuestionForm.swift`（后三者同目录） |
| 内置任务与消息聚合 | `Conversation/ChatController.swift`、`Conversation/TaskMessageAccumulator.swift`、`Conversation/CommandSummary.swift` |
| 外部会话与请求 | `Conversation/DesktopConversationSession.swift`、`Codex/DesktopHistoryReader.swift`、`Codex/DesktopSync.swift`、`Codex/RequestCoordinator.swift` |
| 公开进展与审批 | `Codex/TaskActivity.swift`、`Codex/DesktopRuntimeProjection.swift`、`Codex/DesktopApprovalReader.swift`、`Codex/DesktopApproval.swift`、`Codex/DesktopQuestionReply.swift` |
| 历史与输入窗 | `Conversation/History.swift`、`Conversation/HistorySearch.swift`、`UI/Chat/ChatUI.swift`、`UI/Chat/ChatComposer.swift`、`UI/Chat/TranscriptRenderer.swift`、`UI/Chat/TranscriptPresentation.swift` |
| 用户消息投影 | `Codex/UserInputText.swift`、`DesktopHistoryReader.swift`（同目录）、`Conversation/ChatController.swift`、`UI/Shared/MarkdownText.swift` |
| 输入显示与模型 | `UI/Chat/ChatComposerComponents.swift`、`UI/Chat/ChatViewLayout.swift`、`Codex/ModelSelection.swift` |
| 窗口生命周期与辅助面板 | `App/InterfaceWindows.swift`、`UI/Shared/PanelPresentation.swift` |
| 共用显示 | `UI/Shared/MarkdownText.swift`、`MessageTextView.swift`、`CodeBlockRendering.swift`、`ProgressTextEffects.swift`、`InlineStatusLayout.swift`、`CopyFeedback.swift`（后五者同目录） |
| 文件产物与修改统计 | `UI/Shared/CodexFileCitation.swift`、`Conversation/FileEditSummary.swift`、`UI/Shared/FileEditRendering.swift`、`UI/Shared/FileEditPresentation.swift`、`UI/MessageFileLink.swift`、`UI/FinderFileReveal.swift` |
| 额度 | `Conversation/QuotaCoordinator.swift`、`Codex/QuotaQuery.swift`、`Codex/QuotaResetCards.swift`、`UI/SubscriptionManagement.swift` |
| Token 统计 | `Conversation/TokenUsage.swift`、`Codex/TurnTokenReader.swift`、`Codex/LocalDailyTokenReader.swift`、`Codex/DailyTokenUsage.swift` |
| 设置 | `Settings/Preferences.swift`、`Settings/Settings.swift`、`Settings/SettingsForm.swift`、`Settings/Pages/`、`Settings/SettingsSearch.swift` |
| 更新、启动项与恢复 | `Infrastructure/Updates.swift`、`Infrastructure/Autostart.swift`、`Infrastructure/FollowMonitor.swift`、`Infrastructure/Recovery.swift` |
| 构建与 PNG 接入（仓库根目录） | `scripts/swift-sources.sh`、`scripts/build.sh`、`Tools/NativeHEVC/ApplyPNGRepairs.swift` |

保持单 Swift target。源码通过 `scripts/swift-sources.sh` 递归收集；移动文件时检查引用和 helper 的独立构建路径，不另维护一套手写主程序清单。

## 气泡、文本与复用

- `BubbleCardStore` 拥有身份合并、保留上限、优先级和选卡；`BubbleCountdown` 拥有停留时间。正文视图不管理发送或任务生命周期，拆分不能重建已有问卷草稿。
- `BubbleBodyScrollView` 管理气泡实际文档高度、纵向视口和阅读位置；只有内容溢出才启用原生滚动条，不自绘轨道。`BubbleBodyLayout` 统一正文与视口宽度，左右正文边距对称，轨道使用右边距，禁止重复扣除 gutter。
- 气泡 `lineFragmentPadding` 为 0，输入框及历史保留自身边距。滚动条显隐不改变换行宽度，气泡比例或字号真实变化才重新排版；多行阅读与输入容器禁止横向偏移，单行系统编辑器保持原生行为。
- 普通气泡打开、切卡及正文变化从顶部显示；历史进入会话或重新打开窗口时到最下方，同会话刷新保留阅读位置，搜索显式定位优先。配色刷新不视为进入会话，不用持续锁顶或自动追尾修复布局。
- `MessageTextView` 用同一 TextKit 容器测量富文本，只替换变化尾部；未变化文本不重新排版。底栏占位末尾不附加换行，避免 extraLineFragment 重复继承整块高度；轮次分隔由渲染器显式添加，明细展开／收起重新测量。`TranscriptRenderer` 缓存包含全部显示内容，新增结构化字段须同步签名和搜索。
- 可选择的 Token 表格使用同一 TextKit 管理器测量、显示与选择，显式建立文本存储与容器，避免共享 field editor 丢失制表位。底栏按实际文字／按钮高度排版；用户展开明细时显露末行并计入底部留白，后台刷新不持续追尾。
- `ProgressTextEffects` 共用标题流水与概览跑马灯；任务列表执行中标题复用纯标题流水和列表已有刷新计时，结束恢复静态，不新增行级定时器。盲文仅在显示层生成。超宽才滚动，同文刷新保留相位；隐藏停止，动态效果关闭或减少动态效果时静态显示。正文打字机当前停用，旧偏好仅保留兼容，不显示控件或搜索条目。
- 主气泡和概览进展取当前任务真实会话／轮次及开始时间；内置 activityKey 与 own 调度槽分开，不能取全局最新 activity。TaskActivity.line 展示真实公开摘要及操作，个性台词留在标题。主气泡进展单独增高，短进展气泡不追加跑马灯；固定图标由 TaskActivity 统一分类。
- `InlineStatusLayout` 共用文字基线、盲文与秒表定位；盲文按完整单元字形保持各帧中心一致，固定图标不随跑马灯滚动。`CopyFeedback` 共用写入剪贴板及反馈，恢复原标题、图标和 imagePosition，纯图标按钮保持空标题与 imageOnly。
- 代码块使用原生 NSTextTableBlock，语言标签与拷贝按钮共用 `CodeBlockHeaderLayout`。拷贝与关闭按钮复用 `HoverIconButton` 的悬停和按压反馈；不新增代码执行或远程高亮依赖。

用户输入由 `UserInputText` 统一整理，`MarkdownText.renderUserInput` 同时用于气泡与历史。识别附件包装前先处理空白和换行格式，提取真实提问与紧凑文件链接，不读取图片载荷；只在已识别包装中去除对应的重复图片占位，不全局删除用户写下的 `[图片]`。正文不解析为大标题，不添加额外段间距。显示层重复整理不得截断已生成的链接。

`ChatController.showUserMessage` 共用人设／项目用户卡片展示，各入口保留自己的接收台词。插话标题统一取 `ConversationLines` 的 `taskSteeringTemplate`，设置、搜索、恢复和导入导出共用元数据，不再拼接标题后缀。项目插话通过既有外部观察器按真实 userMessage ID 合并，排除问卷回执，沿用原任务计时；IPC 回执不另造卡片，不触发 taskStarted。显示复用不代表人设会话支持执行中发送，也不改变动画动作切换。

工具调用短进展气泡共用 `Bubble.showProgressToast`，按真实正文视口及 TextKit 排版截断，字素边界后追加 `...`；只截显示文本，hover 使用 TaskActivity 同一份有界工具摘要，原始数据保留。该模式关闭正文滚动，尺寸过渡也不出现滚动条；思考摘要沿用原规则。

普通命令摘要保留首行子命令、参数及对象，无“命令：”前缀；多行命令不拼接脚本正文，标记省略。结构化读取／搜索优先使用公开 commandActions，不根据原始脚本猜测意图；不把 raw tool arguments／输出或 reasoning.content 加入进展。摘要限制与图标选择以 AGENTS 和 TaskActivity 为准。

## 会话入口与选择状态

- `ChatNavigation` 负责目标切换，`ChatDraftCache` 按入口和会话分别保留内存草稿；历史浏览目标、临时发送目标与运行任务不可共用一个选择变量。
- `ChatInputState` 只提供显示状态；发送传递明确会话与入口，异步回执不得清空或关闭后来选择的会话。主按钮统一“发送”，停止任务独立且核对目标身份。
- `ChatModelLoader` 每入口独立，并核对工作区请求身份；外部会话由 `DesktopReply.Settings` 提供结构化只读模型数据，`ChatReadOnlyModelField` 共用展示。首次读取成功前禁用发送；失败保留草稿与真实原因，未加载会话不自动发送或用内置连接接管。
- 临时输入使用原生分段导航，会话选择同行右对齐；关于页保留原生 NSTabView。`ChatComposerComponents` 只拥有显示与用户操作回调，工作区点击由控制器调用 `FinderFileReveal.openDirectory`。最近回复从已有助手正文生成纯文本摘要，hover 最多 200 字，不额外查询或改写历史。
- 临时输入的短普通状态仅在模型旁有足够宽度时同行；错误、多行及超宽状态保留 ComposerStatusView 的整行换行、有限高度滚动与全文选择复制，不用省略号修复拥挤。
- 输入随草稿增高并封顶；发送按钮共用向上箭头及横向留白，完整发送／换行快捷键放在 hover，保留辅助功能说明。`ModelSelector` 展开时固定锚点宽度，关闭恢复；思考滑块松开提交，隐藏说明不占布局高度。
- `InterfaceWindows` 登记尚未关闭的普通窗口，最小化仍保留 Dock 入口，最后一个关闭后收回；Dock 不召回已经关闭的窗口。输入窗独立于卡片，主气泡通过 `BubblePlacement` 避让，进展小气泡在编辑期间让位。源码已接入，运行验收状态查看 README 和本机实施记录。

## 两种会话与数据

- 内置任务由 `ChatController` 管理连接和真实生命周期，`TaskMessageAccumulator` 聚合公开消息；同连接复用已加载线程身份，不反复 resume 或抢占其他 writer。每轮沿用用户选择的模型和思考档位。
- 外部观察通过 `DesktopHistoryReader`／`DesktopSync`，设置、明确回复及插话由 `DesktopConversationSession` 管理。发送沿用原会话设置，不附加桌宠人格；按原请求、轮次和窗口身份处理回执，超时保留草稿及待确认状态，不自动重发或改成新会话。
- 仅 completed 表示成功。中间工具错误不冒充整轮失败，缺少助手正文不以用户输入或会话标题回填。新命令记录只保存状态及命令摘要，不写 aggregatedOutput；已有历史保持原文。
- 实时进展只采用公开 reasoning.summary 和工具结构化字段。敏感问题仅跳转 Codex，不显示或保存答案；审批默认拒绝，真实停止、请求身份校验和进程清理必须保留。
- 外部用户输入通过现有数据库读取边界提取有界文本及附件计数，不放入实时进展投影。历史补缺仅处理当前页，通过 `HistoryStore.canEnrichInput` 和页请求身份校验；不覆盖已有明确发送的输入，不新增全库扫描或轮询。
- 历史关闭时冻结快照，重新开启不补录关闭期间变化。损坏或不支持的数据保持只读，不以空历史覆盖；保存失败暂停自动写入，提供显式重试。详细迁移与恢复行为遵循 AGENTS。

## 文件引用与链接链路

- `CodexFileCitation` 在 `MarkdownText` 入口将 `:codex-file-citation{path="…" ...}` 转为文件名链接，使用绝对路径，不按扩展名限制。用 Foundation 源码位置排除代码块、行内代码及已有链接；不完整标记保留原文，历史源文本不改写。
- Markdown 链接、图片入口、imageGeneration 的公开 savedPath、产物引用及文件修改摘要共用 `MessageTextView → MessageFileLink → FinderFileReveal`。相对路径取所属会话 cwd，仅点击时检查文件；非本机链接交给系统，`sandbox:` 保留下载提示。
- 裸 http(s)／mailto 地址在正文中补充链接属性，排除代码及已有链接。`LinkAppearance` 按 TextKit 实际字形命中；PetWindow 鼠标处理须保留文字链接和 LinkCursorControl 的手形，不用 linkTextAttributes 统一覆盖原有语义颜色。
- 文件点击复用访达目标目录窗口、取消该窗口最小化并选中文件；没有对应窗口才创建。固定脚本通过参数接收路径，不恢复全部窗口，`.app` 只定位不运行，不新增无关 App 权限。
- `FileEditSummary` 共用内外来源的 completed fileChange：内置按 item ID 替换，轮次内同路径合并；add／delete 按完整文本行数，update 按 diff hunk 统计。数值是本轮完成修改的累计量，不是最终 Git 净差异；缺少 diff 仅显示路径。
- `FileEditRendering` 在气泡和历史中共用原生摘要，标题右侧同排显示总计，默认 3 项并支持展开／收起；目录次级灰，文件名及展开／收起用正文色，增减保持绿／红，普通链接用强调色。`FileEditPresentation` 只管理显示层展开状态，同身份更新保留，离开当前正文清理；搜索展开隐藏匹配项。复用 TextKit 与原滚动容器，不添加撤销或 diff 操作。摘要存入可选 `Turn.fileEdits`，不保存原始 diff、不拼进助手正文；快照、搜索和缓存签名同步维护。外部文件汇总读取完整轮次，不受近期消息数量限制。

## 原生界面与设置

界面修改采用已安装的 `macos-golden-gate-design` skill，继续使用 AppKit。设置和历史保留原生分栏、工具栏与列表，液态玻璃只影响背景，正文与输入框保持稳定挂载；不顺带修改第三方 skill。

- `SettingsForm` 统一控件、编辑回调和搜索锚点；设置页增删改名或移动时同步 `SettingsSearchEntry.all`，标题、分组和条件须对应真实控件。建立搜索索引不得创建页面或触发预览、存储扫描和登录项查询。
- 临时输入、历史回复与问卷复用 `MessageEditor`／`MessageInputBox`，发送快捷键来自 `SendShortcut`，保留中文组字保护。NSBox 与焦点层为同级视图，建立共同父视图后再激活约束。
- 危险确认无默认回车操作；普通按钮用强调色，危险与警告保留语义色。应用 hover 使用 `HoverHelp`，关闭按钮与卡片箭头不新增 tooltip，保留辅助功能名称。
- 文件浏览／保存入口共用 `PanelPresentation`，以发起屏幕可用区域居中，首次显示完成布局后定位一次，保留独立拖动；调用方继续拥有文件选择及导入导出回调。`CenteredColorWell` 只在打开调色板时定位，颜色变化不重新居中。桌宠鼠标事件通过 AppKit 延迟并阻止默认窗口排序，明确打开设置／历史仍走原入口。
- 模板使用 `{用户名}`／`{桌宠名}`／`{特定称呼}`，迁移仅处理指定模板字段，不替换名字字面值或历史。留空恢复与特定称呼占位规则见 AGENTS。

## 动画、额度与系统集成

- 播放使用透明 HEVC 与 AVFoundation；当前源码的缩放和颜色转换由 CPU／vImage 处理，动作默认选择按原作：普通待机 4:1、吸边 7:3；任务中先排除上一动作，再按 35:65 选工作／待机组，组内默认均匀。手动频率与偏爱按场景权重成比例调整，其他随机互动保留减少重复。PNG 接入仍使用 Core Image、AVAssetWriter 和系统 avconvert。FFmpeg 播放实验暂缓，不能写成已经切换；离线抽帧的任务授权不等于允许修改运行依赖。原素材与修复副本保留在本地。
- 当前新用户默认 512×512、流式 12 帧缓冲、满帧，已有保存值保留；参数变更同步 AGENTS 与 README。满帧按真实素材帧率调度；整段预加载默认关闭，不预热全素材库。素材解码与几何 displayLink 分离，隐藏和结束释放相应计时器，不以屏幕刷新率增加解码。
- 性能窗口关闭即停止统计。产品统一写“运行内存 (RAM)”，不将像素估算、旧版反馈或系统 Swap 写成当前进程实测。
- 每次额度重新请求，先额度、并行账号，晚到数据仅补同次查询；不缓存旧结果冒充新查询。remaining ≤5% 红色、≤10% 橙色，同时作用于百分比和进度条，无百分比行不套阈值。
- 本轮 Token 使用会话累计快照的轮次增量，缓存输入已含于输入；不把最后请求或上下文占用当整轮用量。用量持久化与渲染签名同步维护，历史补缺只处理当前页并遵守冻结／只读策略。
- 今日 Token 来自当前 Codex 目录的本机日志，以本机时区统计累计增量并去重分叉事件，不冒充账号全量。额度先展示，再同次后台懒加载本机统计；晚到结果核对查询身份，不重开已关闭气泡。所有套餐按内容及屏幕边界布局，加载动画只存在于显示层。
- 刘海位置读取内建屏幕的 safeAreaInsets 与 auxiliary 区域，使用当前逻辑坐标，不按英寸、机型或 Retina 倍率推断。没有有效区域时保留可操作设置与原左右吸边，不伪造顶部收纳。SDK 声明可用性、实际类型检查与硬件验收分开记录。
- 刘海收纳尺寸与露出比例独立于动作 renderScale；当前参数查看 AGENTS／Preferences。正常顶部安全距离保留，收纳按角色轮廓定位，召回窗口位移与旋转／缩放使用同一过渡，不在末帧才移动原位。偏好改默认值保留显式用户选择。
- 不读取凭证、Keychain、auth.json 或修改全局 Codex 配置，不为额度增加登录。启动更新检查默认关闭，仅接收正式 Release，不自动安装应用。
- 登录／跟随启动只维护用户已启用项，尊重系统撤销许可；不要求安装到 /Applications，不接受 AppTranslocation，跟随仅识别 Codex／ChatGPT 桌面端。

## 构建与交付

资源准备见 [开发资源获取](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/blob/joseph/dev/docs/开发资源获取.md)。构建入口：

```sh
./scripts/run-dev.sh --build-only  # 仅编译
./scripts/build.sh arm64           # Apple Silicon App 与跟随助手
```

按用户当次范围选择命令；文档修改不触发应用编译或回归测试。代码改动按实际风险做必要检查，不自动运行全部本地 Tests；用户承担视觉 review 时不追加截图或视觉检查。`--build-only` 生成 `.build/dev/BailongPetDev`，不会更新现有 App 或 dist；打包前核对输出目录，独立试用不覆盖既有产物。默认只构建 Apple Silicon。0.7.4 提供 Apple Silicon 包与 Intel 社区测试包；Intel 实机验收未完成，后续 Intel 构建仍须当次明确授权。交付说明列出具体改动、执行过的检查、产物位置及待手动验收事项。提交或发布前核对范围，不将构建通过写成界面或真实 Codex 链路已验收。main 的 README 面向用户，CHANGELOG 和 Release 分别整理相较上一正式版的变化；未完成的手形光标修复不列为已修复。当前发布版本为 0.7.4；版本与后续发布授权以目标分支 AGENTS 和当次用户要求为准。
