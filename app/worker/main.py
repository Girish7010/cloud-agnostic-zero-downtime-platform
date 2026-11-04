"""Reference queue worker (TEST HARNESS — not the black-box application).

Delivery semantics: Redis Streams consumer groups give AT-LEAST-ONCE delivery.
A message is acknowledged (XACK) only after the job finished. If a worker dies
mid-job the message stays in the Pending Entries List and another worker
reclaims it with XAUTOCLAIM after PENDING_IDLE_TIMEOUT_MS. Duplicate execution
is therefore possible after a crash, so processing is made idempotent with a
per-job completion marker (SET NX) — the black-box app needs an equivalent.

Graceful shutdown: SIGTERM sets running=False. The current job always runs to
completion and is acknowledged; no new job is read afterwards. Kubernetes
terminationGracePeriodSeconds must exceed the max job duration (60 s).
"""

import json
import logging
import os
import signal
import socket
import time

from prometheus_client import Counter, Gauge, start_http_server
from redis import Redis
from redis.exceptions import RedisError

from app.shared.config import REDIS_GROUP, REDIS_STREAM, REDIS_URL

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("job-worker")

WORKER_NAME = os.getenv("WORKER_NAME", f"worker-{socket.gethostname()}")
METRICS_PORT = int(os.getenv("METRICS_PORT", "9090"))

# Must be longer than the longest job (60 s) so a healthy worker's in-flight
# job is never stolen by another worker.
PENDING_IDLE_TIMEOUT_MS = int(os.getenv("PENDING_IDLE_TIMEOUT_MS", "120000"))

# How long a "job done" marker is kept for duplicate suppression.
DONE_MARKER_TTL_SECONDS = int(os.getenv("DONE_MARKER_TTL_SECONDS", "86400"))

JOBS_PROCESSED = Counter("worker_jobs_processed_total", "Successfully processed jobs")
JOBS_FAILED = Counter("worker_jobs_failed_total", "Jobs that failed processing")
JOBS_DUPLICATE = Counter(
    "worker_jobs_duplicate_skipped_total",
    "Redelivered jobs skipped because they were already completed",
)
JOB_IN_PROGRESS = Gauge("worker_job_in_progress", "1 while a job is executing")

running = True


def stop_worker(signum, frame):
    global running
    if running:
        logger.info(
            "Shutdown signal received (signal=%s). Current job will finish "
            "and be acknowledged; no new jobs will be read.",
            signum,
        )
    running = False


def done_key(job_id: str) -> str:
    return f"job:done:{job_id}"


def process_job(message_id, fields, sleep=time.sleep):
    job_id = fields.get("job_id", "unknown")
    duration = int(fields.get("duration_seconds", "1"))
    payload = json.loads(fields.get("payload", "{}"))
    logger.info(
        "Processing job_id=%s message_id=%s duration=%ss payload=%s",
        job_id, message_id, duration, payload,
    )
    # Reference workload; the black-box worker does the real business operation.
    sleep(duration)
    logger.info("Completed job_id=%s message_id=%s", job_id, message_id)


def handle_message(client: Redis, message_id, fields, sleep=time.sleep) -> str:
    """Process one message idempotently. Returns processed|duplicate|failed."""
    job_id = fields.get("job_id", "unknown")

    if client.exists(done_key(job_id)):
        # Already completed by some worker (e.g. it crashed after the work but
        # before XACK). Acknowledge without re-running.
        client.xack(REDIS_STREAM, REDIS_GROUP, message_id)
        JOBS_DUPLICATE.inc()
        logger.info("Skipped duplicate job_id=%s message_id=%s", job_id, message_id)
        return "duplicate"

    JOB_IN_PROGRESS.set(1)
    try:
        process_job(message_id, fields, sleep=sleep)
    except Exception:
        JOBS_FAILED.inc()
        logger.exception("Job failed: %s. Leaving it pending.", message_id)
        return "failed"
    finally:
        JOB_IN_PROGRESS.set(0)

    # Mark done, then acknowledge. A crash between the two lines leaves the
    # message pending; on redelivery the marker turns it into a no-op ACK.
    client.set(done_key(job_id), message_id, ex=DONE_MARKER_TTL_SECONDS)
    client.xack(REDIS_STREAM, REDIS_GROUP, message_id)
    JOBS_PROCESSED.inc()
    logger.info("Acknowledged job_id=%s message_id=%s", job_id, message_id)
    return "processed"


def ensure_group(client: Redis):
    try:
        client.xgroup_create(REDIS_STREAM, REDIS_GROUP, id="0", mkstream=True)
        logger.info("Created Redis consumer group")
    except RedisError as exc:
        if "BUSYGROUP" not in str(exc):
            raise


def fetch_messages(client: Redis, block_ms: int = 2000):
    # 1) Recover messages left pending by workers that stopped or crashed.
    claimed = client.xautoclaim(
        REDIS_STREAM, REDIS_GROUP, WORKER_NAME,
        min_idle_time=PENDING_IDLE_TIMEOUT_MS, start_id="0-0", count=1,
    )
    if claimed[1]:
        return claimed[1]
    # 2) Otherwise read one new message.
    result = client.xreadgroup(
        REDIS_GROUP, WORKER_NAME, {REDIS_STREAM: ">"}, count=1, block=block_ms
    )
    return result[0][1] if result else []


def run_once(client: Redis, block_ms: int = 2000, sleep=time.sleep) -> list[str]:
    outcomes = []
    for message_id, fields in fetch_messages(client, block_ms):
        if not running:
            # Read but not started: stays pending and is reclaimed later.
            break
        outcomes.append(handle_message(client, message_id, fields, sleep=sleep))
    return outcomes


def main():
    signal.signal(signal.SIGTERM, stop_worker)
    signal.signal(signal.SIGINT, stop_worker)

    client = Redis.from_url(REDIS_URL, decode_responses=True)
    try:
        start_http_server(METRICS_PORT)
        logger.info("Worker %s started; metrics on :%s", WORKER_NAME, METRICS_PORT)

        while running:
            try:
                client.ping()
                ensure_group(client)
                break
            except RedisError:
                logger.warning("Redis unavailable. Retrying in 3 seconds.")
                time.sleep(3)

        while running:
            try:
                run_once(client)
            except RedisError:
                logger.exception("Redis operation failed")
                time.sleep(3)

        logger.info("Worker shutdown complete. No in-flight job remains.")
    finally:
        client.close()
        logger.info("Redis connection closed.")


if __name__ == "__main__":
    main()
