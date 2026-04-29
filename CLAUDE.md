# Workday Community MCP — instructions for Claude

This repo is an MCP server that exposes Workday Resource Center / Community search to Claude
through the Coveo API. When a teammate opens this repo and asks you to set it up, follow the
flow below.

## First-time setup

Default flow includes Playwright + auto-refresh — only mention `--no-playwright` if the
user has an explicit org-policy concern. Run these in order:

1. **Install** (creates venv, installs deps + Playwright + Chromium, registers MCP):
   ```bash
   bash bin/install.sh
   ```
   If the user explicitly says they can't have Playwright on their machine:
   ```bash
   bash bin/install.sh --no-playwright
   ```

2. **Capture the user's auth token**:
   ```bash
   bash bin/refresh-token.sh
   ```
   A real Chromium window opens. Tell the user: "Log in to Workday Community in the
   browser window — it closes automatically once login completes." MFA is handled
   naturally because the user drives a real browser.

   For `--no-playwright` users only: walk them through `pbpaste > .captured-curl.sh`
   then `bash bin/refresh-token.sh --manual`. The README has the manual steps.

3. **Confirm it works** — quick smoke search:
   ```bash
   .venv/bin/python -c "import os; from dotenv import load_dotenv; load_dotenv('.env'); from community_mcp.coveo_client import CoveoClient; c = CoveoClient(token=os.environ['COVEO_SEARCH_TOKEN'], org_id=os.environ['COVEO_ORG_ID']); [print(h.title) for h in c.search('release notes', count=3).hits]"
   ```

4. **Tell the user to start a NEW Claude Code session.** The MCP is registered at user
   scope but the current session won't pick it up — only fresh sessions will see the
   `mcp__community__*` tools.

## Refreshing the token

The MCP **auto-refreshes** the token transparently when it hits a 401, as long as the user's
saved storage state is < ~12h old. Normally you don't need to do anything — just retry the
failed tool call once.

**You only need to run a manual refresh** if auto-refresh fails (storage state expired
beyond 12h):

```bash
bash bin/refresh-token.sh
```

- Within ~12h of the last login: silent, ~1 second, no UI.
- After ~12h: a Chromium window opens; user logs in again.

Do NOT ask the user to manually copy cookies from DevTools unless they're on the
`--no-playwright` install path (`bash bin/refresh-token.sh --manual`).

## Tool selection guide

Pick the right tool for the question:

| User asks about | Use |
|---|---|
| Configuration / "how does X work" / "set up Y" | `search_community(..., only_official_docs=True)` or `search_and_read` |
| Specific product (Payroll, HCM, etc.) | `search_community(..., product_line="Payroll")` |
| New feature / "what's new in 2025R2" / release notes | `search_release_notes` |
| Error / failure / troubleshooting | `search_knowledge_base` (Salesforce KB has cause/resolution) |
| Reading a specific article you already found | `get_article(unique_id)` |
| One-shot Q&A — search + read top hits in one call | `search_and_read` |

Defaults are good — start without filters and only narrow if results are noisy.

## Architecture you need to know

- **Coveo searchToken JWT** lives in the `coveo-info` cookie set by the page after login.
  Lifetime ~2h. Org: `workdayproductionurv9exm0`, searchHub: `IPE_AEM`.
- **Playwright storage state** at `.playwright-state.json` (gitignored). It MUST be saved
  AFTER the `coveo-info` cookie appears, not on URL match — `/wrc/home.html` flashes through
  the redirect chain BEFORE login completes, and saving on URL-match alone produces a
  state with only 3 cookies (Cloudflare + LB + SAML state), useless for headless reuse.
- **Cloudflare bot challenge**: blocks headless without a valid `cf_clearance` cookie. The
  state-file approach captures a valid clearance from the headed login.
- **Per-user auth**: each user's `searchToken` carries their individual Workday access scope.
  `.env` and `.playwright-state.json` are gitignored. Never log token contents.

## What NOT to do

- Don't commit `.env`, `.captured-curl.sh`, or `.playwright-state.json` (already gitignored,
  but double-check before any `git add -A`).
- Don't print token values in tool output. Show "expires in N min" instead.
- Don't hard-code the user's email/credentials anywhere.
- Don't try to deploy this as a centralized service. Coveo auth is per-user; centralization
  doesn't work without per-user OAuth (out of scope for v1/v2).
