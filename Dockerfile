# Reference test-harness image (API and worker share one immutable artifact;
# the worker Deployment overrides the command). Built ONCE in CI and promoted
# by digest; never rebuilt per environment.
# Base pinned by digest for reproducibility; Dependabot/Renovate should bump it.
FROM python:3.13-slim@sha256:ae14d4ce8771606477a81446e7ef429edd6762305fc50c84507c1041fa8285d1

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

COPY requirements.txt .
# pip is only needed at build time. It vendors its own msgpack, urllib3 and
# setuptools (pkg_resources) copies, which Trivy reports as fixable HIGH CVEs,
# so remove pip and the ensurepip wheel from the runtime image.
RUN pip install --no-cache-dir -r requirements.txt \
 && python -m pip uninstall -y pip \
 && rm -rf /usr/local/lib/python3.13/ensurepip/_bundled

COPY app/ ./app/

# Numeric UID so Kubernetes runAsNonRoot can verify it.
RUN useradd --uid 1000 --create-home appuser && chown -R appuser:appuser /app
USER 1000

EXPOSE 8080 9090

CMD ["uvicorn", "app.api.main:app", "--host", "0.0.0.0", "--port", "8080", "--timeout-graceful-shutdown", "30"]
