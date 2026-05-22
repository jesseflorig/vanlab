# Tasks: Vaultwarden Password Vault (066)

**Input**: Design documents from `/specs/066-vaultwarden-vault/`
**Branch**: `066-vaultwarden-vault`
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Manifest skeleton, secrets groundwork, DNS — must be in place before ArgoCD sync.

- [x] T001 Look up current stable guerzon/vaultwarden chart version and Vaultwarden image tag: run `helm repo add vaultwarden https://guerzon.github.io/vaultwarden && helm repo update && helm search repo vaultwarden/vaultwarden` and check https://github.com/dani-garcia/vaultwarden/releases — record pinned versions in `specs/066-vaultwarden-vault/research.md` under R1 and R2
- [x] T002 [P] Create manifest directory skeleton: `manifests/vaultwarden/prereqs/` and `manifests/vaultwarden/apps/`
- [x] T003 [P] Add `vaultwarden_admin_token` placeholder to `group_vars/example.all.yml` (value: `CHANGEME`) — follows existing pattern for other service secrets
- [x] T004 Generate admin token and add to `group_vars/all.yml`: run `openssl rand -hex 32` and add `vaultwarden_admin_token: <result>` (untracked file, never committed)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Namespace, SealedSecret, DNS, and ArgoCD prereqs Application — must be complete before the Helm app can deploy.

⚠️ **CRITICAL**: No Helm app sync can succeed until namespace and SealedSecret exist in-cluster.

- [x] T005 Create `manifests/vaultwarden/prereqs/namespace.yaml` — Namespace `vaultwarden`, sync wave 0, labels `app.kubernetes.io/name: vaultwarden` and `argocd.argoproj.io/instance: vaultwarden-prereqs`
- [x] T006 Extend `playbooks/utilities/seal-secrets.yml` with a new task block for `vaultwarden-admin-token` Secret in namespace `vaultwarden` with key `admin-token` from `{{ vaultwarden_admin_token }}` — follow the identical pattern used for `opnsense-exporter-credentials`; output file: `manifests/vaultwarden/prereqs/sealed-secrets.yaml`
- [x] T007 Run `ansible-playbook playbooks/utilities/seal-secrets.yml` to generate `manifests/vaultwarden/prereqs/sealed-secrets.yaml` — verify the file is created and contains a valid SealedSecret with sync-wave annotation `"1"`
- [x] T008 Add `- hostname: vault` to the `fleet1_lan_traefik_dns_records` list in `playbooks/network/network-deploy.yml` — follows the same pattern as `argocd`, `minio`, `grafana`, etc.
- [x] T009 Run `ansible-playbook -i hosts.ini playbooks/network/network-deploy.yml` to register `vault.fleet1.lan` in OPNsense unbound — verify with `nslookup vault.fleet1.lan 10.1.1.1`
- [x] T010 Create `manifests/vaultwarden/prereqs/ingress-route.yaml` — Traefik IngressRoute for `vault.fleet1.lan`, entrypoint `websecure`, standard TLS (empty `tls: {}` block — no device-mTLS per research.md R3), routing to service `vaultwarden` port 80, sync wave 2
- [x] T011 Create `manifests/argocd/prereqs/` ArgoCD Application for `vaultwarden-prereqs` targeting `manifests/vaultwarden/prereqs/` — follow the established prereqs Application pattern from other services (e.g., `manifests/minio/prereqs/`)

**Checkpoint**: Namespace exists, SealedSecret sealed and committed, DNS resolves, prereqs Application registered — Helm app sync can now proceed.

---

## Phase 3: User Story 2 — Initial Vault Setup and Admin Account Bootstrap (Priority: P2) 🎯 MVP

**Note**: US2 (bootstrap) must precede US1 (recovery access test) in implementation order, even though US1 is the P1 safety property. You cannot test recovery access until the vault exists and has an account.

**Goal**: Working Vaultwarden deployment reachable at `https://vault.fleet1.lan`; admin account created; registrations disabled.

**Independent Test**: Navigate to `https://vault.fleet1.lan` from a LAN-connected or Tailscale-connected device, register one account, store a test item, then confirm a second registration attempt is rejected.

- [x] T012 Verify Helm values key names against the pinned chart version: run `helm show values vaultwarden/vaultwarden --version <pinned>` and confirm `signupsAllowed`, `storage.data.name/size/storageClass`, `adminToken.existingSecret/existingSecretKey`, `ingress.enabled`, `service.port` — update `specs/066-vaultwarden-vault/data-model.md` if any keys differ
- [x] T013 [US2] Create `manifests/vaultwarden/vaultwarden-values.yaml` with `signupsAllowed: true` (temporary for bootstrap), `adminToken.existingSecret: vaultwarden-admin-token`, `adminToken.existingSecretKey: admin-token`, `storage.data.name: vaultwarden-data`, `storage.data.size: 1Gi`, `storage.data.class: longhorn` (note: key is `class` not `storageClass`), `ingress.enabled: false`, image tag pinned per T001
- [x] T014 [US2] Create `manifests/vaultwarden/apps/vaultwarden-app.yaml` — multi-source ArgoCD Application: source 1 is guerzon/vaultwarden chart at pinned version, source 2 is Gitea repo supplying `manifests/vaultwarden/vaultwarden-values.yaml`; destination namespace `vaultwarden`; `automated.prune: true`, `automated.selfHeal: true`, `retry.limit: 5` with exponential backoff — follow the minio-app.yaml pattern exactly
- [x] T015 [US2] Register `vaultwarden-prereqs` in `group_vars/all.yml` under `argocd_apps`; note multi-source `vaultwarden` app must be applied directly via `kubectl apply`
- [x] T016 [US2] Commit all files (namespace, ingress-route, sealed-secrets, values, app manifests, network-deploy.yml, example.all.yml, seal-secrets.yml) and push to Gitea: `git push gitea 066-vaultwarden-vault`
- [x] T017 [US2] Bootstrap ArgoCD Applications: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap` — monitor sync at `https://argocd.fleet1.lan` until `vaultwarden-prereqs` and `vaultwarden` are both `Synced` + `Healthy`
- [x] T018 [US2] Register admin account: navigate to `https://vault.fleet1.lan` and create the single admin account — do this within the `signupsAllowed: true` window before the next step
- [x] T019 [US2] Disable registrations: update `manifests/vaultwarden/vaultwarden-values.yaml` to set `signupsAllowed: false`, commit, push to Gitea — ArgoCD will re-sync; verify a second registration attempt is rejected at `https://vault.fleet1.lan`
- [x] T020 [US2] Store initial recovery items in vault: log in and create entries for Authentik TOTP seed placeholder, recovery code placeholder, and ArgoCD admin password — these will be populated during spec 063

---

## Phase 4: User Story 1 — Access Vault During Authentik Outage (Priority: P1)

**Goal**: Confirm Vaultwarden is reachable and credentials are accessible when Authentik is completely unavailable.

**Independent Test**: Scale Authentik to zero replicas (or skip — Authentik isn't deployed yet), verify `https://vault.fleet1.lan` loads and the admin account is accessible.

- [x] T021 [US1] Verify Vaultwarden independence from Authentik: since Authentik is not yet deployed, confirm no Authentik middleware is on the IngressRoute — run `kubectl --context=default get ingressroute vaultwarden -n vaultwarden -o yaml` and confirm no `middlewares:` block referencing Authentik exists
- [x] T022 [US1] Verify TLS — confirm no device-mTLS: access `https://vault.fleet1.lan` from a browser without a client certificate installed and confirm the login page loads (device-mTLS would return a 400/handshake error)
- [x] T023 [US1] Document Authentik-outage access test in `specs/066-vaultwarden-vault/spec.md` acceptance scenario 1 — mark it as verified with date

---

## Phase 5: User Story 3 — Vault Survives Pod Restart (Priority: P3)

**Goal**: Confirm stored credentials persist across pod deletion and rescheduling.

**Independent Test**: Store a test item, delete the pod, wait for reschedule, confirm item is still present.

- [x] T024 [US3] Store a canary test item in the vault (e.g., "Pod restart test — 2026-05-22") before the restart test
- [x] T025 [US3] Delete the Vaultwarden pod and wait for reschedule: `kubectl --context=default delete pod -n vaultwarden -l app.kubernetes.io/name=vaultwarden` — wait for new pod to reach Running state
- [x] T026 [US3] Log back in to `https://vault.fleet1.lan` and confirm the canary test item is present — delete it after verification
- [x] T027 [US3] Verify Longhorn PVC is bound and healthy: `kubectl --context=default get pvc -n vaultwarden` — confirm `STATUS: Bound` and `STORAGECLASS: longhorn`

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T028 Add Vaultwarden PVC to Longhorn Tier A backup label list in `playbooks/utilities/label-pvcs.yml`: add `{ name: vaultwarden-data, namespace: vaultwarden }` to the loop — re-run after deploy
- [x] T029 Update `specs/063-authentik-idp/spec.md` — change the Vaultwarden hard dependency from "new spec required" to "✅ Spec 066 deployed" and add the `vault.fleet1.lan` URL
- [x] T030 Update spec status: set `specs/066-vaultwarden-vault/spec.md` Status field from `Draft` to `Deployed`

---

## Dependencies

```
T001 → T013 (pinned versions needed for values file)
T002 → T005, T010, T011, T014 (directories must exist)
T003, T004 → T006 (example.all.yml and all.yml needed before sealing)
T006 → T007 (playbook extension before running)
T007 → T016 (sealed-secrets.yaml must exist before commit)
T005, T008, T010 → T016 (all prereq manifests before commit)
T009 → T017 (DNS must resolve before ArgoCD sync completes successfully)
T011, T014, T015 → T016 (all manifests before commit)
T016 → T017 (push to Gitea before ArgoCD can sync)
T017 → T018 (pod must be running before account registration)
T018 → T019 (account must exist before disabling signups)
T019 → T020 (signups disabled before storing items)
T020 → T021, T024 (vault populated before verification phases)
T024 → T025 → T026 (sequential pod restart test)
T020 → T028 (deployment complete before labeling PVC)
T028 → T029 → T030 (polish in order)
```

## Parallel Opportunities

**Phase 1** (T002, T003 can run in parallel with T001 after T004):
- T002 (create directories) and T003 (example.all.yml) are independent of each other and of T001

**Phase 2** (T005, T008, T010 can be written in parallel):
- Namespace, DNS entry, and IngressRoute are in different files with no cross-dependencies
- T006 (seal-secrets extension) is independent of T005/T008/T010

**Phase 3** (T013, T014 can be written in parallel after T012):
- Values file and ArgoCD Application manifest are in different files

## Implementation Strategy

**MVP = Phase 1 + Phase 2 + Phase 3 (T001–T020)**

This delivers a working, accessible Vaultwarden instance with an admin account and signups disabled — sufficient for spec 063 (Authentik) to proceed.

Phases 4–6 are verification and hardening; they don't block 063 but should be completed before closing this spec.
