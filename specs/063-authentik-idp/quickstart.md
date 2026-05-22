# Quickstart: Authentik IdP Standup (063)

**Branch**: `063-authentik-idp` | **Date**: 2026-05-22

Integration scenarios and acceptance tests for each user story.

---

## US1 — Working IdP with MFA (P1)

**Goal**: Authentik is reachable at `https://authentik.fleet1.lan`, admin account exists, TOTP is enrolled.

### Setup
1. ArgoCD has synced `authentik-prereqs` and `authentik` (both Synced + Healthy)
2. Pod `authentik-server-*` and `authentik-worker-*` are Running
3. Pod `authentik-postgresql-0` is Running

### Scenario 1: First-run setup wizard
1. Navigate to `https://authentik.fleet1.lan`
2. You should be redirected to the initial setup wizard (only appears before any admin account exists)
3. Set the `akadmin` password — store immediately in Vaultwarden
4. **Verify**: Authentik admin dashboard loads after login

### Scenario 2: TOTP enrollment
1. Log in as `akadmin`
2. Click gear icon → Settings → MFA Devices → Enroll → TOTP Authenticator
3. Scan QR code with authenticator app; enter 6-digit code to confirm
4. **Verify**: MFA Devices list shows one active TOTP device
5. Log out and log back in — Authentik should prompt for TOTP on second factor
6. **Store TOTP seed** in Vaultwarden under `Authentik Admin — TOTP Seed`

### Scenario 3: MFA required on login
1. Log out of Authentik
2. Log in with username + password
3. **Verify**: Authentik prompts for TOTP code as second factor
4. Enter correct code — admin dashboard loads

---

## US2 — Prometheus Observability (P2)

**Goal**: Authentik metrics are being scraped by Prometheus; no missing scrape targets.

### Scenario 1: ServiceMonitor exists
```bash
kubectl --context=default get servicemonitor -n authentik
# Expected: authentik-server and authentik-worker ServiceMonitors
```

### Scenario 2: Prometheus scraping
1. Navigate to `https://prometheus.fleet1.lan`
2. Go to Status → Targets
3. **Verify**: Two `authentik` targets are shown as UP (one for server, one for worker)

### Scenario 3: Sample metrics
1. In Prometheus, query `authentik_policies_count`
2. **Verify**: Returns a value (any non-error result confirms Authentik is exporting metrics)

---

## US3 — Blueprint Export (P3)

**Goal**: Authentik configuration can be exported as a YAML blueprint for disaster recovery.

### Scenario 1: Export blueprint
```bash
kubectl --context=default exec -n authentik deployment/authentik-worker -- ak export_blueprint \
  > specs/063-authentik-idp/blueprint-backup.yaml
```
**Verify**: `blueprint-backup.yaml` is created and contains valid YAML with Authentik flow definitions.

### Scenario 2: Backup is non-empty and parseable
```bash
python3 -c "import yaml; data = yaml.safe_load(open('specs/063-authentik-idp/blueprint-backup.yaml')); print('OK —', len(data.get('entries', [])), 'entries')"
# Expected: OK — N entries (where N > 0)
```

---

## Cluster Commands Reference

```bash
# Watch ArgoCD sync status
kubectl --context=default get applications -n argocd authentik authentik-prereqs

# Check all pods
kubectl --context=default get pods -n authentik

# Check PVCs
kubectl --context=default get pvc -n authentik

# View server logs
kubectl --context=default logs -n authentik deployment/authentik-server --tail=50

# View worker logs
kubectl --context=default logs -n authentik deployment/authentik-worker --tail=50

# Apply multi-source app directly
kubectl --context=default apply -f manifests/authentik/apps/authentik-app.yaml
```
