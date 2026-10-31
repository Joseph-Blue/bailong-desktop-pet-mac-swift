# 原生透明动画实验环境

本目录提供素材准备工具和独立的 AppKit / AVFoundation 预览程序。预览版本由本目录 `VERSION` 定义，当前为 `0.3.0-dev.2`；完整桌宠已在 `codex/native-hevc-alpha` 分支接入原生解码，根目录 `VERSION` 为 `0.3.0-dev.3`。两者独立构建，技术栈见 [来源与架构](../../docs/来源与架构.md)。

完整桌宠使用 `scripts/prepare-native-assets.sh` 准备全部动作，再以 `scripts/build.sh arm64` 或 `scripts/build.sh x86_64` 打包，输出 `dist/native-hevc/<根目录 VERSION>/<架构>/白龙娘桌宠MacOS-Swift版.app`。以下命令与操作说明仅针对三动作独立预览。

## 构建

需要 macOS 14 或更高版本、Apple Command Line Tools，以及本机架构的现有 FFmpeg：

- Apple Silicon：`local-assets/tools/ffmpeg`
- Intel：`local-assets/tools/x86_64/ffmpeg`

FFmpeg 必须包含 `libvpx-vp9` 解码器与 `prores_ks` 编码器。脚本先生成带透明通道的 ProRes 4444 中间素材，再调用系统 `/usr/bin/avconvert` 的 `PresetHEVCHighestQualityWithAlpha` 预设，完成 HEVC 编码和 MOV 封装。受限沙箱可能无法访问系统编解码服务，应在具备服务访问权限的终端执行。不需要安装 Python、Homebrew 包或第三方 Swift 包。

在仓库根目录运行：

```sh
scripts/prepare-native-hevc.sh
```

工具读取现有素材清单的待机、拖拽、落地三个动作，优先采用清单中的 `playbackFile`，生成独立的 `local-assets/native-hevc/samples/`。保留原尺寸、帧时序与原 WebM，输出为 HEVC with Alpha MOV。此流程经过中间编码，不宣称无损；成功后删除 ProRes 中间文件，不打包进预览。

`dev.1` 使用 FFmpeg 7.1 直接生成透明 HEVC，本机 AVFoundation 可读取其元数据，却在真实解码时返回 -11801 / -12713。`dev.2` 更换生成链路，并在样本生成时检查原生首帧解码。升级时必须重新生成样本，不能复用 `dev.1` 的 MOV。

输出目录存在时停止，避免覆盖已 review 的样本。仅重建预览程序可使用：

```sh
scripts/prepare-native-hevc.sh --reuse-assets
```

如需重新转码，先将旧 samples 目录移走，再运行不带参数的命令。失败转码的 `.partial` 目录保留以供查看。

## 预览

构建同时生成两份本地签名的独立应用，不自动启动：

- `dist/native-hevc/0.3.0-dev.2/arm64/白龙娘原生动画预览.app`
- `dist/native-hevc/0.3.0-dev.2/x86_64/白龙娘原生动画预览.app`

在对应架构的 Mac 上打开，选择待机／拖拽／落地、浅色／深色／透明背景及 0.5×／1×／2× 播放。预览会循环所选动作，采用系统 AVFoundation 播放，包内不携带 FFmpeg。

预览有独立包标识 `com.bailongpet.native-hevc-preview`，不读取正式桌宠的设置、历史或 Codex 数据。它尚未接入桌宠的鼠标命中、吸边、位移和任务动画调度，因此不能代替完整桌宠的运行验收。

样本生成检查 AVFoundation 可读取的轨道、尺寸、帧率、时长、透明通道标记和首帧解码，不自动做截图、视觉或性能测试。双架构编译不代表 Intel 真机通过。

实现依据：[Apple HEVC Video with Alpha](https://developer.apple.com/videos/play/wwdc2019/506/)，以及系统 `avconvert --help` 所列透明 HEVC 预设。
