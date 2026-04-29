# community-mcp

MCP server that exposes Workday Community / Resource Center documentation to Claude through
Workday's Coveo-backed search index.

## How it works

Workday Community runs on AEM behind Workday CIAM (Okta), but search and content delivery are
powered by **Coveo**. Logging into the browser sets a `coveo-info` cookie containing a short-lived
JWT (`searchToken`) authorized for the Coveo Search REST API. This MCP wraps that API directly —
no AEM scraping, no SAML dance.

Trade-off: tokens expire ~2 hours after capture. v2 will add Playwright auto-refresh.

## Setup

```bash
git clone git@github.com:krishnagutta/workday-community-mcp.git
cd workday-community-mcp
bash bin/install.sh
```

`install.sh` creates the venv, installs deps, and registers the MCP server with Claude Code at user scope.
Each teammate captures their own Coveo token (see below) — tokens are per-user and carry your individual
Workday Community access scope. **Do not share tokens.**

## Capture the token (every ~2h until v2 lands)

1. Open Chrome **incognito** at <https://community.workday.com> and log in.
2. DevTools → Network → reload `resourcecenter.workday.com/en-us/wrc/home.html`.
3. Right-click the `home.html` request → Copy → **Copy as cURL (bash)**.
4. From this directory:

   ```bash
   pbpaste > .captured-curl.sh
   ./bin/refresh-token.sh
   ```

   The script extracts the Coveo `searchToken` JWT, writes `.env`, and prints token expiry.

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
