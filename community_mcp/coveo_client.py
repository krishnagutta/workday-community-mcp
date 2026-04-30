"""Thin Coveo Search REST API client used by the Workday Community MCP."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import httpx
from markdownify import markdownify

DEFAULT_TIMEOUT_SECONDS = 20.0
SEARCH_PATH = "/rest/search/v2"
HTML_PATH = "/rest/search/v2/html"

MAX_RESULTS = 50
DEFAULT_EXCERPT_LENGTH = 400

# Coveo `source` field buckets — useful for filtering noise (forum) from official docs.
SOURCE_OFFICIAL_DOCS = "iLX-AEM-Admin-Guide"
SOURCE_RELEASE_NOTES = "iLX-AEM-Release-Notes"
SOURCE_KNOWLEDGE_ARTICLES = "Salesforce Knowledge Expansion"
SOURCE_FORUM_KHOROS = "Community Khoros"
SOURCE_FORUM_DRUPAL = "Community Drupal"

FIELDS_TO_INCLUDE = [
    "commoncontenttype",
    "commonproductline",
    "commonproduct",
    "source",
    "date",
]


class CoveoAuthError(RuntimeError):
    """Raised when the Coveo search token is missing, expired, or rejected."""


@dataclass(frozen=True)
class SearchHit:
    title: str
    url: str
    excerpt: str
    unique_id: str
    has_html: bool
    content_type: str | None = None
    product_lines: tuple[str, ...] = field(default_factory=tuple)
    products: tuple[str, ...] = field(default_factory=tuple)
    source: str | None = None
    date_ms: int | None = None


@dataclass(frozen=True)
class SearchResult:
    hits: list[SearchHit]
    total_count: int
    offset: int

    @property
    def next_offset(self) -> int | None:
        end = self.offset + len(self.hits)
        return end if end < self.total_count else None


class CoveoClient:
    def __init__(
        self,
        token: str,
        org_id: str,
        search_hub: str = "IPE_AEM",
        timeout: float = DEFAULT_TIMEOUT_SECONDS,
    ) -> None:
        if not token:
            raise CoveoAuthError("COVEO_SEARCH_TOKEN is empty — run ./bin/refresh-token.sh")
        self._token = token
        self._org_id = org_id
        self._search_hub = search_hub
        self._base = f"https://{org_id}.org.coveo.com"
        self._http = httpx.Client(timeout=timeout)

    def search(
        self,
        query: str,
        count: int = 10,
        offset: int = 0,
        *,
        sources: list[str] | None = None,
        content_types: list[str] | None = None,
        product_lines: list[str] | None = None,
        excerpt_length: int = DEFAULT_EXCERPT_LENGTH,
    ) -> SearchResult:
        payload: dict[str, Any] = {
            "q": query,
            "numberOfResults": max(1, min(count, MAX_RESULTS)),
            "firstResult": max(0, offset),
            "excerptLength": excerpt_length,
            "searchHub": self._search_hub,
            "fieldsToInclude": FIELDS_TO_INCLUDE,
        }
        aq = _build_advanced_query(sources, content_types, product_lines)
        if aq:
            payload["aq"] = aq
        response = self._post_json(SEARCH_PATH, payload)
        return SearchResult(
            hits=[_to_hit(result) for result in response.get("results", [])],
            total_count=int(response.get("totalCount", 0)),
            offset=offset,
        )

    def get_html(self, unique_id: str) -> str:
        if not unique_id:
            raise ValueError("unique_id is required")
        response = self._http.post(
            f"{self._base}{HTML_PATH}",
            params={"organizationId": self._org_id},
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            data={"uniqueId": unique_id},
        )
        _raise_for_auth(response)
        response.raise_for_status()
        return response.text

    def get_article_markdown(self, unique_id: str) -> str:
        return markdownify(self.get_html(unique_id), heading_style="ATX").strip()

    def close(self) -> None:
        self._http.close()

    def _post_json(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        response = self._http.post(
            f"{self._base}{path}",
            params={"organizationId": self._org_id},
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
        _raise_for_auth(response)
        response.raise_for_status()
        return response.json()


def _build_advanced_query(
    sources: list[str] | None,
    content_types: list[str] | None,
    product_lines: list[str] | None,
) -> str:
    clauses = []
    if sources:
        clauses.append(_or_clause("@source", sources))
    if content_types:
        clauses.append(_or_clause("@commoncontenttype", content_types))
    if product_lines:
        clauses.append(_or_clause("@commonproductline", product_lines))
    return " AND ".join(clauses)


def _or_clause(field_name: str, values: list[str]) -> str:
    parts = [f'{field_name}=="{v}"' for v in values]
    return f"({' OR '.join(parts)})"


def _to_hit(result: dict[str, Any]) -> SearchHit:
    raw = result.get("raw", {}) or {}
    return SearchHit(
        title=result.get("title", "") or "",
        url=result.get("clickUri", "") or "",
        excerpt=result.get("excerpt", "") or "",
        unique_id=result.get("uniqueId", "") or "",
        has_html=bool(result.get("hasHtmlVersion", False)),
        content_type=raw.get("commoncontenttype"),
        product_lines=tuple(_as_list(raw.get("commonproductline"))),
        products=tuple(_as_list(raw.get("commonproduct"))),
        source=raw.get("source"),
        date_ms=raw.get("date") if isinstance(raw.get("date"), int) else None,
    )


def _as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


def _raise_for_auth(response: httpx.Response) -> None:
    if response.status_code in (401, 403, 419):
        raise CoveoAuthError(
            f"Coveo returned {response.status_code}. The search token has likely expired. "
            "Re-capture from your browser and run ./bin/refresh-token.sh."
        )
