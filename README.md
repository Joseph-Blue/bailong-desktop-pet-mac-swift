# 白龙娘桌宠MacOS-Swift版

## 项目简介

**白龙娘桌宠的非官方 macOS 原生重写版，使用 Swift + AppKit，由 Codex 重写。**

参考 [jingh12312-rgb 的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet) 的功能与交互，沿用原作动画素材，独立维护。不代表原作者或 OpenAI。

当前版本 **0.2.1**，功能仍在早期阶段，很可能有不少问题，欢迎反馈。

## 下载与安装

需要 **Apple Silicon Mac 和 macOS 14 或更新版本**。

**[下载安装包 ZIP](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/download/%E7%99%BD%E9%BE%99%E5%A8%98%E6%A1%8C%E5%AE%A0v0.2.1/bailong-desktop-pet-v0.2.1-macos-apple-silicon.zip)** · [发布说明](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/tag/%E7%99%BD%E9%BE%99%E5%A8%98%E6%A1%8C%E5%AE%A0v0.2.1) · [全部版本](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases)

解压后，将 `白龙娘桌宠MacOS-Swift版.app` 拖入「应用程序」。安装包已包含动画、音效和解码器；聊天与任务功能另需本机安装并登录 Codex。

### 首次打开

**本项目没有 Apple 公证和 Developer ID 签名。通过浏览器下载后，在 macOS 默认安全设置下，首次打开一定会被拦截。**

尝试打开一次后，前往「系统设置 → 隐私与安全性」，找到对应提示，点击「仍要打开」。详见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。本地自行编译不属于上述下载场景。

更新时，退出桌宠后用新版替换旧 App 即可，聊天记录保留。当前没有自动更新。

## 功能与操作

- 桌面动画、随机互动、拖拽与落地、左右吸边、全屏隐藏。
- 在聊天气泡或历史窗口中使用 Codex，查看进展、回复和额度，处理审批或停止任务。
- 只读观察外部 Codex 对话；外部任务的审批和补充输入仍在原窗口处理。
- 自定义称呼、台词、鼠标动作、活动频率、消息提醒、大小和外观。

| 默认操作 | 行为 |
| --- | --- |
| 单击 / 双击 | 随机互动 / 查看额度 |
| 右键单击 / 右键双击 | 打开菜单 / 临时聊天 |
| 吸边时单击或拖出 | 召回桌宠 |
| ⌘ Command + ↩ Enter | 发送消息；单独 Enter 换行 |
| ⌘, | 打开设置 |

鼠标动作和发送快捷键可在设置中调整。关闭聊天窗口不会停止任务，需要中止时请点击「停止」。聊天记录与输入框支持选择、复制。

聊天历史保存在 `~/Library/Application Support/BailongPetAppKit/conversations.json`，可从设置打开数据目录备份。恢复默认设置不会删除聊天记录。

## 从源码构建

需要 Apple Command Line Tools。当前原生动画分支使用 AppKit、AVFoundation 与 Core Image；FFmpeg 仅用于离线准备素材，应用运行不依赖 FFmpeg 或 Python。

仓库不含素材、解码器和图标，构建前需自行准备：

| 文件 | 来源 |
| --- | --- |
| 动画与素材清单 | [原作 v0.5.1 发布包](https://github.com/jingh12312-rgb/bailong-desktop-pet/releases/tag/v0.5.1)中的 `outputs`，解压提取即可 |
| 构建时 FFmpeg | 当前使用 [imageio-ffmpeg 0.6.0](https://pypi.org/project/imageio-ffmpeg/0.6.0/) 的 macOS 二进制，需支持 `libvpx-vp9` 和 `prores_ks`，架构与构建主机一致 |
| 音效与来源说明 | [原作 app/sounds](https://github.com/jingh12312-rgb/bailong-desktop-pet/tree/main/app/sounds) |
| 应用图标 | 本地从待机首帧生成，暂未提供生成脚本或独立下载 |

按以下结构放置资源，其中 `ffmpeg` 需有执行权限：

```text
local-assets/
  outputs/白龙桌宠素材/素材清单.json
  outputs/白龙桌宠素材/透明WebM/*.webm
  tools/ffmpeg
  tools/x86_64/ffmpeg             # 仅在 Intel 主机上转码时需要
  sounds/click.wav
  sounds/来源.txt
  BailongPet.icns
```

在仓库根目录执行：

```sh
./scripts/prepare-native-assets.sh # 首次准备完整 HEVC 素材；保留原 WebM
./scripts/build.sh arm64            # 打包 Apple Silicon 应用
./scripts/build.sh x86_64           # 打包 Intel 应用
./scripts/run-dev.sh                # 开发运行
./scripts/run-dev.sh --build-only   # 仅编译
```

当前 review 版本为 `0.3.0-dev.3`，应用输出至 `dist/native-hevc/0.3.0-dev.3/<架构>/白龙娘桌宠MacOS-Swift版.app`，采用本地 ad-hoc 签名。两份应用均包含完整功能与原生动画，不是之前的独立预览程序。Intel 实机表现待 review。

开发运行或 review 前请退出已有桌宠，新旧版本沿用同一设置与历史目录。素材准备输出位于 `local-assets/native-hevc/catalog`，已有输出时不会覆盖；重新转码前先移走旧目录。

启用“随 Codex 启动”前，建议先用访达将 `.app` 放到“应用程序”等固定位置。旧版本用户在新版“设置 → 通用 → 随 Codex 启动 → 配置…”中选择“修复／更新”，将已有启动项绑定到新版。系统临时位置运行的应用不能注册；移动应用后也需要更新启动项。仅识别 Codex／ChatGPT 桌面应用，不监测 CLI。

## 反馈与来源

问题请提交至 [Issues](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues)，附应用版本、macOS 版本和复现步骤。聊天问题请注明是桌宠内任务还是外部对话观察，截图前记得遮住私人内容。

原作基线为 **v0.5.1 / b102e73**，未指定开源许可证；素材再分发授权仍待确认。FFmpeg 和音效遵循各自许可，详见 [来源与架构](docs/来源与架构.md)。

[版本记录](CHANGELOG.md)
