# 白龙娘桌宠MacOS-Swift版

**白龙娘桌宠的非官方 macOS 原生重写版，使用 Swift + AppKit，由 Codex 重写。**

参考 [jingh12312-rgb 的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet) 的功能与交互，沿用原作动画素材，独立维护。不代表原作者或 OpenAI。

当前源码版本 **0.3.0**。本版本仅在本地构建、提交，尚未推送或发布。

## 安装与运行

需要 **Apple Silicon Mac 和 macOS 14 或更新版本**。当前本地应用输出：

`dist/native-hevc/0.3.0/arm64/白龙娘桌宠MacOS-Swift版.app`

应用包包含透明 HEVC 动画、音效、图标及同架构跟随启动 helper，使用 macOS 原生解码；不携带第三方视频解码器或 Python。聊天与任务功能另需本机安装并登录 Codex。

[已发布版本](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases)仍为此前版本，不能当作 0.3.0 下载。当前应用采用本地 ad-hoc 签名，没有 Apple 公证或 Developer ID 签名。下载旧版后的首次打开说明见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

更新时先退出桌宠，再用新版替换旧 App，设置和聊天记录保留。**检查更新**是下一项计划功能，当前没有更新检查或自动下载安装。

## 功能与操作

- 桌面动画、随机互动、拖拽与落地、左右吸边、全屏隐藏。
- 在聊天气泡或历史窗口中使用 Codex，查看进展、回复和额度，处理审批或停止任务。
- 只读观察外部 Codex 对话；外部审批和补充输入仍在原窗口处理。
- 自定义称呼、台词、鼠标动作、活动频率、消息提醒、大小和外观。
- “我还在留意进展…”和“让我看看额度…”气泡标题显示盲文滚动动画，历史记录不添加这些动画字符。

| 默认操作 | 行为 |
| --- | --- |
| 单击 / 双击 | 随机互动 / 查看额度 |
| 右键单击 / 右键双击 | 打开菜单 / 临时聊天 |
| 吸边时单击或拖出 | 召回桌宠 |
| ⌘ Command + ↩ Enter | 发送消息；单独 Enter 换行 |
| ⌘, | 打开设置 |

鼠标动作和发送快捷键可在设置中调整。关闭聊天窗口不会停止任务，需要中止时点击“停止”。聊天历史位于 `~/Library/Application Support/BailongPetAppKit/conversations.json`；恢复默认设置不会删除历史。

“随 Codex 启动”仅识别 Codex／ChatGPT 桌面应用。先将 App 放到固定位置，再从“设置 → 通用”配置；移动应用后使用“修复／更新”绑定新位置。

## 性能设置

| 项目 | 默认值 | 可选范围 |
| --- | --- | --- |
| 画质 | 清晰 512×512 | 均衡 384×384、节省运行内存 (RAM) 256×256 |
| 帧率上限 | 满帧 | 30／24／20／15 FPS |
| 动画缓冲帧数 | 24 | 6～240；刻度滑块及输入框，非法输入结束编辑时恢复 24 |
| 整段动画预加载 | 关闭 | 开启后缓冲帧数置灰，关闭恢复原值 |

默认流式读取，首帧就绪即播放；缓冲满后停止预读。整段预加载完整读取当前动作再播放，同动作循环复用帧，提示“不推荐，会显著增加运行内存 (RAM) 占用。”设置保存到本机，帧率上限不改变动画时长。

性能页还可开启“应用性能信息统计”：显示 FPS／HI／LO、折线图、CPU 总体与单核基准、GPU 应用组时间占比、运行内存 (RAM)、缓冲与预加载、版本及设备架构，分别列出 Codex 桌面端和桌宠自有 CLI 状态。

统计窗口默认左上角置顶，可从 Dock／菜单召回，关闭窗口即停止采样。左下角 pin 开关控制置顶，右侧为关闭和拷贝信息。设置中开关统计窗口保留设置焦点。Swap 区分系统交换空间、本进程压缩及累计换入，不将系统用量当成本进程磁盘占用。

## 从源码构建

需要 Apple Command Line Tools，运行和素材工具均使用 Apple 原生框架。旧 FFmpeg 运行及离线转码方案已移除。

仓库不含素材、图标或构建产物。构建使用已准备好的原生素材目录；可从本机已有原生版 App 的 `Contents/Resources/outputs/白龙桌宠素材` 复制清单和透明 HEVC 子目录。原作的 WebM 发布包不能直接用作本版运行资源。

```text
local-assets/
  native-hevc/catalog/素材清单.json
  native-hevc/catalog/透明HEVC/*.mov
  sounds/click.wav
  sounds/来源.txt
  BailongPet.icns
```

```sh
./scripts/build.sh arm64          # Apple Silicon 完整应用
./scripts/run-dev.sh --build-only # 开发版仅编译
./scripts/run-dev.sh              # 开发运行
```

Intel 构建入口 `./scripts/build.sh x86_64` 保留；本次仅构建 Silicon。主程序与 helper 使用同一架构。

已修复的编号 PNG 通过 `./scripts/apply-native-png-repairs.sh <PNG根目录>` 接入待机、第二待机、拖拽；加 `--landing` 单独接入落地。工具使用 AVAssetWriter 生成 ProRes 4444，再用系统 avconvert 生成透明 HEVC。成功后切换素材目录并保留旧目录，原始 WebM、原始及修复 PNG 全部本地保留。输入结构见 [素材工具说明](Tools/NativeHEVC/README.md)。

## 来源与反馈

原作基线为 **v0.5.1 / b102e73**。素材来源与授权范围见 [来源与架构](docs/来源与架构.md)，版本变化见 [CHANGELOG](CHANGELOG.md)。不将公开源码或本地素材修复同意扩大解释为其他授权。

反馈提交到 [Issues](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues)，附版本、macOS 版本和复现步骤。
