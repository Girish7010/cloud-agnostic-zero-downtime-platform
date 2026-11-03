import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    baseline: { executor: 'constant-arrival-rate', rate: 150, timeUnit: '1s', duration: '2m', preAllocatedVUs: 50, maxVUs: 500 },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<400'],
  },
};

export default function () {
  const res = http.get(`${__ENV.BASE_URL}/healthz`);
  check(res, { 'health endpoint responds': (r) => r.status === 200 });
  sleep(0.1);
}
