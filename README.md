# 白龙桌宠Swift · Dev

这是 `joseph/dev` 开发分支，提供源码、开发文档与素材包。安装正式版请前往 [main 主线](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/tree/main)。

当前候选版本：**0.8.0-rc.10**，基于 **0.7.5-rc.1**；正式版为 **0.7.4**。

本候选版承接 rc.9：解决 Codex 桌面端完全退出后的首次发送延迟，补齐冷启动换窗会话导航与 IPC 发现广播唤醒；保留原生玻璃内容承载、非激活亮边、深浅色文字适配、Git 自动更新与变化召回、进度组标题、Token 展开及工具短气泡顶部展示。初始滚动位置及空白摘要待主程序复测；玻璃、Git 与窗口交互的待验收事项见 [TODO](todo.md)，逐版变化见 [CHANGELOG](CHANGELOG.md)。

基于 [jingh12312-rgb（風-隐）的 GPT白龙娘动态桌宠](https://github.com/jingh12312-rgb/bailong-desktop-pet)，由 Codex 使用 Swift + AppKit 原生重写，独立维护。动画使用透明 HEVC 与 AVFoundation，当前开发试验由 CPU / vImage 完成缩放和颜色转换；界面支持液态玻璃和系统外观。

本项目作者：**Joseph Blue（约瑟Blue）**。

## 当前开发内容

| 方向 | 当前内容 | 详细规则 |
| --- | --- | --- |
| 动画与播放 | 原生图层显示透明 HEVC；默认 512×512、满帧、12 帧缓冲，开头缓存默认开启；支持平滑过渡、杂点清理与动作权重。 | [动画与吸边](docs/来源与架构.md#current-animation) |
| 会话与进展 | 桌宠人设与 Codex 项目会话分别处理发送、审批及生命周期；主气泡和概览显示进度组标题，短进展显示单项摘要。 | [会话与任务](docs/来源与架构.md#current-tasks) |
| 气泡与窗口 | 原生玻璃承载正文并补充非激活亮边；支持卡片翻阅、正文滚动、Token 明细展开和输入避让。 | [气泡与显示](docs/来源与架构.md#current-bubble)、[输入与窗口](docs/来源与架构.md#current-windows) |
| 历史与数据 | SQLite 按需读取正文，分页、搜索和冻结快照；窗口关闭释放显示缓存。历史与临时输入分别保留草稿。 | [历史与数据](docs/来源与架构.md#current-history) |
| 额度与 Token | 查询额度、重置时间和重置卡；展示本轮及本机今日 Token 明细，提供可选额度缓存与立即刷新。 | [额度与用量](docs/来源与架构.md#current-usage) |
| 文件与 Git | 监听当前工作区变化，显示 Git 状态和本轮累计文件增删；提供工作区／远端链接、访达定位与文件详情。 | [文件与产物](docs/来源与架构.md#current-files) |
| 设置与外观 | 自定义称呼、台词、大小和主题；强调色文字与填充分开适配，支持设置搜索、导入导出及系统动态效果偏好。 | [设置与个性](docs/来源与架构.md#current-settings) |
| 系统集成 | 显示器选择、左右／刘海吸边、登录／跟随启动、桌宠召回、默认工作区与正式版更新检查。 | [构建与集成](docs/来源与架构.md#current-build) |

气泡任务信息栏默认开启；独立工作区小窗和常驻默认关闭，小窗默认停留 20 秒。常驻时隐藏显示时长，关闭常驻后恢复原值。倒计时收起后，Git 状态或本轮文件统计变化可再次显示；手动关闭停止监听。已有保存值保留，历史与输入窗口继续提供 Git／文件入口。

动画的运行内存改善已获用户反馈，手动连续切换、长期负载及最低目标机继续观察。Codex 完全退出后的首次发送支持自动进入原会话并提交，准备期间保留输入并可取消。气泡、工作区和真实会话验收统一记录在 [TODO](todo.md)。

默认构建 Apple Silicon。最低目标为 13 英寸 M1 MacBook Air／macOS 14 Sonoma；开发环境为 16 英寸 M5 Pro MacBook Pro／macOS 27.2 Golden Gate。最低目标机和 Intel Mac 实机验收仍待完成。

## 分支与更新检查

- `main` 保留正式版源码和普通用户说明；`joseph/dev` 保留开发源码、完整开发变更、开发文档和待办。本地与远端使用相同开发分支名。
- 两条分支独立提交，不自动合并或变基。同步时明确选取改动，不把开发文档整体覆盖到主线。
- 本分支不创建程序 Release 或应用版本标签。开发素材通过独立的 `dev-assets-*` Pre-release 提供，不设为 Latest。
- 应用更新检查读取 GitHub 最新正式 Release，并排除草稿、预发布和带预发布后缀的版本；不读取分支中的 VERSION。开发分支版本号更高也不会进入正式更新提醒。

历史接入和文档跟踪范围见 [开发分支维护](docs/开发分支.md)。

## 获取资源与构建

双击 `build.command` 检查环境、准备资源并构建 App。缺少 Apple 开发工具时，先说明 Apple 官方安装来源，再按 Y/N 选择；缺素材时先介绍原作来源，展示本项目 GitHub 下载地址，再按 Y/N 下载。拒绝后显示手动命令并等待任意键。默认 Apple Silicon，Intel Mac 双击后可选择 Intel。无参数且连接终端时启用菜单；带参数调用及 scripts 入口默认不弹菜单。

**[2026-11-10 完整资源包已发布](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/releases/tag/dev-assets-2026-11-10)。** 2026-11-02 旧包缺少两个桌宠模板图，无法单独完成当前版本构建。请使用最新资源包，详见 [开发资源获取](docs/开发资源获取.md)。

```sh
./build.command --resources-zip /路径/bailong-dev-assets-2026-11-10.zip
./build.command --check           # 只检查环境和资源，不构建 App
./build.command                  # Apple Silicon App
./build.command x86_64            # Intel App
./run-dev.command --build-only    # 只编译开发程序
./run-dev.command                # 编译并运行开发程序
```

导入默认只补齐缺失文件；加 `--replace-resources` 备份后替换包内文件，其他本地素材保留。可用 `--download-resources` 获取清单指定的资源包。`--help` 查看参数。

- 编译显示阶段及耗时，warning／error 与上下文实时输出，结束汇总诊断，不保留日志文件。下载显示原网址、进度条、百分比、大小及速度。
- 构建共用 SDK 和资源清单。三档按当前 SDK 标 ✓／✗：full（SDK 27+）为液态玻璃＋菜单图标优先显示，glass（26+）为液态玻璃，plain（14+）为普通材质；后两档的菜单图标由系统决定。`SDKROOT` 指定 SDK，`BAILONG_BUILD_PROFILE=auto|full|glass|plain` 选档，默认自动。三档最低运行目标均为 macOS 14，液态玻璃需 26+、菜单图标优先显示需 27+；缺环境时显示手动步骤与 Apple 官方中文教程链接。
- App 输出到 `dist/<VERSION>/<架构>/白龙桌宠Swift.app`，显式档位增加 `<档位>/`。`launch.command [arm64|x86_64]` 支持相同档位变量。双击构建完成后可在访达中显示或启动 App。
- `run-dev.command` 缓存核对源码、SDK、工具链及档位；arm64 输出 `.build/dev/`，显式 Intel 输出 `.build/dev-x86_64/`。开发运行沿用现有设置和历史，显示 PID；`^C` 请求退出并倒计时 5 秒，提前退出即结束脚本，超时只强制结束该 PID。`--build-only` 不要求运行资源，不更新已有 App。
- 正式版 0.7.4 提供 Apple Silicon 包与 Intel 社区测试包，Intel Mac 实机验收尚未完成。

## 代码与维护入口

源码位于 `Sources/BailongPet/`，保持单个 Swift target：

| 目录 | 职责 |
| --- | --- |
| `App/`、`Pet/` | 启动退出、桌宠动作、素材播放、菜单与位置 |
| `Conversation/` | 任务与会话协调、消息聚合、历史及额度 |
| `Codex/` | 协议连接、外部记录读取、请求与同步 |
| `UI/Bubble/`、`UI/Chat/` | 气泡卡片与正文布局、临时输入和历史界面 |
| `UI/Shared/` | 富文本、代码块、文件摘要、输入、复制反馈及文字动效 |
| `Settings/`、`Infrastructure/` | 偏好与设置页、更新、启动项、存储及恢复 |

- [维护 skill](skills/bailong-macos-port/SKILL.md)：仓库内可跟踪的维护指南，与本机安装的同名 skill 同步。
- [AGENTS.md](AGENTS.md)：协作边界和按任务阅读入口。
- [来源与架构](docs/来源与架构.md)：技术方案、来源及现行行为。
- [todo](todo.md)：稳定性观察、解耦、资源优化与后续功能。
- [完整变更记录](CHANGELOG.md)与[历史变更索引](docs/开发变更索引.md)：保留开发过程及正式版汇总。
- 历史调查：[启动闪退](docs/启动闪退调查.md)、[0.6.0-dev.10 设置界面检查](docs/设置界面检查.md)。

## 来源、致谢与反馈

原作参考基线为 **v0.5.1 / b102e73**。动画、音效、图标与软件组件的来源见 [来源与架构](docs/来源与架构.md) 和应用设置中的“关于 → 来源与致谢／开源许可”。

**感谢 [ruyeli/bailong-desktop-pet-english](https://github.com/ruyeli/bailong-desktop-pet-english) 分享的 SDK 兼容处理，为本轮编译脚本改进提供了灵感与参考。**

[提交 Issue](https://github.com/Joseph-Blue/bailong-desktop-pet-mac-swift/issues) 时请提供应用版本、macOS 版本和复现步骤；Codex 问题另附桌面端版本，并注明是桌宠内置对话还是 Codex 原会话。
