# 原生透明动画实验环境

本目录提供独立的素材准备工具和 AppKit / AVFoundation 预览程序。预览版本为 `0.3.0-dev.1`，正式桌宠的 `VERSION` 与运行链路仍保留原状。

## 构建

需要 macOS 14 或更高版本、Apple Command Line Tools，以及本机架构的现有 FFmpeg：

- Apple Silicon：`local-assets/tools/ffmpeg`
- Intel：`local-assets/tools/x86_64/ffmpeg`

FFmpeg 必须包含 `libvpx-vp9` 解码器与支持 alpha 的 `hevc_videotoolbox` 编码器。脚本使用系统 VideoToolbox 编码服务；受限沙箱可能无法创建编码会话，应在具备系统编码服务访问权限的终端执行。不需要安装 Python、Homebrew 包或第三方 Swift 包。

在仓库根目录运行：

```sh
scripts/prepare-native-hevc.sh
```

工具读取现有素材清单的待机、拖拽、落地三个动作，优先采用清单中的 `playbackFile`，生成独立的 `local-assets/native-hevc/samples/`。保留原尺寸、帧时序与原 WebM，输出为 HEVC with Alpha MOV。颜色目标码率为 8 Mbps、alpha 质量参数为 1；这些参数不代表无损转换。

输出目录存在时停止，避免覆盖已 review 的样本。仅重建预览程序可使用：

```sh
scripts/prepare-native-hevc.sh --reuse-assets
```

如需重新转码，先将旧 samples 目录移走，再运行不带参数的命令。失败转码的 `.partial` 目录保留以供查看。

## 预览

构建同时生成两份本地签名的独立应用，不自动启动：

- `dist/native-hevc/arm64/白龙娘原生动画预览.app`
- `dist/native-hevc/x86_64/白龙娘原生动画预览.app`

在对应架构的 Mac 上打开，选择待机／拖拽／落地、浅色／深色／透明背景及 0.5×／1×／2× 播放。预览会循环所选动作，采用系统 AVFoundation 播放，包内不携带 FFmpeg。

预览有独立包标识 `com.bailongpet.native-hevc-preview`，不读取正式桌宠的设置、历史或 Codex 数据。它尚未接入桌宠的鼠标命中、吸边、位移和任务动画调度，因此不能代替完整桌宠的运行验收。

样本生成只检查 AVFoundation 可读取的轨道、尺寸、帧率、时长及透明通道标记，不自动做截图、视觉或性能测试。双架构编译不代表 Intel 真机通过。

实现依据：[Apple HEVC Video with Alpha](https://developer.apple.com/videos/play/wwdc2019/506/)、[FFmpeg VideoToolbox 编码器](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)。
