# Data Model: Authentik OIDC App Integration (064)

**Branch**: `064-authentik-oidc-apps` | **Date**: 2026-05-22

---

## Authentik Entities (created via Admin UI)

### Groups

| Field | Value |
|-------|-------|
| `admins` group | Grants admin role on all three apps |
| `users` group | Regular user (optional; default behavior for anyone not in `admins`) |
| `akadmin` membership | Added to `admins` group |

### Scope Mapping (custom)

| Field | Value |
|-------|-------|
| Name | `groups-claim` |
| Scope name | `groups` |
| Expression | `return {"groups": [g.name for g in request.user.ak_groups.all()]}` |
| Assigned to | All three OIDC providers |

### OIDC Providers (one per app)

| App | Provider Name | Client ID | Client Secret var | Redirect URIs |
|-----|--------------|-----------|-------------------|---------------|
| Grafana | `grafana` | `grafana` | `grafana_oidc_client_secret` | `https://grafana.fleet1.lan/login/generic_oauth`, `https://grafana.fleet1.cloud/login/generic_oauth` |
| Gitea | `gitea` | `gitea` | `gitea_oidc_client_secret` | `https://gitea.fleet1.lan/user/oauth2/authentik/callback`, `https://gitea.fleet1.cloud/user/oauth2/authentik/callback` |
| ArgoCD | `argocd` | `argocd` | `argocd_oidc_client_secret` | `https://argocd.fleet1.lan/auth/callback`, `https://argocd.fleet1.cloud/auth/callback` |

### Applications (one per provider)

Each Application links a Provider to an access policy. Use `default-provider-authorization-implicit-consent` flow. Application slug must match the issuer URL segment (e.g., `/application/o/grafana/`).

---

## group_vars Variables (added to `all.yml` + `example.all.yml`)

| Variable | Description | Generation |
|----------|-------------|------------|
| `grafana_oidc_client_id` | Grafana OIDC client ID | `grafana` (static) |
| `grafana_oidc_client_secret` | Grafana OIDC client secret | `openssl rand -hex 32` |
| `gitea_oidc_client_id` | Gitea OIDC client ID | `gitea` (static) |
| `gitea_oidc_client_secret` | Gitea OIDC client secret | `openssl rand -hex 32` |
| `argocd_oidc_client_id` | ArgoCD OIDC client ID | `argocd` (static) |
| `argocd_oidc_client_secret` | ArgoCD OIDC client secret | `openssl rand -hex 32` |

---

## Helm Values Changes (per service)

### kube-prometheus-stack (`roles/kube-prometheus-stack/templates/values.yaml.j2`)

Added section under `grafana:`:
```yaml
grafana:
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      name: Authentik
      allow_sign_up: true
      client_id: "{{ grafana_oidc_client_id }}"
      client_secret: "{{ grafana_oidc_client_secret }}"
      scopes: openid profile email groups
      auth_url: https://authentik.fleet1.lan/application/o/authorize/
      token_url: https://authentik.fleet1.lan/application/o/token/
      api_url: https://authentik.fleet1.lan/application/o/userinfo/
      role_attribute_path: "contains(groups[*], 'admins') && 'Admin' || 'Viewer'"
      role_attribute_strict: false
      allow_assign_grafana_admin: true
```

### gitea (`roles/gitea/templates/values.yaml.j2`)

Added section under `gitea:`:
```yaml
gitea:
  oauth:
    - name: authentik
      provider: openidConnect
      key: "{{ gitea_oidc_client_id }}"
      secret: "{{ gitea_oidc_client_secret }}"
      autoDiscoverUrl: https://authentik.fleet1.lan/application/o/gitea/.well-known/openid-configuration
      scopes: "openid profile email groups"
      groupClaimName: groups
      adminGroup: admins
  config:
    oauth2_client:
      ENABLE_AUTO_REGISTRATION: true
      USERNAME: preferred_username
      UPDATE_AVATAR: true
      ACCOUNT_LINKING: login
```

### argocd (`roles/argocd/templates/values.yaml.j2`)

Added sections under `configs:`:
```yaml
configs:
  cm:
    oidc.config: |
      name: Authentik
      issuer: https://authentik.fleet1.lan/application/o/argocd/
      clientID: argocd
      clientSecret: $oidc.authentik.clientSecret
      requestedScopes:
        - openid
        - profile
        - email
        - groups
      requestedIDTokenClaims:
        groups:
          essential: true
  rbac:
    scopes: '[groups]'
    policy.csv: |
      g, admins, role:admin
  secret:
    extra:
      oidc.authentik.clientSecret: "{{ argocd_oidc_client_secret }}"
```

---

## Token Shape (expected after OIDC login)

```json
{
  "sub": "...",
  "preferred_username": "akadmin",
  "email": "akadmin@fleet1.lan",
  "groups": ["admins"],
  "iss": "https://authentik.fleet1.lan/application/o/grafana/",
  ...
}
```

The `groups` array drives role assignment on all three apps.

---

## Role Mapping Summary

| App | Claim | `admins` member | Not in `admins` |
|-----|-------|-----------------|-----------------|
| Grafana | `groups` via JMESPath | Admin | Viewer |
| Gitea | `adminGroup: admins` | Site admin | Regular user |
| ArgoCD | `g, admins, role:admin` in policy.csv | `role:admin` | `role:readonly` (default) |
