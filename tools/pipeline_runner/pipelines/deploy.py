"""Deploy pipeline — build container image and optionally push."""

from __future__ import annotations

import os
import subprocess


def _run(cmd: list[str], label: str) -> bool:
    print(f"\n--- {label} ---")
    result = subprocess.run(cmd, text=True)
    if result.returncode != 0:
        print(f"FAILED: {label}")
        return False
    print(f"PASSED: {label}")
    return True


def run_deploy_pipeline() -> int:
    print("=== OpenClaw MQ Deploy Pipeline ===")

    image = os.environ.get("IAMQ_IMAGE", "openclaw-iamq")
    tag = os.environ.get("IAMQ_TAG", "latest")
    full_image = f"{image}:{tag}"

    steps: list[tuple[list[str], str]] = [
        (["docker", "build", "-t", full_image, "."], f"Build image: {full_image}"),
    ]

    registry = os.environ.get("IAMQ_REGISTRY", "")
    if registry:
        remote_image = f"{registry}/{full_image}"
        steps.append((["docker", "tag", full_image, remote_image], f"Tag: {remote_image}"))
        steps.append((["docker", "push", remote_image], f"Push: {remote_image}"))

    all_passed = True
    for cmd, label in steps:
        if not _run(cmd, label):
            all_passed = False
            break

    print(f"\n=== Deploy {'PASSED' if all_passed else 'FAILED'} ===")
    return 0 if all_passed else 1
