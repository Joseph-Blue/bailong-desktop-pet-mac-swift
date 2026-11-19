# 白龙桌宠Swift · Dev

本分支（`joseph/dev`）维护 白龙桌宠Swift 的开发源码、架构文档与构建资源。开发版本见 [VERSION](VERSION)。

普通用户请跳转 [main 主分支](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/tree/main) 以下载最新的正式版应用。

本项目基于 [jingh12312-rgb（風-隐）的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet)（参考基线 `v0.5.1 / b102e73`），使用 Swift + AppKit 原生重写并独立维护。角色动画采用透明 HEVC（HEVC with Alpha）与 AVFoundation 解码，由 CPU／vImage 完成线性光缩放与色彩转换；界面采用原生 AppKit 分栏与液态玻璃材质。

本项目作者：**Joseph Blue（约瑟Blue）**。

## 模块概览

| 方向 | 核心实现 | 详细规范 |
| --- | --- | --- |
| 动画与吸边 | `CALayer` 直接呈现透明 HEVC 帧；默认 512×512、满帧、12 帧缓冲与 24 MiB 开头缓存，支持平滑过渡、杂点清理、左右边缘与刘海吸边。 | [动画与吸边](docs/来源与架构.md#current-animation) |
| 会话与进展 | 内置人设对话（`codex app-server`）与外部项目会话（只读 SQLite + 桌面 IPC）通道隔离；2 秒气泡首行与任务概览共用进展标题和图标，第二行仅显示新增细节，相同内容不重复弹出，重连提示除外。 | [会话与任务](docs/来源与架构.md#current-tasks) |
| 气泡与窗口 | `NSGlassEffectView.contentView` 承载正文并补充非激活细微亮边；非激活面板保持前台应用输入焦点，支持卡片翻阅、审批问卷与输入窗四向避让。 | [气泡与显示](docs/来源与架构.md#current-bubble)、[输入与窗口](docs/来源与架构.md#current-windows) |
| 历史与数据 | SQLite（schema 3）按需加载正文，提供每页 20 轮分页、全文搜索与关闭记录时的快照冻结；窗口关闭即释放排版缓存，各入口独立保留输入草稿。 | [历史与数据](docs/来源与架构.md#current-history) |
| 额度与用量 | 按订阅档位展示 30 天额度或 5 小时／周额度、重置倒计时与重置卡；共用 `TokenDisclosureControl` 展开本轮及本机今日 Token 明细，支持可选运行内存 (RAM) 缓存与立即刷新。 | [额度与用量](docs/来源与架构.md#current-usage) |
| 文件与工作区 | `FSEvents` 监听当前仓库变更，实时展示 Git 分支／状态与本轮 `fileChange` 增删统计；气泡内置任务信息栏（默认开启）与独立常驻「工作区状态条」（默认关闭）各自独立控制。 | [文件与产物](docs/来源与架构.md#current-files) |
| 设置与外观 | 支持自定义称呼变量、台词试播、字号比例与强调色；前景文字按背景对比度动态适配明暗，配备无副作用的静态设置搜索索引与 JSON 导入导出。 | [设置与个性](docs/来源与架构.md#current-settings) |
| 系统集成 | 支持指定显示器或随拖动跨屏、登录自启、随 Codex 桌面端启动、默认工作区管理与 GitHub 正式版更新检查。 | [构建与集成](docs/来源与架构.md#current-build) |

默认构建 Apple Silicon（`arm64`），最低支持 macOS 14 Sonoma。基准机型为 13 英寸 M1 MacBook Air。

## 分支与发布规则

- `main` 仅存放正式版代码与面向普通用户的说明；`joseph/dev` 维护开发代码、完整变更记录、架构规范与待办清单。跨分支同步按需挑选提交，不自动合并或直接覆盖主线文档。
- 开发分支不打应用版本标签，也不发布可执行程序 Release。开发期素材通过独立的 `dev-assets-*` Pre-release（标记为非 Latest）分发。
- 应用内更新检查请求 GitHub `releases/latest` 正式接口，自动过滤草稿、预发布及带 `-dev`／`-rc` 后缀的版本，仅提示正式版更新并打开下载页面，不自动下载或替换应用。

详见 [开发分支维护](docs/开发分支.md)。

## 获取素材与构建

首次构建需准备 Apple Command Line Tools 与开发素材包 **[bailong-dev-assets-2026-11-10.zip](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/tag/dev-assets-2026-11-10)**。目录结构与制作工具见 [开发资源获取](docs/开发资源获取.md)。

双击 `build.command` 可在终端交互完成环境检查、素材下载与打包；也可通过命令行直接执行：

```sh
./build.command                   # 构建 Apple Silicon 正式结构 App
./build.command x86_64            # 构建 Intel App
./build.command --resources-zip /绝对路径/bailong-dev-assets-2026-11-10.zip
                                  # 导入指定路径的素材包并构建
./build.command --check           # 仅检查编译环境与运行素材
./run-dev.command                 # 启动开发程序，默认显示协议、会话和逐段动画
./run-dev.command --monitor       # 启动时收起逐段动画明细
./run-dev.command --build-only     # 仅编译开发可执行文件（无需运行素材）
```

**终端日志**随开发程序启动，默认显示 Codex 协议、会话状态和逐段动画。交互终端按 `M` 暂停或恢复日志，按 `A` 收起或展开逐段动画，无需回车。用 `./run-dev.command > bailong-monitor.log` 可将本次标准输出保存为纯文本。[终端监视说明](docs/开发资源获取.md#终端监视)

- **素材导入**：默认仅补齐缺失文件；追加 `--replace-resources` 会先备份同名旧文件至 `.build/resource-import/` 再替换，追加 `--download-resources` 则直接拉取清单指定版本的素材包。
- **SDK 档位**：构建脚本自动检测当前 SDK 并选择最高可用档位（可通过 `BAILONG_BUILD_PROFILE=auto|full|glass|plain` 或 `SDKROOT` 显式指定）。三档编译产物的最低运行系统均为 macOS 14：
  - `full`（SDK 27+）：启用液态玻璃（macOS 26+ 生效）与菜单图标强制显示（macOS 27+ 生效）；
  - `glass`（SDK 26+）：启用液态玻璃，菜单图标遵循系统默认策略；
  - `plain`（SDK 14+）：固定使用普通窗口材质。
- **构建产物**：`build.command` 输出至 `dist/<VERSION>/<架构>/白龙桌宠Swift.app`（显式指定档位时追加 `<档位>/` 子目录），配套 `launch.command` 可直接打开对应架构产物。`run-dev.command` 输出至 `.build/dev/`（或 `.build/dev-x86_64/`），复用本机设置与历史数据；终端按 `^C` 会先请求应用优雅退出并显示 5 秒倒计时，超时仅终止本次启动的 PID。

## 源码结构与文档导航

- **协作与架构**：[AGENTS.md](AGENTS.md)（开发协作规则） · [来源与架构](docs/来源与架构.md)（源码入口、现行行为与历史演进） · [维护 Skill](skills/bailong-macos-port/SKILL.md)
- **进度与记录**：[TODO](todo.md)（待办与验收清单） · [CHANGELOG](CHANGELOG.md)（完整开发变更） · [开发变更索引](docs/开发变更索引.md)

## 致谢与问题反馈

- 感谢原作者 jingh12312-rgb（風-隐）提供角色动画与主要交互设计。
- 感谢 [ruyeli/bailong-desktop-pet-english](https://github.com/ruyeli/bailong-desktop-pet-english) 分享的 macOS SDK 兼容处理方案。
- 感谢 [moon135246/bailong-desktop-pet-optimization](https://github.com/moon135246/bailong-desktop-pet-optimization) 在动作开头缓存与内存预算上的优化参考。
- 图标许可原文见[第三方许可](第三方许可.txt)，也可从「设置 → 关于 → 来源与致谢」打开随应用附带的文本。
- 提交 [GitHub Issue](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues) 时，请附上应用版本号、macOS 版本与复现步骤；涉及会话同步或发送问题时，请一并说明 Codex 桌面端版本及会话类型（桌宠内置对话／Codex 项目会话）。
- 欢迎 fork 本仓库，也欢迎提出建议或建设性批评。
