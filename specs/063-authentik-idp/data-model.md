# Data Model: Authentik IdP Standup (063)

**Branch**: `063-authentik-idp` | **Date**: 2026-05-22

This document inventories every Kubernetes resource created or modified by this spec.

---

## Kubernetes Resources

### Namespace

| Resource | Name | Namespace | Notes |
|----------|------|-----------|-------|
| Namespace | `authentik` | — | Sync wave 0 |

---

### Secrets (SealedSecret → K8s Secret)

| SealedSecret | K8s Secret Name | Namespace | Keys | Wave |
|---|---|---|---|---|
| `authentik-secrets` | `authentik-secrets` | `authentik` | `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_POSTGRESQL__PASSWORD`, `password`, `postgres-password` | 1 |

**Key name rationale** (confirmed by T001 chart template inspection):
- `AUTHENTIK_SECRET_KEY` — env var name consumed via `envFrom` when `authentik.existingSecret.secretName` is set
- `AUTHENTIK_POSTGRESQL__PASSWORD` — env var name (nested yaml → double-underscore env var), same value as `password`
- `password` — bitnami PostgreSQL subchart convention for app user password (used by `postgresql.auth.existingSecret`)
- `postgres-password` — bitnami PostgreSQL subchart convention for superuser password (used by `postgresql.auth.existingSecret`)

**Single secret, two consumers**: `authentik.existingSecret.secretName: authentik-secrets` and `postgresql.auth.existingSecret: authentik-secrets` both reference the same SealedSecret.

---

### Ingress

| Resource | Name | Namespace | Host | Service | Port | TLS | Wave |
|----------|------|-----------|------|---------|------|-----|------|
| IngressRoute | `authentik` | `authentik` | `authentik.fleet1.lan` | `authentik` | 80 | `{}` (wildcard, no device-mTLS) | 2 |

**No device-mTLS**: Authentik is the identity provider — placing it behind its own auth middleware is a circular dependency. Uses `tls: {}` (same pattern as Vaultwarden).

---

### ArgoCD Applications

| Application | Type | Target Path | Namespace | Notes |
|---|---|---|---|---|
| `authentik-prereqs` | Single-source | `manifests/authentik/prereqs/` | `authentik` | Registered in `argocd_apps` |
| `authentik` | Multi-source | chart + `manifests/authentik/authentik-values.yaml` | `authentik` | `kubectl apply` directly (multi-source) |

---

### Helm-managed Resources (deployed by ArgoCD via chart)

| Resource | Kind | Name | Namespace | Notes |
|----------|------|------|-----------|-------|
| Deployment | Deployment | `authentik-server` | `authentik` | HTTP port 9000, metrics port 9300 |
| Deployment | Deployment | `authentik-worker` | `authentik` | Background task processor |
| StatefulSet | StatefulSet | `authentik-postgresql` | `authentik` | Bitnami PostgreSQL subchart |
| PVC | PersistentVolumeClaim | `data-authentik-postgresql-0` | `authentik` | 10Gi, storageClass: longhorn |
| Service | Service | `authentik` | `authentik` | Port 80 → 9000 |
| ServiceMonitor | ServiceMonitor | `authentik-server` | `authentik` | kube-prometheus-stack scrape |
| ServiceMonitor | ServiceMonitor | `authentik-worker` | `authentik` | kube-prometheus-stack scrape |

---

### DNS

| Hostname | Record Type | Target | Registered In |
|----------|-------------|--------|---------------|
| `authentik.fleet1.lan` | A | `10.1.20.11` (Traefik) | OPNsense Unbound via `network-deploy.yml` |

---

### Longhorn Backup Labels (label-pvcs.yml)

| PVC | Namespace | Tier | Notes |
|-----|-----------|------|-------|
| `data-authentik-postgresql-0` | `authentik` | A | Source-of-truth user/flow/config data |

No Valkey/Redis PVC — Authentik 2026.5.0 uses `django-postgres-cache` (PostgreSQL-backed caching). No separate cache service needed.

---

## Manifest Layout

```text
manifests/authentik/
├── prereqs/
│   ├── namespace.yaml          ← Namespace, sync wave 0
│   ├── sealed-secrets.yaml     ← SealedSecret authentik-secrets, sync wave 1
│   └── ingress-route.yaml      ← IngressRoute authentik.fleet1.lan, sync wave 2
├── apps/
│   └── authentik-app.yaml      ← Multi-source ArgoCD Application
└── authentik-values.yaml       ← Helm values (no secret values)
```

---

## Values File Key Decisions

| Key | Value | Rationale |
|-----|-------|-----------|
| `authentik.existingSecret.secretName` | `authentik-secrets` | Injects AUTHENTIK_SECRET_KEY and AUTHENTIK_POSTGRESQL__PASSWORD via envFrom |
| `postgresql.enabled` | `true` | Use bundled bitnami PostgreSQL |
| `postgresql.auth.existingSecret` | `authentik-secrets` | Postgres passwords from SealedSecret (keys: `password`, `postgres-password`) |
| `postgresql.auth.username` | `authentik` | App DB user |
| `postgresql.auth.database` | `authentik` | App DB name |
| `postgresql.primary.persistence.storageClass` | `longhorn` | Constitution Principle VIII |
| `postgresql.primary.persistence.size` | `10Gi` | Single-user, minimal data volume |
| ~~`valkey.*`~~ | N/A | No Valkey/Redis subchart — cache is PostgreSQL-backed in 2026.5.0 |
| `server.metrics.serviceMonitor.enabled` | `true` | Prometheus integration |
| `worker.metrics.serviceMonitor.enabled` | `true` | Prometheus integration |
| `ingress.enabled` | `false` | Using Traefik IngressRoute in prereqs/ instead |

⚠️ **Verify all key paths with `helm show values authentik/authentik --version 2026.5.0` in T001** — particularly `valkey.*` keys and `authentik.existingSecret` key names.
