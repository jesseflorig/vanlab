# Quickstart: Authentik OIDC App Integration (064)

**Branch**: `064-authentik-oidc-apps` | **Date**: 2026-05-22

---

## Prerequisites

- Spec 063 (Authentik) deployed and stable — `https://authentik.fleet1.lan` reachable
- `akadmin` account exists with TOTP enrolled
- Break-glass credentials (native admin) for Grafana, Gitea, ArgoCD stored in Vaultwarden

---

## Phase 0: Authentik Shared Setup (before any app PR)

### 1. Create groups in Authentik

Admin UI → **Directory** → **Groups** → **Create**:
- Name: `admins` → Save
- Name: `users` → Save

Admin UI → **Directory** → **Users** → click `akadmin` → **Groups** tab → **Add** → select `admins` → Save.

### 2. Create custom `groups` scope mapping

Admin UI → **Customization** → **Property Mappings** → **Create** → **Scope Mapping**:
- Name: `groups-claim`
- Scope name: `groups`
- Expression:
  ```python
  return {
      "groups": [group.name for group in request.user.ak_groups.all()]
  }
  ```
→ Save.

### 3. Verify groups claim

Navigate to `https://authentik.fleet1.lan/application/o/userinfo/` while logged in as akadmin.
Expected response contains: `"groups": ["admins"]`

---

## App 1: Grafana OIDC

### Authentik side

Admin UI → **Applications** → **Providers** → **Create** → **OAuth2/OpenID Connect Provider**:
- Name: `grafana`
- Client type: Confidential
- Client ID: `grafana`
- Client Secret: (paste the value of `grafana_oidc_client_secret` from `group_vars/all.yml`)
- Redirect URIs:
  - `https://grafana.fleet1.lan/login/generic_oauth`
  - `https://grafana.fleet1.cloud/login/generic_oauth`
- Scope Mappings: add `groups-claim` (plus default `openid`, `profile`, `email`)
→ Save, then create Application:
- Name: `Grafana`
- Slug: `grafana`
- Provider: `grafana`

### App side

Add `auth.generic_oauth` to `roles/kube-prometheus-stack/templates/values.yaml.j2`, re-run playbook.

### Verification

Navigate to `https://grafana.fleet1.lan` → click **Sign in with Authentik** → log in as akadmin → confirm landing in Grafana as **Admin** role.

**Regression check**: Native `admin` login still works at `https://grafana.fleet1.lan/login`.

---

## App 2: Gitea OIDC

### Authentik side

Create provider `gitea`:
- Client ID: `gitea`, Client Secret: (value of `gitea_oidc_client_secret`)
- Redirect URIs:
  - `https://gitea.fleet1.lan/user/oauth2/authentik/callback`
  - `https://gitea.fleet1.cloud/user/oauth2/authentik/callback`
- Add `groups-claim` scope mapping
Create Application with slug `gitea`.

### App side

Add `gitea.oauth` and `gitea.config.oauth2_client` to `roles/gitea/templates/values.yaml.j2`, re-run playbook.

### Verification

Navigate to `https://gitea.fleet1.lan` → **Sign In** → **Sign in with authentik** → log in as akadmin → confirm site admin badge visible. Check that PATs and SSH keys still work for git CLI.

---

## App 3: ArgoCD OIDC

### Authentik side

Create provider `argocd`:
- Client ID: `argocd`, Client Secret: (value of `argocd_oidc_client_secret`)
- Redirect URIs:
  - `https://argocd.fleet1.lan/auth/callback`
  - `https://argocd.fleet1.cloud/auth/callback`
- Add `groups-claim` scope mapping
Create Application with slug `argocd`.

### App side

Add `oidc.config` + `rbac.policy.csv` + `secret.extra` to `roles/argocd/templates/values.yaml.j2`, re-run playbook.

### Verification

Navigate to `https://argocd.fleet1.lan` → **Log In via Authentik** → log in as akadmin → confirm full admin access (can see all apps, sync, delete). CLI: `argocd login argocd.fleet1.lan --sso`.

**Regression check**: `argocd login argocd.fleet1.lan --username admin --password <password>` still works.

---

## Rollback Procedure (per app)

If OIDC login breaks after a re-deploy, always fall back to native admin:

| App | Break-glass login |
|-----|-------------------|
| Grafana | `https://grafana.fleet1.lan/login` → username `admin` |
| Gitea | `https://gitea.fleet1.lan/user/login` → username `gitadmin` |
| ArgoCD | `https://argocd.fleet1.lan/login` → username `admin` |

To disable OIDC: remove the OIDC block from the values template, re-run the Ansible role.
