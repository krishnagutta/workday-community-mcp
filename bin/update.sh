#!/usr/bin/env bash
# Update community-mcp to the latest version.
#
#   bash bin/update.sh
#
# What it does:
#   1. git pull --ff-only (refuses to merge — you must resolve local changes manually).
#   2. Re-runs bin/install.sh — reinstalls deps, refreshes Playwright, re-registers
#      the MCP with both Claude Code and Claude Desktop. Idempotent.
#   3. If Claude Desktop was running, briefly quits and relaunches it so new tools
#      are picked up.
#
# Your auth state (.env, .playwright-state.json) is preserved.

set -eo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Pulling latest from origin/main"
if ! git diff --quiet HEAD -- 2>/dev/null; then
    echo "ERROR: you have uncommitted local changes in $ROOT_DIR." >&2
    echo "  Stash or commit them first, then re-run: git stash && bash bin/update.sh" >&2
    exit 1
fi

PREV_HEAD=$(git rev-parse HEAD)
git pull --ff-only

NEW_HEAD=$(git rev-parse HEAD)
if [[ "$PREV_HEAD" == "$NEW_HEAD" ]]; then
    echo "    Already up to date ($NEW_HEAD)."
else
    echo "    $PREV_HEAD..$NEW_HEAD"
    echo ""
    echo "==> Changes since last update:"
    git log --oneline "$PREV_HEAD..$NEW_HEAD"
fi

echo ""
echo "==> Re-running bin/install.sh (idempotent — refreshes deps and registrations)"
bash bin/install.sh "$@"

cat <<EOF

✅ Updated.

Claude Code:    start a NEW terminal/claude session to pick up new tools.
Claude Desktop: already restarted (if it was running).

Run this anytime to update:  bash bin/update.sh
EOF
