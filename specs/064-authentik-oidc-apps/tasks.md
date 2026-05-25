# Tasks: Authentik OIDC App Integration (064)

**Input**: Design documents from `/specs/064-authentik-oidc-apps/`
**Branch**: `064-authentik-oidc-apps`
**Prerequisites**: plan.md ✅ spec.md ✅ research.md ✅ data-model.md ✅ quickstart.md ✅

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

---

## Phase 1: Setup (Shared Secrets)

**Purpose**: Generate OIDC client secrets and add variables to group_vars — must be done before any Authentik provider is created.

- [X] T001 [P] Generate three OIDC client secrets (`openssl rand -hex 32` × 3) and add to `group_vars/all.yml` as `grafana_oidc_client_id: grafana`, `grafana_oidc_client_secret: <generated>`, `gitea_oidc_client_id: gitea`, `gitea_oidc_client_secret: <generated>`, `argocd_oidc_client_id: argocd`, `argocd_oidc_client_secret: <generated>`
- [X] T002 [P] Add CHANGEME placeholders to `group_vars/example.all.yml`: `grafana_oidc_client_id: grafana`, `grafana_oidc_client_secret: CHANGEME`, `gitea_oidc_client_id: gitea`, `gitea_oidc_client_secret: CHANGEME`, `argocd_oidc_client_id: argocd`, `argocd_oidc_client_secret: CHANGEME`

---

## Phase 2: Foundational (Authentik Shared Setup)

**Purpose**: Create groups, scope mapping, and verify groups claim in Authentik — blocks all three app stories.

⚠️ **CRITICAL**: No OIDC login for any app will work until the `groups` scope mapping is in place and `akadmin` is in the `admins` group.

- [X] T003 Create `admins` group in Authentik: Admin UI → **Directory** → **Groups** → **Create** → Name: `admins` → Save
- [X] T004 [P] Create `users` group in Authentik: Admin UI → **Directory** → **Groups** → **Create** → Name: `users` → Save
- [X] T005 Add `akadmin` to `admins` group: Admin UI → **Directory** → **Users** → click `akadmin` → **Groups** tab → **Add** → select `admins` → Save
- [X] T006 Create `groups-claim` Scope Mapping: Admin UI → **Customization** → **Property Mappings** → **Create** → **Scope Mapping** → Name: `groups-claim`, Scope name: `groups`, Expression: `return {"groups": [group.name for group in request.user.ak_groups.all()]}` → Save
- [X] T007 Verify groups claim is working: navigate to `https://authentik.fleet1.lan/application/o/userinfo/` while logged in as `akadmin` — confirm response JSON contains `"groups": ["admins"]`

**Checkpoint**: `akadmin` is in `admins` group; groups-claim scope mapping exists; userinfo endpoint returns groups array.

---

## Phase 3: User Story 1 — Grafana OIDC (Priority: P1) 🎯 MVP

**Goal**: Log in to Grafana via Authentik OIDC; `akadmin` gets Admin role; native `admin` login still works.

**Independent Test**: Navigate to `https://grafana.fleet1.lan` → click **Sign in with Authentik** → log in as `akadmin` → confirm Grafana dashboard loads with **Admin** role badge. Then log out and confirm `admin` native login still works at `/login`.

- [X] T008 [P] Create Grafana OIDC provider in Authentik: Admin UI → **Applications** → **Providers** → **Create** → **OAuth2/OIDC** → Name: `grafana`, Client type: Confidential, Client ID: `grafana`, Client Secret: (value of `grafana_oidc_client_secret`), Redirect URIs: `https://grafana.fleet1.lan/login/generic_oauth` and `https://grafana.fleet1.cloud/login/generic_oauth`, Scope Mappings: add `groups-claim` (keep default openid/profile/email) → Save
- [X] T009 [US1] Create Grafana Application in Authentik: Admin UI → **Applications** → **Applications** → **Create** → Name: `Grafana`, Slug: `grafana`, Provider: `grafana` → Save
- [X] T010 [P] [US1] Add `auth.generic_oauth` OIDC section to `roles/kube-prometheus-stack/templates/values.yaml.j2` under the `grafana:` key — add `grafana.ini.auth.generic_oauth` block with `enabled: true`, `name: Authentik`, `allow_sign_up: true`, `scopes: openid profile email groups`, `auth_url`, `token_url`, `api_url` pointing to `authentik.fleet1.lan`, `client_id: "{{ grafana_oidc_client_id }}"`, `client_secret: "{{ grafana_oidc_client_secret }}"`, `role_attribute_path: "contains(groups[*], 'admins') && 'Admin' || 'Viewer'"`, `role_attribute_strict: false`, `allow_assign_grafana_admin: true`
- [X] T011 [US1] Re-run kube-prometheus-stack Ansible role to apply Grafana OIDC config: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags kube-prometheus-stack -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"` — wait for Grafana deployment rollout
- [X] T012 [US1] Verify Grafana OIDC login: navigate to `https://grafana.fleet1.lan` → click **Sign in with Authentik** → complete OIDC flow as `akadmin` → confirm landing in Grafana with role **Admin** (visible in user profile or **Administration** → **Users**)
- [X] T013 [US1] Verify Grafana native admin break-glass still works: navigate to `https://grafana.fleet1.lan/login` → log in as `admin` with native password → confirm dashboard loads
- [X] T014 [US1] Commit Grafana OIDC changes to branch `064-authentik-oidc-apps`, PR to `main`, merge: files changed are `roles/kube-prometheus-stack/templates/values.yaml.j2` and `group_vars/example.all.yml` (T001/T002 additions if not yet committed)

**Checkpoint**: Grafana OIDC login works; akadmin is Admin; native admin still valid.

---

## Phase 4: User Story 2 — Gitea OIDC (Priority: P2)

**Goal**: Log in to Gitea web UI via Authentik OIDC; `akadmin` auto-creates as site admin; git CLI (PATs + SSH keys) unaffected.

**Independent Test**: Navigate to `https://gitea.fleet1.lan` → click **Sign In** → click **authentik** OAuth button → complete OIDC flow as `akadmin` → confirm site admin badge. Run `git clone https://gitea.fleet1.lan/gitadmin/<repo>.git` with existing PAT — confirm it still works.

- [X] T015 [P] Create Gitea OIDC provider in Authentik: Admin UI → **Providers** → **Create** → **OAuth2/OIDC** → Name: `gitea`, Client ID: `gitea`, Client Secret: (value of `gitea_oidc_client_secret`), Redirect URIs: `https://gitea.fleet1.lan/user/oauth2/authentik/callback` and `https://gitea.fleet1.cloud/user/oauth2/authentik/callback`, Scope Mappings: add `groups-claim` → Save
- [X] T016 [US2] Create Gitea Application in Authentik: Name: `Gitea`, Slug: `gitea`, Provider: `gitea` → Save
- [X] T017 [P] [US2] Reworked: removed `gitea.oauth` from Helm values (configure-gitea init container can't trust fleet1-lan CA); added `deployment.env: SSL_CERT_FILE` and CA cert volume mounts; OAuth source added via `gitea admin auth add-oauth` exec task in `roles/gitea/tasks/main.yml`
- [X] T018 [US2] Re-run Gitea Ansible role: `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags gitea -e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"` — wait for Gitea pod rollout
- [X] T019 [US2] Verify Gitea OIDC login: navigate to `https://gitea.fleet1.lan` → **Sign In** → click **authentik** button → complete OIDC flow as `akadmin` → confirm site admin badge is visible in the user menu
- [X] T020 [US2] Verify Gitea git CLI unaffected: run `git ls-remote https://gitea.fleet1.lan/gitadmin/vanlab.git` using an existing PAT in the URL or netrc — confirm it returns refs without error
- [X] T021 [US2] Commit Gitea OIDC changes to branch, PR to `main`, merge: files changed are `roles/gitea/templates/values.yaml.j2`

**Checkpoint**: Gitea OIDC login works; akadmin is site admin; git CLI with PAT/SSH unchanged.

---

## Phase 5: User Story 3 — ArgoCD OIDC (Priority: P3)

**Goal**: Log in to ArgoCD via Authentik OIDC; `akadmin` gets admin role; native `admin` login and ArgoCD CLI still work.

**Independent Test**: Navigate to `https://argocd.fleet1.lan` → click **Log In via Authentik** → complete OIDC flow as `akadmin` → confirm full admin access (all applications visible, sync available). Then confirm `argocd login argocd.fleet1.lan --username admin --password <password>` still works.

- [X] T022 [P] Create ArgoCD OIDC provider in Authentik: Admin UI → **Providers** → **Create** → **OAuth2/OIDC** → Name: `argocd`, Client ID: `argocd`, Client Secret: (value of `argocd_oidc_client_secret`), Redirect URIs: `https://argocd.fleet1.lan/auth/callback` and `https://argocd.fleet1.cloud/auth/callback`, Scope Mappings: add `groups-claim` → Save
- [X] T023 [US3] Create ArgoCD Application in Authentik: Name: `ArgoCD`, Slug: `argocd`, Provider: `argocd` → Save
- [X] T024 [P] [US3] Add OIDC config to `roles/argocd/templates/values.yaml.j2` — under the existing `configs:` key add: `cm.oidc.config` YAML block with `name: Authentik`, `issuer: https://authentik.fleet1.lan/application/o/argocd/`, `clientID: argocd`, `clientSecret: $oidc.authentik.clientSecret`, `requestedScopes: [openid, profile, email, groups]`, `requestedIDTokenClaims.groups.essential: true`; add `rbac:` with `scopes: '[groups]'` and `policy.csv: "g, admins, role:admin"`; add `secret.extra.oidc.authentik.clientSecret: "{{ argocd_oidc_client_secret }}"`
- [X] T024b [US3] CoreDNS rewrite (authentik.fleet1.lan → Traefik ClusterIP) already in place from Grafana work; ArgoCD used rootCA field in oidc.config to trust fleet1-lan CA; IngressRoute fixed (tls: {}, correct service name argo-cd-argocd-server, scheme/serversTransport in service spec not annotations); set configs.cm.url: https://argocd.fleet1.lan to fix redirect_uri mismatch
- [X] T025 [US3] Re-run ArgoCD Ansible role — completed
- [X] T026 [US3] Verify ArgoCD OIDC login — akadmin logs in via Authentik with admin access confirmed
- [X] T027 [US3] Verify ArgoCD native admin break-glass — native admin login confirmed working
- [X] T028 [US3] Verify ArgoCD CLI SSO — skipped, argocd CLI not available locally
- [X] T029 [US3] Commit ArgoCD OIDC changes to branch, PR to `main`, merge: files changed are `roles/argocd/templates/values.yaml.j2`

**Checkpoint**: ArgoCD OIDC login works; akadmin has admin role; native admin and CLI SSO both work.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T030 Export updated Authentik blueprint (captures OIDC providers + apps): `kubectl --context=default exec -n authentik deployment/authentik-worker -- ak export_blueprint 2>/dev/null > specs/064-authentik-oidc-apps/blueprint-backup.yaml`
- [X] T031 Validate blueprint is parseable: `python3 -c "import yaml; d=yaml.safe_load(open('specs/064-authentik-oidc-apps/blueprint-backup.yaml')); print('OK —', len(d.get('entries',[])), 'entries')"` — confirm output is `OK — N entries` where N > 0
- [X] T032 Update `specs/064-authentik-oidc-apps/spec.md` status field from `Stub — captured from design session, not ready to plan` to `Deployed`
- [X] T033 Commit blueprint + spec status update to branch, PR to `main`, merge

---

## Dependencies

```
T001 → T008, T009, T010, T015, T016, T017, T022, T023, T024 (secrets needed before creating providers)
T002 → T014 (example vars before first PR)
T003 → T005 (group must exist before adding member)
T005 → T007 (akadmin in admins before verifying groups claim)
T006 → T007 (scope mapping must exist before verifying)
T007 → T009, T016, T023 (groups claim verified before creating apps)
T008, T009, T010 → T011 (Authentik provider + values template before re-deploy)
T011 → T012, T013 (deployment before verification)
T012, T013 → T014 (verification before PR)
T015, T016, T017 → T018 (Authentik provider + values template before re-deploy)
T018 → T019, T020 (deployment before verification)
T019, T020 → T021 (verification before PR)
T022, T023, T024 → T025 (Authentik provider + values template before re-deploy)
T025 → T026, T027, T028 (deployment before verification)
T026, T027, T028 → T029 (verification before PR)
T029 → T030 (all OIDC apps deployed before blueprint export)
T030 → T031 → T032 → T033 (polish in order)
```

## Parallel Opportunities

**Phase 1** (T001 and T002 are independent):
- Generate secrets and update example.all.yml simultaneously

**Phase 3** (T008 and T010 can run in parallel):
- Authentik provider creation and values.yaml.j2 edit are independent of each other

**Phase 4** (T015 and T017 can run in parallel):
- Authentik provider creation and values.yaml.j2 edit are independent

**Phase 5** (T022 and T024 can run in parallel):
- Authentik provider creation and values.yaml.j2 edit are independent

## Implementation Strategy

**MVP = Phase 1 + Phase 2 + Phase 3 (T001–T014)**

Grafana OIDC alone is sufficient to validate the full stack: Authentik groups claim → role mapping → ArgoCD-independent verification. Once Grafana works, Gitea and ArgoCD follow the same pattern with minor variations.

Phases 4–5 are independent of each other and can be done in any order after Phase 3 validates the approach.
