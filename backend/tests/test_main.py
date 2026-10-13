from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_create_and_list_item() -> None:
    response = client.post("/api/items", json={"text": "buy milk"})
    assert response.status_code == 201
    created = response.json()
    assert created["text"] == "buy milk"
    assert "id" in created

    response = client.get("/api/items")
    assert response.status_code == 200
    assert any(item["id"] == created["id"] for item in response.json())


def test_delete_item() -> None:
    created = client.post("/api/items", json={"text": "temporary"}).json()

    response = client.delete(f"/api/items/{created['id']}")
    assert response.status_code == 204

    response = client.get("/api/items")
    assert all(item["id"] != created["id"] for item in response.json())


def test_delete_missing_item_returns_404() -> None:
    response = client.delete("/api/items/999999")
    assert response.status_code == 404
