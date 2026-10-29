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

需要 Apple Command Line Tools。界面使用系统 AppKit，透明 WebM 由 FFmpeg 解码，无需 Python 运行环境。

仓库不含素材、解码器和图标，构建前需自行准备：

| 文件 | 来源 |
| --- | --- |
| 动画与素材清单 | [原作 v0.5.1 发布包](https://github.com/jingh12312-rgb/bailong-desktop-pet/releases/tag/v0.5.1)中的 `outputs`，解压提取即可 |
| FFmpeg | 当前使用 [imageio-ffmpeg 0.6.0](https://pypi.org/project/imageio-ffmpeg/0.6.0/) 中的 macOS arm64 二进制，需支持 `libvpx-vp9` |
| 音效与来源说明 | [原作 app/sounds](https://github.com/jingh12312-rgb/bailong-desktop-pet/tree/main/app/sounds) |
| 应用图标 | 本地从待机首帧生成，暂未提供生成脚本或独立下载 |

按以下结构放置资源，其中 `ffmpeg` 需有执行权限：

```text
local-assets/
  outputs/白龙桌宠素材/素材清单.json
  outputs/白龙桌宠素材/透明WebM/*.webm
  tools/ffmpeg
  sounds/click.wav
  sounds/来源.txt
  BailongPet.icns
```

在仓库根目录执行：

```sh
./scripts/build.sh arm64            # 打包应用
./scripts/run-dev.sh                # 开发运行
./scripts/run-dev.sh --build-only   # 仅编译
```

应用输出至 `dist/arm64/白龙娘桌宠MacOS-Swift版.app`，采用本地 ad-hoc 签名。开发运行前请退出已有桌宠，两者共用默认数据目录。

## 反馈与来源

问题请提交至 [Issues](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues)，附应用版本、macOS 版本和复现步骤。聊天问题请注明是桌宠内任务还是外部对话观察，截图前记得遮住私人内容。

原作基线为 **v0.5.1 / b102e73**，未指定开源许可证；素材再分发授权仍待确认。FFmpeg 和音效遵循各自许可，详见 [来源与架构](docs/来源与架构.md)。

[版本记录](CHANGELOG.md)
