# Workday Community MCP — instructions for Claude

This repo is an MCP server that exposes Workday Resource Center / Community search to Claude
through the Coveo API. When a teammate opens this repo and asks you to set it up, follow the
flow below.

## First-time setup

Run these in order. Stop and ask the user before any step that requires their input or a
multi-minute download.

1. **Install the MCP itself** (always required):
   ```bash
   bash bin/install.sh
   ```
   This creates `.venv`, installs the package, and registers the `community` MCP with
   Claude Code at user scope. It does NOT capture an auth token.

2. **Ask the user**: do they want auto-refresh (Playwright)?
   - **Yes** (recommended): adds Playwright + downloads ~250MB of Chromium. Tokens then
     refresh automatically with no manual cookie capture.
   - **No**: stick with the manual `bin/refresh-token.sh` flow (Copy-as-cURL from DevTools).
   - **Lyft users**: warn them that Playwright may need security review at their org. Both
     paths are supported; the user can decide.

   If yes, run:
   ```bash
   uv pip install -e '.[auto-refresh]' --project "$(pwd)"
   ./.venv/bin/playwright install chromium
   ```

3. **Capture the user's auth token** (always required):
   - With auto-refresh installed:
     ```bash
     bash bin/refresh-token.sh --auto
     ```
     A real Chromium window opens. Tell the user: "Log in to Workday Community in the
     browser window that opened — it will close automatically when login completes." MFA
     is handled naturally because the user drives a real browser.
   - Without auto-refresh: walk them through `pbpaste > .captured-curl.sh` then
     `bash bin/refresh-token.sh`. The README has the manual steps in detail.

4. **Confirm it works**: run a smoke search to prove the auth token is valid:
   ```bash
   .venv/bin/python -c "import os; from dotenv import load_dotenv; load_dotenv('.env'); from community_mcp.coveo_client import CoveoClient; c = CoveoClient(token=os.environ['COVEO_SEARCH_TOKEN'], org_id=os.environ['COVEO_ORG_ID']); [print(h.title) for h in c.search('release notes', count=3)]"
   ```

5. **Tell the user to start a NEW Claude Code session.** The MCP is registered at user scope
   but the current session won't pick it up — only fresh sessions will see the
   `mcp__community__*` tools.

## Refreshing the token (every ~2h)

When tools return `AUTH ERROR: Coveo returned 401`, run:

```bash
bash bin/refresh-token.sh --auto
```

- Within ~12h of the last login: silent, ~1 second, no UI.
- After ~12h: a Chromium window opens; user logs in again.

Do NOT ask the user to manually copy cookies from DevTools unless they explicitly opted out
of Playwright.

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
