# Tasks: Authentik IdP Standup (063)

**Input**: Design documents from `/specs/063-authentik-idp/`
**Branch**: `063-authentik-idp`
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅ quickstart.md ✅

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Verify chart values, generate secrets, create directory skeleton — must be in place before any manifest is written.

- [X] T001 Verify Helm values key paths against pinned chart version: run `helm repo add authentik https://charts.goauthentik.io && helm repo update && helm search repo authentik/authentik` then `helm show values authentik/authentik --version 2026.5.0` — confirm exact keys for `authentik.existingSecret`, `valkey.*` vs `redis.*`, `postgresql.primary.persistence.*`, `server.metrics.serviceMonitor.*`, and the service name/port created by the chart — record findings in `specs/063-authentik-idp/research.md` under R1 and update data-model.md if any key names differ
- [X] T002 [P] Create manifest directory skeleton: `manifests/authentik/prereqs/` and `manifests/authentik/apps/`
- [X] T003 [P] Add authentik secret placeholders to `group_vars/example.all.yml`: `authentik_secret_key: CHANGEME`, `authentik_db_password: CHANGEME`, `authentik_db_superuser_password: CHANGEME` — follows existing pattern for other service secrets
- [X] T004 Generate secrets and add to `group_vars/all.yml`: run `openssl rand -base64 60 | tr -d '\n'` for `authentik_secret_key`, `openssl rand -hex 24` for `authentik_db_password`, `openssl rand -hex 24` for `authentik_db_superuser_password` (untracked file, never committed)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Namespace, SealedSecret, DNS, IngressRoute, and ArgoCD prereqs Application — must be complete before the Helm app can deploy.

⚠️ **CRITICAL**: No Helm app sync can succeed until namespace and SealedSecret exist in-cluster.

- [X] T005 [P] Create `manifests/authentik/prereqs/namespace.yaml` — Namespace `authentik`, sync wave 0, labels `app.kubernetes.io/name: authentik` and `argocd.argoproj.io/instance: authentik-prereqs`
- [X] T006 Extend `playbooks/utilities/seal-secrets.yml` with a new play block for `authentik-secrets` Secret in namespace `authentik` with keys `authentik.secret_key` from `{{ authentik_secret_key }}`, `postgresql-password` from `{{ authentik_db_password }}`, and `postgres-password` from `{{ authentik_db_superuser_password }}` — follow the identical pattern used for `vaultwarden-admin-token`; tag: `authentik`; output file: `manifests/authentik/prereqs/sealed-secrets.yaml`
- [X] T007 Run `ansible-playbook playbooks/utilities/seal-secrets.yml --tags authentik -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"` to generate `manifests/authentik/prereqs/sealed-secrets.yaml` — verify the file is created and contains a valid SealedSecret with sync-wave annotation `"1"` and all three keys encrypted
- [X] T008 [P] Add `- hostname: authentik` to the `fleet1_lan_traefik_dns_records` list in `playbooks/network/network-deploy.yml` — follows the same pattern as `vault`, `argocd`, `minio`, etc.
- [X] T009 Run `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"` to register `authentik.fleet1.lan` in OPNsense Unbound — verify with `nslookup authentik.fleet1.lan 10.1.1.1`
- [X] T010 [P] Create `manifests/authentik/prereqs/ingress-route.yaml` — Traefik IngressRoute for `authentik.fleet1.lan`, entrypoint `websecure`, standard TLS (`tls: {}` — no device-mTLS per research.md R7), routing to service `authentik-server` port 80 (verify service name from T001), sync wave 2
- [X] T011 Register `authentik-prereqs` in `group_vars/all.yml` under `argocd_apps` targeting `manifests/authentik/prereqs/`, namespace `authentik`, revision `main` — add a comment noting the multi-source `authentik` app must be applied directly via `kubectl apply`

**Checkpoint**: Namespace exists, SealedSecret sealed and committed, DNS resolves, prereqs Application registered — Helm app sync can now proceed.

---

## Phase 3: User Story 1 — Working IdP with MFA Enrolled (Priority: P1) 🎯 MVP

**Goal**: Authentik is running at `https://authentik.fleet1.lan`; `akadmin` account created via setup wizard; TOTP MFA enrolled; credentials stored in Vaultwarden.

**Independent Test**: Navigate to `https://authentik.fleet1.lan` — see the Authentik login page. Log in as `akadmin` with password + TOTP code. Confirm the admin dashboard loads. Log out and confirm TOTP is required again on re-login.

- [X] T012 [US1] Create `manifests/authentik/authentik-values.yaml` — using T001-verified key paths: `authentik.existingSecret: authentik-secrets`, `postgresql.enabled: true`, `postgresql.auth.existingSecret: authentik-secrets`, `postgresql.auth.username: authentik`, `postgresql.auth.database: authentik`, `postgresql.primary.persistence.enabled: true`, `postgresql.primary.persistence.storageClass: longhorn`, `postgresql.primary.persistence.size: 10Gi`, valkey persistence keys (from T001), `server.metrics.enabled: true`, `server.metrics.serviceMonitor.enabled: true`, `server.metrics.serviceMonitor.labels.release: prometheus`, `worker.metrics.enabled: true`, `worker.metrics.serviceMonitor.enabled: true`, `worker.metrics.serviceMonitor.labels.release: prometheus`, `ingress.enabled: false`
- [X] T013 [US1] Create `manifests/authentik/apps/authentik-app.yaml` — multi-source ArgoCD Application: source 1 is `authentik/authentik` chart at pinned version from T001, source 2 is Gitea repo supplying `manifests/authentik/authentik-values.yaml`; destination namespace `authentik`; `automated.prune: true`, `automated.selfHeal: true`, `retry.limit: 5` with exponential backoff — follow the `vaultwarden-app.yaml` pattern exactly; add comment that this must be applied directly via `kubectl apply`
- [ ] T014 [US1] Commit all files (namespace, ingress-route, sealed-secrets, values, app manifests, network-deploy.yml, example.all.yml, seal-secrets.yml, all.yml argocd_apps entry) and push to Gitea on branch `063-authentik-idp`, then merge PR to `main` and update GitHub mirror
- [ ] T015 [US1] Bootstrap ArgoCD Applications: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"` — confirms `authentik-prereqs` is applied
- [ ] T016 [US1] Apply multi-source Authentik app: `kubectl --context=default apply -f manifests/authentik/apps/authentik-app.yaml` — then trigger sync: `kubectl --context=default patch application authentik -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'`
- [ ] T017 [US1] Wait for all pods to reach Running/Ready: `kubectl --context=default get pods -n authentik` — confirm `authentik-server-*`, `authentik-worker-*`, and `authentik-postgresql-0` are all `1/1 Running`; confirm PVCs are `Bound` on `longhorn`
- [ ] T018 [US1] Complete Authentik first-run setup wizard: navigate to `https://authentik.fleet1.lan`, set `akadmin` password — **immediately store password in Vaultwarden** under a new `Authentik Admin — Password` Login item at `https://authentik.fleet1.lan`
- [ ] T019 [US1] Enroll TOTP MFA: log in as `akadmin` → gear icon → Settings → MFA Devices → Enroll → TOTP Authenticator → scan QR code → enter 6-digit code to confirm — **store TOTP seed in Vaultwarden** by updating the `Authentik Admin — TOTP Seed` placeholder entry with the actual base32 secret; also update `Authentik Admin — Recovery Codes` placeholder with any recovery codes Authentik generates

**Checkpoint**: `https://authentik.fleet1.lan` loads, akadmin login requires password + TOTP, credentials in Vaultwarden.

---

## Phase 4: User Story 2 — Prometheus Observability (Priority: P2)

**Goal**: Authentik metrics scraped by Prometheus; both server and worker ServiceMonitors showing UP.

**Independent Test**: In Prometheus UI (`https://prometheus.fleet1.lan` → Status → Targets) confirm two Authentik scrape targets are green. Query `authentik_policies_count` returns a value.

- [ ] T020 [US2] Verify ServiceMonitors exist: `kubectl --context=default get servicemonitor -n authentik` — confirm both `authentik-server` and `authentik-worker` ServiceMonitors are present; if missing, check `server.metrics.serviceMonitor.enabled` in values and re-sync
- [ ] T021 [US2] Verify Prometheus is scraping: navigate to `https://prometheus.fleet1.lan` → Status → Targets → search for `authentik` — confirm both targets show `State: UP`
- [ ] T022 [US2] Verify metric export: in Prometheus query `authentik_policies_count` — confirm the query returns a non-error result (any numeric value confirms Authentik is exporting metrics correctly)

**Checkpoint**: Both Authentik scrape targets UP in Prometheus; metric queries return values.

---

## Phase 5: User Story 3 — Blueprint Export (Priority: P3)

**Goal**: Authentik configuration can be exported as a YAML blueprint; file committed to Git for disaster recovery.

**Independent Test**: `blueprint-backup.yaml` exists in `specs/063-authentik-idp/`, is valid YAML, and contains at least one entry.

- [ ] T023 [US3] Export blueprint from Authentik worker pod: `kubectl --context=default exec -n authentik deployment/authentik-worker -- ak export_blueprint > specs/063-authentik-idp/blueprint-backup.yaml` — verify file is created and non-empty
- [ ] T024 [US3] Validate blueprint is parseable: `python3 -c "import yaml; d=yaml.safe_load(open('specs/063-authentik-idp/blueprint-backup.yaml')); print('OK —', len(d.get('entries',[])), 'entries')"` — confirm output is `OK — N entries` where N > 0
- [ ] T025 [US3] Commit blueprint to Git on a new branch, PR to `main`: `git add specs/063-authentik-idp/blueprint-backup.yaml` — the blueprint contains no secret values (it describes flows/policies only) so it is safe to commit

**Checkpoint**: Blueprint in Git; Authentik configuration is recoverable from Git + Longhorn backup.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T026 Add Authentik PostgreSQL PVC to Longhorn Tier A backup label list in `playbooks/utilities/label-pvcs.yml`: add `{ name: data-authentik-postgresql-0, namespace: authentik }` to the named PVC loop — also update the header comment to include Authentik; re-run playbook after confirming PVC name with `kubectl --context=default get pvc -n authentik`
- [ ] T027 Update `specs/063-authentik-idp/spec.md` status field from `Clarified — ready for /speckit.plan` to `Deployed`
- [ ] T028 Update `playbooks/utilities/label-pvcs.yml` header comment: change "When spec 063 (Authentik) deploys, add its Postgres PVC to Tier A" note to "✅ spec 063 deployed — `data-authentik-postgresql-0` added"

---

## Dependencies

```
T001 → T012 (verified key paths needed before writing values file)
T002 → T005, T010, T013 (directories must exist)
T003, T004 → T006 (example.all.yml and all.yml needed before sealing)
T006 → T007 (playbook extension before running)
T007 → T014 (sealed-secrets.yaml must exist before commit)
T005, T008, T010, T011 → T014 (all prereq manifests before commit)
T009 → T015 (DNS must resolve before ArgoCD sync)
T012, T013 → T014 (all manifests before commit)
T014 → T015 (push to Gitea before ArgoCD bootstrap)
T015 → T016 (prereqs must be applied before Helm app)
T016 → T017 (app synced before pods can run)
T017 → T018 (pods running before setup wizard)
T018 → T019 (akadmin account must exist before MFA enrollment)
T019 → T020 (deployment complete before observability verification)
T019 → T023 (Authentik running before blueprint export)
T026 → T027 → T028 (polish in order)
```

## Parallel Opportunities

**Phase 1** (T002, T003 can run in parallel with T001 lookup):
- T002 (create directories) and T003 (example.all.yml) are independent of T001 and each other

**Phase 2** (T005, T008, T010 can be written in parallel after T001):
- Namespace, DNS entry, and IngressRoute are in different files with no cross-dependencies
- T006 (seal-secrets extension) is independent of T005/T008/T010

**Phase 3** (T012 and T013 can be written in parallel after T001):
- Values file and ArgoCD Application manifest are in different files

## Implementation Strategy

**MVP = Phase 1 + Phase 2 + Phase 3 (T001–T019)**

This delivers a working Authentik instance with an enrolled admin account — sufficient for specs 064 (OIDC apps) and 065 (forward auth) to proceed.

Phases 4–6 are observability, backup, and polish; they don't block 064/065 but should be completed before closing this spec.
