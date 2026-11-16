# 原生素材工具（NativeHEVC）

本目录提供基于 Apple 原生媒体框架的透明 PNG 序列转码与独立动画预览工具，版本号与仓库根目录 [VERSION](../../VERSION) 保持一致。

## 1. 局部替换透明 HEVC 动作

首次准备素材请先按 [开发资源获取](../../docs/开发资源获取.md) 导入完整开发素材包（需包含 `local-assets/native-hevc/catalog/素材清单.json`、`samples.json` 与 `透明HEVC/*.mov`；正式版 `.app` 包内不含 `samples.json`）。

工具支持用修整后的 720×720（带 Alpha 通道）连续编号 PNG 序列替换以下 4 段核心动作：

| 动作 | PNG 子目录名 | 帧序列规格 |
| --- | --- | --- |
| 待机 | `01_待机_idle` | `0001.png`～`0096.png`，24 fps |
| 第二待机 | `02_第二待机_idle2` | `0001.png`～`0096.png`，24 fps |
| 拖拽 | `03_拖拽_drag` | `0001.png`～`0096.png`，24 fps |
| 落地 | `04_落地_landing` | `0001.png`～`0048.png`，24 fps |

执行替换：

```sh
./scripts/apply-native-png-repairs.sh <PNG根目录>
./scripts/apply-native-png-repairs.sh <落地PNG根目录> --landing
```

**编码与切换流程**：`ApplyPNGRepairs.swift` 使用 Core Image 读取 PNG 帧，经 `AVAssetWriter` 编码为中间 ProRes 4444 视频，再调用系统 `avconvert`（`PresetHEVCHighestQualityWithAlpha`）输出带 Alpha 通道的透明 HEVC `.mov`。编码完成后会自动核对输出分辨率、时长、帧率、Alpha 标记与首帧解码可用性；全部通过后将原目录备份为 `catalog-before-png-<VERSION>` 并切换至新 catalog，中间产物不打入应用包。

## 2. 独立素材预览器

```sh
./scripts/prepare-native-hevc.sh
```

该脚本直接复用现有 catalog 中的 `samples.json` 与透明 `.mov` 构建独立预览小工具（支持 `arm64`／`x86_64`，构建后不自动启动）。预览器采用系统 `AVPlayerLayer` 直接回放素材，与主程序的 `AVAssetReader` 流式解码管线相互独立，也不读写桌宠偏好、聊天历史或 Codex 数据，适合单独核对转码后的透明边缘与画面表现。
