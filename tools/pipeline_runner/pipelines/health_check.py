"""Health check pipeline — verify Elixir service and dependency status."""

from __future__ import annotations

import json
import os
import subprocess
import urllib.request


def _check_service(url: str, name: str) -> bool:
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
            print(f"  [OK]   {name}: {json.dumps(data, indent=None)[:80]}")
            return True
    except Exception as exc:
        print(f"  [FAIL] {name}: {exc}")
        return False


def _check_command(cmd: list[str], name: str) -> bool:
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            print(f"  [OK]   {name}")
            return True
        print(f"  [FAIL] {name}: exit code {result.returncode}")
        return False
    except FileNotFoundError:
        print(f"  [SKIP] {name}: not installed")
        return True
    except Exception as exc:
        print(f"  [FAIL] {name}: {exc}")
        return False


def run_health_check() -> int:
    print("=== OpenClaw MQ Health Check ===\n")

    port = os.environ.get("IAMQ_HTTP_PORT", "18790")
    base_url = f"http://127.0.0.1:{port}"

    checks_passed = 0
    checks_total = 0

    print("Service:")
    checks_total += 1
    if _check_service(f"{base_url}/status", "MQ Status"):
        checks_passed += 1

    checks_total += 1
    if _check_service(f"{base_url}/agents", "Agent Registry"):
        checks_passed += 1

    print("\nTools:")
    checks_total += 1
    if _check_command(["docker", "--version"], "Docker"):
        checks_passed += 1

    checks_total += 1
    if _check_command(["gh", "--version"], "GitHub CLI"):
        checks_passed += 1

    checks_total += 1
    if _check_command(["mix", "--version"], "Elixir/Mix"):
        checks_passed += 1

    print(f"\n=== {checks_passed}/{checks_total} checks passed ===")
    return 0 if checks_passed == checks_total else 1
