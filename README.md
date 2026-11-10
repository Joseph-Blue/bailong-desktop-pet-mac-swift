# 白龙桌宠Swift · Dev

**这是 `joseph/dev` 开发分支，面向开发者，不属于普通用户的安装说明，也不提供开发版 Release 程序下载。** 普通用户请前往 [main 主线](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/tree/main)。

当前候选版本：**0.7.5-rc.1**，正式版为 **0.7.4**。本轮汇总模型弹窗与长错误显示、历史消息排版与操作、变量圆角标签和整块删除、双版本头像、动画续播与起播缓冲，以及 SDK 兼容构建与 command 入口改进。新用户默认 512×512、12 帧缓冲，已有设置保留。手动动画停顿和运行内存占用仍列为 P0，见 [TODO](todo.md)。

基于 [jingh12312-rgb（風-隐）的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet)，由 Codex 使用 Swift + AppKit 原生重写，独立维护。动画使用透明 HEVC 与 AVFoundation，当前开发试验由 CPU / vImage 完成缩放和颜色转换；界面支持液态玻璃和系统外观。

本项目作者：**Joseph Blue（约瑟Blue）**。

## 本轮改动与验证

RC1 保留 dev.1 至 dev.7 的实现。模型弹窗按内容和实际视口重排，长错误独立换行滚动；历史消息显示角色图标、强调色标题与结束时间，提供拷贝和 Codex 跳转。个性页变量在标签和输入框内均使用连续圆角底色，退格按整块变量删除；托盘使用笑眼头像，设置与历史保留更多细节。

本轮源码通过 Swift 语法解析、脚本语法与差异检查，未构建或运行。界面最终显示、拷贝／跳转及变量编辑行为待用户验收。旧会话“重新读取”不会加载 Codex 原会话，读取设置失败仍单独跟进。头像资源不进 Git，构建前按[开发资源获取](docs/开发资源获取.md)准备两份模板。

动画加载期间保留旧动作供帧，目标准备完成后交接画面、时间轴及素材校准。按下桌宠不再停帧；流式目标先准备首帧和后续缓冲，整段预加载等完整解码，快速连续选择只接收最后一次请求。起播缓冲为解码较慢的设备留出准备时间，保留为面向老设备的优化方向，M1 Air 的实际收益待实测。不预缓存全部素材。吸边召回指定动作直接播放，手动入口减少重复显示刷新，并先加载动画再排版气泡。

构建入口共用 SDK 与编译器选择，按实际 SDK 编入外观能力；开发缓存同时核对工具链、SDK、档位与源码。默认输出改为 `dist/<VERSION>/<架构>/`，`launch.command` 同步该路径。用户已对这轮构建入口改进表示满意。感谢 [ruyeli/bailong-desktop-pet-english](https://github.com/ruyeli/bailong-desktop-pet-english) 分享的 SDK 兼容处理，为本轮编译脚本改进提供了灵感与参考。

dev.6 验证状态：SDK 27.2 完整档开发编译与缓存复用、SDK 26.5 玻璃档主程序／helper 类型检查通过。用户在 agy 运行期间使用 dev.4、dev.6 均遇到停顿；负载下降后 dev.3 基本流畅。dev.5 的续播与起播缓冲改进保留，P0 继续定位并发负载下的刷新和供帧瓶颈。最低目标机 M1 Air 与切换期运行内存待实测。

## 当前开发内容

| 方向 | 已落入源码的改动 |
| --- | --- |
| 动画与任务反馈 | 默认普通待机 4:1、吸边 7:3，任务按工作／待机 35:65 抽选并排除上一动作；手动频率与偏爱保留。试验复用 CPU 帧处理缓冲；恢复默认开启的轮廓阴影、任务台词及久无进展提醒，内置对话与外部 Codex 任务分别使用对应台词。当前尚未达到运行内存优化目标。 |
| 运行内存 | 历史正文改为 SQLite 按需读取，缓存最多 16 条、合计 2 MiB；每页展示 20 轮。保存仅写变化正文，首次迁移保留旧 JSON；历史关闭释放显示缓存，外部同步减少重复快照，实时观察仅保留目标轮次正文。气泡隐藏释放富文本与临时视图，搜索弹出框关闭释放结果，任务结束释放消息聚合器。 |
| 气泡与滚动 | 共用正文尺寸和纵向滚动组件；按实际溢出显示原生滚动条，显隐不改变换行宽度。普通气泡从顶部阅读，历史进入会话时定位底部。 |
| 辅助窗口 | 文件浏览与保存、设置调色板打开时在发起屏幕居中，保留拖动；桌宠点击阻止默认应用窗口整体置前。 |
| 会话入口 | 临时输入窗用无围框的原生分段导航区分桌宠人设对话／Codex 项目对话，显示目标会话与工作区；历史列表显示来源类型。两入口分别缓存草稿，主按钮统一为发送，停止任务独立。 |
| 会话职责 | 内置桌宠对话与外部 Codex 会话分别处理发送、模型设置和状态；共用用户消息整理、气泡入口、Markdown、代码块及文件链接。Codex 项目对话支持执行中插话；人设对话尚不支持执行中发送。卡片管理、倒计时、历史渲染和输入窗已拆分。 |
| 用户消息 | 附件包装显示为实际提问与紧凑文件链接；气泡和历史共用排版，不重复显示图片占位。Codex 历史补充用户消息，旧记录只在打开当前页时补缺，遵守历史冻结规则；插话按真实消息 ID 显示卡片并沿用原任务计时。 |
| 模型与输入 | 两入口共用模型字段样式，人设对话可选模型，项目对话只读原设置；模型弹窗按内容和屏幕自适应，滑块松开提交。工作区链接、最多 200 字回复摘要 hover、发送按钮与快捷键提示共用组件。 |
| 进展与拷贝 | 工具调用短气泡超出可见高度时以 `...` 收尾，完整内容可悬停查看；插话使用统一可编辑台词。复用标题流水、概览跑马灯、盲文及计时对齐；拷贝按钮统一反馈与恢复状态。正文打字机暂时停用，保留原设置值。 |
| 产物文件 | 将 Codex 的 `:codex-file-citation` 产物引用显示为文件名链接，与已有文件、图片入口共用访达定位逻辑。 |
| 文件修改摘要 | 气泡与历史共用文件列表，标题与总增减同排右对齐，默认展示 3 项并支持展开／收起；目录为次级灰，文件名及展开／收起为正文色；右侧显示绿色 `+N`／红色 `−N`。历史搜索可展开隐藏的匹配项，无撤销或 diff 查看按钮。 |
| 设置与目录 | 外观模式和消息窗口材质采用原生分段选择；高级页可选择桌宠对话默认工作区，清理只将内置 Workspace 内容移到废纸篓。新对话提供默认／当前／其他工作区入口；已有会话目录不变。 |
| 显隐与召回 | 仅托盘菜单顶部提供带图标的隐藏／显示项；再次打开 App 召回原桌宠，保留任务，不重新打开已关闭的设置／历史。 |

沿用正式版的任务概览、额度查询、历史搜索、气泡审批与问卷、Codex 项目快捷回复／插话、原生代码块及本机文件定位。详细行为见 [来源与架构](docs/来源与架构.md)，开发迭代见 [CHANGELOG](CHANGELOG.md)。

相关源码已在 main 整理为 0.7.4，并完成 Apple Silicon 与 Intel 社区测试包构建。用户已确认前一轮历史能显示用户消息；后续气泡附件、紧凑排版、插话台词、工具短气泡省略、动画选择及链接交互仍待用户 review，编译通过不代表运行验收。待办见 [TODO](todo.md)，其中一键卸载仅记录方案，尚未实现。

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

先安装 Apple Command Line Tools。构建按实际选用的 SDK 编入对应外观能力：SDK 27+ 包含液态玻璃与菜单图标显式显示，SDK 26 包含液态玻璃，更早 SDK 使用普通材质；运行时仍检查系统版本。脚本显示实际 SDK、Swift 编译器与能力，最低运行目标保持 macOS 14。

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
  pet-status-template.png           # 本轮新增，旧资源包不包含
```

资源不存放在 Git 中。本轮新增模板图须按 [开发资源获取](docs/开发资源获取.md) 单独准备。`samples.json` 用于独立预览与 PNG 替换，不是 App 运行必需文件。

```sh
./scripts/run-dev.sh --build-only  # 仅编译
./scripts/build.sh arm64           # 构建 Apple Silicon App
./scripts/build.sh x86_64          # 按需构建 Intel App
./scripts/run-dev.sh               # 编译并开发运行
```

也可双击 `build.command`、`launch.command`、`run-dev.command`。版本取自 [VERSION](VERSION)，应用产物位于 `dist/<VERSION>/<架构>/白龙桌宠Swift.app`。正式版 0.7.4 提供 Apple Silicon 包与 Intel 社区测试包；Intel Mac 实机验收尚未完成，开发构建默认只选择 Apple Silicon。

三个入口会显示版本、目标架构、当前阶段和耗时。交互终端显示盲文转圈，重定向日志时使用普通阶段文本；原始诊断在阶段结束时输出，失败保留退出码。完成时显示产物绝对路径和大小。

- `SDKROOT` 可指定已安装 SDK；`BAILONG_BUILD_PROFILE` 可选 `auto`（默认）、`full`、`glass`、`plain`。显式档位产物存于 `dist/<VERSION>/<架构>/<档位>/`；`launch.command` 打开默认目录，分档产物直接打开对应 App。`full` 要求 SDK 27+，`glass` 要求 SDK 26+；`plain` 在新系统上也使用普通材质。
- `run-dev.command` 缓存同时核对源码、SDK、Swift 工具链及构建档位，切换环境后重新编译。
- `build.command` 默认只构建 Apple Silicon；Intel 须显式执行 `./build.command x86_64`。构建替换当前版本、当前架构的产物，不自动安装到 `/Applications`。
- `launch.command` 按当前进程架构打开已有应用，成功提示仅表示已提交打开请求。
- `run-dev.command` 编译或复用 Apple Silicon 开发程序；开发运行沿用现有设置和历史，终端需保持打开，Ctrl+C 停止。`--build-only` 只生成 `.build/dev/BailongPetDev`，不会更新已有 App 或 `dist`。


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
