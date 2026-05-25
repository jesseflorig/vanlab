# GitOps

ArgoCD backed by a self-hosted Gitea instance for fully declarative application delivery.

## Infrastructure vs Application Workloads

Not everything is ArgoCD-managed. The boundary is defined by bootstrap ordering — ArgoCD needs certain services running before it can sync anything.

**Ansible/Helm-managed (infrastructure) — never migrate to ArgoCD:**

| Service | Reason |
|---------|--------|
| Traefik | Ingress controller — must exist before any service is reachable |
| cert-manager | PKI — TLS certs must exist before services can come up |
| Longhorn | Storage — PVCs must exist before stateful workloads can start |
| Sealed Secrets | Secret controller — must exist before ArgoCD syncs encrypted secrets |
| Gitea | ArgoCD's source-of-truth — can't sync from Gitea if Gitea isn't running |
| ArgoCD | The GitOps controller itself |
| kube-prometheus-stack | Cluster observability infrastructure |

**ArgoCD-managed (application workloads) — all new apps go here:**

| ArgoCD App | Manifests | Description |
|------------|-----------|-------------|
| `static-site` | `manifests/static-site/` | fleet1.cloud landing page |
| `redirects` | `manifests/redirects/` | Wildcard subdomain → apex redirect |
| `home-automation-prereqs` | `manifests/home-automation/prereqs/` | Namespace, certs, SealedSecrets, ConfigMaps |
| `home-automation-apps` | `manifests/home-automation/apps/` | ArgoCD Applications for each HA service |

Rule of thumb: if the cluster can't function or recover without it, it's infrastructure. If it runs *on top of* the cluster, it belongs in `manifests/` under ArgoCD.

## Development Workflow

This project uses a dual-remote strategy (GitHub + Gitea) with automated PR creation and merging.

- **`make pr`** — pushes the current feature branch to both `origin` (GitHub) and `gitea`, then creates PRs on both.
- **`make merge`** — merges the open PRs on both remotes and runs `make sync`.
- **`make sync`** — pulls the latest `main` from GitHub, updates local state, and prunes merged branches.

All work happens on a feature branch named `NNN-short-description`. Never commit directly to `main`.

## First-time Bootstrap

```bash
# 1. Fill in Gitea and ArgoCD values in group_vars/all.yml
#    gitea_admin_username, gitea_admin_password, gitea_argocd_token,
#    argocd_admin_password_bcrypt

# 2. Deploy the full stack
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml

# 3. Access dashboards
#    https://gitea.fleet1.cloud  /  https://argocd.fleet1.cloud
```

## Registering a New Application

Add an entry to `argocd_apps` in `group_vars/all.yml`:

```yaml
argocd_apps:
  - name: my-service
    repo: gitadmin/vanlab.git
    path: manifests/my-service
    namespace: my-service
    revision: main
```

Then re-run the bootstrap role:

```bash
ansible-playbook -i hosts.ini playbooks/cluster/services-deploy.yml --tags argocd-bootstrap
```

## Rollback

ArgoCD continuously reconciles the cluster to match the desired state in Gitea. To roll back:

1. Revert the commit in Gitea (web UI or `git revert` + push)
2. ArgoCD detects the change and re-syncs within 3 minutes
3. Verify: `kubectl get applications -n argocd`

No direct `kubectl` intervention required — Git history is the source of truth.

## Smoke Test

```bash
ansible-playbook -i hosts.ini playbooks/cluster/argocd-smoke-test.yml
```
