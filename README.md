# community-mcp

MCP server that exposes Workday Community / Resource Center documentation to Claude through
Workday's Coveo-backed search index.

## How it works

Workday Community runs on AEM behind Workday CIAM (Okta), but search and content delivery are
powered by **Coveo**. Logging into the browser sets a `coveo-info` cookie containing a short-lived
JWT (`searchToken`) authorized for the Coveo Search REST API. This MCP wraps that API directly —
no AEM scraping, no SAML dance.

Trade-off: tokens expire ~2 hours after capture. v2 will add Playwright auto-refresh.

## Quickstart (let Claude Code do the setup)

```bash
git clone git@github.com:krishnagutta/workday-community-mcp.git
cd workday-community-mcp
claude
```

Then in Claude Code, just say:

> Read CLAUDE.md and set this up for me.

Claude reads `CLAUDE.md`, runs the install, asks if you want Playwright auto-refresh,
captures your Workday Community auth token (a real browser window opens; you log in
normally), and verifies the MCP works. Total time: 2-3 minutes including login.

**After setup, start a new Claude Code session** — the MCP tools (`mcp__community__*`) are
registered at user scope and available globally.

### Manual setup (if you don't want to use Claude Code)

```bash
bash bin/install.sh

# Optional: enable Playwright auto-refresh (recommended)
uv pip install -e '.[auto-refresh]'
./.venv/bin/playwright install chromium

# Capture your Coveo token (opens a browser for login)
bash bin/refresh-token.sh --auto
```

Each teammate captures their own Coveo token — tokens are per-user and carry your individual
Workday Community access scope. **Do not share tokens, `.env`, or `.playwright-state.json`.**

## Refreshing the token

Tokens last ~2 hours. Two ways to refresh — pick one.

### Option A — Auto (recommended): Playwright browser drive

Opt-in once:

```bash
uv pip install -e '.[auto-refresh]'
playwright install chromium
```

Then:

```bash
./bin/refresh-token.sh --auto
```

- **First run** (or after ~12h): a real Chromium window opens; complete login + MFA normally; window closes.
- **Subsequent runs** (within ~12h): headless, silent, ~1 second.

Storage state is persisted to `.playwright-state.json` (gitignored). When it ages out, the next run automatically falls back to headed login.

### Option B — Manual: copy-as-cURL

1. Open Chrome **incognito** at <https://community.workday.com> and log in.
2. DevTools → Network → reload `resourcecenter.workday.com/en-us/wrc/home.html`.
3. Right-click the `home.html` request → Copy → **Copy as cURL (bash)**.
4. From this directory:

   ```bash
   pbpaste > .captured-curl.sh
   ./bin/refresh-token.sh
   ```

## Run

```bash
uv run python -m community_mcp.server
```

## Wire into Claude Code

Add to `~/.claude/settings.json` (or a project `.mcp.json`):

```json
{
  "mcpServers": {
    "community": {
      "command": "uv",
      "args": [
        "run",
        "--directory",
        "/Users/krishnagutta/Documents/community-mcp",
        "python",
        "-m",
        "community_mcp.server"
      ]
    }
  }
}
```

## Tools

| Tool | Purpose |
|---|---|
| `search_community(query, count)` | Coveo search → numbered list of `{title, URL, uniqueId, excerpt}` |
| `get_article(unique_id)` | Fetches Coveo's cached HTML for one article, returns markdown |
| `search_and_read(query, top_n)` | Search + fetch top N bodies in one call (one-shot Q&A) |

## Files

```
community-mcp/
├── community_mcp/
│   ├── coveo_client.py       # Coveo REST API wrapper
│   └── server.py             # FastMCP tool registrations
├── bin/refresh-token.sh      # Extract Coveo token from captured curl
├── env.example               # Template for .env
├── pyproject.toml
└── .gitignore                # Excludes .env, .captured-curl.sh
```
