"""Worker semantics tests against fakeredis (MOCKED Redis, no real sleeps)."""
import fakeredis
import pytest

import app.worker.main as w


@pytest.fixture
def r(monkeypatch):
    client = fakeredis.FakeRedis(decode_responses=True)
    w.ensure_group(client)
    monkeypatch.setattr(w, "running", True)
    return client


def add(r, job_id, duration=1):
    return r.xadd(w.REDIS_STREAM, {"job_id": job_id, "payload": "{}", "duration_seconds": str(duration)})


def pending(r):
    return r.xpending(w.REDIS_STREAM, w.REDIS_GROUP)["pending"]


def test_processes_and_acks(r):
    add(r, "j1", 5)
    slept = []
    assert w.run_once(r, block_ms=10, sleep=slept.append) == ["processed"]
    assert slept == [5]
    assert pending(r) == 0
    assert r.exists(w.done_key("j1"))


def test_failed_job_stays_pending(r):
    add(r, "j2")
    def boom(_):
        raise RuntimeError("fail")
    assert w.run_once(r, block_ms=10, sleep=boom) == ["failed"]
    assert pending(r) == 1


def test_redelivered_completed_job_is_not_rerun(r):
    mid = add(r, "j3")
    r.set(w.done_key("j3"), mid)  # completed earlier, crash before XACK
    slept = []
    assert w.run_once(r, block_ms=10, sleep=slept.append) == ["duplicate"]
    assert slept == [] and pending(r) == 0


def test_no_new_job_started_after_sigterm(r):
    add(r, "j4")
    w.stop_worker(15, None)
    slept = []
    assert w.run_once(r, block_ms=10, sleep=slept.append) == []
    assert slept == []
    assert pending(r) == 1  # read-but-unstarted message is reclaimable


def test_sigterm_during_job_still_acks(r, monkeypatch):
    add(r, "j5", 3)
    def sleep_and_get_sigterm(_):
        w.stop_worker(15, None)
    assert w.run_once(r, block_ms=10, sleep=sleep_and_get_sigterm) == ["processed"]
    assert pending(r) == 0 and w.running is False


def test_stale_pending_message_is_reclaimed(r, monkeypatch):
    add(r, "j6")
    r.xreadgroup(w.REDIS_GROUP, "dead-worker", {w.REDIS_STREAM: ">"}, count=1)
    monkeypatch.setattr(w, "PENDING_IDLE_TIMEOUT_MS", 0)
    assert w.run_once(r, block_ms=10, sleep=lambda _: None) == ["processed"]
    assert pending(r) == 0
