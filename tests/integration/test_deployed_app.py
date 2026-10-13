"""Black-box integration tests against a DEPLOYED instance of the app.

This is the Spar C gate that stands between dev and prod: if these fail,
deploy-prod in the Spar C pipeline (course-material/templates/spar-c/
deploy.yml) never runs and the approval prompt never appears.

These are NOT a second copy of backend/tests/. Those exercise the FastAPI app
in-process, with no container, no nginx, no network. That makes them fast and
precise, and it also makes them completely blind to the failures that
actually happen at deploy time:

  * the image was never pulled, so the VM is still running last week's code
  * nginx's /api/ proxy_pass points at the wrong host or port
  * the frontend container is up but the backend behind it is not
  * the security group closes the port the app is published on

Every one of those leaves backend/tests/ green. All of them are caught here,
because these tests go over the wire to the same URL a browser would use.

Run against the deployed app:

    BASE_URL=http://<floating-ip>:8080 pytest tests/integration -v

Run against your own machine (start it first with `docker compose up -d`):

    BASE_URL=http://localhost:8080 pytest tests/integration -v
"""
from __future__ import annotations

import os
import uuid

import httpx
import pytest

# No default. An integration test that silently falls back to localhost is
# worse than one that fails to start: in CI it would pass against nothing at
# all and report a green gate for a deploy that never happened.
BASE_URL = os.environ.get("BASE_URL")

# Generous but finite. The app is two small containers behind nginx; if a
# request takes more than 10s something is wrong, and hanging forever would
# just turn a failed deploy into a job that runs until the runner times out.
TIMEOUT = 10.0


@pytest.fixture(scope="module")
def client() -> httpx.Client:
    if not BASE_URL:
        pytest.fail(
            "BASE_URL is not set. These tests must run against a deployed app, "
            "e.g. BASE_URL=http://<floating-ip>:8080"
        )
    with httpx.Client(base_url=BASE_URL, timeout=TIMEOUT) as c:
        yield c


def test_frontend_is_served(client: httpx.Client) -> None:
    """The nginx container serves the page itself, not just the API.

    Hitting / (rather than /api/...) is what proves the frontend half of the
    stack came up at all.
    """
    response = client.get("/")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]


def test_health_endpoint(client: httpx.Client) -> None:
    """/api/health through nginx proves the proxy reaches the backend.

    This is the single most valuable assertion in the file: it fails whenever
    the frontend is up but the backend is not, which is the most common
    partial-deploy state.
    """
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_list_items_returns_a_list(client: httpx.Client) -> None:
    response = client.get("/api/items")
    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_create_read_delete_roundtrip(client: httpx.Client) -> None:
    """Full write path, then clean up after itself.

    The unique marker matters: this runs against a shared, long-lived
    environment where other runs (and humans clicking around) leave data
    behind. Asserting on the exact contents of /api/items would make this
    test fail for reasons that have nothing to do with the deploy — so it
    asserts only that ITS OWN item appears and then disappears.
    """
    marker = f"integration-test-{uuid.uuid4()}"

    created = client.post("/api/items", json={"text": marker})
    assert created.status_code == 201
    body = created.json()
    assert body["text"] == marker
    item_id = body["id"]

    try:
        listed = client.get("/api/items")
        assert listed.status_code == 200
        assert any(item["id"] == item_id for item in listed.json()), (
            "the item we just created is missing from /api/items — the write "
            "reached one process but the read hit another, or state is not "
            "being kept at all"
        )
    finally:
        deleted = client.delete(f"/api/items/{item_id}")
        assert deleted.status_code == 204


def test_deleting_a_missing_item_returns_404(client: httpx.Client) -> None:
    """The negative case, and it is not a formality.

    A misconfigured proxy that swallows errors, or an error handler that
    turns everything into a 200, would pass every happy-path test above. This
    is the assertion that notices.
    """
    response = client.delete("/api/items/99999999")
    assert response.status_code == 404
