"""API contract tests. Redis is replaced by fakeredis (MOCKED dependency)."""
import fakeredis
import pytest
from fastapi.testclient import TestClient
from redis.exceptions import ConnectionError as RedisConnectionError

import app.api.main as api


@pytest.fixture
def client():
    with TestClient(api.app) as c:
        api.redis_client = fakeredis.FakeAsyncRedis(decode_responses=True)
        yield c


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200 and r.json() == {"status": "healthy"}


def test_readyz_ready_when_redis_up(client):
    r = client.get("/readyz")
    assert r.status_code == 200 and r.json()["redis"] == "connected"


def test_readyz_503_when_redis_down(client):
    class Down:
        async def ping(self):
            raise RedisConnectionError("down")

        async def aclose(self):
            pass
    api.redis_client = Down()
    assert client.get("/readyz").status_code == 503


def test_submit_job_enqueues_to_stream(client):
    r = client.post("/jobs", json={"job_id": "t-1", "duration_seconds": 2, "payload": {"a": 1}})
    assert r.status_code == 202 and r.json()["job_id"] == "t-1"

    import asyncio
    entries = asyncio.run(api.redis_client.xrange(api.REDIS_STREAM))
    assert entries[-1][1]["job_id"] == "t-1"
    assert entries[-1][1]["duration_seconds"] == "2"


@pytest.mark.parametrize("body", [{"job_id": ""}, {"job_id": "x", "duration_seconds": 61}])
def test_submit_job_validation(client, body):
    assert client.post("/jobs", json=body).status_code == 422


def test_metrics_exposes_request_counter(client):
    client.get("/healthz")
    body = client.get("/metrics").text
    assert 'http_requests_total{method="GET",path="/healthz",status="200"}' in body


def test_fault_injection_spares_probes(client, monkeypatch):
    monkeypatch.setattr(api, "FAULT_ERROR_RATE", 1.0)
    assert client.get("/healthz").status_code == 200
    assert client.get("/readyz").status_code == 200
    assert client.get("/version").status_code == 500
