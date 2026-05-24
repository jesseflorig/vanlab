---
description: "Task list for spec 065 — Authentik forward-auth for Tier 1b apps"
---

# Tasks: Authentik Forward-Auth for Tier 1b Apps (spec 065)

**Input**: Design documents from `/specs/065-authentik-forward-auth/`
**Branch**: `065-authentik-forward-auth`
**PRs**: 5 — one per app (Prometheus → Alertmanager → Traefik dashboard → Loki UI → Node-RED)

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[US#]**: Which PR/app this task belongs to
- Each PR is independently deployable and verifiable

---

## Phase 1: Setup (Pre-flight checks)

**Purpose**: Confirm prerequisites are in place before writing any manifests

- [X] T001 Verify Authentik embedded outpost is reachable: `kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl -v http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik` — expect HTTP 401 with Location header (not a connection error)

---

## Phase 2: Foundational (Shared Middleware — blocks all PRs)

**Purpose**: Create the single shared `authentik-forward-auth` Middleware in the `traefik` namespace. All subsequent IngressRoute updates depend on this resource existing in-cluster.

**⚠️ CRITICAL**: No app-level forward-auth work can begin until T002–T003 are complete and applied.

- [X] T002 Create `manifests/traefik/forward-auth-middleware.yaml` — Middleware resource: namespace=traefik, forwardAuth.address=`http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik`, trustForwardHeader=true, authResponseHeaders list (X-authentik-username, X-authentik-email, X-authentik-groups, X-authentik-uid, X-authentik-jwt, X-authentik-meta-jwks, X-authentik-meta-outpost, X-authentik-meta-provider, X-authentik-meta-app, X-authentik-meta-version)
- [X] T003 Apply shared Middleware: `kubectl apply -f manifests/traefik/forward-auth-middleware.yaml` — verify with `kubectl get middleware -n traefik authentik-forward-auth`

**Checkpoint**: `kubectl get middleware -n traefik` shows `authentik-forward-auth` — all 5 app PRs can now proceed

---

## Phase 3: User Story 1 — Prometheus (PR 1) 🎯 MVP

**Goal**: Gate `https://prometheus.fleet1.lan` behind Authentik forward-auth while preserving unauthenticated access to `/metrics` and `/api/v1/` for Prometheus self-scraping.

**Independent Test**:
- Private window → `https://prometheus.fleet1.lan` → redirects to Authentik login
- `curl -s https://prometheus.fleet1.lan/metrics | head -5` returns metric lines (not 401)
- After login at Prometheus, navigate to Alertmanager (after PR 2) without re-auth

### Implementation for User Story 1

- [X] T004 [US1] Authentik UI: Create Proxy Provider — name=Prometheus, mode=Forward auth (single application), external host=`https://prometheus.fleet1.lan`; then create Application — name=Prometheus, slug=prometheus, linked to the provider
- [X] T005 [US1] Split Prometheus IngressRoute in `manifests/monitoring/fleet1-lan-ingressroutes.yaml`: add rule `Host(\`prometheus.fleet1.lan\`) && (PathPrefix(\`/metrics\`) || PathPrefix(\`/api/v1/\`))` with priority=20 (no middleware) and change existing catch-all rule to priority=10 with `middlewares: [{name: authentik-forward-auth, namespace: traefik}]`
- [X] T006 [US1] Apply: `kubectl apply -f manifests/monitoring/fleet1-lan-ingressroutes.yaml`
- [X] T007 [US1] Verify PR 1 per quickstart.md: browser auth gate (redirect → Authentik login → Prometheus UI), scrape check (`curl -s https://prometheus.fleet1.lan/metrics | head -5` returns metrics, not redirect)
- [X] T008 [US1] Export Authentik blueprint via Authentik UI (System → Blueprints → Export) to `specs/065-authentik-forward-auth/blueprint-backup.yaml`
- [X] T009 [US1] Commit `manifests/traefik/forward-auth-middleware.yaml` + updated `manifests/monitoring/fleet1-lan-ingressroutes.yaml` + `specs/065-authentik-forward-auth/blueprint-backup.yaml`; open PR for PR 1

**Checkpoint**: Prometheus requires Authentik login; Prometheus can still scrape itself on `/metrics` and `/api/v1/`

---

## Phase 4: User Story 2 — Alertmanager (PR 2)

**Goal**: Gate `https://alertmanager.fleet1.lan` behind Authentik forward-auth. Alertmanager has no existing IngressRoute — create it with split scrape/browser rules.

**Independent Test**:
- Private window → `https://alertmanager.fleet1.lan` → redirects to Authentik login (or reuses Prometheus session)
- `curl -s https://alertmanager.fleet1.lan/metrics | head -5` returns metric lines
- Session from Prometheus PR 1 is reused (SSO on `.fleet1.lan`)

### Implementation for User Story 2

- [X] T010 [US2] Authentik UI: Create Proxy Provider — name=Alertmanager, external host=`https://alertmanager.fleet1.lan`; Application — slug=alertmanager
- [X] T011 [US2] Add Alertmanager IngressRoute to `manifests/monitoring/fleet1-lan-ingressroutes.yaml`: split rule `Host(\`alertmanager.fleet1.lan\`) && (PathPrefix(\`/metrics\`) || PathPrefix(\`/api/v2/\`))` priority=20 (no middleware) + catch-all `Host(\`alertmanager.fleet1.lan\`)` priority=10 with forward-auth middleware; service=kube-prometheus-stack-alertmanager port=9093
- [X] T012 [US2] Apply: `kubectl apply -f manifests/monitoring/fleet1-lan-ingressroutes.yaml`
- [X] T013 [US2] Verify PR 2 per quickstart.md: browser auth gate, scrape check (`curl -s https://alertmanager.fleet1.lan/metrics | head -5`), SSO reuse from Prometheus session
- [X] T014 [US2] Update `specs/065-authentik-forward-auth/blueprint-backup.yaml` (re-export from Authentik UI, now includes Prometheus + Alertmanager providers)
- [X] T015 [US2] Commit updated `manifests/monitoring/fleet1-lan-ingressroutes.yaml` + `blueprint-backup.yaml`; open PR for PR 2

**Checkpoint**: Alertmanager requires Authentik login; scrape paths open; SSO works across Prometheus + Alertmanager

---

## Phase 5: User Story 3 — Traefik Dashboard (PR 3)

**Goal**: Gate `https://traefik.fleet1.lan` behind Authentik forward-auth. The dashboard IngressRoute is Helm-managed via `roles/traefik/files/values.yaml` — update the values, redeploy Traefik.

**Independent Test**:
- Private window → `https://traefik.fleet1.lan` → redirects to Authentik login
- After login: Traefik dashboard loads (routers, services, middleware list visible)

### Implementation for User Story 3

- [ ] T016 [US3] Authentik UI: Create Proxy Provider — name=Traefik Dashboard, external host=`https://traefik.fleet1.lan`; Application — slug=traefik-dashboard
- [ ] T017 [US3] Add middlewares block to `ingressRoute.dashboard` in `roles/traefik/files/values.yaml`: add `middlewares: [{name: authentik-forward-auth, namespace: traefik}]` under `ingressRoute.dashboard`
- [ ] T018 [US3] Redeploy Traefik: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags traefik` — verify Traefik pod restarts cleanly
- [ ] T019 [US3] Verify PR 3 per quickstart.md: private window → `https://traefik.fleet1.lan` → redirect to Authentik login → dashboard loads after auth
- [ ] T020 [US3] Update `specs/065-authentik-forward-auth/blueprint-backup.yaml` (re-export, now includes Prometheus + Alertmanager + Traefik dashboard)
- [ ] T021 [US3] Commit updated `roles/traefik/files/values.yaml` + `blueprint-backup.yaml`; open PR for PR 3

**Checkpoint**: Traefik dashboard requires Authentik login; all three monitoring+infra UIs now gated

---

## Phase 6: User Story 4 — Loki UI (PR 4)

**Goal**: Gate `https://loki.fleet1.lan` behind Authentik forward-auth. Loki has no existing IngressRoute. Grafana's Loki data source uses in-cluster URL directly — no scrape exemption needed.

**Independent Test**:
- Private window → `https://loki.fleet1.lan` → redirects to Authentik login
- After login: Loki API root loads (JSON or Loki ready endpoint — Loki's web UI is minimal)
- Grafana dashboards still populate Loki data (Grafana uses `http://loki.monitoring.svc.cluster.local:3100`, bypasses IngressRoute entirely)

### Implementation for User Story 4

- [ ] T022 [US4] Authentik UI: Create Proxy Provider — name=Loki, external host=`https://loki.fleet1.lan`; Application — slug=loki
- [ ] T023 [US4] Add Loki IngressRoute to `manifests/monitoring/fleet1-lan-ingressroutes.yaml`: single rule `Host(\`loki.fleet1.lan\`)` with forward-auth middleware; service=loki port=3100 (no scrape exemption — Grafana uses in-cluster URL)
- [ ] T024 [US4] Apply: `kubectl apply -f manifests/monitoring/fleet1-lan-ingressroutes.yaml`
- [ ] T025 [US4] Verify PR 4 per quickstart.md: browser auth gate, Loki API root loads after login, confirm Grafana Loki panels still populate
- [ ] T026 [US4] Update `specs/065-authentik-forward-auth/blueprint-backup.yaml` (re-export)
- [ ] T027 [US4] Commit updated `manifests/monitoring/fleet1-lan-ingressroutes.yaml` + `blueprint-backup.yaml`; open PR for PR 4

**Checkpoint**: Loki UI gated; Grafana data source unaffected (in-cluster path bypasses IngressRoute)

---

## Phase 7: User Story 5 — Node-RED (PR 5)

**Goal**: Gate `https://node-red.fleet1.lan` behind Authentik forward-auth AND fix the existing broken cross-namespace TLSOption reference (`tls.options.namespace: traefik` for `device-mtls` — Traefik v3 silently drops routes with cross-namespace TLSOption). WebSocket must remain functional after adding forward-auth.

**Independent Test**:
- Private window → `https://node-red.fleet1.lan` → redirects to Authentik login
- After login: Node-RED editor loads
- Deploy a test flow (inject → debug node) — editor communicates via WebSocket; successful deploy confirms WebSockets work through forward-auth
- `https://hass.fleet1.lan` and `https://influxdb.fleet1.lan` still load (regression — same file, unchanged routes)

### Implementation for User Story 5

- [ ] T028 [US5] Authentik UI: Create Proxy Provider — name=Node-RED, external host=`https://node-red.fleet1.lan`; Application — slug=node-red
- [ ] T029 [US5] Update `node-red-fleet1-lan` IngressRoute in `manifests/home-automation/fleet1-lan-ingressroutes.yaml`: change `tls: options: name: device-mtls / namespace: traefik` to `tls: {}` AND add `middlewares: [{name: authentik-forward-auth, namespace: traefik}]` to the route rule; leave `home-assistant-fleet1-lan` and `influxdb-fleet1-lan` unchanged (their broken TLSOption is out of scope)
- [ ] T030 [US5] Apply: `kubectl apply -f manifests/home-automation/fleet1-lan-ingressroutes.yaml`
- [ ] T031 [US5] Verify PR 5 per quickstart.md: browser auth gate, Node-RED editor loads, deploy a test flow to confirm WebSocket works, confirm `https://hass.fleet1.lan` and `https://influxdb.fleet1.lan` still load
- [ ] T032 [US5] If editor loads but deploys fail (WebSocket broken): split IngressRoute — add second rule `Host(\`node-red.fleet1.lan\`) && (PathPrefix(\`/comms\`) || PathPrefix(\`/socket.io/\`))` with higher priority and no middleware
- [ ] T033 [US5] Update `specs/065-authentik-forward-auth/blueprint-backup.yaml` (re-export — final state with all 5 apps)
- [ ] T034 [US5] Commit updated `manifests/home-automation/fleet1-lan-ingressroutes.yaml` + `blueprint-backup.yaml`; open PR for PR 5

**Checkpoint**: All 5 Tier 1b apps gated behind Authentik forward-auth; Node-RED WebSocket confirmed working

---

## Phase 8: Polish & Wrap-up

**Purpose**: Finalize documentation and mark spec deployed

- [ ] T035 Update `specs/065-authentik-forward-auth/spec.md` status to `Deployed — 2026-05-23` (or actual deploy date)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — run immediately
- **Foundational (Phase 2)**: Depends on Phase 1 outpost check — BLOCKS all PR phases
- **US1 Prometheus (Phase 3)**: Depends on Foundational (Middleware must exist in-cluster)
- **US2–US5 (Phases 4–7)**: Each depends on Foundational; ordered sequentially by risk (Prometheus validates pattern before others)
- **Polish (Phase 8)**: Depends on all PRs merged

### PR Ordering Rationale

1. **Prometheus first**: Validates the shared Middleware + scrape-exemption split-rule pattern
2. **Alertmanager second**: Same scrape-exemption pattern — low risk after Prometheus confirms it
3. **Traefik dashboard third**: Helm-managed route; different deploy path (Ansible, not kubectl)
4. **Loki UI fourth**: New IngressRoute, no scrape exemption — simplest shape
5. **Node-RED last**: TLSOption fix + WebSocket concern — highest risk, isolated last

### Sequential Constraint

Each app PR should be **merged and verified** before starting the next. The shared `.fleet1.lan` SSO cookie makes cross-app verification dependent on earlier PRs being live.

---

## Parallel Opportunities

Within each PR phase, the Authentik UI step (T004, T010, T016, T022, T028) can run in parallel with reading the existing manifest file to plan the edit — but the manifest edit itself must follow both.

```bash
# PR 1 parallel start:
# These two can run simultaneously:
Task: T004 — Create Prometheus Proxy Provider in Authentik UI
Task: Read manifests/monitoring/fleet1-lan-ingressroutes.yaml to plan split-rule edit

# Then sequentially:
Task: T005 — Edit the IngressRoute (depends on T004 slug + T002 Middleware)
Task: T006 — kubectl apply
Task: T007 — Verify
```

---

## Implementation Strategy

### MVP (PR 1 Only — Validates the Pattern)

1. Complete Phase 1: pre-flight outpost check
2. Complete Phase 2: create + apply shared Middleware
3. Complete Phase 3 (PR 1): Prometheus split IngressRoute + Authentik provider
4. **STOP and VALIDATE**: browser auth gate + scrape check per quickstart.md
5. Merge PR 1 — pattern confirmed, proceed to remaining PRs

### Incremental Delivery

- PR 1 → merge → validate → PR 2 → merge → validate → ... → PR 5
- Each PR adds one app without risk to previously deployed apps
- SSO session reuse validates automatically as each app comes online

### Rollback Per App

If forward-auth breaks an app:
- Remove the middleware reference from the IngressRoute
- `kubectl apply` the reverted file
- App is immediately accessible again without touching other apps (Middleware resource stays in-cluster)

---

## Notes

- All IngressRoute edits to `manifests/monitoring/` and `manifests/home-automation/` are applied via `kubectl apply -f` (not ArgoCD — these files are manually applied per Constitution XI note in plan.md)
- The Traefik dashboard IngressRoute is Helm-managed — changes require `ansible-playbook --tags traefik`, not `kubectl apply`
- The shared `authentik-forward-auth` Middleware in `traefik` namespace is created once (T002) and referenced by all 5 apps — never duplicated
- Forward-auth failures are silent 401s at Traefik; debug via `kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=50 | grep -E "401|forward|authentik"` (see quickstart.md for full debug commands)
- Node-RED T032 (WebSocket split) is conditional — only execute if T031 verification shows deploy failures
