import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    baseline: {
      executor: 'constant-arrival-rate',
      rate: 50,
      timeUnit: '1s',
      duration: '30s',
      preAllocatedVUs: 15,
      maxVUs: 25,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<400'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8083';

export default function () {
  const response = http.get(`${BASE_URL}/healthz`);

  check(response, {
    'health endpoint responds': (r) => r.status === 200,
  });
}
