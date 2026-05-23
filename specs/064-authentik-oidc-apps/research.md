# Research: Authentik OIDC App Integration (064)

**Branch**: `064-authentik-oidc-apps` | **Date**: 2026-05-22

---

## R1 — Architecture: Infrastructure-Managed Services

**Decision**: Grafana, Gitea, and ArgoCD are **infrastructure** (per Constitution Principle XI) — they are Ansible-managed via Helm, NOT ArgoCD-managed. Their OIDC configuration goes in Ansible Jinja2 templates (`roles/*/templates/values.yaml.j2`), rendered from `group_vars/all.yml` at playbook time.

**Implication**: OIDC client secrets do NOT need SealedSecrets. They are stored in `group_vars/all.yml` (untracked) and rendered into Helm values by Ansible. The template files committed to Git contain `{{ variable }}` placeholders — the actual secret values never reach Git.

**Contrast**: If these were ArgoCD-managed apps, all secrets would require SealedSecrets per Principle IV.

---

## R2 — Authentik: Groups Claim Scope Mapping

**Decision**: Create a custom **Scope Mapping** in Authentik that explicitly emits the `groups` claim. While Authentik's default `profile` scope returns user info, group membership must be explicitly configured as a scope mapping for reliable cross-version behavior.

**Implementation**:
1. Admin UI → **Customization** → **Property Mappings** → **Create** → **Scope Mapping**
2. Name: `groups-claim`, Scope name: `groups`
3. Expression:
   ```python
   return {
       "groups": [group.name for group in request.user.ak_groups.all()]
   }
   ```
4. Assign this mapping to each OIDC provider under **Scope Mappings**
5. Each client requests `openid profile email groups` scopes

**Result**: Token contains `"groups": ["admins"]` (or whatever groups the user is in).

---

## R3 — Authentik: One Provider + Application Per App

**Decision**: Create three OIDC providers + applications in Authentik (one per app). Client secrets are pre-generated locally and set in Authentik.

**Per-provider setup**:
- Authorization flow: `default-provider-authorization-implicit-consent`
- Client type: Confidential
- Redirect URIs: see R6
- Scopes: `openid`, `profile`, `email`, `groups` (custom mapping from R2)
- Client secret: pre-generated via `openssl rand -hex 32`, stored in `group_vars/all.yml`

**Naming convention**:
| App | Provider name | Application slug |
|-----|--------------|-----------------|
| Grafana | `grafana` | `grafana` |
| Gitea | `gitea` | `gitea` |
| ArgoCD | `argocd` | `argocd` |

---

## R4 — Grafana OIDC (kube-prometheus-stack)

**Decision**: Add `auth.generic_oauth` section to `roles/kube-prometheus-stack/templates/values.yaml.j2`. Client ID and secret rendered from `group_vars/all.yml`.

**Helm values addition**:
```yaml
grafana:
  grafana.ini:
    auth.generic_oauth:
      name: Authentik
      enabled: true
      allow_sign_up: true
      scopes: openid profile email groups
      auth_url: https://authentik.fleet1.lan/application/o/authorize/
      token_url: https://authentik.fleet1.lan/application/o/token/
      api_url: https://authentik.fleet1.lan/application/o/userinfo/
      client_id: "{{ grafana_oidc_client_id }}"
      client_secret: "{{ grafana_oidc_client_secret }}"
      role_attribute_path: "contains(groups[*], 'admins') && 'Admin' || 'Viewer'"
      role_attribute_strict: false
      allow_assign_grafana_admin: true
```

**Group mapping**: `role_attribute_path` uses JMESPath — if user is in `admins` group → Grafana Admin role; otherwise → Viewer. `role_attribute_strict: false` means missing claim → Viewer (not login failure).

**Client secret**: `{{ grafana_oidc_client_secret }}` rendered from `group_vars/all.yml`.

---

## R5 — Gitea OIDC

**Decision**: Add `gitea.oauth` and `gitea.config.oauth2_client` sections to `roles/gitea/templates/values.yaml.j2`.

**Helm values addition**:
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

**Group→admin mapping**: Gitea supports `adminGroup` in the oauth block — users in `admins` group become site admins. `ACCOUNT_LINKING: login` ties OIDC identity to an existing account by username on first login.

**Git CLI unaffected**: OIDC only applies to the web UI. `git push`/`git pull` over HTTPS uses PATs; SSH uses keys. No change to existing developer workflow.

---

## R6 — ArgoCD OIDC (Dex Already Disabled)

**Decision**: Add `oidc.config` to `configs.cm` and `policy.csv` to `configs.rbac` in `roles/argocd/templates/values.yaml.j2`. Dex is **already disabled** (`dex.enabled: false`) — no change needed there.

**Helm values addition**:
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

**Secret substitution**: ArgoCD expands `$oidc.authentik.clientSecret` from its own `argocd-secret` Secret at runtime. The Helm `configs.secret.extra` key injects the value into that Secret via the Helm chart — rendered from `group_vars/all.yml` at Ansible deploy time.

**CLI auth**: `argocd login argocd.fleet1.lan --sso` works with direct OIDC. The browser opens for the OIDC flow, then the CLI gets a token. The `admin` bootstrap user still works via `--username admin --password`.

---

## R7 — Redirect URIs Per App

All apps have both `*.fleet1.lan` (internal) and `*.fleet1.cloud` (public via Cloudflare Tunnel) hostnames. Since Authentik is internal-only (`authentik.fleet1.lan`), **OIDC only works on the LAN**. Register both URIs in Authentik for flexibility, but the `.cloud` OIDC flow will only work from inside the LAN (browser must reach `authentik.fleet1.lan`).

| App | Redirect URIs to register in Authentik |
|-----|----------------------------------------|
| Grafana | `https://grafana.fleet1.lan/login/generic_oauth`, `https://grafana.fleet1.cloud/login/generic_oauth` |
| Gitea | `https://gitea.fleet1.lan/user/oauth2/authentik/callback`, `https://gitea.fleet1.cloud/user/oauth2/authentik/callback` |
| ArgoCD | `https://argocd.fleet1.lan/auth/callback`, `https://argocd.fleet1.cloud/auth/callback` |

---

## R8 — Authentik Groups: Create Before App OIDC

**Decision**: Create `admins` and `users` groups in Authentik and add `akadmin` to `admins` before testing any OIDC login. Without group membership, every user lands in the lowest-privilege role.

**Steps** (manual in Authentik UI):
1. Admin UI → **Directory** → **Groups** → **Create** → Name: `admins`
2. **Directory** → **Groups** → **Create** → Name: `users`  
3. **Directory** → **Users** → click `akadmin` → **Groups** tab → add to `admins`

**Verification**: Log out and back in; check that the token contains `"groups": ["admins"]` via the Authentik debug endpoint: `https://authentik.fleet1.lan/application/o/userinfo/`.

---

## R9 — Ansible Re-Deploy Strategy

**Decision**: Each app OIDC change is applied by re-running its Ansible role on the appropriate playbook. No ArgoCD sync involved (infrastructure services).

| Service | Playbook command |
|---------|-----------------|
| Grafana | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags kube-prometheus-stack` |
| Gitea | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags gitea` |
| ArgoCD | `ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd` |

All commands use `-e "ansible_ssh_common_args='-o StrictHostKeyChecking=no'"` to bypass ProxyJump.

---

## R10 — PR Strategy

**Decision**: One PR per app (Grafana → Gitea → ArgoCD). Each PR contains:
1. Ansible role template changes (`roles/*/templates/values.yaml.j2`)
2. `group_vars/example.all.yml` placeholder additions
3. `specs/064-authentik-oidc-apps/tasks.md` progress updates

`group_vars/all.yml` is never committed. The Ansible role re-run applies the changes to the cluster.

---

## R11 — Hairpin NAT: Use In-Cluster Service URLs for Server-Side OIDC Calls

**Decision**: Any URL that a pod calls server-side (token exchange, userinfo, OIDC discovery) must use the Authentik in-cluster service URL, not the external hostname.

**Rationale**: `authentik.fleet1.lan` resolves to the node IP (`10.1.20.11`). From inside the cluster, connections to that IP on port 443 are refused — pods cannot hairpin through the node's external interface to reach Traefik. Only browser-facing URLs (the `auth_url` / authorization endpoint) should use the external hostname since those are opened by the user's browser, not by the pod.

**Pattern**:
| URL type | Use |
|----------|-----|
| `auth_url` (browser redirect) | `https://authentik.fleet1.lan/...` |
| `token_url`, `api_url`, `autoDiscoverUrl` (pod-to-pod) | `http://authentik-server.authentik.svc.cluster.local/...` |

**Applied in**:
- Grafana: `token_url` and `api_url` use internal service URL
- Gitea: `autoDiscoverUrl` uses internal service URL
- ArgoCD: issuer URL must use internal service URL (or ArgoCD must be configured to skip external issuer validation)

---

## R12 — Traefik v3: TLSOption Must Be In Same Namespace as IngressRoute

**Decision**: Do not reference a cross-namespace TLSOption in IngressRoutes. Use `tls: {}` until mTLS is properly set up per-namespace.

**Rationale**: Traefik v3 enforces that a `TLSOption` resource must reside in the same namespace as the `IngressRoute` referencing it. The `device-mtls` TLSOption lives in the `traefik` namespace. IngressRoutes in `monitoring`, `gitea`, `argocd`, etc. cannot reference it — Traefik silently drops the route, resulting in a 404.

**Fix**: Change `tls: options: name: device-mtls / namespace: traefik` to `tls: {}`. This uses the default wildcard cert from the TLSStore without mTLS enforcement.

**TODO**: Mirror `device-ca-public` secret and `device-mtls` TLSOption into each service namespace (per the frigate pattern) to restore mTLS enforcement.

**Affected files**: `manifests/monitoring/fleet1-lan-ingressroutes.yaml`, `manifests/gitea/fleet1-lan-ingressroute.yaml` — check all remaining `manifests/*/fleet1-lan-ingressroute*.yaml` before testing.

---

## R14 — Gitea Helm Chart: `gitea.extraEnvs` Goes to Init Containers, Not Main Container

**Decision**: Use `deployment.env` (not `gitea.extraEnvs`) to inject environment variables into the main Gitea container.

**Rationale**: In gitea-charts/gitea v10.3.0, `gitea.extraEnvs` injects into the `configure-gitea` init container, not the main container. `deployment.env` is the correct key for main container env vars. Volumes work correctly via `extraVolumes` / `extraContainerVolumeMounts` / `extraInitVolumeMounts` as documented.

**Consequence for OIDC**: The `configure-gitea` init container also can't use Go's `SSL_CERT_FILE` for custom CA trust because the goth library (`openidConnect.New()`) uses its own HTTP client that bypasses `SSL_CERT_FILE`. The fix is to remove `gitea.oauth` from Helm values entirely (skip configure-gitea's OIDC discovery) and instead register the OAuth source via `gitea admin auth add-oauth` exec into the running container, which inherits `SSL_CERT_FILE` from `deployment.env`.

---

## R13 — RWO PVC Rolling Update Deadlock

**Decision**: Pre-scale deployments to 0 before running Helm upgrades on services with ReadWriteOnce PVCs.

**Rationale**: Helm's default rolling update strategy starts the new pod before terminating the old one. With RWO PVCs, the new pod (potentially on a different node) cannot claim the volume while the old pod holds it. The rollout stalls until timeout. Scaling to 0 first cleanly detaches the PVC, then the new pod attaches it without contention.

**Pattern**:
```bash
kubectl -n <namespace> scale deployment/<name> --replicas=0
# run ansible-playbook / helm upgrade
# deployment scales back to 1 automatically via Helm
```

**Affected services**: Gitea (confirmed), Grafana (confirmed via different symptom — old pod didn't terminate). Any single-replica Deployment with a RWO Longhorn PVC is at risk.

