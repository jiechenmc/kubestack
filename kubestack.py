#!/usr/bin/env python3
"""
kubestack.py - CLI for managing kubestack deployments

Usage:
    python3 kubestack.py generate
"""

import argparse
import subprocess
import sys
from pathlib import Path

HELM_DIR = Path("helm")
GENERATED_DIR = Path("kubernetes/generated")


def run(cmd: list, capture=False) -> subprocess.CompletedProcess:
    print(f"+ {' '.join(str(c) for c in cmd)}")
    result = subprocess.run(cmd, capture_output=capture, text=True)
    if result.returncode != 0:
        print(f"ERROR: {result.stderr if capture else ''}")
        sys.exit(result.returncode)
    return result


def cmd_generate():
    if not HELM_DIR.exists():
        print(f"ERROR: {HELM_DIR} not found")
        sys.exit(1)

    GENERATED_DIR.mkdir(parents=True, exist_ok=True)

    charts = [d for d in sorted(HELM_DIR.iterdir()) if d.is_dir()]
    if not charts:
        print(f"No charts found in {HELM_DIR}")
        sys.exit(1)

    print(f"── Rendering {len(charts)} chart(s) → {GENERATED_DIR}\n")

    failed = []
    for chart_dir in charts:
        release = chart_dir.name
        values = chart_dir / "values.yaml"
        out = GENERATED_DIR / f"{release}.yaml"

        if not values.exists():
            print(f"  WARN: no values.yaml in {chart_dir}, skipping")
            continue

        print(f"  {release} → {out}")
        result = subprocess.run(
            [
                "helm",
                "template",
                release,
                str(chart_dir),
                "--values",
                str(values),
                "--include-crds",
            ],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            print(f"  ERROR: failed to render {release}")
            print(f"  {result.stderr.strip()}")
            failed.append(release)
            continue

        out.write_text(result.stdout)

    print(f"\n── Done — {len(charts) - len(failed)}/{len(charts)} rendered")
    if failed:
        print(f"   Failed: {', '.join(failed)}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(prog="kubestack")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("generate", help="Render all Helm charts to kubernetes/generated")

    args = parser.parse_args()

    if args.command == "generate":
        cmd_generate()
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
