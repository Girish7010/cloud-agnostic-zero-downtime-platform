import os

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
REDIS_STREAM = os.getenv("REDIS_STREAM", "jobs")
REDIS_GROUP = os.getenv("REDIS_GROUP", "job-workers")
