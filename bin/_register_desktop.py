#!/usr/bin/env python3
"""Internal helper: idempotently add the community MCP entry to Claude Desktop config.

Invoked by bin/install.sh. Not meant to be run directly.

Usage:
    _register_desktop.py <config-path> <python-path> <cwd>
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

EXPECTED_ARGS = 4  # script + 3 positional


def main() -> int:
    if len(sys.argv) != EXPECTED_ARGS:
        print(f"Usage: {sys.argv[0]} <config-path> <python-path> <cwd>", file=sys.stderr)
        return 2

    config_path = Path(sys.argv[1])
    python_path = sys.argv[2]
    cwd = sys.argv[3]

    config: dict[str, object] = {}
    if config_path.exists():
        try:
            config = json.loads(config_path.read_text())
        except json.JSONDecodeError as exc:
            print(
                f"    ERROR: {config_path} has invalid JSON ({exc}); not modifying.",
                file=sys.stderr,
            )
            return 1

    servers = config.setdefault("mcpServers", {})
    if not isinstance(servers, dict):
        print("    ERROR: mcpServers is not an object; not modifying.", file=sys.stderr)
        return 1

    if "community" in servers:
        print("    'community' already in Claude Desktop config — skipping.")
        return 0

    servers["community"] = {
        "command": python_path,
        "args": ["-m", "community_mcp.server"],
        "cwd": cwd,
    }

    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    print(f"    Wrote 'community' entry to {config_path}")
    print("    Fully quit (Cmd+Q) and reopen Claude Desktop to pick up the new MCP.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
