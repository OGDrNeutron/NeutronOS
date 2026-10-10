#!/usr/bin/env python3
"""Bounded command-line adapter for Patch 72/73 app security."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
from neutronos_app_security import PackageAnalyzer, QuarantineStore, SandboxCapabilities, SandboxPolicy


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("analyze", "capabilities", "quarantine-list"))
    parser.add_argument("--package")
    parser.add_argument("--quarantine-root", default="/var/lib/neutronos/security-core/quarantine-apps")
    args = parser.parse_args()
    if args.action == "analyze":
        if not args.package: parser.error("--package is required")
        result = PackageAnalyzer().analyze(Path(args.package))
    elif args.action == "capabilities":
        result = {"capabilities": vars(SandboxCapabilities.detect()), "policy": SandboxPolicy().limits()}
    else:
        result = {"items": QuarantineStore(Path(args.quarantine_root)).list()}
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
