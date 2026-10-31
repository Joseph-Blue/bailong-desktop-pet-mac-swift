# 白龙娘桌宠MacOS-Swift版

**白龙娘桌宠的非官方 macOS 原生重写版，使用 Swift + AppKit，由 Codex 重写。**

参考 [jingh12312-rgb 的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet) 的功能与交互，沿用原作动画素材，独立维护。不代表原作者或 OpenAI。

本项目为[公开 GitHub 仓库](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift)。当前开发版本 **0.4.0-dev.13**，位于 `codex/check-updates` 分支，尚未合并、推送或发布。

## 下载与首次打开

需要 **Apple Silicon Mac 和 macOS 14 或更新版本**。聊天、任务和额度查询另需本机安装并登录 Codex。

**[前往 GitHub Releases 下载](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases)**

发布页提供已发布版本；本文介绍的 **0.4.0-dev.13 为本地开发版，尚未发布**。下载后解压，将 App 移入“应用程序”再打开。更新时先退出桌宠，用新版替换旧 App，设置与聊天记录保留。

### 遇到 macOS 安全拦截

当前构建采用本地 ad-hoc 签名，尚无 Developer ID 签名和 Apple 公证。确认 App 来自本仓库发布页后，若提示无法验证开发者或无法检查恶意软件：

1. 尝试打开一次 App。
2. 打开“系统设置 → 隐私与安全性”，点击“仍要打开”。
3. 在随后出现的确认框中点击“打开”。

这是针对该 App 的放行操作，步骤见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

## 特色功能

- **边工作，边看任务进展。** 桌宠只读跟进 Codex 桌面端的任务，将进展、待审批和最终结果送到气泡；秒表显示经过时间，结束后冻结，成功绿色，失败／取消／中断红色。
- **从气泡回到任务。** “转到 Codex”直达关联会话，“查看记录详情”打开桌宠历史。也可以在桌宠的临时输入窗或历史窗口里发起内置 Codex 任务、处理审批和停止任务。
- **额度与重置卡，一起查看。** 双击查询套餐额度、已购买的可用点数、剩余重置卡及到期时间。每次重新请求，时间按本机时区显示；这里只查看，不消耗重置卡。
- **原生透明动画，按需解码。** Swift + AppKit 界面配合透明 HEVC、AVFoundation 与 Core Image。默认只缓冲 24 帧，可调整画质、素材帧率与缓冲数量；桌宠的位置动画独立跟随屏幕刷新。
- **外观跟着你的 Mac。** macOS 26 及以上默认使用液态玻璃，旧系统使用普通材质；支持系统或自定义强调色、消息大小、动态效果和即时预览。称呼、台词、互动频率及鼠标操作也可调整。
- **性能信息看得见。** 独立窗口显示 FPS 曲线、CPU、GPU、运行内存 (RAM)、缓冲与预加载状态，并区分 Codex 桌面端和桌宠自有 CLI 的连接情况。窗口可置顶、拷贝信息，关闭即停止统计。

桌宠保留随机互动、拖拽与落地、左右吸边、全屏避让和随 Codex 桌面端启动。设置与历史窗口可从 Dock 找回；关闭界面不会退出桌宠，完整退出请使用桌宠菜单中的“退出”。

## 常用操作

| 默认操作 | 行为 |
| --- | --- |
| 单击 / 双击 | 随机互动 / 查看额度 |
| 右键单击 / 右键双击 | 打开菜单 / 临时聊天 |
| 吸边时单击或拖出 | 召回桌宠 |
| ⌘ Command + ↩ Enter | 发送消息；单独 Enter 换行 |
| ⌘, | 打开设置 |

鼠标动作和发送快捷键可在设置中调整。关闭聊天窗口不会停止任务，需要中止时点击“停止”。聊天历史位于 `~/Library/Application Support/BailongPetAppKit/conversations.json`；恢复默认设置不会删除历史。

“随 Codex 启动”仅识别 Codex／ChatGPT 桌面应用。先将 App 放到固定位置，再从“设置 → 通用”配置；移动应用后使用“修复／更新”绑定新位置。

## 检查更新

设置中的“更新”页和应用菜单均可检查更新，显示上次完成检查的时间及结果。启动自动检查默认开启，只在发现新版时提醒；失败记录在更新页，不弹窗打扰。自动提醒中的“😡 不许打扰我，禁用自动更新检查”与设置同步。

通过 GitHub 正式 Release 获取版本和更新说明，下载入口跳转到发布页，不自动安装或替换运行中的 App。更新请求沿用 macOS 系统代理设置及 TUN 系统路由，无需填写代理端口。

## 性能设置

| 项目 | 默认值 | 可选范围 |
| --- | --- | --- |
| 画质 | 清晰 512×512 | 均衡 384×384、节省运行内存 (RAM) 256×256 |
| 素材帧率上限 | 满帧 (≥ 24 FPS) | 20／15 FPS |
| 动画缓冲帧数 | 24 | 6～240；刻度滑块及输入框，非法输入结束编辑时恢复 24 |
| 整段动画预加载 | 关闭 | 开启后缓冲帧数置灰，关闭恢复原值 |

默认流式读取，首帧就绪即播放；缓冲满后停止预读。整段预加载完整读取当前动作再播放，同动作循环复用帧，提示“不推荐，会显著增加运行内存 (RAM) 占用。”设置保存到本机，帧率上限不改变动画时长。

性能页还可开启“应用性能信息统计”：显示 FPS／HI／LO、折线图、CPU 总体与单核基准、GPU 应用组时间占比、运行内存 (RAM)、缓冲与预加载、版本及设备架构，分别列出 Codex 桌面端和桌宠自有 CLI 状态。

统计窗口默认左上角置顶，可从 Dock／菜单召回，关闭窗口即停止采样。左下角 pin 开关控制置顶，右侧为关闭和拷贝信息。设置中开关统计窗口保留设置焦点。Swap 区分系统交换空间、本进程压缩及累计换入，不将系统用量当成本进程磁盘占用。

## 从源码构建

需要 Apple Command Line Tools，运行和素材工具均使用 Apple 原生框架。旧 FFmpeg 运行及离线转码方案已移除。

当前本地产物位于 `dist/native-hevc/0.4.0-dev.13/arm64/白龙娘桌宠MacOS-Swift版.app`。应用包包含运行用透明 HEVC 动画、音效、图标和同架构跟随启动 helper，不携带 Python 或第三方视频解码器。

仓库不含素材、图标或构建产物。构建使用已准备好的原生素材目录；可从本机已有原生版 App 的 `Contents/Resources/outputs/白龙桌宠素材` 复制清单和透明 HEVC 子目录。原作的 WebM 发布包不能直接用作本版运行资源。

```text
local-assets/
  native-hevc/catalog/素材清单.json
  native-hevc/catalog/透明HEVC/*.mov
  sounds/click.wav
  glass-symbols/                      # 玻璃滑块的两个 PDF 符号
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

玻璃符号资源在 macOS 27 上使用 `Tools/ExportGlassSymbols/main.swift` 导出至 `local-assets/glass-symbols`，构建时复制到应用。旧系统构建可使用已准备的这两个 PDF，不依赖其系统符号库包含新符号。
