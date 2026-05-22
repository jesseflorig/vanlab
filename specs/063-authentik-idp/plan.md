# Implementation Plan: Authentik IdP Standup

**Branch**: `063-authentik-idp` | **Date**: 2026-05-22 | **Spec**: specs/063-authentik-idp/spec.md  
**Input**: Feature specification from `/specs/063-authentik-idp/spec.md`

## Summary

Deploy Authentik as the cluster's internal SSO identity provider, accessible at `https://authentik.fleet1.lan`. Helm chart `goauthentik/authentik` v2026.5.0 deployed via multi-source ArgoCD Application. Bundled bitnami/postgresql on a Longhorn-backed 10Gi PVC stores flows, users, and policies. Bundled Valkey (Redis replacement) on a 1Gi Longhorn PVC provides caching. Admin secrets (SECRET_KEY, DB passwords) injected via SealedSecret. TOTP MFA enrolled manually post-deploy. Prometheus ServiceMonitors enabled for both server and worker. Blueprint exported to Git for disaster recovery. No app integration in this spec — outpost and forward-auth wiring is deferred to specs 064/065.

## Technical Context

**Language/Version**: YAML (Kubernetes manifests + Helm values)  
**Primary Dependencies**: goauthentik/authentik Helm chart v2026.5.0; bitnami/postgresql (bundled subchart); bitnami/valkey (bundled subchart); Traefik v3 (existing); cert-manager wildcard cert (spec 054, existing); Longhorn v1.11.1 (existing); Sealed Secrets controller (existing); ArgoCD (existing)  
**Storage**: Longhorn PVC `data-authentik-postgresql-0` (10Gi, Tier A backup); Longhorn PVC for Valkey master (1Gi, no backup — cache only)  
**Testing**: Manual acceptance tests per quickstart.md  
**Target Platform**: K3s arm64 cluster (`10.1.20.x`)  
**Project Type**: GitOps Helm service deployment  
**Performance Goals**: Single-user homelab — no concurrency requirements  
**Constraints**: arm64 image required; no device-mTLS on IngressRoute (circular dependency); no app integration in this spec  
**Scale/Scope**: 1 admin user, ~5 services to integrate in future specs

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I — Infrastructure as Code | ✅ PASS | All resources in manifests/, deployed via ArgoCD |
| II — Idempotency | ✅ PASS | Helm chart is idempotent; ArgoCD selfHeal ensures convergence |
| III — Reproducibility | ✅ PASS | Chart version pinned; sealed-secrets.yml generates SealedSecret from group_vars |
| IV — Secrets Hygiene | ✅ PASS | SECRET_KEY and DB passwords via SealedSecret `authentik-secrets`; never in values file |
| V — Simplicity | ✅ PASS | Official Helm chart with bundled subcharts; no custom manifests beyond prereqs/ pattern |
| VI — Encryption in Transit | ✅ PASS | HTTPS via Traefik wildcard cert; internal service traffic stays in-cluster |
| VII — Least Privilege | ✅ N/A | No MQTT/camera VLAN interaction |
| VIII — Persistent Storage | ✅ PASS | Longhorn storageClass explicit in values; PVC size explicit |
| IX — Secure Service Exposure | ✅ PASS | HTTPS only via Traefik IngressRoute; wildcard cert; HTTP not exposed |
| X — Intra-Cluster Locality | ✅ PASS | `authentik.fleet1.lan` resolves internally via OPNsense Unbound; no public tunnel |
| XI — GitOps Application Deployment | ✅ PASS | Multi-source ArgoCD Application; prereqs/ pattern; Ansible not used for Helm |

**No device-mTLS justification**: Authentik is the identity provider itself. Placing it behind its own forward-auth middleware is a circular dependency — users cannot authenticate to reach the service that authenticates them. Uses `tls: {}` (same reasoning as Vaultwarden in spec 066). This exception is intentional and documented.

## Project Structure

### Documentation (this feature)

```text
specs/063-authentik-idp/
├── plan.md              ← This file
├── research.md          ← Phase 0 output
├── data-model.md        ← Phase 1 output
├── quickstart.md        ← Phase 1 output
└── tasks.md             ← Phase 2 output (/speckit.tasks)
```

### Source Code (repository)

```text
manifests/authentik/
├── prereqs/
│   ├── namespace.yaml          ← Namespace, sync wave 0
│   ├── sealed-secrets.yaml     ← SealedSecret authentik-secrets, sync wave 1
│   └── ingress-route.yaml      ← IngressRoute authentik.fleet1.lan, sync wave 2
├── apps/
│   └── authentik-app.yaml      ← Multi-source ArgoCD Application
└── authentik-values.yaml       ← Helm values (no secret values; secrets via SealedSecret)

group_vars/example.all.yml      ← Add authentik_secret_key, authentik_db_password,
                                   authentik_db_superuser_password placeholders
group_vars/all.yml              ← Add generated values (untracked)
playbooks/utilities/
└── seal-secrets.yml            ← Extend with authentik play block (tag: authentik)
playbooks/network/
└── network-deploy.yml          ← Add hostname: authentik to fleet1_lan_traefik_dns_records
playbooks/utilities/
└── label-pvcs.yml              ← Add data-authentik-postgresql-0 to Tier A
```

## Key Implementation Decisions

### 1. existingSecret wiring
Authentik server reads `SECRET_KEY` from env var `AUTHENTIK_SECRET_KEY`. The Helm chart's `authentik.existingSecret` field references a K8s Secret; that Secret (produced by unsealing `authentik-secrets`) must contain key `authentik.secret_key`.  
**Verify** exact key name expected: `helm show values authentik/authentik --version 2026.5.0 | grep -A10 existingSecret` (T001).

### 2. Multi-source Application
Like minio and vaultwarden, the Authentik app is multi-source (Helm chart + Gitea values file). It cannot be registered in `argocd_apps` and must be applied via `kubectl apply -f manifests/authentik/apps/authentik-app.yaml`.

### 3. First-run wizard
The initial `akadmin` password is NOT set via Helm values — it is set through Authentik's first-run browser wizard on first access. This is a manual step (T018) that cannot be automated without direct DB manipulation.

### 4. Valkey key names
The chart 2026.5.0 uses Valkey (not Redis). Key paths under `valkey.*` must be verified against the actual chart values in T001, as the agent found no Redis keys and Valkey became the default in 2024.8.

### 5. Outpost deferred
Proxy outpost configuration, OIDC application setup, and forward-auth IngressRoute wiring are all deferred to specs 064 and 065. The `/outpost.goauthentik.io/` path rule is NOT added to the IngressRoute in this spec.

## Complexity Tracking

No Constitution violations. No complexity justification required.
