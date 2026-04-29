#!/usr/bin/env bash
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/krishnagutta/workday-community-mcp/main/bin/quickstart.sh | bash
#
# What it does:
#   1. Clones the repo into ~/community-mcp (or $COMMUNITY_MCP_DIR if set).
#   2. Runs bin/install.sh — venv, deps, Playwright + Chromium, MCP registration.
#   3. Captures your Coveo auth token via Playwright (browser opens for login).
#
# Pass --no-playwright to skip Chromium download and use the manual cURL flow instead.
#
# Prerequisites: git, Python 3.11+, uv, and the Claude Code CLI on PATH.

set -euo pipefail

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
abort() { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

bold "==> community-mcp quickstart"
note "Target directory: $INSTALL_DIR"

command -v git >/dev/null    || abort "git not found. Install git, then re-run."
command -v uv >/dev/null     || abort "uv not found. Install from https://docs.astral.sh/uv/getting-started/installation/, then re-run."
command -v claude >/dev/null || abort "Claude Code CLI not found. Install from https://claude.com/claude-code, then re-run."

if [[ -d "$INSTALL_DIR" ]]; then
    note "Directory already exists. Pulling latest instead of cloning."
    git -C "$INSTALL_DIR" pull --ff-only
else
    note "Cloning $REPO_URL into $INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

bold "==> Running bin/install.sh"
INSTALL_FLAGS=()
[[ "$WITH_PLAYWRIGHT" == "false" ]] && INSTALL_FLAGS+=("--no-playwright")
[[ "$WITH_DESKTOP" == "false" ]]    && INSTALL_FLAGS+=("--no-desktop")
bash bin/install.sh "${INSTALL_FLAGS[@]}"

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

bold ""
bold "✅ Installed."
note "Start a new Claude Code session and ask Workday Community questions."
note "Tools: search_community, search_release_notes, search_knowledge_base,"
note "       get_article, search_and_read"
