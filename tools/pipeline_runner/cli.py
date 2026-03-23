"""CLI entry point for the pipeline runner."""

from __future__ import annotations

import argparse
import sys

from tools.pipeline_runner.pipelines.ci import run_ci_pipeline
from tools.pipeline_runner.pipelines.deploy import run_deploy_pipeline
from tools.pipeline_runner.pipelines.health_check import run_health_check
from tools.pipeline_runner.pipelines.queue_monitor import run_queue_monitor

PIPELINES = {
    "health": ("Health check — verify service and dependencies are running", run_health_check),
    "ci": ("CI pipeline — lint, test, build", run_ci_pipeline),
    "deploy": ("Deploy pipeline — build and push container image", run_deploy_pipeline),
    "monitor": ("Queue monitor — check queue stats and alert on anomalies", run_queue_monitor),
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="iamq-pipeline",
        description="OpenClaw IAMQ Pipeline Runner",
    )
    sub = parser.add_subparsers(dest="pipeline", help="Pipeline to run")

    for name, (desc, _) in PIPELINES.items():
        sub.add_parser(name, help=desc)

    # List command
    sub.add_parser("list", help="List available pipelines")

    args = parser.parse_args(argv)

    if args.pipeline == "list" or args.pipeline is None:
        print("Available pipelines:\n")
        for name, (desc, _) in PIPELINES.items():
            print(f"  {name:12s}  {desc}")
        return 0

    _, run_fn = PIPELINES[args.pipeline]
    return run_fn()


if __name__ == "__main__":
    sys.exit(main())
