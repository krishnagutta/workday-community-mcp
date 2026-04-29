#!/usr/bin/env bash
# One-shot installer for community-mcp.
#
# What it does:
#   1. Creates a Python 3.11 venv in .venv (via uv)
#   2. Installs the package and dependencies (Playwright included by default)
#   3. Downloads Chromium for Playwright auto-refresh (~170MB) — pass --no-playwright to skip
#   4. Registers the MCP server with Claude Code (`claude mcp add community ...` at user scope)
#
# What it does NOT do:
#   - Capture the Coveo auth token. Run `bash bin/refresh-token.sh` after install.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WITH_PLAYWRIGHT=true
for arg in "$@"; do
    case "$arg" in
        --no-playwright) WITH_PLAYWRIGHT=false ;;
    esac
done

if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv is required. Install it from https://docs.astral.sh/uv/getting-started/installation/" >&2
    exit 1
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: Claude Code CLI ('claude') not found on PATH." >&2
    echo "  Install it from https://claude.com/claude-code, then re-run." >&2
    exit 1
fi

echo "==> Creating Python 3.11 virtualenv at .venv"
uv venv --python 3.11 .venv

echo "==> Installing package + dependencies"
VIRTUAL_ENV="$ROOT_DIR/.venv" uv pip install --project "$ROOT_DIR" -e "$ROOT_DIR" >/dev/null

if [[ "$WITH_PLAYWRIGHT" == "true" ]]; then
    echo "==> Downloading Chromium for Playwright (~170MB)"
    "$ROOT_DIR/.venv/bin/playwright" install chromium
else
    echo "==> Skipping Chromium download (--no-playwright). Auto-refresh disabled."
    echo "    You'll need to capture tokens manually via 'bash bin/refresh-token.sh --manual'."
fi

echo "==> Registering MCP server with Claude Code (user scope)"
if claude mcp list 2>&1 | grep -q "^community:"; then
    echo "    'community' MCP already registered — skipping."
else
    claude mcp add community --scope user -- "$ROOT_DIR/.venv/bin/python" -m community_mcp.server
fi

cat <<EOF

✅ Installed.

Next step — capture your Coveo auth token:

  bash bin/refresh-token.sh

A real Chromium window will open. Log in to Workday Community
(handle MFA normally). The window closes automatically once login completes.

Subsequent refreshes are silent (headless, ~1 second) — until your saved
session ages out (~12h), at which point the browser opens again for re-login.

Then start a new Claude Code session and ask it to search Workday Community.
EOF
