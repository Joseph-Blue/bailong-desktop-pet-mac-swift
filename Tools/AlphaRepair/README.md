# 白龙透明动画修边工具

用 Python、NumPy 和 Pillow 离线处理 RGBA PNG 序列。两份脚本取自白龙桌宠Swift 的落地动作修复批次，读取的动作名称来自输入目录。可以直接运行，也可以把整个 `bailong-webm-edge-repair` 文件夹交给 agent，从 `SKILL.md` 开始。要安装为可复用技能，把这个完整文件夹复制到该 agent 的技能目录。[技能说明](bailong-webm-edge-repair/SKILL.md) · [四个仓库的素材修复对照](bailong-webm-edge-repair/references/四个仓库的素材修复对照.md)

## Windows 命令行

在此 README 所在目录打开 PowerShell。用以下命令准备 Python 环境。输入已经是 RGBA PNG 时，只需 Python 依赖。

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install numpy Pillow
```

每个批次在 `originals` 下按动作分目录。以 `work/originals/动作ID/0001.png` 为例，`动作ID` 可以换成清单里的名称。已有 PNG 可以直接放进对应目录。若原片是带 Alpha 的 VP9 WebM，可用带 `libvpx-vp9` 解码器的 FFmpeg 抽取完整帧序列，保留原尺寸并记录原片时间轴以便回封。把示例路径换成自己的文件。

```powershell
New-Item -ItemType Directory -Force ".\work\originals\动作ID" | Out-Null
ffmpeg -n -c:v libvpx-vp9 -i "动作文件.webm" -fps_mode passthrough -pix_fmt rgba ".\work\originals\动作ID\%04d.png"
```

### 清理

```powershell
.\.venv\Scripts\python.exe -X utf8 .\bailong-webm-edge-repair\scripts\repair_frames.py --batch .\work --mode conservative
```

`conservative` 优先保护紫色描边，清理与透明区相连的残留。`aggressive` 额外处理卷发等封闭空隙，并削弱两路清理后留下的边缘。这是历史脚本省略 `--mode` 时的默认值。要对照两种模式，用相同输入分别建立批次，每次写入新的输出目录。

修后帧在 `work/repaired/动作ID/`，删除蒙版在 `work/masks/动作ID/`，白色表示删除，黑色表示保留。逐帧统计在 `work/repair-report.json`。清理阶段只改 Alpha。要试指定坏帧，可以只把该帧及前后几帧放入一个批次。`--samples` 固定读取已存在的 `0001.png`、`0048.png`、`0096.png`。

### 局部平滑（可选）

需要改善修后轮廓的锯齿时，将清理结果作为第二个批次的输入。

```powershell
New-Item -ItemType Directory -Force ".\smooth\originals" | Out-Null
Copy-Item -Recurse ".\work\repaired\动作ID" ".\smooth\originals\动作ID"
.\.venv\Scripts\python.exe -X utf8 .\bailong-webm-edge-repair\scripts\smooth_frames.py --batch .\smooth
```

平滑帧在 `smooth/repaired/`，变化图在 `smooth/masks/`，红色表示 Alpha 减少，绿色表示增加。新增的半透明像素从相邻可见像素取色。两步都按单帧处理。对含粒子或光效的动作，值得把原帧、蒙版和修后同帧一起看，再按原速观察特效出现和淡出的过程。

原角色和动画来自 jingh12312-rgb（風-隐）的《GPT白龙娘动态桌宠》，本目录提供修复工具。两份脚本有 macOS 制作记录，Windows 实机运行待验证。[原作仓库](https://github.com/jingh12312-rgb/bailong-desktop-pet)
