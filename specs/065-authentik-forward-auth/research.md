# Research: Authentik Forward-Auth for Tier 1b Apps (065)

**Branch**: `065-authentik-forward-auth` | **Date**: 2026-05-23

---

## R1 — Traefik v3 forwardAuth Middleware for Authentik Embedded Outpost

**Decision**: Use a single `Middleware` resource in the `traefik` namespace, referenced cross-namespace from all IngressRoutes using `name: authentik-forward-auth / namespace: traefik`.

**Rationale**: Centralizing the Middleware in `traefik` namespace avoids duplicating the resource across 4 namespaces.

**⚠️ CORRECTION (confirmed during implementation 2026-05-23)**: Cross-namespace Middleware references in Traefik v3 require `providers.kubernetesCRD.allowCrossNamespace: true` — this is NOT enabled by default. Without it, Traefik logs `middleware traefik/authentik-forward-auth is not in the IngressRoute namespace monitoring` and the route returns 404. Added `allowCrossNamespace: true` to `roles/traefik/files/values.yaml` and patched the running deployment with `--providers.kubernetescrd.allowCrossNamespace=true`. This applies to Middleware just as it does to TLSOption — both require this flag for cross-namespace references in Traefik v3.

**forwardAuth address**: `http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik`

Using the in-cluster service URL is mandatory (hairpin NAT — pods cannot reach node IPs on port 443 from inside the cluster, confirmed in R11 of spec 064 research). The external URL `https://authentik.fleet1.lan/...` MUST NOT be used here.

**Middleware spec**:
```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik-forward-auth
  namespace: traefik
spec:
  forwardAuth:
    address: http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-email
      - X-authentik-groups
      - X-authentik-uid
      - X-authentik-jwt
      - X-authentik-meta-jwks
      - X-authentik-meta-outpost
      - X-authentik-meta-provider
      - X-authentik-meta-app
      - X-authentik-meta-version
```

**IngressRoute reference**:
```yaml
middlewares:
  - name: authentik-forward-auth
    namespace: traefik
```

---

## R2 — Prometheus and Alertmanager Scrape Path Exemptions

**Decision**: Split IngressRoute into two rules on the same Host — one rule matching scrape/API paths with no middleware, one rule for all other paths with the forward-auth middleware. Use route priority to ensure the no-auth rule wins for scrape paths.

**Rationale**: Prometheus scrapes itself on `/metrics` and `/api/v1/`. Alertmanager is scraped on `/metrics` and `/api/v2/`. Applying forward-auth blanket-style to these paths breaks metric collection. The split-rule approach avoids exemption logic in Authentik.

**Priority ordering**: In Traefik v3, a more specific `PathPrefix` rule wins over a less specific one. List the scrape-path rule first in the routes list with an explicit `priority` if needed. Traefik calculates priority by rule length by default — `Host() && PathPrefix(/metrics)` wins over `Host()` alone.

**Prometheus exempted paths**: `/metrics`, `/api/v1/`  
**Alertmanager exempted paths**: `/metrics`, `/api/v2/`

**Pattern**:
```yaml
routes:
  - match: Host(`prometheus.fleet1.lan`) && (PathPrefix(`/metrics`) || PathPrefix(`/api/v1/`))
    kind: Rule
    priority: 20
    services:
      - name: kube-prometheus-stack-prometheus
        port: 9090
  - match: Host(`prometheus.fleet1.lan`)
    kind: Rule
    priority: 10
    middlewares:
      - name: authentik-forward-auth
        namespace: traefik
    services:
      - name: kube-prometheus-stack-prometheus
        port: 9090
```

---

## R3 — Authentik Proxy Provider vs OIDC Provider

**Decision**: Use Authentik **Proxy Provider** (not OAuth2/OIDC) for forward-auth. One Proxy Provider + Application per Tier 1b app.

**Rationale**: Proxy Providers are specifically designed for the forward-auth/reverse-proxy pattern. They handle the auth cookie lifecycle, session management, and the outpost auth check. OIDC providers (used in spec 064) require the app itself to implement OAuth2 — Tier 1b apps don't have OIDC clients.

**External host per provider**: Each Proxy Provider needs the `External host` set to the app's fleet1.lan URL (e.g., `https://prometheus.fleet1.lan`). This is what Authentik uses to scope the auth cookie and the redirect-after-login URL.

**Proxy mode**: Use `Forward auth (single application)` mode, not `Proxy` mode. Single-application forward-auth has no outpost-side proxy — Traefik calls the outpost to check auth, then forwards the request directly to the backend. This avoids routing all traffic through the outpost.

---

## R4 — Node-RED WebSocket Compatibility

**Decision**: Apply forward-auth to the full Node-RED IngressRoute (no WebSocket-specific split). Validate WebSocket behavior after deployment; split to exempt `/comms` if the editor breaks.

**Rationale**: Traefik's `forwardAuth` middleware performs a one-time auth check per new connection, then caches the result. WebSocket upgrades are HTTP connections — the auth check fires once on the initial HTTP upgrade request, after which the WebSocket is established and auth is not re-checked per message. The Authentik embedded outpost passes upgrade headers through. Most implementations work without special handling. The split-route fallback (exempt `/comms`, `/socket.io/`, etc.) is available if testing shows issues.

---

## R5 — Existing IngressRoute Inventory and Gaps

**Cluster state as of 2026-05-23**:

| App | Namespace | Existing fleet1.lan IngressRoute | Notes |
|-----|-----------|----------------------------------|-------|
| Prometheus | monitoring | `prometheus-fleet1-lan` ✅ | No forward-auth, no scrape exemption yet |
| Alertmanager | monitoring | None ❌ | Needs new IngressRoute |
| Traefik dashboard | traefik | `traefik-dashboard` (covers both fleet1.lan + fleet1.cloud) | Needs middleware added |
| Loki UI | monitoring | None ❌ | Needs new IngressRoute |
| Node-RED | home-automation | `node-red-fleet1-lan` ✅ | Has broken cross-namespace TLSOption — fix + add middleware |

**Alertmanager service**: `kube-prometheus-stack-alertmanager` in `monitoring` namespace, port 9093.  
**Loki service**: `loki` in `monitoring` namespace, port 3100. Loki UI is served at `/` (Loki's built-in query API + Grafana Loki UI is minimal — primarily accessible via API; the web UI shows at port 3100 root).  
**Node-RED service**: `node-red` in `home-automation` namespace, port 1880.  
**Traefik dashboard**: `api@internal` TraefikService (not a K8s Service).

**Also noted**: `home-assistant-fleet1-lan` and `influxdb-fleet1-lan` in `home-automation` have the same broken cross-namespace TLSOption issue. These apps are out of scope for spec 065 (HA and InfluxDB are in the skipped list) but the IngressRoute bug should be tracked.

---

## R6 — Onboarding Order and Per-PR Structure

**Decision**: One PR per app: Prometheus → Alertmanager → Traefik dashboard → Loki UI → Node-RED.

**First PR (Prometheus) also includes**: The shared `authentik-forward-auth` Middleware in the `traefik` namespace. Subsequent PRs reference it without creating a new Middleware.

**Authentik manual steps per app**: Create Proxy Provider (Forward auth single application mode) + Application in Authentik UI, then export updated blueprint. No Ansible automation for Authentik config — follows spec 063/064 pattern of UI creation + blueprint export.

---

## R7 — Session Cookie Domain

**Decision**: Authentik's proxy provider issues cookies scoped to `.fleet1.lan` (set via Authentik's `authentik_host` config `https://authentik.fleet1.lan`). No per-app cookie configuration needed.

**Rationale**: All Tier 1b apps are on `*.fleet1.lan` subdomains. Authentik's embedded outpost sets the session cookie on the parent domain. A user authenticating at `prometheus.fleet1.lan` will have their session reused at `alertmanager.fleet1.lan` without re-authentication (SSO across Tier 1b apps).
