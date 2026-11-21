#!/usr/bin/env python3
"""为一个 Codex 项目登记白龙桌宠的命令审批 Hook。信任由用户在 Codex 中确认。"""
import argparse
import json
import os
from pathlib import Path
import shlex
import tempfile


def register(project, executable):
    project = project.resolve(strict=True)
    directory = project / ".codex"
    target = directory / "hooks.json"
    user_config = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex").resolve()
    if project == Path.home() or directory.resolve() == user_config or directory.is_symlink() or target.is_symlink():
        raise ValueError("请选择项目目录及其本地 .codex 配置。")
    executable = executable.resolve(strict=True)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError("请先构建本地开发版，或用 --binary 指定桌宠可执行文件。")
    command = "exec " + shlex.quote(str(executable)) + " --codex-permission-request"
    directory.mkdir(mode=0o700, exist_ok=True)
    original = target.read_bytes() if target.exists() else None
    config = json.loads(original) if original is not None else {}
    groups = config.setdefault("hooks", {}).setdefault("PermissionRequest", [])
    handler = {"type": "command", "command": command, "timeout": 120, "statusMessage": "等待桌宠审批"}
    for group in groups:
        if any(entry.get("type") == "command" and entry.get("command") == command for entry in group["hooks"]):
            if group.get("matcher") in (None, "", "Bash", "^Bash$"):
                return target
            raise ValueError("此审批命令已有其他匹配规则，请在项目 Hook 配置中核对。")
    groups.append({"matcher": "^Bash$", "hooks": [handler]})
    content = json.dumps(config, ensure_ascii=False, indent=2) + "\n"
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=directory, delete=False) as temp:
        temporary = Path(temp.name)
        temp.write(content)
    try:
        if original is None:
            os.link(temporary, target)
        else:
            if target.read_bytes() != original:
                raise ValueError("项目 Hook 配置已更新，请重新运行。")
            temporary.chmod(target.stat().st_mode & 0o777)
            os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return target


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", type=Path, help="要试用桌宠审批的项目目录")
    parser.add_argument("--binary", type=Path, default=Path(__file__).resolve().parents[1] / ".build/dev/BailongPetDev")
    args = parser.parse_args()
    try:
        path = register(args.project, args.binary)
    except (OSError, ValueError, TypeError, AttributeError, KeyError) as error:
        parser.exit(1, f"登记失败：{error}\n")
    print(f"项目审批 Hook 已登记到 {path}。在该项目的 Codex CLI 中打开 /hooks，核对并信任后，回到桌面端测试。")
