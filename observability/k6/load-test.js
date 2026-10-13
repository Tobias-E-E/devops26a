// Reference load test for the template app's REST API.
//
// Run with the k6 CLI:
//   k6 run observability/k6/load-test.js
// or via the official Docker image (no local k6 install needed):
//   docker run --rm -i --add-host=host.docker.internal:host-gateway \
//     grafana/k6 run - <observability/k6/load-test.js \
//     -e BASE_URL=http://host.docker.internal:8080
//
// BASE_URL defaults to http://localhost:8080 (the frontend's published
// port from ../docker-compose.yml).
import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost:8080";

export const options = {
  vus: 10,
  duration: "30s",
  // A basic SLO: k6 exits non-zero if either threshold is breached, the
  // same way a CI gate would - a starting point to tighten/loosen once
  // you know your app's real numbers.
  thresholds: {
    http_req_duration: ["p(95)<500"], // 95% of requests under 500ms
    http_req_failed: ["rate<0.01"], // fewer than 1% of requests may fail
  },
};

export default function () {
  const health = http.get(`${BASE_URL}/api/health`);
  check(health, { "health status is 200": (r) => r.status === 200 });

  const list = http.get(`${BASE_URL}/api/items`);
  check(list, { "list status is 200": (r) => r.status === 200 });

  const payload = JSON.stringify({ text: `load-test-item-${__VU}-${__ITER}` });
  const create = http.post(`${BASE_URL}/api/items`, payload, {
    headers: { "Content-Type": "application/json" },
  });
  check(create, { "create status is 201": (r) => r.status === 201 });

  sleep(1);
}
