"""Reference API (TEST HARNESS — not the assignment's black-box application).

It mimics the black-box contract (port 8080, /healthz, /readyz, /metrics, Redis
queue producer) so the platform (probes, rollouts, gates, autoscaling) can be
exercised. The platform must not depend on anything here beyond that contract.
"""

import json
import os
import random
import time
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)
from pydantic import BaseModel, Field
from redis.asyncio import Redis
from redis.exceptions import RedisError

from app.shared.config import REDIS_STREAM, REDIS_URL

redis_client: Redis | None = None

APP_VERSION = os.getenv("APP_VERSION", "v1")

# Fault injection used ONLY to simulate a "bad release" in rollback tests:
# a fraction of business requests (/jobs, /version) return HTTP 500 while the
# probes stay green, i.e. a release that passes readiness but fails real
# traffic. Default 0 = disabled.
FAULT_ERROR_RATE = float(os.getenv("FAULT_ERROR_RATE", "0"))

# Paths excluded from fault injection so probes keep passing.
_PROBE_PATHS = {"/healthz", "/readyz", "/metrics"}

HTTP_REQUESTS = Counter(
    "http_requests_total",
    "HTTP requests by method, route and status code",
    ["method", "path", "status"],
)

HTTP_REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency by route",
    ["path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.4, 0.8, 1.6, 5.0),
)

JOBS_SUBMITTED = Counter(
    "jobs_submitted_total",
    "Total number of jobs submitted",
)


class JobRequest(BaseModel):
    job_id: str = Field(min_length=1, max_length=100)
    payload: dict[str, Any] = Field(default_factory=dict)
    duration_seconds: int = Field(default=1, ge=1, le=60)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global redis_client
    redis_client = Redis.from_url(REDIS_URL, decode_responses=True)
    yield
    if redis_client:
        await redis_client.aclose()


app = FastAPI(
    title="Cloud Deployment Platform Reference API",
    version="1.1.0",
    lifespan=lifespan,
)


@app.middleware("http")
async def metrics_and_faults(request: Request, call_next):
    path = request.url.path
    # Bound label cardinality: only known routes get their own label.
    route = path if path in _PROBE_PATHS | {"/jobs", "/version"} else "other"
    start = time.perf_counter()

    if (
        FAULT_ERROR_RATE > 0
        and path not in _PROBE_PATHS
        and random.random() < FAULT_ERROR_RATE
    ):
        response = JSONResponse({"detail": "injected fault"}, status_code=500)
    else:
        response = await call_next(request)

    HTTP_REQUEST_DURATION.labels(route).observe(time.perf_counter() - start)
    HTTP_REQUESTS.labels(request.method, route, str(response.status_code)).inc()
    return response


@app.get("/healthz")
async def health():
    # Liveness: the process is up and serving. No dependency checks here, so a
    # Redis outage does not cause restart storms.
    return {"status": "healthy"}


@app.get("/readyz")
async def readiness():
    # Readiness: only receive traffic when the queue dependency is reachable.
    if redis_client is None:
        raise HTTPException(status_code=503, detail="Redis not initialized")
    try:
        await redis_client.ping()
        return {"status": "ready", "redis": "connected"}
    except RedisError:
        raise HTTPException(status_code=503, detail="Redis unavailable")


@app.get("/version")
async def version():
    return {"version": APP_VERSION}


@app.post("/jobs", status_code=202)
async def submit_job(job: JobRequest):
    if redis_client is None:
        raise HTTPException(status_code=503, detail="Redis not initialized")
    try:
        message_id = await redis_client.xadd(
            REDIS_STREAM,
            {
                "job_id": job.job_id,
                "payload": json.dumps(job.payload),
                "duration_seconds": str(job.duration_seconds),
            },
        )
    except RedisError:
        raise HTTPException(status_code=503, detail="Unable to enqueue job")

    JOBS_SUBMITTED.inc()
    return {"status": "accepted", "job_id": job.job_id, "message_id": message_id}


@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
