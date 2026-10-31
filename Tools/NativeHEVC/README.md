# 原生素材工具

应用和工具版本以仓库根目录 VERSION 为准。运行、构建和 PNG 接入均使用 Apple 原生技术；退役的 WebM 转码工具已删除。

## 输入资源

完整应用读取 `local-assets/native-hevc/catalog/素材清单.json` 与 `透明HEVC/*.mov`。本地保留的原始 WebM 不参与运行。PNG 接入使用已有完整 catalog，其中 `samples.json` 是素材来源与预览元数据。

修复 PNG 根目录包含以下连续编号文件：

| 动作 | 子目录 | 帧数／帧率 |
|---|---|---|
| 待机 | 01_待机_idle | 0001.png～0096.png，24 fps |
| 第二待机 | 02_第二待机_idle2 | 0001.png～0096.png，24 fps |
| 拖拽 | 03_拖拽_drag | 0001.png～0096.png，24 fps |
| 落地 | 04_落地_landing | 0001.png～0048.png，24 fps |

所有 PNG 为 720×720，保留透明通道。执行：

```sh
./scripts/apply-native-png-repairs.sh <PNG根目录>
./scripts/apply-native-png-repairs.sh <落地PNG根目录> --landing
```

Swift 工具以 Core Image 读取 PNG，通过 AVAssetWriter 写入 ProRes 4444，再调用系统 avconvert 的 PresetHEVCHighestQualityWithAlpha 编码透明 HEVC。工具检查输出尺寸、时长、帧率、透明标记和原生首帧读取；完成后才切换当前 catalog，旧目录保留为 `catalog-before-png-<VERSION>`。中间文件不进入应用包。0.3.0 中新编码实现已编译，未重新转换现有素材。

## 独立预览

`./scripts/prepare-native-hevc.sh` 直接复制已有 catalog 的 samples.json 和透明 MOV，构建 arm64／x86_64 独立预览，不转码、不自动启动。预览使用 AVPlayerLayer，与桌宠的流式 AVAssetReader 实现不同；它不读取桌宠设置、历史或 Codex 数据。这里只保留原生预览，不再维护独立开发版版本号。
