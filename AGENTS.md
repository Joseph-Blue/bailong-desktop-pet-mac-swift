# 白龙桌宠 AppKit 工程

- 用户已授权：从零实现 Swift + AppKit 桌宠，第一阶段保留原 WebM 和 FFmpeg。不得引入 Python/PySide6 运行依赖；旧 Mac 工程仅作交互参考。
- 官方行为依据：../bailong-desktop-pet，当前源码基线 b102e73 / v0.5.1。修改前阅读相关函数，不整仓复制，不修改参考仓库。
- 版本独立遵守 SemVer，从 0.1.0-dev.1 开始。中文 commit message（添加/修复/构建/文档等分类），中文 CHANGELOG。
- 不要过度校验或过度防御。必要编译与针对改动的静态检查即可，不自动跑 SHA-256、截图、视觉、自检或冒烟流程。不用静默吞错或猜测性兼容层掩盖问题。
- 原生窗口、菜单、设置、历史、审批使用 AppKit。动画也使用原生视图；保留从吸边拖出后松手直接待机的用户选择。
- Apple Silicon 优先，不冒称 Intel 已验证。素材、解码器、构建产物及用户数据不进 Git；不运行 Windows EXE。
- 内置 Codex 任务与外部只读观察分开；真实停止、默认拒绝审批、历史保护、进程回收属于功能，必须实现。仅 completed 可宣告成功。
- 默认数据目录为 ~/Library/Application Support/BailongPetAppKit，与旧工程隔离。不读取凭证、不改全局 Codex 配置、不自动启用 LaunchAgent。
- 当前不派发其他 agent。实现进度与证据写入 docs/实施记录.md，未验证行为明确记录，不把构建成功当运行验收。
