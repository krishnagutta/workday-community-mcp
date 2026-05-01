#!/usr/bin/env bash
# Reinstall community-mcp from scratch.
# Use this if a previous install failed or Claude Desktop isn't picking up the MCP.
#
#   bash bin/reinstall.sh
#
# What it does:
#   1. Removes existing MCP registration from Claude Code (if installed)
#   2. Removes community entry from Claude Desktop config
#   3. Deletes the .venv so dependencies are reinstalled cleanly
#   4. Re-runs bin/install.sh (fresh venv, deps, Playwright, registrations)

set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="$HOME/.local/bin:$PATH"

echo "==> Removing existing registrations"

# Claude Code
if command -v claude >/dev/null 2>&1; then
    if claude mcp list 2>&1 | grep -q "^community:"; then
        claude mcp remove community
        echo "    Removed from Claude Code."
    else
        echo "    Not in Claude Code — skipping."
    fi
fi

# Claude Desktop
case "$(uname -s)" in
    Darwin*) DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
    Linux*)  DESKTOP_CONFIG="$HOME/.config/Claude/claude_desktop_config.json" ;;
    *)       DESKTOP_CONFIG="" ;;
esac

if [[ -n "$DESKTOP_CONFIG" && -f "$DESKTOP_CONFIG" ]]; then
    "$ROOT_DIR/.venv/bin/python" 2>/dev/null - "$DESKTOP_CONFIG" <<'EOF' || \
    python3 - "$DESKTOP_CONFIG" <<'EOF'
import json, sys
path = sys.argv[1]
with open(path) as f:
    config = json.load(f)
servers = config.get("mcpServers", {})
if "community" in servers:
    del servers["community"]
    with open(path, "w") as f:
        json.dump(config, f, indent=2)
    print("    Removed from Claude Desktop config.")
else:
    print("    Not in Claude Desktop config — skipping.")
EOF
fi

echo ""
echo "==> Removing .venv for clean reinstall"
rm -rf "$ROOT_DIR/.venv"

echo ""
echo "==> Re-running install"
bash "$ROOT_DIR/bin/install.sh" "$@"
