"""Queue monitor pipeline — check Elixir service stats and flag anomalies."""

from __future__ import annotations

import json
import os
import urllib.request


def run_queue_monitor() -> int:
    print("=== OpenClaw MQ Monitor ===\n")

    port = os.environ.get("IAMQ_HTTP_PORT", "18790")
    base_url = f"http://127.0.0.1:{port}"

    max_unread = int(os.environ.get("IAMQ_ALERT_MAX_UNREAD", "100"))

    try:
        req = urllib.request.Request(f"{base_url}/status", method="GET")
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
    except Exception as exc:
        print(f"[CRITICAL] Cannot reach MQ service: {exc}")
        return 2

    print(f"  Checked at:   {data.get('checkedAt', 'unknown')}")

    agents = data.get("agents_online", [])
    print(f"  Agents online: {len(agents)}")
    for agent in agents:
        print(f"    - {agent.get('id', 'unknown')}")

    queues = data.get("queues", {})
    alerts: list[str] = []

    total_unread = 0
    for queue_name, stats in queues.items():
        unread = stats.get("unread", 0)
        total_unread += unread
        print(f"\n  Queue [{queue_name}]:")
        print(f"    unread={unread}  read={stats.get('read', 0)}  acted={stats.get('acted', 0)}")
        oldest = stats.get("oldest_unread")
        if oldest:
            print(f"    oldest unread: {oldest}")

    if total_unread > max_unread:
        alerts.append(f"Total unread messages: {total_unread} (threshold: {max_unread})")
    if len(agents) == 0:
        alerts.append("No agents online")

    if alerts:
        print("\n[ALERTS]")
        for alert in alerts:
            print(f"  !! {alert}")
        return 1

    print("\n[OK] No anomalies detected")
    return 0
