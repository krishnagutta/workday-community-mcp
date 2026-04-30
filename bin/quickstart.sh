#!/usr/bin/env bash
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/krishnagutta/workday-community-mcp/main/bin/quickstart.sh | bash
#
# What it does:
#   1. Auto-installs uv if missing.
#   2. Clones the repo into ~/community-mcp (or $COMMUNITY_MCP_DIR if set).
#   3. Runs bin/install.sh — venv, deps, Playwright + Chromium, MCP registration.
#   4. Captures your Coveo auth token via Playwright (browser opens for login).
#
# Pass --no-playwright to skip Chromium and use the manual cURL flow instead.
# Pass --no-desktop to skip Claude Desktop registration.
#
# Prerequisites: git, Claude Code CLI. (uv is auto-installed if missing.)

set -eo pipefail
# Note: deliberately NOT using `set -u` because macOS bash 3.2 chokes on
# empty-array expansions like "${INSTALL_FLAGS[@]}" under nounset.

REPO_URL="${COMMUNITY_MCP_REPO_URL:-https://github.com/krishnagutta/workday-community-mcp.git}"
INSTALL_DIR="${COMMUNITY_MCP_DIR:-$HOME/community-mcp}"

WITH_PLAYWRIGHT=true
WITH_DESKTOP=true
for arg in "$@"; do
    case "$arg" in
        --no-playwright) WITH_PLAYWRIGHT=false ;;
        --no-desktop)    WITH_DESKTOP=false ;;
    esac
done

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
note()  { printf '  %s\n' "$*"; }
warn()  { printf '\033[33m  ! %s\033[0m\n' "$*"; }
abort() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

bold "==> community-mcp quickstart"
note "Target directory: $INSTALL_DIR"

# --- Pre-flight ---

# Defensive PATH update so a fresh uv install is visible immediately.
export PATH="$HOME/.local/bin:$PATH"

command -v git >/dev/null || abort "git not found. Install git, then re-run."

HAS_CLAUDE_CODE=true
if ! command -v claude >/dev/null 2>&1; then
    HAS_CLAUDE_CODE=false
    warn "Claude Code CLI not found — will register with Claude Desktop only."
    warn "If you also use Claude Code, install it from https://claude.com/claude-code and re-run."
fi

if ! command -v uv >/dev/null 2>&1; then
    note "uv not found — auto-installing from astral.sh ..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v uv >/dev/null 2>&1; then
        abort "uv install failed. Try manually:
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
fi

# Note: if Claude Desktop is running, install.sh will briefly quit it and relaunch.

# --- Clone ---

if [[ -d "$INSTALL_DIR" ]]; then
    note "Directory already exists. Pulling latest instead of cloning."
    git -C "$INSTALL_DIR" pull --ff-only
else
    note "Cloning $REPO_URL into $INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# --- Install ---

bold "==> Running bin/install.sh"
INSTALL_FLAGS=()
[[ "$WITH_PLAYWRIGHT" == "false" ]] && INSTALL_FLAGS+=("--no-playwright")
[[ "$WITH_DESKTOP" == "false" ]]    && INSTALL_FLAGS+=("--no-desktop")
# bash 3.2-safe expansion: only pass the array if it has entries.
if [[ ${#INSTALL_FLAGS[@]} -gt 0 ]]; then
    bash bin/install.sh "${INSTALL_FLAGS[@]}"
else
    bash bin/install.sh
fi

# --- Token capture ---

bold "==> Capturing your Workday Community auth token"
if [[ "$WITH_PLAYWRIGHT" == "true" ]]; then
    note "A Chromium window will open. Log in to Workday Community (handle MFA normally)."
    note "The window closes automatically once login completes."
    bash "$INSTALL_DIR/bin/refresh-token.sh"
else
    cat <<EOF
Manual flow (no Playwright):
  1. Open https://community.workday.com in incognito Chrome and log in.
  2. DevTools -> Network -> reload the home page.
  3. Right-click the 'home.html' request -> Copy -> Copy as cURL (bash).
  4. Then run:
       cd "$INSTALL_DIR"
       pbpaste > .captured-curl.sh
       bash bin/refresh-token.sh --manual

Token expires every ~2 hours. Repeat this when tools return AUTH ERROR.
EOF
fi

# --- Final banner ---

printf '\n'
printf '\033[32m\033[1m✅ Installed.\033[0m\n\n'
printf '\033[1m  IMPORTANT: open a NEW terminal session before using community tools.\033[0m\n'
note "  This shell can't see the newly-registered MCP — only fresh sessions will."
printf '\n'
if [[ "$WITH_DESKTOP" == "true" ]]; then
    printf '\033[1m  If you use Claude Desktop, fully quit (Cmd+Q) and reopen it.\033[0m\n'
    printf '\n'
fi
note "Available tools:"
note "  search_community, search_release_notes, search_knowledge_base,"
note "  get_article, search_and_read"
