#!/usr/bin/env bash
# One-shot installer for community-mcp.
#
# What it does:
#   1. Creates a Python 3.11 venv in .venv (via uv)
#   2. Installs the package and dependencies
#   3. Registers the MCP server with Claude Code (`claude mcp add community ...` at user scope)
#
# What it does NOT do:
#   - Capture the Coveo auth token. You'll do that the first time you use the tool:
#       1. Open https://community.workday.com in incognito Chrome and log in.
#       2. DevTools -> Network -> reload home -> right-click home.html -> Copy as cURL (bash).
#       3. From this directory:  pbpaste > .captured-curl.sh && bash bin/refresh-token.sh
#
# Tokens last ~2 hours. Re-run step 3 above when you see "AUTH ERROR: Coveo returned 401".

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

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

echo "==> Installing package"
VIRTUAL_ENV="$ROOT_DIR/.venv" uv pip install --project "$ROOT_DIR" -e "$ROOT_DIR" >/dev/null

echo "==> Registering MCP server with Claude Code (user scope)"
if claude mcp list 2>&1 | grep -q "^community:"; then
    echo "    'community' MCP already registered — skipping."
else
    claude mcp add community --scope user -- "$ROOT_DIR/.venv/bin/python" -m community_mcp.server
fi

cat <<EOF

✅ Installed.

Next step — capture your Coveo auth token (each user does this with their own Workday Community login):

  1. Open https://community.workday.com in incognito Chrome and log in.
  2. DevTools → Network tab → reload the home page.
  3. Right-click the 'home.html' request → Copy → Copy as cURL (bash).
  4. From this directory:
       pbpaste > .captured-curl.sh
       bash bin/refresh-token.sh

Then start a new Claude Code session and ask it to search Workday Community.

Token expiry: ~2 hours. When you see 'AUTH ERROR: Coveo returned 401', repeat step 4.
EOF
