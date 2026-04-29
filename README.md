# community-mcp

MCP server that exposes Workday Community / Resource Center documentation to Claude through
Workday's Coveo-backed search index.

> **Disclaimer**: Unofficial — not affiliated with, endorsed by, or supported by Workday, Inc.
> This MCP uses each user's own authenticated browser session and only accesses content the
> user's Workday Community account is already authorized to read. Use at your own risk; respect
> Workday's terms of service.

## How it works

Workday Community runs on AEM behind Workday CIAM (Okta), but search and content delivery are
powered by **Coveo**. Logging into the browser sets a `coveo-info` cookie containing a short-lived
JWT (`searchToken`) authorized for the Coveo Search REST API. This MCP wraps that API directly —
no AEM scraping, no SAML dance.

Trade-off: tokens expire ~2 hours after capture. v2 will add Playwright auto-refresh.

## Quickstart — one-line install

For users who just want it working:

```bash
curl -fsSL https://raw.githubusercontent.com/krishnagutta/workday-community-mcp/main/bin/quickstart.sh | bash
```

This clones the repo into `~/community-mcp`, installs deps, optionally sets up Playwright
auto-refresh, captures your Workday Community auth token, and registers the MCP with Claude
Code. Total time: 2-3 minutes including login.

After install, **start a new Claude Code session** — the MCP tools (`mcp__community__*`)
are registered at user scope and available globally.

## Quickstart — let Claude Code drive the setup

If you prefer Claude Code to walk you through it:

```bash
git clone https://github.com/krishnagutta/workday-community-mcp.git
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
        "<absolute-path-to-this-repo>",
        "python",
        "-m",
        "community_mcp.server"
      ]
    }
  }
}
```

(`bin/install.sh` and the quickstart installer do this automatically using
`claude mcp add` — you only need to edit the JSON manually if you're not using Claude Code.)

## Tools

| Tool | Purpose |
|---|---|
| `search_community(query, count, only_official_docs?, product_line?)` | General search with optional filters by source bucket and product line |
| `search_release_notes(query, count, product_line?)` | Search only Workday release notes |
| `search_knowledge_base(query, count)` | Search Salesforce KB articles (troubleshooting / errors) |
| `get_article(unique_id)` | Returns the full body of one article as markdown |
| `search_and_read(query, top_n)` | Search official docs + fetch top N bodies in one call |

Each result includes content type, product line, source bucket, and date.

The MCP **auto-refreshes its auth token on 401** — you'll only see auth errors if your
Playwright storage state has aged out (≥12h). At that point run `bash bin/refresh-token.sh --auto`.

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
