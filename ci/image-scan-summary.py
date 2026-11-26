#!/usr/bin/env python3
"""Print a bounded vulnerability summary without copying raw scanner output."""

import json
import os
import sys
from collections import Counter
from pathlib import Path


def safe(value: object) -> str:
    return "".join(c if c.isascii() and (c.isalnum() or c in "-._+:") else "_" for c in str(value))[:120]


def main() -> int:
    report = json.loads(Path(sys.argv[1]).read_text())
    findings = [
        vulnerability
        for result in report.get("Results") or []
        for vulnerability in result.get("Vulnerabilities") or []
    ]
    counts = Counter(item.get("Severity", "UNKNOWN") for item in findings)
    fixable = sum(bool(item.get("FixedVersion")) for item in findings)
    priority = {"CRITICAL": 0, "HIGH": 1}
    findings.sort(
        key=lambda item: (
            priority.get(item.get("Severity"), 2),
            not bool(item.get("FixedVersion")),
            str(item.get("VulnerabilityID", "")),
        )
    )
    lines = [
        f"pipeline={safe(os.environ.get('CI_PIPELINE_ID', 'unknown'))} "
        f"job={safe(os.environ.get('CI_JOB_ID', 'unknown'))} "
        f"image_findings={len(findings)} high={counts['HIGH']} "
        f"critical={counts['CRITICAL']} fixable={fixable}"
    ]
    for item in findings[:20]:
        lines.append(
            f"{safe(item.get('Severity', 'UNKNOWN'))} "
            f"{safe(item.get('VulnerabilityID', 'unknown'))} "
            f"package={safe(item.get('PkgName', 'unknown'))} "
            f"installed={safe(item.get('InstalledVersion', 'unknown'))} "
            f"fixed={safe(item.get('FixedVersion') or 'none')}"
        )
    if len(findings) > 20:
        lines.append(f"additional_findings={len(findings) - 20}")
    for line in lines:
        print(line, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
