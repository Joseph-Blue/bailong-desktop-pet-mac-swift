# 白龙桌宠Swift

**陪你工作，也把 Codex 的任务进展带到桌面。**

基于 [jingh12312-rgb 的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet)，由 Codex 进行 Swift + AppKit 原生重写，独立维护。支持桌面互动、Codex 对话、任务气泡与本机历史管理。

[下载正式版](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/latest) · [版本变化](CHANGELOG.md) · [反馈问题](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues)

**正式版：[0.5.0](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/tag/v0.5.0)。**

## 0.5.0 特色功能

<p>
  <a href=".github/images/task-progress.png"><img src=".github/images/task-progress.png" alt="任务进展" width="240"></a>
  <a href=".github/images/task-overview.png"><img src=".github/images/task-overview.png" alt="任务概览" width="240"></a>
</p>
<p>
  <a href=".github/images/codex-quota.png"><img src=".github/images/codex-quota.png" alt="额度查询" width="240"></a>
  <a href=".github/images/quick-chat.png"><img src=".github/images/quick-chat.png" alt="临时对话" width="240"></a>
</p>

### 更轻的动画播放，更快进入画面

- **安装包缩小 33.5%**：Apple Silicon ZIP 从 0.2.1 的 **168.91 MiB** 缩小到 **112.28 MiB**。动画改用透明 HEVC，移除随包 FFmpeg 解码器和 WebM 运行素材。
- **降低动画驻留开销**：默认流式解码，使用 24 帧缓冲，切换动作后释放旧缓冲；替代旧版多动作整段解码与缓存。
- **优化启动与切换**：首帧就绪即开始播放，后续帧在后台按需读取；取消基础动作预热。
- **原画与性能可调**：默认 720×720 原画，另有 512、384、256 三档；可调帧率、缓冲和播放速度。
- **独立性能窗口**：查看 FPS、CPU、GPU、运行内存 (RAM) 和动画缓冲，关闭窗口即停止统计。

技术栈继续使用 Swift + AppKit；动画链路从 WebM／FFmpeg 切换为 **HEVC with Alpha + AVFoundation + Core Image**。拖动、旋转与自主位移跟随屏幕刷新，素材帧率独立控制。

### 在气泡中接着处理 Codex 任务

- **快捷回复与插话**：从消息气泡打开临时输入窗，或在历史会话中回复；已结束对话继续聊，执行中对话可插话。原会话沿用 Codex 的模型与思考等级。
- **问卷直接回答**：气泡内选择选项、补充文字、逐题切换和提交，草稿随卡片保留。
- **审批入口**：气泡提示待批准操作；内置任务打开原生审批窗口，外部任务跳转 Codex。敏感提问使用原生安全输入或转到 Codex。
- **桌宠内置对话**：选择模型与思考等级，发起任务、处理审批、查看进展和停止任务。
- **实时进展**：标题流水、强调色盲文转圈与秒表显示执行状态；任务结束后冻结用时。

### 多条消息能回看，任务一眼能找到

气泡支持左右翻页、页码、快捷回复、跳转 Codex 和查看记录详情。独立消息分别保留，流式内容更新原卡片。

单击桌宠播放随机动画，并显示正在执行及近期结束的任务。每个会话展示最新轮次，提供状态图标、用时和跳转入口；任务概览始终复用一张卡片。

历史窗口支持正文搜索、匹配高亮、本地重命名、同步 Codex 标题和删除桌宠副本。关闭历史记录后，已有记录保留，新的内容不再写入。

### 文件、图片和表格直接呈现

- **文件链接**：点击本机文件链接，在访达定位对应文件；网页链接交给浏览器打开。
- **生成图片入口**：imagegen 生成的图片显示独立链接，多张图片各自保留，并汇集到结果气泡。
- **Markdown 排版**：气泡与历史支持标题、列表、引用、代码、链接和表格。

### 液态玻璃与原生 macOS 界面

- **液态玻璃支持**：macOS 26 起，消息气泡与临时输入窗使用系统液态玻璃，支持材质切换、背景不透明度调整与独立预览。
- **原生界面优化**：设置与历史采用 AppKit 原生分栏、侧栏和工具栏；搜索可定位具体选项、动作或台词，输入框保留原生焦点环与快捷键。
- **统一外观与排版**：支持跟随系统或自定义强调色、字号、气泡比例与动态效果；按钮尺寸和对齐随缩放同步，已有卡片即时应用新外观。

称呼和台词支持 `{用户名}`、`{桌宠名}`、`{特定称呼}`。右键台词或特定称呼输入框可插入变量；名字和台词清空后恢复可编辑的默认内容，特定称呼留空沿用你的名字。

设置侧栏提供关闭按钮；设置与额度结果窗口打开时，桌宠继续自主活动。设置与历史窗口的绿色按钮用于填满当前屏幕可用区域，再次点击恢复。

### 额度、更新与本机管理

额度每次重新查询，显示当前用量、重置时间、点数和重置卡。结果气泡默认显示 **5 秒**。

更新页与菜单支持检查 GitHub 正式版本，**启动自动检查默认关闭**。发现新版后可打开发布页下载。登录启动和随 Codex 启动会在新版首次运行时更新已启用的路径。

高级设置提供本应用所占本机存储统计、数据与缓存清理；错误恢复页支持重试、拷贝报告和跳转仓库反馈。

## 下载与使用

需要 **Apple Silicon Mac、macOS 14 或更新版本**。Codex 功能需要在本机安装并登录 Codex。

1. 下载 [Apple Silicon ZIP](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/latest) 并解压。
2. 将 `白龙桌宠Swift.app` 放到你选择的固定目录，从访达打开。
3. 在“设置 → 通用”中选择是否随登录或 Codex 启动。

App 使用本地签名。若 macOS 提示无法验证开发者，尝试打开一次，再到“系统设置 → 隐私与安全性 → 仍要打开”。[Apple 操作说明](https://support.apple.com/zh-cn/102445)

### 从旧版升级

退出旧桌宠，再打开新版。新版保留设置与历史，升级历史格式前会备份原文件。已经启用的启动项会在新版首次运行时更新；App 移动到新目录后，手动打开一次即可更新路径。

历史和任务文件位于 `~/Library/Application Support/BailongPetAppKit`。历史备份为 `conversations-before-schema2-<时间戳>.json`；若切回 0.2.1，使用升级前的备份。

## 常用操作

| 操作 | 默认行为 |
| --- | --- |
| 单击 / 双击桌宠 | 随机动画与任务概览 / 查询额度 |
| 右键单击 / 右键双击 | 打开菜单 / 临时聊天 |
| 吸边时单击或拖出 | 召回桌宠 |
| ⌘ Command + ↩ Enter | 发送消息；Enter 换行 |
| ⌘, | 打开设置 |
| 设置或历史中的 ⌘F | 搜索设置项或历史消息 |
| 历史中的 ⌘G / ⇧⌘G | 下一处 / 上一处正文匹配 |

鼠标动作、发送快捷键和消息时长均可调整。右键菜单提供随机动画、Codex 跳转、历史，以及大小和称呼台词设置入口。

- 气泡默认保留本次运行的 **20 张卡片**，可设为 5～100；磁盘历史单独保存。
- 鼠标移入气泡暂停倒计时，移出接着计时；切换卡片重新计时。待回答、待批准和错误气泡由用户处理后关闭。
- 新任务消息替换任务概览；正在翻阅旧卡或填写问卷时保留当前卡片。
- 关闭窗口或按 ⌘Q 收起界面；完整退出使用菜单中的“退出白龙桌宠Swift”。停止任务使用对话中的“停止”。

## 性能设置

| 设置 | 默认 | 可选 |
| --- | --- | --- |
| 画质 | 原画 720×720 | 512×512、384×384、256×256 |
| 素材帧率 | 满帧，按实际素材帧率 | 20 / 15 FPS |
| 动画缓冲 | 24 帧 | 6～240 帧 |
| 整段预加载 | 关闭 | 开启后完整加载当前动作，占用更多运行内存 (RAM) |

流式播放和整段预加载可按设备调整；独立性能窗口提供当前占用与帧率。实现细节见 [来源与架构](docs/来源与架构.md)。

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

原作参考基线为 **v0.5.1 / b102e73**。动画、音效、图标与软件组件的来源见 [来源与架构](docs/来源与架构.md) 和设置中的“关于 → 开源致谢”。

反馈问题请提供应用版本、macOS 版本和复现步骤；Codex 问题另附桌面端版本，并注明桌宠内置对话或 Codex 原会话。[提交 Issue](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues)
