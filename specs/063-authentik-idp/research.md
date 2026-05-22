# Research: Authentik IdP Standup (063)

**Branch**: `063-authentik-idp` | **Date**: 2026-05-22

---

## R1 — Helm Chart Version

**Decision**: Pin to chart version `2026.5.0` (Authentik application version `2026.5.0`)  
**Rationale**: Latest stable release as of 2026-05-22. Authentik uses calendar versioning aligned to the app version.  
**Source**: https://github.com/goauthentik/helm/releases  
**Action**: Run `helm repo add authentik https://charts.goauthentik.io && helm repo update && helm search repo authentik/authentik` to confirm. Pin both `targetRevision` (chart) and `image.tag` in values.

---

## R2 — PostgreSQL Bundled Subchart

**Decision**: Use bundled bitnami/postgresql subchart (`postgresql.enabled: true`)  
**Rationale**: Single Helm release is simpler; external PostgreSQL adds operational overhead for a single-user homelab.  
**Storage keys**:
- `postgresql.enabled: true`
- `postgresql.primary.persistence.enabled: true`
- `postgresql.primary.persistence.storageClass: longhorn`
- `postgresql.primary.persistence.size: 10Gi`
- `postgresql.auth.username: authentik`
- `postgresql.auth.database: authentik`
- `postgresql.auth.existingSecret: authentik-secrets` (key: `postgresql-password`)

**PVC name convention**: bitnami StatefulSet generates `data-authentik-postgresql-0` — this is the name to use in `label-pvcs.yml` Tier A.

**Verification needed**: Confirm `postgresql.primary.persistence.*` keys with `helm show values authentik/authentik --version 2026.5.0` before writing values file (T001).

---

## R3 — No Redis/Valkey Required (2026.5.0)

**Decision**: No Redis/Valkey subchart needed — Authentik 2026.5.0 uses `django-postgres-cache` (PostgreSQL-backed caching)  
**Rationale**: T001 Helm chart inspection confirmed Chart.yaml has only `postgresql` and `authentik-remote-cluster` as dependencies — no Redis or Valkey subchart. Authentik migrated from Redis to PostgreSQL-based caching (via `packages/django-postgres-cache`) in the 2026.x series. The values.yaml contains no `redis.*` or `valkey.*` keys whatsoever.  
**Impact**: Removes one StatefulSet, one PVC, and all valkey.* Helm values from the plan. Only one storage component: the PostgreSQL PVC.  
**Source**: `curl https://raw.githubusercontent.com/goauthentik/helm/authentik-2026.5.0/charts/authentik/Chart.yaml` + 2026.5 release notes (`packages/django-postgres-cache: rework to use ORM`)

---

## R4 — Authentik SECRET_KEY

**Decision**: Generate with `openssl rand -base64 60 | tr -d '\n'`, store in SealedSecret  
**Rationale**: base64 60-byte key; Authentik documentation warns against hex format and embedded newlines.  
**Critical**: Must never change after first deploy (invalidates sessions and cookie signatures).  
**Helm values key**: `authentik.existingSecret.secretName: "authentik-secrets"` (NOT `authentik.existingSecret: "..."`)  
**How it works**: When `existingSecret.secretName` is set, the server/worker Deployment uses `envFrom: secretRef: name: <secretName>`. The Secret's data keys ARE the env var names. The Secret must contain: `AUTHENTIK_SECRET_KEY` (the Django SECRET_KEY).  
**Confirmed by T001**: `helm show values` inspection of `_helpers.tpl` and `secret.yaml` templates confirms the env var naming convention — nested `authentik.postgresql.password` becomes `AUTHENTIK_POSTGRESQL__PASSWORD`.

---

## R5 — Bootstrap Admin Password

**Decision**: No Helm values bootstrap — set via Authentik's first-run web UI  
**Rationale**: The Helm chart does not expose an initial admin password field. Initial `akadmin` account setup happens through the browser wizard on first access.  
**Procedure**: Navigate to `https://authentik.fleet1.lan` after deploy, complete the setup wizard to set the `akadmin` password. Store the password in Vaultwarden (`vault.fleet1.lan`) immediately after.

---

## R6 — Outpost Configuration

**Decision**: Outpost is NOT deployed by the Helm chart — it is configured via the Authentik UI in spec 064/065  
**Rationale**: The chart deploys the Authentik server and worker only. Outposts (proxy, LDAP) are created in the Admin UI and Authentik generates deployment manifests for them. This is deferred to spec 064 (OIDC apps) and spec 065 (forward auth).  
**Helm key**: `authentik.outposts.container_image_base` — leave at default.

---

## R7 — IngressRoute Pattern

**Decision**: Standard HTTPS IngressRoute with `tls: {}` — no device-mTLS, no middlewares  
**Rationale**: Authentik IS the identity provider; it cannot be placed behind its own auth middleware. No device-mTLS for the same reason as Vaultwarden — circular dependency. The `/outpost.goauthentik.io/` PathPrefix rule is only needed when Authentik is acting as forward auth for other services (spec 064/065); for spec 063 (deploy only) a simple Host rule suffices.  
**Service port**: Authentik server service typically exposes port 80 (internally proxied to 9000). Verify with `kubectl get svc -n authentik` post-deploy.  
**DNS**: Add `- hostname: authentik` to `fleet1_lan_traefik_dns_records` in `network-deploy.yml`.

---

## R8 — Prometheus ServiceMonitor

**Decision**: Enable ServiceMonitor for both server and worker components  
**Rationale**: Spec requires observability wiring; kube-prometheus-stack is already deployed with ServiceMonitor CRD.  
**Helm values**:
```yaml
server:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      interval: 30s
      labels:
        release: prometheus

worker:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
      interval: 30s
      labels:
        release: prometheus
```

---

## R9 — TOTP MFA Enrollment Procedure

**Decision**: Self-enroll via Authentik user portal (not admin UI)  
**Step sequence**:
1. Log in as `akadmin` at `https://authentik.fleet1.lan`
2. Click the **cog/gear icon** (upper right) → Settings
3. Navigate to **MFA Devices**
4. Click **Enroll** → select **TOTP Authenticator**
5. Scan QR code with authenticator app (or manually enter secret)
6. Enter the 6-digit code to confirm
7. **Save the TOTP seed (base32 secret) in Vaultwarden** under `Authentik Admin — TOTP Seed`

---

## R10 — Blueprint Export Procedure

**Decision**: `kubectl exec` into the Authentik worker pod and run `ak export_blueprint`  
**Command**:
```bash
kubectl --context=default exec -n authentik deployment/authentik-worker -- ak export_blueprint > specs/063-authentik-idp/blueprint-backup.yaml
```
**When to run**: After MFA enrollment and any flow customisation — captures the full Authentik configuration as a YAML blueprint for disaster recovery.  
**Storage**: Commit to `specs/063-authentik-idp/blueprint-backup.yaml` (contains no secrets — blueprints describe flows/policies, not credential data).

---

## R11 — PostgreSQL SealedSecret Keys (REVISED after T001)

**Decision**: SealedSecret `authentik-secrets` in namespace `authentik` with **four** keys:
- `AUTHENTIK_SECRET_KEY` — Authentik Django SECRET_KEY (env var name, used by `authentik.existingSecret.secretName`)
- `AUTHENTIK_POSTGRESQL__PASSWORD` — authentik app's DB user password (env var name, same value as `password`)
- `password` — bitnami PostgreSQL subchart convention for app user password (used by `postgresql.auth.existingSecret`)
- `postgres-password` — bitnami PostgreSQL subchart convention for superuser password (used by `postgresql.auth.existingSecret`)

**Why two password keys**: The authentik server reads `AUTHENTIK_POSTGRESQL__PASSWORD` via `envFrom`. The bitnami postgresql subchart reads `password` from its `auth.existingSecret`. Both must be in the same Secret to share one SealedSecret.

**Single secret, two consumers**:
- `authentik.existingSecret.secretName: authentik-secrets` → picks up `AUTHENTIK_SECRET_KEY` and `AUTHENTIK_POSTGRESQL__PASSWORD`
- `postgresql.auth.existingSecret: authentik-secrets` → picks up `password` and `postgres-password`

**Generation**:
```bash
openssl rand -base64 60 | tr -d '\n'   # → AUTHENTIK_SECRET_KEY (authentik_secret_key in group_vars)
openssl rand -hex 24                    # → AUTHENTIK_POSTGRESQL__PASSWORD + password (authentik_db_password)
openssl rand -hex 24                    # → postgres-password (authentik_db_superuser_password)
```
Add all three to `group_vars/all.yml` under `authentik_secret_key`, `authentik_db_password`, `authentik_db_superuser_password`.  
Extend `playbooks/utilities/seal-secrets.yml` with a `vaultwarden`-style block tagged `authentik`.

---

## R12 — Longhorn Backup Labeling

**PVCs to add to Tier A** in `label-pvcs.yml`:
- `data-authentik-postgresql-0` in namespace `authentik` (source-of-truth user/flow data)

**No Valkey PVC**: Confirmed by T001 — Authentik 2026.5.0 uses django-postgres-cache; no Redis/Valkey subchart exists. Only one PVC to back up.  
**Add after deploy** (PVC names confirmed by `kubectl get pvc -n authentik`).
