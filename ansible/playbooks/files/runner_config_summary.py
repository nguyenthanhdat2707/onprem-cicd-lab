#!/usr/bin/env python3
"""Print only runner fields needed for the Docker hostname migration."""

import json
import re
import sys
import tomllib
from pathlib import Path


def main() -> int:
    try:
        raw = Path(sys.argv[1]).read_bytes()
        config = tomllib.loads(raw.decode("utf-8"))
    except (IndexError, OSError, UnicodeError, tomllib.TOMLDecodeError):
        print("Runner configuration is unreadable or invalid TOML", file=sys.stderr)
        return 2

    section = None
    sections = []
    extra_hosts_sections = []
    for line in raw.decode("utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped.strip("[]")
            sections.append(section)
        elif re.match(r"^[ \t]*extra_hosts[ \t]*=", line):
            extra_hosts_sections.append(section)

    runners = []
    for runner in config.get("runners", []):
        runners.append(
            {
                "name": runner.get("name", ""),
                "executor": runner.get("executor", ""),
                "extra_hosts": runner.get("docker", {}).get("extra_hosts", []),
            }
        )

    print(
        json.dumps(
            {
                "runners": runners,
                "docker_section_count": sections.count("runners.docker"),
                "extra_hosts_sections": extra_hosts_sections,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
