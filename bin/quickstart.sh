#!/usr/bin/env bash
# One-line installer:
#   curl -fsSL https://raw.githubusercontent.com/krishnagutta/workday-community-mcp/main/bin/quickstart.sh | bash
#
# What it does:
#   1. Clones the repo into ~/community-mcp (or $COMMUNITY_MCP_DIR if set).
#   2. Runs bin/install.sh (creates venv, installs deps, registers MCP with Claude Code).
#   3. Walks you through capturing a Coveo auth token via Playwright (if installed).
#
# Prerequisites: git, Python 3.11+, uv, and the Claude Code CLI on PATH.

set -euo pipefail

REPO_URL="${COMMUNITY_MCP_REPO_URL:-https://github.com/krishnagutta/workday-community-mcp.git}"
INSTALL_DIR="${COMMUNITY_MCP_DIR:-$HOME/community-mcp}"

bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
note()   { printf '  %s\n' "$*"; }
abort()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

bold "==> community-mcp quickstart"
note "Target directory: $INSTALL_DIR"

# Preflight
command -v git >/dev/null  || abort "git not found. Install git, then re-run."
command -v uv >/dev/null   || abort "uv not found. Install from https://docs.astral.sh/uv/getting-started/installation/, then re-run."
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
bash bin/install.sh

bold "==> Optional: Playwright auto-refresh"
note "Auto-refresh skips manual cookie capture. Adds ~250MB Chromium to your laptop."
read -r -p "  Install Playwright + Chromium for auto-refresh? [Y/n] " ans
case "${ans,,}" in
    n|no)
        note "Skipping. You'll capture tokens manually via DevTools (see README)."
        AUTO_REFRESH=false
        ;;
    *)
        VIRTUAL_ENV="$INSTALL_DIR/.venv" uv pip install --project "$INSTALL_DIR" -e "$INSTALL_DIR[auto-refresh]" >/dev/null
        "$INSTALL_DIR/.venv/bin/playwright" install chromium
        AUTO_REFRESH=true
        ;;
esac

bold "==> Capturing your Workday Community auth token"
if [[ "$AUTO_REFRESH" == "true" ]]; then
    note "A Chromium window will open. Log in to Workday Community (handle MFA normally)."
    note "The window closes automatically once login completes."
    bash "$INSTALL_DIR/bin/refresh-token.sh" --auto
else
    cat <<EOF
Manual flow:
  1. Open https://community.workday.com in incognito Chrome and log in.
  2. DevTools -> Network -> reload the home page.
  3. Right-click the 'home.html' request -> Copy -> Copy as cURL (bash).
  4. Then run:
       cd "$INSTALL_DIR"
       pbpaste > .captured-curl.sh
       bash bin/refresh-token.sh

Token expires every ~2 hours. Repeat this when tools return AUTH ERROR.
EOF
fi

bold ""
bold "✅ Installed."
note "Start a new Claude Code session and ask Workday Community questions."
note "Tools available:  mcp__community__search_community,"
note "                  mcp__community__search_release_notes,"
note "                  mcp__community__search_knowledge_base,"
note "                  mcp__community__get_article,"
note "                  mcp__community__search_and_read"
