# Feature Specification: Authentik Forward-Auth for Tier 1b Apps

**Feature Branch**: `065-authentik-forward-auth`
**Created**: 2026-05-11
**Status**: Ready to plan
**Input**: User description: "Put apps without native auth (Prometheus, Alertmanager, Traefik dashboard, Frigate, Node-RED) behind Authentik forward-auth via Traefik middleware."

---

> ⚠️ **STATUS: NEEDS REVALIDATION BEFORE PLANNING**
>
> This spec was seeded from a grill-me session on 2026-05-11. It is **not** a ready-to-plan spec. Before invoking `/speckit.plan` or `/speckit.tasks`, run `/speckit.clarify` and confirm:
> - Is Authentik (spec 063) deployed and stable?
> - Has spec 059 (Tailscale) shipped? Forward-auth without remote break-glass access is risky.
> - Is the Tier 1b app list still correct? Have any of these apps gained native auth in the meantime (e.g., Frigate)?
> - Is the "any authenticated user" gating policy still appropriate, or has multi-user with finer gates become a real need?

---

## Clarifications

### Session 2026-05-23

- Q: Is spec 059 (Tailscale) deployed? → A: Yes — Tailscale deployed, connects to edge device for remote break-glass.
- Q: Frigate auth posture — forward-auth or leave on native? → A: Leave on native auth only, remove from scope.
- Q: Prometheus/Alertmanager scrape path exemption approach? → A: Split IngressRoute — scrape paths (no middleware), browser paths (forward-auth middleware).
- Q: Onboarding order? → A: One PR per app — Prometheus → Alertmanager → Traefik dashboard → Loki UI → Node-RED.

---

## Captured Design Summary

**Purpose**: Put apps that don't speak OIDC (or that have weak/no native auth) behind Authentik forward-auth via Traefik middleware. Authentik's proxy provider + embedded outpost handles the auth check; Traefik's `forwardAuth` middleware enforces it on each IngressRoute.

**Apps in scope**:

| App | Auth posture today | After this spec |
|---|---|---|
| Prometheus | None / LAN-only | Forward-auth, any authenticated user |
| Alertmanager | None / LAN-only | Forward-auth, any authenticated user |
| Traefik dashboard | None / LAN-only | Forward-auth, any authenticated user |
| Frigate | Native auth (recent versions) | **Out of scope** — stays on native auth; forward-auth breaks mobile/API clients |
| Node-RED | Built-in but weak | Forward-auth, any authenticated user |
| Loki UI | None | Forward-auth, any authenticated user |

**Apps explicitly NOT in scope** (Tier 0 break-glass — stay on native auth):
- ArgoCD, Gitea, Longhorn UI, Kubernetes API.

**Apps explicitly skipped** (don't break the mobile app or token-driven flows):
- Home Assistant.
- InfluxDB (token auth fine).
- Vaultwarden (out-of-band recovery vault).
- Frigate (native auth in recent versions is sufficient; forward-auth would break mobile app and API clients).

**Dependencies**:
- **Hard**: Spec 063 (Authentik IdP) deployed and stable.
- **Hard**: Authentik proxy provider configured; outpost is reachable from Traefik.
- **Strong soft**: Spec 059 (Tailscale) merged and deployed — remote break-glass confirmed available via Tailscale edge device connection. ✅

**Gating policy**:
- Single global policy: "member of `admins` OR `users`" — any authenticated user passes.
- Configured at the **outpost/proxy-provider level**, not per-app, until multi-user with finer roles becomes a real need.

**Per-app integration shape**:
- One Authentik **Proxy Provider** + **Application** per protected app (managed in blueprints, committed to Git).
- One Traefik `Middleware` resource referencing the Authentik outpost's `/outpost.goauthentik.io/auth/traefik` endpoint.
- Each protected app's `IngressRoute` adds the middleware to its router config.

## Open Questions to Revalidate

1. ~~**Frigate's auth choice**~~ — **Resolved**: Frigate stays on native auth, removed from scope.
2. **Header pass-through**: Does any Tier 1b app need to consume `X-authentik-username` / `X-authentik-email` / `X-authentik-groups` for per-user behavior? Most will not. Node-RED with the user-mapping plugin might.
3. ~~**Anonymous-read paths**~~ — **Resolved**: Split IngressRoute per app — one rule for scrape/API paths (no middleware), one rule for browser paths with forward-auth middleware. Applies to Prometheus (`/metrics`, `/api/v1/`) and Alertmanager (`/metrics`, `/api/v2/`).
4. **Outpost as single point of failure**: With a single-replica embedded outpost, every Tier 1b app shares a fate. Is the existing `AuthentikOutpostDown` alert (from spec 063) sufficient, or does this spec warrant additional liveness wiring?
5. **Session cookie scope**: Confirm Authentik's proxy provider issues cookies on `.fleet1.lan` (not the per-app hostname) so SSO is shared across Tier 1b apps.
6. ~~**Onboarding order**~~ — **Resolved**: One PR per app in order: Prometheus → Alertmanager → Traefik dashboard → Loki UI → Node-RED.

## Known Gotchas to Carry into Planning

- Forward-auth failures = silent 401s at Traefik. No useful error in the app. Plan to debug via Traefik logs + Authentik logs side-by-side.
- Prometheus and Alertmanager need scrape path exemptions — split IngressRoute: one rule matching `/metrics` and `/api/v1/` (Prometheus) or `/api/v2/` (Alertmanager) with no middleware, one rule for all other paths with forward-auth middleware.
- WebSocket support in forward-auth: confirm the Authentik proxy provider correctly proxies WebSocket upgrades for apps that need them (Node-RED, Frigate live view).
- Cookie domain must match what Authentik issues (`.fleet1.lan` per spec 063); each protected app must live under that parent domain.
- If you change Authentik's hostname *or* the proxy provider's external URL, existing sessions can become invalid in subtle ways. Avoid hostname changes after this spec lands.
- **Traefik v3 cross-namespace TLSOption**: IngressRoutes in any namespace other than `traefik` cannot reference the `device-mtls` TLSOption — Traefik v3 silently drops the route (404). Every `fleet1-lan-ingressroute.yaml` that references `namespace: traefik` must be changed to `tls: {}` until the TLSOption + `device-ca-public` secret are mirrored into each app namespace (per frigate pattern). Confirmed broken in monitoring, gitea, argocd — fixed in spec 064.
- **Hairpin NAT — forwardAuth URL must use in-cluster service**: Traefik's `forwardAuth` middleware makes a server-side HTTP call to the Authentik outpost endpoint. This URL must use the Authentik outpost's in-cluster service address (`http://authentik-server.authentik.svc.cluster.local/outpost.goauthentik.io/auth/traefik`), NOT `https://authentik.fleet1.lan/...`. Pods cannot reach the node IP on port 443 from inside the cluster (hairpin NAT). Confirmed in spec 064 for Grafana token exchange and Gitea OIDC discovery.
- **RWO PVC rolling update deadlock**: Services with ReadWriteOnce Longhorn PVCs stall on Helm upgrade if the new pod lands on a different node than the old pod. Pre-scale to 0 before running `helm upgrade` / Ansible playbook on any single-replica Deployment with a RWO PVC (confirmed: Grafana, Gitea).

## Assumptions (revalidate)

- Spec 063 (Authentik IdP) has shipped and is stable. ✅
- Spec 059 (Tailscale) has shipped — Tailscale deployed, connects to edge device for remote break-glass. ✅
- All Tier 1b apps are reachable on `*.fleet1.lan` hostnames sharing the cookie-domain parent.
- Single-replica embedded outpost is acceptable; outage is mitigated by Tier 0 apps remaining on native auth.
- "Any authenticated user" gating is sufficient; per-app group gating is a future change if multi-user emerges.
- Native auth (where it exists, e.g., Frigate) is disabled on Tier 1b apps to avoid two auth surfaces — revalidate per-app.
- Forward-auth is incrementally rolled out one PR per app: Prometheus → Alertmanager → Traefik dashboard → Loki UI → Node-RED.
