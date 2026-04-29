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

Tokens last ~2 hours, but Playwright handles refresh automatically. After your first
login, subsequent refreshes are silent and headless (~1 second). When your saved session
ages out (~12h), the browser opens once for re-login.

## Quickstart — one-line install

```bash
curl -fsSL https://raw.githubusercontent.com/krishnagutta/workday-community-mcp/main/bin/quickstart.sh | bash
```

This clones the repo into `~/community-mcp`, installs everything (including Playwright
+ Chromium for auto-refresh), captures your Workday Community auth token by opening a
browser for login, and registers the MCP with **both Claude Code and Claude Desktop**
(if Claude Desktop is installed). Total time: 2-3 minutes.

After install:
- **Claude Code**: start a new session — tools auto-load.
- **Claude Desktop**: the installer briefly quits and relaunches Desktop so the new
  config is picked up. Your conversations and window state are preserved.

If your org doesn't allow Playwright, pass `--no-playwright`. To skip Claude Desktop
registration (e.g., you don't use it), pass `--no-desktop`:

```bash
curl -fsSL https://raw.githubusercontent.com/krishnagutta/workday-community-mcp/main/bin/quickstart.sh | bash -s -- --no-playwright --no-desktop
```

## Quickstart — let Claude Code drive the setup

If you prefer Claude Code to walk you through it:

```bash
git clone https://github.com/krishnagutta/workday-community-mcp.git
cd workday-community-mcp
claude
```

Then in Claude Code, say:

> Read CLAUDE.md and set this up for me.

Claude reads `CLAUDE.md`, runs the install, captures your Workday Community auth token
(a real browser window opens; you log in normally), and verifies the MCP works.

## Manual setup (no installer scripts)

```bash
bash bin/install.sh           # venv, deps, Playwright + Chromium, MCP registration
bash bin/refresh-token.sh     # opens a browser for first-time login
```

Each user captures their own Coveo token — tokens are per-user and carry your individual
Workday Community access scope. **Do not share tokens, `.env`, or `.playwright-state.json`.**

## Refreshing the token

Tokens auto-refresh in the background — you almost never need to think about this. The MCP
catches `401` errors and silently runs a headless Playwright refresh in ~1 second. You'll
only see `AUTH ERROR` if your saved session has aged out beyond ~12h, in which case:

```bash
bash bin/refresh-token.sh
```

A browser window opens, you log in once, you're good for another ~12 hours.

### Manual fallback (no Playwright)

If you installed with `--no-playwright`:

1. Open Chrome **incognito** at <https://community.workday.com> and log in.
2. DevTools → Network → reload `resourcecenter.workday.com/en-us/wrc/home.html`.
3. Right-click the `home.html` request → Copy → **Copy as cURL (bash)**.
4. From this directory:

   ```bash
   pbpaste > .captured-curl.sh
   bash bin/refresh-token.sh --manual
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

## Where this MCP lives

This installs as a **local MCP server** running on your laptop. After install you'll see
it in `claude mcp list` (Claude Code) and in the developer settings of Claude Desktop.

It is **not** in Anthropic's public `/connectors` registry. If a teammate asks "why isn't
there a connector card for it?" — that's why. Installation is via this repo.

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
Playwright storage state has aged out (≥12h). At that point run `bash bin/refresh-token.sh`.

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
