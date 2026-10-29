# 白龙娘桌宠MacOS-Swift版

基于 [jingh12312-rgb 的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet)，以 **Swift + AppKit** 从零重写的非官方 macOS 桌宠。当前版本 **0.2.0**，独立维护；原透明 WebM 使用随包 FFmpeg 解码，无 Python、PySide6 或 PyObjC 运行依赖。

本仓库为独立私有仓库，尚未发布 GitHub Release。原作行为基线为 [v0.5.1 / b102e73](https://github.com/jingh12312-rgb/bailong-desktop-pet/commit/b102e734f20bb50889af12df5778f1499109f41b)。来源与许可边界见 [来源与架构](docs/来源与架构.md)。

## 运行要求与应用包

- macOS 14 或更新版本；分别构建 Apple Silicon（arm64）与 Intel（x86_64）应用。
- 两份应用携带对应架构 FFmpeg，名称相同、目录分开；“关于”按编译目标显示架构。
- 使用本机已经登录的 Codex CLI，或已安装 Codex/ChatGPT 桌面应用内置 CLI。
- 本地应用采用 ad-hoc 签名，未做 Developer ID 签名或公证。

| 架构 | 本地应用位置 |
| --- | --- |
| Apple Silicon | `dist/arm64/白龙娘桌宠MacOS-Swift版.app` |
| Intel | `dist/x86_64/白龙娘桌宠MacOS-Swift版.app` |

构建成功不代表全部运行验收完成。设置布局、真实鼠标手势、中文输入法、多屏和登录项仍待实际使用确认；Intel 版尚未在 Intel 真机验收。旧应用包不会自动更新，也没有自动启动新应用。

## 主要功能

- 原生透明桌宠、待机／互动／工作／移动动作、拖拽与落地、左右吸边、额度查看及可选全屏隐藏。
- 原生临时聊天与历史窗口，共享模型、推理等级及输入快捷键；公开摘要、回复逐步显示与 Markdown 排版。
- 真实停止任务、默认拒绝的命令／文件审批、补充输入、历史保护及自有进程回收。只有任务 completed 才显示完成。
- 外部 Codex 任务仅只读观察公开进展、回复和终态；不把工具中间输出自动包装为错误提醒。历史转入新对话前先生成可编辑草稿。
- 原生关于与来源致谢；菜单提供显示、聊天、历史、设置与退出入口。

## 鼠标与键盘

| 操作 | 默认行为 |
| --- | --- |
| 普通单击 | 松手立即随机动画 |
| 普通双击 | 查看额度；第一下已执行单击动作 |
| 右键单击 | 按下立即打开菜单 |
| 右键双击 | 关闭菜单后打开临时聊天 |
| 躲在角落时单击 | 松手后等待 250ms，只召回，不执行自定义单击动作 |
| 角落里的第二击 | 250ms 内按下取消召回，执行双击动作 |
| 吸边拖动 | 立即召回，不等待；普通拖动保留拖拽／落地动画 |

普通单击、双击和右键双击可分别配置为无动作、临时聊天、查看额度、查看历史消息或随机动画。

两处输入框同步使用设置中的方案，提示均写全按键；中文输入法组字时不发送：

| 方案 | 发送 | 换行 |
| --- | --- | --- |
| 默认 | ⌘ Command + ↩ Enter | ↩ Enter |
| 备选 | ↩ Enter | ⇧ Shift + ↩ Enter 或 ⌥ Option + ↩ Enter |

## 设置

菜单“设置…”或 **⌘ Command + , 逗号** 打开。名称与说明在左，控件在右，更改即时保存。

- **通用**：启动显隐、记住位置、全屏隐藏、显示器，以及用户主动启用的登录／跟随启动。
- **称呼与个性**：主人和桌宠名字、称呼方式、问候语和互动台词。默认桌宠名为白龙娘；原始对话正文不被替换。
- **动作与活动**：鼠标动作、自主活动间隔、移动范围、频率与偏爱、减少重复、整体及单动作速度、任务开场与庆祝。动画列表使用影片图标。
- **消息与提醒**：发送方案、各类消息时长、悬停暂停、文字显示后计时、逐步显示、音效、安静陪伴与专注时段。0 秒表示手动关闭；待审批、补充输入和失败保留通知入口。
- **外观**：桌宠大小 50%—200%、气泡大小 50%—150%、字号、明暗外观及强调色。两种大小初始均为 100%。
- **高级**：导入／导出设置、打开数据目录、全部恢复默认。

各普通页提供“恢复本页设置为默认值”。恢复操作不删除历史或素材，也不改变系统登录项；设置中不单列“关于”。

## 构建

安装 Apple Command Line Tools，并自行准备以下本地资源。克隆仓库不包含素材、FFmpeg 或成品应用：

```text
local-assets/
  outputs/白龙桌宠素材/素材清单.json
  outputs/白龙桌宠素材/透明WebM/*.webm
  tools/ffmpeg                 # arm64
  tools/x86_64/ffmpeg          # x86_64
  sounds/click.wav
  sounds/来源.txt
  BailongPet.icns
```

当前使用 imageio-ffmpeg 0.6.0 分发的 FFmpeg 7.1 二进制；仅提取二进制，不安装 Python 运行依赖。Intel 二进制自带 `nonfree and unredistributable` 声明，仅用于本地构建，不能作为未来公开应用的可再分发解码器；公开分发前须替换并重新核对依赖许可。构建时按架构选择解码器：

```sh
./scripts/build.sh arm64
./scripts/build.sh x86_64
```

双击 `启动桌宠.command` 按当前架构打开对应应用；`构建应用.command` 默认构建 arm64。也可直接打开上表中的应用。

Apple Silicon 开发时可运行 `./scripts/run-dev.sh`，或双击 `开发运行.command`；只编译用 `./scripts/run-dev.sh --build-only`。开发运行读取原地资源，不打包；Ctrl+C 正常退出并回收自有进程。与应用包共用单实例锁和数据，运行前先退出已有桌宠。

## 数据与仓库边界

数据保存到 `~/Library/Application Support/BailongPetAppKit`，与旧 Python 工程隔离；可用 `BAILONG_DATA_DIR` 指定目录。包标识仍为 `com.bailongpet.appkit`，应用改名不改变数据位置。

Codex 优先使用 `BAILONG_CODEX_BIN`，其次查找已安装桌面应用内置 CLI，再查找 PATH 等位置。沿用现有 CLI 登录，不读取或复制凭证，不修改全局 Codex 配置。外部观察只读 `CODEX_HOME` 下的公开记录；用户点击发送才发起模型任务。登录项／LaunchAgent 默认不启用。

Git 只保存源码、定向测试、构建脚本、正式说明和可复用 skill。素材、解码器、构建产物、用户数据、备份及计划／对比／调查／实施记录仅留本地。首次远端历史从干净的 0.2.0 快照开始，不携带旧内部文档。

维护约定见 [AGENTS.md](AGENTS.md) 与 [项目 skill](skills/bailong-macos-port/SKILL.md)，版本变化见 [CHANGELOG](CHANGELOG.md)。已有定向测试按需执行，不自动跑截图、视觉、冒烟或模型请求；编译与静态检查不等于运行验收。
