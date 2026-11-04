// Business-path load for the reference harness: GET /version (read path) plus
// a fraction of POST /jobs (enqueue path). Runs INSIDE the cluster against the
// Service (no port-forward). Parameters via env:
//   PROFILE=constant  RATE=<rps> DURATION=<e.g. 120s>
//   PROFILE=ramp15x   BASE_RATE=<rps>  (ramps BASE -> 15x BASE -> BASE)
//   JOB_EVERY=<n>     one POST /jobs every n iterations (0 = never)
import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';

const jobsAccepted = new Counter('jobs_accepted');
const JOB_PREFIX = __ENV.JOB_PREFIX || 'load';

const BASE_URL = __ENV.BASE_URL || 'http://devops-platform-api:8080';
const PROFILE = __ENV.PROFILE || 'constant';
const JOB_EVERY = parseInt(__ENV.JOB_EVERY || '0', 10);

function scenario() {
  if (PROFILE === 'ramp15x') {
    const base = parseInt(__ENV.BASE_RATE || '10', 10);
    return {
      executor: 'ramping-arrival-rate',
      startRate: base,
      timeUnit: '1s',
      preAllocatedVUs: 40,
      maxVUs: 150,
      stages: [
        { target: base, duration: '30s' },        // baseline
        { target: base * 15, duration: '60s' },   // ramp to 15x
        { target: base * 15, duration: '180s' },  // hold peak
        { target: base, duration: '30s' },        // back to baseline
        { target: base, duration: '60s' },
      ],
    };
  }
  return {
    executor: 'constant-arrival-rate',
    rate: parseInt(__ENV.RATE || '50', 10),
    timeUnit: '1s',
    duration: __ENV.DURATION || '60s',
    preAllocatedVUs: 30,
    maxVUs: 120,
  };
}

export const options = {
  scenarios: { load: scenario() },
  thresholds: {
    http_req_failed: [`rate<=${__ENV.MAX_FAIL_RATE || '0.01'}`],
    http_req_duration: ['p(95)<400'],
  },
};

export default function () {
  const it = exec.scenario.iterationInTest;
  if (JOB_EVERY > 0 && it % JOB_EVERY === 0) {
    const res = http.post(
      `${BASE_URL}/jobs`,
      JSON.stringify({ job_id: `${JOB_PREFIX}-${it}`, duration_seconds: 1 }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'POST /jobs' } },
    );
    if (check(res, { 'job accepted (202)': (r) => r.status === 202 })) jobsAccepted.add(1);
  } else {
    const res = http.get(`${BASE_URL}/version`, { tags: { name: 'GET /version' } });
    check(res, { 'version 200': (r) => r.status === 200 });
  }
}

export function handleSummary(data) {
  const m = data.metrics;
  const out = {
    profile: PROFILE,
    requests: m.http_reqs.values.count,
    rps_avg: Number(m.http_reqs.values.rate.toFixed(2)),
    failed_rate: m.http_req_failed.values.rate,
    failed_count: m.http_req_failed.values.passes,
    p95_ms: Number(m.http_req_duration.values['p(95)'].toFixed(2)),
    p99_ms: m.http_req_duration.values['p(99)'] !== undefined ? Number(m.http_req_duration.values['p(99)'].toFixed(2)) : null,
    max_ms: Number(m.http_req_duration.values.max.toFixed(2)),
    jobs_accepted: m.jobs_accepted ? m.jobs_accepted.values.count : 0,
    dropped_iterations: m.dropped_iterations ? m.dropped_iterations.values.count : 0,
    thresholds_ok: Object.values(m).every((x) => !x.thresholds || Object.values(x.thresholds).every((t) => t.ok)),
  };
  return { stdout: `\nK6_SUMMARY_JSON ${JSON.stringify(out)}\n` };
}
