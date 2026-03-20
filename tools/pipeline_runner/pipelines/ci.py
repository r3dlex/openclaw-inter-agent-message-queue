"""CI pipeline — lint tools, compile and test Elixir service."""

from __future__ import annotations

import subprocess


def _run(cmd: list[str], label: str, cwd: str | None = None) -> bool:
    print(f"\n--- {label} ---")
    result = subprocess.run(cmd, text=True, cwd=cwd)
    if result.returncode != 0:
        print(f"FAILED: {label}")
        return False
    print(f"PASSED: {label}")
    return True


def run_ci_pipeline() -> int:
    print("=== OpenClaw MQ CI Pipeline ===")

    steps = [
        # Elixir
        (["mix", "deps.get"], "Elixir deps", "openclaw_mq"),
        (["mix", "compile", "--warnings-as-errors"], "Elixir compile", "openclaw_mq"),
        (["mix", "test"], "Elixir tests", "openclaw_mq"),
        # Python tools
        (["ruff", "check", "tools/"], "Lint Python tools (ruff)", None),
        (["ruff", "format", "--check", "tools/"], "Format check Python tools (ruff)", None),
    ]

    all_passed = True
    for cmd, label, cwd in steps:
        if not _run(cmd, label, cwd=cwd):
            all_passed = False

    print(f"\n=== CI {'PASSED' if all_passed else 'FAILED'} ===")
    return 0 if all_passed else 1
