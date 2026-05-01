"""FastMCP server exposing Workday Community search and article retrieval."""

from __future__ import annotations

import datetime
import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

from community_mcp.coveo_client import (
    SOURCE_KNOWLEDGE_ARTICLES,
    SOURCE_OFFICIAL_DOCS,
    SOURCE_RELEASE_NOTES,
    CoveoAuthError,
    CoveoClient,
    SearchHit,
    SearchResult,
)

ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(ENV_FILE)

logger = logging.getLogger(__name__)

DEFAULT_SEARCH_COUNT = 10
DEFAULT_READ_TOP_N = 3
RETRY_REFRESH_HINT = "Run: bash bin/refresh-token.sh to manually re-authenticate."

mcp = FastMCP("workday-community")


def _client() -> CoveoClient:
    token = os.environ.get("COVEO_SEARCH_TOKEN", "")
    org_id = os.environ.get("COVEO_ORG_ID", "workdayproductionurv9exm0")
    search_hub = os.environ.get("COVEO_SEARCH_HUB", "IPE_AEM")
    return CoveoClient(token=token, org_id=org_id, search_hub=search_hub)


def _try_refresh() -> bool:
    """Refresh the Coveo token. Tries headless first; opens a browser if MFA is needed.

    The tool call blocks while the user completes login — the browser window
    closes automatically once login is done, and the tool retries with a fresh token.
    """
    try:
        from community_mcp.auth import AuthRefreshError, refresh
    except ImportError:
        return False
    try:
        refresh()
    except (AuthRefreshError, Exception) as exc:
        logger.warning("refresh failed: %s", exc)
        return False
    load_dotenv(ENV_FILE, override=True)
    return True


def _with_auto_refresh(call):
    """Run `call`; on CoveoAuthError, refresh (headless or browser) and retry once."""
    try:
        return call()
    except CoveoAuthError as first_exc:
        if not _try_refresh():
            raise first_exc
        return call()


def _format_date(date_ms: int | None) -> str:
    if not date_ms:
        return ""
    try:
        return datetime.datetime.fromtimestamp(date_ms / 1000).strftime("%Y-%m-%d")
    except (OverflowError, OSError, ValueError):
        return ""


def _format_hit(index: int, hit: SearchHit) -> str:
    metadata_bits = []
    if hit.content_type:
        metadata_bits.append(hit.content_type)
    if hit.product_lines:
        metadata_bits.append(" / ".join(hit.product_lines))
    if hit.source:
        metadata_bits.append(f"source: {hit.source}")
    date_str = _format_date(hit.date_ms)
    if date_str:
        metadata_bits.append(date_str)
    metadata = "  •  ".join(metadata_bits) if metadata_bits else ""
    lines = [f"{index}. {hit.title}"]
    if metadata:
        lines.append(f"   {metadata}")
    lines.append(f"   URL: {hit.url}")
    lines.append(f"   ID:  {hit.unique_id}")
    if hit.excerpt:
        lines.append(f"   {hit.excerpt}")
    return "\n".join(lines)


def _format_results(query: str, result: SearchResult) -> str:
    if not result.hits:
        suffix = f" ({result.total_count:,} total)" if result.total_count else ""
        return f"No results for '{query}'{suffix}."
    end = result.offset + len(result.hits)
    header = (
        f"Showing {result.offset + 1}-{end} of {result.total_count:,} results "
        f"for '{query}'"
    )
    if result.next_offset is not None:
        header += f" — call again with offset={result.next_offset} for more"
    body = "\n\n".join(_format_hit(i, h) for i, h in enumerate(result.hits, result.offset + 1))
    return f"{header}\n\n{body}"


def _auth_error_message(exc: CoveoAuthError) -> str:
    return f"AUTH ERROR: {exc}\n\n{RETRY_REFRESH_HINT}"


@mcp.tool()
def search_community(
    query: str,
    count: int = DEFAULT_SEARCH_COUNT,
    offset: int = 0,
    only_official_docs: bool = False,
    product_line: str | None = None,
) -> str:
    """Search Workday Resource Center / Community docs (Coveo-backed). Returns a header
    line ("Showing X-Y of Z results") plus a numbered list with title, content type,
    product line, source, date, URL, Coveo uniqueId, and a ~400-char excerpt that often
    answers the question without needing get_article.

    For more results past the first page, call again with offset=<previous_end>.
    The header tells you when to stop.

    Set only_official_docs=True to drop community forum posts and Salesforce KB articles —
    keeps only the official Workday admin guide. Use this for "how does X work" or
    "configure Y" questions.

    product_line filters by Workday's top-level product line. Common values:
    "Human Capital Management", "Financial Management", "Payroll", "Talent Management",
    "Platform and Product Extensions", "Analytics and Reporting", "Adaptive Planning",
    "Workforce Management". Pass exactly one (or None for no filter)."""
    sources = [SOURCE_OFFICIAL_DOCS] if only_official_docs else None
    product_lines = [product_line] if product_line else None
    try:
        result = _with_auto_refresh(
            lambda: _client().search(
                query, count=count, offset=offset,
                sources=sources, product_lines=product_lines,
            )
        )
    except CoveoAuthError as exc:
        return _auth_error_message(exc)
    return _format_results(query, result)


@mcp.tool()
def get_article(unique_id: str) -> str:
    """Fetch the full body of a Workday Community article as markdown. Pass the `uniqueId`
    returned by search_community / search_release_notes / search_knowledge_base. Bodies
    come from Coveo's cached HTML index so they don't require a Workday SSO round-trip."""
    try:
        return _with_auto_refresh(lambda: _client().get_article_markdown(unique_id))
    except CoveoAuthError as exc:
        return _auth_error_message(exc)


@mcp.tool()
def search_release_notes(
    query: str,
    count: int = DEFAULT_SEARCH_COUNT,
    offset: int = 0,
    product_line: str | None = None,
) -> str:
    """Search ONLY official Workday release notes (e.g. 2025R2, service packs).
    Use for "what's new in...", "release note for ...", "is this a new feature" questions.
    Paginate by passing offset=<previous_end>."""
    product_lines = [product_line] if product_line else None
    try:
        result = _with_auto_refresh(
            lambda: _client().search(
                query, count=count, offset=offset,
                sources=[SOURCE_RELEASE_NOTES],
                product_lines=product_lines,
            )
        )
    except CoveoAuthError as exc:
        return _auth_error_message(exc)
    return _format_results(query, result)


@mcp.tool()
def search_knowledge_base(
    query: str,
    count: int = DEFAULT_SEARCH_COUNT,
    offset: int = 0,
) -> str:
    """Search Salesforce Knowledge Articles — Workday's troubleshooting / support KB.
    Use when the user reports an error, hit an issue, or needs a fix recipe.
    Returns articles like "Error X — Cause and Resolution".
    Paginate by passing offset=<previous_end>."""
    try:
        result = _with_auto_refresh(
            lambda: _client().search(
                query, count=count, offset=offset, sources=[SOURCE_KNOWLEDGE_ARTICLES]
            )
        )
    except CoveoAuthError as exc:
        return _auth_error_message(exc)
    return _format_results(query, result)


@mcp.tool()
def search_and_read(query: str, top_n: int = DEFAULT_READ_TOP_N) -> str:
    """Search and fetch full bodies of the top N hits in one call. Best for one-shot
    Q&A where you immediately need to reason over article contents.

    By default this restricts to official Workday docs (no forum posts) — set top_n
    higher if the question needs broader context."""
    try:
        client = _client()
        result = _with_auto_refresh(
            lambda: client.search(query, count=top_n, sources=[SOURCE_OFFICIAL_DOCS])
        )
    except CoveoAuthError as exc:
        return _auth_error_message(exc)
    if not result.hits:
        return f"No results for '{query}'."
    sections = []
    for hit in result.hits:
        sections.append(f"# {hit.title}\n\nSource: {hit.url}\n")
        if not hit.has_html:
            sections.append("_(No cached body available.)_\n")
            continue
        try:
            body = _with_auto_refresh(lambda: client.get_article_markdown(hit.unique_id))
            sections.append(body)
        except CoveoAuthError as exc:
            return _auth_error_message(exc)
        except Exception as exc:
            logger.exception(
                "failed to fetch article body", extra={"unique_id": hit.unique_id}
            )
            sections.append(f"_(Failed to fetch body: {exc})_")
        sections.append("\n---\n")
    return "\n".join(sections)


if __name__ == "__main__":
    mcp.run()
