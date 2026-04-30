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

set -eo pipefail
# Note: deliberately NOT using `set -u` — macOS bash 3.2 trips on empty-array
# expansions and we'd rather not require bash 4+.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

WITH_PLAYWRIGHT=true
WITH_DESKTOP=true
for arg in "$@"; do
    case "$arg" in
        --no-playwright) WITH_PLAYWRIGHT=false ;;
        --no-desktop)    WITH_DESKTOP=false ;;
    esac
done

export PATH="$HOME/.local/bin:$PATH"

if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv is required. Install it from https://docs.astral.sh/uv/getting-started/installation/ then re-run." >&2
    echo "  Quick install: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
    exit 1
fi

HAS_CLAUDE_CODE=true
if ! command -v claude >/dev/null 2>&1; then
    HAS_CLAUDE_CODE=false
    echo "    Claude Code CLI not found — skipping Claude Code registration."
    echo "    Will register with Claude Desktop only."
    echo "    (Install Claude Code from https://claude.com/claude-code and re-run to also register there.)"
fi

# If we're going to write Claude Desktop config and Desktop is running, briefly quit it
# (it caches the config in memory and would auto-save over our edits). We relaunch it
# at the end of install so the user doesn't notice.
RELAUNCH_DESKTOP=false
relaunch_desktop_on_exit() {
    if [[ "$RELAUNCH_DESKTOP" == "true" ]]; then
        _relaunch_claude
    fi
}
trap relaunch_desktop_on_exit EXIT

_relaunch_claude() {
    if open -a "Claude" 2>/dev/null; then
        echo "==> Claude Desktop relaunched."
    else
        echo ""
        echo "⚠️  Could not relaunch Claude Desktop automatically."
        echo "   Open it manually from your Applications folder or Spotlight."
    fi
}

if [[ "$WITH_DESKTOP" == "true" ]] && pgrep -x "Claude" >/dev/null 2>&1; then
    echo "==> Claude Desktop is running — quitting briefly to update its config"
    echo "    (your conversations are preserved; macOS will restore the same window on relaunch)"
    osascript -e 'quit app "Claude"' 2>/dev/null || true
    # Wait up to 10s for graceful quit
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "Claude" >/dev/null 2>&1 || break
        sleep 1
    done
    if pgrep -x "Claude" >/dev/null 2>&1; then
        echo "ERROR: Claude Desktop didn't quit within 10s. Quit it manually (Cmd+Q) and re-run." >&2
        exit 1
    fi
    RELAUNCH_DESKTOP=true
fi

if [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
    echo "==> Reusing existing Python virtualenv at .venv"
else
    echo "==> Creating Python 3.11 virtualenv at .venv"
    uv venv --python 3.11 .venv
fi

echo "==> Installing package + dependencies"
VIRTUAL_ENV="$ROOT_DIR/.venv" uv pip install --project "$ROOT_DIR" -e "$ROOT_DIR" >/dev/null

if [[ "$WITH_PLAYWRIGHT" == "true" ]]; then
    echo "==> Downloading Chromium for Playwright (~170MB)"
    "$ROOT_DIR/.venv/bin/playwright" install chromium
else
    echo "==> Skipping Chromium download (--no-playwright). Auto-refresh disabled."
    echo "    You'll need to capture tokens manually via 'bash bin/refresh-token.sh --manual'."
fi

if [[ "$HAS_CLAUDE_CODE" == "true" ]]; then
    echo "==> Registering MCP server with Claude Code (user scope)"
    if claude mcp list 2>&1 | grep -q "^community:"; then
        echo "    'community' MCP already registered — skipping."
    else
        claude mcp add community --scope user -- "$ROOT_DIR/.venv/bin/python" -m community_mcp.server
    fi
fi

if [[ "$WITH_DESKTOP" == "true" ]]; then
    case "$(uname -s)" in
        Darwin*) DESKTOP_CONFIG_DIR="$HOME/Library/Application Support/Claude" ;;
        Linux*)  DESKTOP_CONFIG_DIR="$HOME/.config/Claude" ;;
        *)       DESKTOP_CONFIG_DIR="" ;;
    esac
    if [[ -n "$DESKTOP_CONFIG_DIR" && -d "$DESKTOP_CONFIG_DIR" ]]; then
        echo "==> Registering MCP server with Claude Desktop"
        "$ROOT_DIR/.venv/bin/python" "$ROOT_DIR/bin/_register_desktop.py" \
            "$DESKTOP_CONFIG_DIR/claude_desktop_config.json" \
            "$ROOT_DIR/.venv/bin/python" \
            "$ROOT_DIR"
    elif [[ -n "$DESKTOP_CONFIG_DIR" ]]; then
        echo "==> Claude Desktop not detected at $DESKTOP_CONFIG_DIR — skipping."
        echo "    (Install Claude Desktop later then re-run: bash bin/install.sh)"
    fi
fi

if [[ "$RELAUNCH_DESKTOP" == "true" ]]; then
    _relaunch_claude
    RELAUNCH_DESKTOP=false  # done; suppress the EXIT trap relaunch
fi

if [[ "$HAS_CLAUDE_CODE" == "true" ]]; then
    NEXT_STEP="Then start a new Claude Code session and ask it to search Workday Community."
else
    NEXT_STEP="Then fully quit Claude Desktop (Cmd+Q) and reopen it to pick up the new MCP."
fi

cat <<EOF

✅ Installed.

Next step — capture your Coveo auth token:

  bash bin/refresh-token.sh

A real Chromium window will open. Log in to Workday Community
(handle MFA normally). The window closes automatically once login completes.

Subsequent refreshes are silent (headless, ~1 second) — until your saved
session ages out (~12h), at which point the browser opens again for re-login.

$NEXT_STEP
EOF
