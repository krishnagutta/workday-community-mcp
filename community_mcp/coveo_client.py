"""Thin Coveo Search REST API client used by the Workday Community MCP."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import httpx
from markdownify import markdownify

DEFAULT_TIMEOUT_SECONDS = 20.0
SEARCH_PATH = "/rest/search/v2"
HTML_PATH = "/rest/search/v2/html"


class CoveoAuthError(RuntimeError):
    """Raised when the Coveo search token is missing, expired, or rejected."""


@dataclass(frozen=True)
class SearchHit:
    title: str
    url: str
    excerpt: str
    unique_id: str
    has_html: bool


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

    def search(self, query: str, count: int = 10) -> list[SearchHit]:
        payload = {
            "q": query,
            "numberOfResults": max(1, min(count, 50)),
            "searchHub": self._search_hub,
        }
        response = self._post_json(SEARCH_PATH, payload)
        return [_to_hit(result) for result in response.get("results", [])]

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


def _to_hit(result: dict[str, Any]) -> SearchHit:
    return SearchHit(
        title=result.get("title", "") or "",
        url=result.get("clickUri", "") or "",
        excerpt=result.get("excerpt", "") or "",
        unique_id=result.get("uniqueId", "") or "",
        has_html=bool(result.get("hasHtmlVersion", False)),
    )


def _raise_for_auth(response: httpx.Response) -> None:
    if response.status_code in (401, 403):
        raise CoveoAuthError(
            f"Coveo returned {response.status_code}. The search token has likely expired. "
            "Re-capture from your browser and run ./bin/refresh-token.sh."
        )
