# Quickstart: Verification Steps per App (spec 065)

## Per-App Verification Pattern

For each app, verify two things after each PR:
1. **Auth gate works**: unauthenticated access redirects to Authentik login
2. **Scrape/API paths unaffected** (where applicable): Prometheus can still scrape the target

---

## PR 1 — Prometheus

**Browser check (auth gate)**:
1. Open a private/incognito window
2. Navigate to `https://prometheus.fleet1.lan`
3. Should redirect to `https://authentik.fleet1.lan/...` login page
4. Log in as `akadmin`
5. Should land on Prometheus UI (`/graph`)

**Scrape check (no-auth paths)**:
```bash
# From a cluster pod or node — simulates Prometheus scraping itself
curl -s https://prometheus.fleet1.lan/metrics | head -5
# Should return metric lines, NOT a redirect or 401
```

**Authentik session reuse**:
- After logging in at Prometheus, navigate to `https://alertmanager.fleet1.lan` (after PR 2)
- Should NOT prompt for login again (SSO cookie on `.fleet1.lan`)

---

## PR 2 — Alertmanager

**Browser check**:
1. Private window → `https://alertmanager.fleet1.lan`
2. Should redirect to Authentik login (or reuse session from Prometheus)
3. After login: Alertmanager UI loads

**Scrape check**:
```bash
curl -s https://alertmanager.fleet1.lan/metrics | head -5
# Should return metric lines
```

---

## PR 3 — Traefik Dashboard

**Browser check**:
1. Private window → `https://traefik.fleet1.lan`
2. Should redirect to Authentik login
3. After login: Traefik dashboard loads (routers, services, middleware list visible)

**No scrape exemption needed** (dashboard has no `/metrics` path used by Prometheus).

---

## PR 4 — Loki UI

**Browser check**:
1. Private window → `https://loki.fleet1.lan`
2. Should redirect to Authentik login
3. After login: Loki API root loads (Loki's web UI is minimal — expect JSON or the Loki ready endpoint)

**API check** (Grafana data source — must remain accessible from in-cluster without auth):
- Grafana's Loki data source uses `http://loki.monitoring.svc.cluster.local:3100` (in-cluster, bypasses IngressRoute/forward-auth entirely)
- No exemption needed: Grafana never goes through the IngressRoute

---

## PR 5 — Node-RED

**Browser check**:
1. Private window → `https://node-red.fleet1.lan`
2. Should redirect to Authentik login
3. After login: Node-RED editor loads

**WebSocket check**:
- In the Node-RED editor, deploy a change (e.g., inject a timestamp node)
- The editor communicates via WebSocket — if the deploy succeeds and the debug panel shows output, WebSockets are working through forward-auth
- If the editor loads but deploys fail or show connection errors, split the IngressRoute to exempt `/comms` from forward-auth

**Regression check**:
- Confirm Home Assistant (`https://hass.fleet1.lan`) and InfluxDB (`https://influxdb.fleet1.lan`) still load — their IngressRoutes are in the same file but should be unchanged

---

## Debugging Forward-Auth Failures

Forward-auth failures are silent 401s at Traefik with no error in the app. Debug via:

```bash
# Traefik logs — look for 401s from the forwardAuth middleware
kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=50 | grep -E "401|forward|authentik"

# Authentik logs — look for rejected requests
kubectl logs -n authentik -l app.kubernetes.io/component=server --tail=50 | grep -E "401|outpost|forward"

# Test the outpost directly from a pod in the cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik
```

Expected outpost response without a valid session cookie: `HTTP/1.1 401` with a `Location` header pointing to the Authentik login URL.
