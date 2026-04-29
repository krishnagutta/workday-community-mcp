"""FastMCP server exposing Workday Community search and article retrieval."""

from __future__ import annotations

import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from mcp.server.fastmcp import FastMCP

from community_mcp.coveo_client import CoveoAuthError, CoveoClient, SearchHit

ENV_FILE = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(ENV_FILE)

logger = logging.getLogger(__name__)

DEFAULT_SEARCH_COUNT = 10
DEFAULT_READ_TOP_N = 3
EXCERPT_PREVIEW_CHARS = 220

mcp = FastMCP("workday-community")


def _client() -> CoveoClient:
    token = os.environ.get("COVEO_SEARCH_TOKEN", "")
    org_id = os.environ.get("COVEO_ORG_ID", "workdayproductionurv9exm0")
    search_hub = os.environ.get("COVEO_SEARCH_HUB", "IPE_AEM")
    return CoveoClient(token=token, org_id=org_id, search_hub=search_hub)


def _format_hit(index: int, hit: SearchHit) -> str:
    excerpt = hit.excerpt[:EXCERPT_PREVIEW_CHARS]
    if len(hit.excerpt) > EXCERPT_PREVIEW_CHARS:
        excerpt += "…"
    return (
        f"{index}. {hit.title}\n"
        f"   URL: {hit.url}\n"
        f"   ID:  {hit.unique_id}\n"
        f"   {excerpt}"
    )


@mcp.tool()
def search_community(query: str, count: int = DEFAULT_SEARCH_COUNT) -> str:
    """Search Workday Resource Center / Community docs (Coveo-backed). Returns a numbered list
    of hits with title, URL, the Coveo uniqueId (pass to get_article), and a short excerpt.
    Use for questions like: how does payroll integration work, where are integration system
    user docs, what's the latest release note for HCM."""
    try:
        hits = _client().search(query, count=count)
    except CoveoAuthError as exc:
        return f"AUTH ERROR: {exc}"
    if not hits:
        return f"No results for '{query}'."
    body = "\n\n".join(_format_hit(i, h) for i, h in enumerate(hits, 1))
    return f"Found {len(hits)} results for '{query}':\n\n{body}"


@mcp.tool()
def get_article(unique_id: str) -> str:
    """Fetch the full body of a Workday Community article as markdown. Pass the `uniqueId`
    returned by search_community. Bodies come from Coveo's cached HTML index."""
    try:
        return _client().get_article_markdown(unique_id)
    except CoveoAuthError as exc:
        return f"AUTH ERROR: {exc}"


@mcp.tool()
def search_and_read(query: str, top_n: int = DEFAULT_READ_TOP_N) -> str:
    """Search and fetch full bodies of the top N hits in one call. Convenient when you want
    Claude to immediately reason over article contents rather than orchestrating two tool calls."""
    try:
        client = _client()
        hits = client.search(query, count=top_n)
    except CoveoAuthError as exc:
        return f"AUTH ERROR: {exc}"
    if not hits:
        return f"No results for '{query}'."
    sections = []
    for hit in hits:
        sections.append(f"# {hit.title}\n\nSource: {hit.url}\n")
        if not hit.has_html:
            sections.append("_(No cached body available.)_\n")
            continue
        try:
            body = client.get_article_markdown(hit.unique_id)
            sections.append(body)
        except CoveoAuthError as exc:
            return f"AUTH ERROR: {exc}"
        except Exception as exc:
            logger.exception("Failed to fetch article body", extra={"unique_id": hit.unique_id})
            sections.append(f"_(Failed to fetch body: {exc})_")
        sections.append("\n---\n")
    return "\n".join(sections)


if __name__ == "__main__":
    mcp.run()
